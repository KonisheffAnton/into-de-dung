extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
const PresentationState = preload("res://scripts/core/actions/action_presentation_state.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION CAPTURE: " + label)

func _snapshot(session: Variant) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	return result.snapshot.to_dict() if result.code == ItemSnapshotResult.Code.OK and result.snapshot != null else {}

func _brute_force_action_areas(state: ItemSimulationState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or (state.abilities != null and state.abilities.stage in ["setup", "terminal"]): return result
	var board := state.get_board()
	for unit: UnitState in board.get_all_units():
		if not unit.is_alive() or state.is_summon_pending(unit.id) or ControlRules.action_reason(unit) != &"": continue
		var stats := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict()) if unit.stats != null else null
		if stats == null: continue
		var reach := stats.get_value(StatTypes.StatType.ATTACK_RANGE)
		var cells: Array[Vector2i] = []
		for y: int in board.height:
			for x: int in board.width:
				var cell := Vector2i(x, y)
				if cell != unit.cell and board.is_terrain_walkable(cell) and AttackReachCheck.inspect_spatial_cells(board, unit.cell, unit.faction, cell, reach) == &"": cells.append(cell)
		var mode := unit.combat_perks.mode if unit.combat_perks != null else CombatPerksState.Mode.NONE
		if MeleeThreat.has_passive_opportunist(unit): mode = CombatPerksState.Mode.OPPORTUNIST
		var ready := mode in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COUNTERATTACK] and MeleeThreat.reaction_ready_state(state, unit, mode)
		result.append({"owner_id": unit.id, "name": unit.debug_name, "faction": int(unit.faction), "origin": unit.cell, "cells": cells, "mode": mode, "ready": ready})
	return result

func _stats_cache_signature(session: BattleCoreReactionsSession) -> Dictionary:
	var result: Dictionary = {}
	for unit: UnitState in session.units:
		var stats: Dictionary = {}
		if unit.stats != null:
			for stat_type: Variant in unit.stats._stats:
				var stat: Stat = unit.stats._stats[stat_type]
				stats[stat_type] = [stat._cache_dirty, stat._cached_value]
		result[unit.id] = stats
	return result

func _area_observation(session: BattleCoreReactionsSession) -> Dictionary:
	var cells: Array[Vector2i] = []
	for unit: UnitState in session.units: cells.append(unit.cell)
	return {"snapshot": _snapshot(session), "cache": _stats_cache_signature(session),
		"board_version": session.board.board_version, "unit_cells": cells,
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters()}

func _check_action_area_oracle(session: BattleCoreReactionsSession, label: String) -> void:
	var before := _area_observation(session)
	var expected := _brute_force_action_areas(session.state)
	var actual := PresentationState.capture_action_areas(session.state)
	var after := _area_observation(session)
	check(actual == expected, "%s preserves brute-force action-area DTO" % label)
	check(after == before, "%s leaves live state, stat cache, board, RNG, and counters unchanged" % label)
	var before_capture := PresentationState.capture(session.state)
	var after_capture := PresentationState.capture(session.state)
	check(before_capture.action_areas == after_capture.action_areas and after_capture.action_areas == expected,
		"%s full capture keeps the same action-area DTO" % label)

func _action_area_candidate_parity() -> void:
	var session := PlayerTurnFixture.create()
	var actor: UnitState = session.units[0]
	var ally: UnitState = session.units[2]
	var enemy: UnitState = session.units[1]
	var other_ally: UnitState = session.units[3]
	check(actor.is_friendly_to(ally) and not actor.is_friendly_to(enemy), "area fixture has both friendly and enemy blockers")
	check(session.board.move_unit(other_ally, Vector2i(1, 5)), "area fixture clears central ally cell")
	check(session.board.move_unit(actor, Vector2i(3, 3)), "area fixture moves actor to center")
	check(session.board.move_unit(ally, Vector2i(3, 5)), "area fixture places friendly line blocker")
	check(session.board.move_unit(enemy, Vector2i(5, 3)), "area fixture places enemy line blocker")
	session.board.set_terrain(Vector2i(1, 3), TerrainType.Type.WALL)
	session.board.set_terrain(Vector2i(0, 3), TerrainType.Type.FLOOR)
	session.board.set_terrain(Vector2i(3, 1), TerrainType.Type.VOID)
	session.board.set_terrain(Vector2i(3, 0), TerrainType.Type.FLOOR)
	session.board.set_terrain(Vector2i(6, 3), TerrainType.Type.FLOOR)
	session.board.set_height_steps(Vector2i(3, 2), 3)
	session.board.set_height_steps(Vector2i(3, 4), 2)
	actor.control = ControlState.new()
	for reach: float in [1.0, 2.0, 7.0, 1.5, 4097.0]:
		actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, reach)
		_check_action_area_oracle(session, "reach %s" % reach)
	actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 7.0)
	actor.control.stunned_turns = 1
	_check_action_area_oracle(session, "stunned actor")
	actor.control.stunned_turns = 0
	check(session.board.move_unit(actor, Vector2i.ZERO), "area fixture moves actor to board edge")
	_check_action_area_oracle(session, "board edge")
	var valid_origin := actor.cell
	actor.cell = Vector2i(-1, 0)
	_check_action_area_oracle(session, "out-of-bounds origin")
	actor.cell = valid_origin
	session.close()

func _contains_runtime_ref(value: Variant) -> bool:
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		return true
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value:
			if _contains_runtime_ref(key) or _contains_runtime_ref(value[key]):
				return true
	elif typeof(value) == TYPE_ARRAY:
		for item: Variant in value:
			if _contains_runtime_ref(item):
				return true
	return false

func _attack_capture_parity() -> void:
	var session := PlayerTurnFixture.create()
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[3]
	check(session.board.move_unit(actor, Vector2i(2, 2)), "attack fixture places actor")
	check(session.board.move_unit(target, Vector2i(3, 2)), "attack fixture places adjacent target")
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	# Forecast использует отдельную очередь с capture_presentation=false и даёт полные значения parity.
	var expected := ForecastSimulation.run(session.context, session._queue, command)
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(command, session.context)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == expected.status and receipt.reason == expected.reason, "attack status matches capture-off forecast")
	check(_snapshot(session) == expected.snapshot_after, "attack snapshot matches capture-off forecast")
	check(receipt.get_events() == expected.events and receipt.get_steps() == expected.steps, "attack events and steps match capture-off forecast")
	check(session.context.get_rng().to_dict() == expected.rng_after and session.context.simulation_counters() == expected.counters_after, "attack RNG and counters match capture-off forecast")
	check(frames.size() == receipt.get_steps().size() and not frames.is_empty(), "attack captures every executed step")
	check(frames.size() > 0 and frames[-1].after == PresentationState.capture(session.state), "attack final frame matches live after state")

func _faulted_prefix() -> void:
	var session := PlayerTurnFixture.create()
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[3]
	check(session.board.move_unit(actor, Vector2i(2, 2)), "fault fixture places actor")
	check(session.board.move_unit(target, Vector2i(3, 2)), "fault fixture places adjacent target")
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	session._queue = ActionQueue.new(256, 1)
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(command, session.context)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"event_limit", "event limit faults after the committed command prefix")
	check(frames.size() == receipt.get_steps().size() and not frames.is_empty(), "faulted command step remains represented in prefix frames")
	check(not frames.is_empty() and frames[-1].step == receipt.get_steps()[-1], "faulted frame preserves final executed step")
	check(not frames.is_empty() and frames[-1].after == PresentationState.capture(session.state), "faulted final frame matches retained live prefix")

func _eventless_ability_boundary() -> void:
	var session := BattleCoreReactionsSession.new()
	var ability: BattleAbilityState = session.state.abilities
	var command := AbilityBoundaryCommand.new(&"close", ability.team, ability.serials[ability.team], session.context.get_revision())
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(command, session.context)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and frames.size() == 1, "ability boundary directly captures its executed command")
	check(not frames.is_empty() and (frames[0].events as Array).is_empty(), "ability boundary frame has no events")
	check(not frames.is_empty() and frames[0].after.abilities == ability.to_dict(), "eventless frame records the boundary state")

func _run() -> void:
	var session := PlayerTurnFixture.create()
	var actor: UnitState = session.units[0]
	var from_cell := actor.cell
	var to_cell := from_cell + Vector2i(0, 1)
	actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 4.0)
	var stats_before := actor.stats.to_snapshot_dict()
	var before: Dictionary = PresentationState.capture(session.state)
	check(before.units[actor.id].attack_range == 4.0 and actor.stats.to_snapshot_dict() == stats_before, "range is captured without warming dirty live stats")
	actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 3.0)
	check(before.units[actor.id].attack_range == 4.0, "captured range does not follow later live changes")
	var command := MoveCommand.new(actor.id, [from_cell, to_cell], session.context.get_revision())
	var predicted := ForecastSimulation.run(session.context, session._queue, command)
	var snapshot_before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(command, session.context)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and frames.size() == receipt.get_steps().size(), "one frame per executed step")
	check(not frames.is_empty() and frames[0].get("step") == receipt.get_steps()[0], "frame step is a value copy of its receipt step")
	check(not frames.is_empty() and frames[0].get("events") == receipt.get_events(), "frame holds only this call's events")
	check(not _contains_runtime_ref(frames), "frames contain values without runtime references")
	check(not frames.is_empty() and frames[-1].get("after") == PresentationState.capture(session.state), "last frame matches live state")
	check(not frames.is_empty() and frames[0].after.units[actor.id].cell == to_cell, "movement is visible in its executed frame")
	check(before.units[actor.id].cell == from_cell, "initial captured values stay unchanged")
	check(_snapshot(session) == predicted.snapshot_after and receipt.get_events() == predicted.events and receipt.get_steps() == predicted.steps, "capture preserves execution and preview parity")
	check(snapshot_before != _snapshot(session) and rng_before == predicted.rng_after and counters_before != session.context.simulation_counters() and session.context.simulation_counters() == predicted.counters_after, "capture adds no RNG or counter changes beyond normal execution")
	frames[0].after.units[actor.id].cell = Vector2i(99, 99)
	check(receipt.get_presentation_frames()[0].after.units[actor.id].cell == to_cell, "getter returns detached nested values")
	var simulation_copy := session._queue.copy_for_simulation()
	check(simulation_copy != null and not simulation_copy.capture_presentation, "simulation queue defaults capture off")
	var no_capture := PlayerTurnFixture.create()
	no_capture._queue.capture_presentation = false
	check(no_capture._queue.submit(GuardCommand.new(no_capture.units[0].id, no_capture.context.get_revision()), no_capture.context).get_presentation_frames().is_empty(), "capture off keeps no frames")
	var refill := PlayerTurnFixture.create()
	refill._queue.capture_presentation = true
	var refill_receipt := refill._queue.submit(BattleTurnRefill.new(refill.living_ids(Faction.Type.PLAYER), refill.context.get_revision(), Faction.Type.PLAYER), refill.context)
	var refill_frames := refill_receipt.get_presentation_frames()
	check(refill_receipt.status == ActionReceipt.APPLIED and not refill_frames.is_empty(), "eventless refill still publishes executed frames")
	var refill_has_eventless_frame := false
	for frame: Dictionary in refill_frames:
		if (frame["events"] as Array).is_empty():
			refill_has_eventless_frame = true
	check(refill_has_eventless_frame, "refill frame may contain an empty event list")
	_attack_capture_parity()
	_faulted_prefix()
	_eventless_ability_boundary()
	_action_area_candidate_parity()
	print("PRESENTATION CAPTURE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
