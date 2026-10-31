extends "res://tests/test_battle_action_performance.gd"

const REPORT_PATH: String = "user://battle-soak-performance.json"
const DEFAULT_ROUNDS: int = 3
const DEFAULT_IDLE_FRAMES: int = 3600
const FIRE_CELL_COUNT: int = 24

class BenchmarkInputGuard extends Node:
	var event_counts: Dictionary = {}

	func _input(event: InputEvent) -> void:
		var event_type := event.get_class()
		event_counts[event_type] = int(event_counts.get(event_type, 0)) + 1
		var viewport := get_viewport()
		if viewport != null: viewport.set_input_as_handled()

var soak_trace: Array[Dictionary] = []
var receipt_step_count: int = 0
var applied_command_count: int = 0
var mass_dot_count: int = 0
var status_damage_target_ids: Dictionary = {}
var environment_damage_count: int = 0
var environment_cleanup_count: int = 0
var round_lifecycle: Array[Dictionary] = []
var action_metrics: Array[Dictionary] = []
var startup_frame_ms: Array[float] = []
var steady_idle_frame_ms: Array[float] = []
var combat_frame_ms: Array[float] = []
var last_round: int = 1
var last_alive: Dictionary = {}
var trace_phase: String = "startup"
var trace_bucket: String = "startup_frames"
var previous_frame_usec: int = 0
var fire_entry_cell := Vector2i(-1, -1)
var warning_cell := Vector2i(-1, -1)
var seen_event_sequences: Dictionary = {}
var seen_receipt_ids: Dictionary = {}
var last_action_reason: String = ""
var requested_unit_count: int = UNIT_COUNT
var minimum_alive_count: int = 2147483647
var test_planning_frame_ms: Array[float] = []
var input_guard: BenchmarkInputGuard
var initial_view_state: Dictionary = {}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var rounds := _argument_int(args, "--rounds", DEFAULT_ROUNDS, 3, 20)
	var idle_frames := _argument_int(args, "--idle-frames", DEFAULT_IDLE_FRAMES, 0, 100000)
	requested_unit_count = _argument_int(args, "--units", UNIT_COUNT, 24, 40)
	var uncapped := args.has("--uncapped")
	if uncapped: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = HERO_BATTLE_SCENE.instantiate() as HeroHubBattleView
	session = _make_stress_session()
	check(session != null, "soak fixture builds through production expedition factory")
	if session == null:
		demo.free()
		quit(1)
		return
	if requested_unit_count % 2 != 0:
		check(false, "--units must be even to preserve balanced factions")
		session.close()
		demo.free()
		print("BATTLE SOAK PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var expansion_error := _expand_roster(session)
	if not expansion_error.is_empty():
		check(false, "requested roster fixture: " + expansion_error)
		session.close()
		demo.free()
		print("BATTLE SOAK PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var balance_error := _rebalance_factions(session)
	if not balance_error.is_empty():
		check(false, "balanced expedition fixture: " + balance_error)
		session.close()
		demo.free()
		print("BATTLE SOAK PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	_prepare_soak_state()
	fire_entry_cell = _find_fire_entry_candidate()
	var fixture_error := _fixture_validity_reason()
	if not fixture_error.is_empty():
		check(false, "soak fixture snapshot valid before scene startup: " + fixture_error)
		session.close()
		demo.free()
		print("BATTLE SOAK PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	demo.supplied_session = session
	demo.expedition_battle = true
	root.gui_disable_input = true
	# Начальный refill принадлежит фикстуре, а не измеряемым live-командам.
	if session.last_receipt != null: seen_receipt_ids[session.last_receipt.get_instance_id()] = true
	previous_frame_usec = Time.get_ticks_usec()
	process_frame.connect(_on_process_frame)
	root.add_child(demo)
	input_guard = BenchmarkInputGuard.new()
	root.add_child(input_guard) # Guard сто́ит после UI, чтобы аппаратный ввод не менял сценарий.
	await process_frame
	check(demo.session == session and demo.board_view != null, "rendered HeroHubBattleView owns the production fixture")
	var team_size: int = floori(float(requested_unit_count) / 2.0)
	check(session.board.width == WIDTH and session.board.height == HEIGHT and session.units.size() == requested_unit_count,
		"soak board is 24x16 with the requested registered roster")
	check(session.living_ids(Faction.Type.PLAYER).size() == team_size and session.living_ids(Faction.Type.ENEMY).size() == team_size,
		"soak fixture has a balanced %d/%d live roster" % [team_size, team_size])
	check(session.living_ids(Faction.Type.PLAYER).size() + session.living_ids(Faction.Type.ENEMY).size() == requested_unit_count,
		"soak starts with %d live units" % requested_unit_count)
	check(_valid_status_count() >= requested_unit_count, "all requested units start with schema-valid elemental DOT state")
	check(session.state.environment.fires.size() >= FIRE_CELL_COUNT and CombatEnvironmentState.valid(session.state.environment.to_dict()),
		"fixture retains at least 24 schema-valid fire cells")
	check(warning_cell.x >= 0 and session.state.environment.collapse.get("marked", []).size() == 1,
		"fixture starts with one valid warned collapse cell")
	check(session.state.deck != null and session.state.abilities != null and not session.actor_loadouts.is_empty()
		and not session.unit_visual_classes.is_empty(), "production deck, loadouts, and visual classes remain active")
	_check_lifecycle()
	_record_round_lifecycle(session.round_number)
	last_round = session.round_number
	last_alive = _alive_counts()
	minimum_alive_count = requested_unit_count
	initial_view_state = _view_state_snapshot()
	await _sample_idle("startup_frames", IDLE_FRAME_COUNT, "startup_frames")
	await _sample_idle("steady_idle_frames", idle_frames, "steady_idle_frames")
	var started_round := session.round_number
	if fire_entry_cell.x >= 0:
		# Первый настоящий переход на fire-клетку проверяет entry damage через MoveCommand children.
		if stress_actor_id != UnitId.NONE:
			var actor := session.board.get_unit_by_id(stress_actor_id)
			if actor != null and actor.is_alive() and ControlRules.action_reason(actor, true) == &"":
				trace_phase = "test_planning"
				var path := session.path_to(fire_entry_cell)
				if path.size() > 1 and actor.action_resources.get_main_left() > 0:
					var fire_move := MoveCommand.new(actor.id, path, session.context.get_revision())
					if fire_move.validate(session.context) == &"" and session.select_unit(actor.id):
						await process_frame
						var fire_applied := await _execute_live(&"move_to", [fire_entry_cell], "fire_entry")
						check(fire_applied, "natural worker movement into an armed fire cell applies: " + last_action_reason)
	# Каждый цикл содержит живое действие игрока и настоящий end_player_turn;
	# встроенный _process исполняет AI, worker и playback без custom_step/skip.
	for round_index: int in rounds:
		if session == null or demo.session == null: break
		trace_phase = "player_round_%d" % (round_index + 1)
		var action_ok := await _perform_player_action()
		check(action_ok, "round %d contains an applied live movement or attack: %s" % [round_index + 1, last_action_reason])
		var end_turn_ok := await _execute_live(&"end_player_turn", [], "end_player_turn")
		check(end_turn_ok, "round %d dispatches a natural end-player-turn worker: %s" % [round_index + 1, last_action_reason])
		if not end_turn_ok: break
		var phase_ok := await _wait_for_player_turn(90000)
		check(phase_ok, "round %d completes enemy AI, DOT, environment and presentation" % (round_index + 1))
		if not phase_ok: break
		if round_index == 0:
			check(status_damage_target_ids.size() >= 20, "first full cycle records DOT damage on at least 20 unique targets")
		if session == null: break
		_record_round_lifecycle(session.round_number)
		check(session.last_receipt != null and session.phase == BattleTacticalSession.Phase.PLAYER_TURN,
			"round %d returns to player input with a final command receipt" % (round_index + 1))
	# Сохраняем измеренный префикс до освобождения сцены, чтобы отчёт описывал тот же rendered бой.
	check(session != null and session.round_number >= started_round + 2,
		"at least two complete player/enemy turn cycles finished")
	if requested_unit_count >= 32 and session != null:
		check(minimum_alive_count >= 24,
			"32-unit soak retains at least 24 living combatants throughout the measured run")
	check(applied_command_count >= 3, "soak recorded applied worker commands")
	check(mass_dot_count > 0, "real turn receipts contain mass DOT damage events")
	check(environment_damage_count > 0 or environment_cleanup_count > 0,
		"natural receipts contain fire entry damage or environment cleanup")
	check(not demo.is_execution_pending() and not demo.is_presentation_pending(), "EOF has no pending worker or natural playback")
	var final_state := _live_summary()
	metrics["scenario"] = "rendered %d-unit expedition DOT and environment soak" % requested_unit_count
	metrics["seed"] = 9404
	metrics["board"] = {"width": WIDTH, "height": HEIGHT, "initial_live_units": requested_unit_count,
		"fire_cells": session.state.environment.fires.size() if session != null else FIRE_CELL_COUNT,
		"valid_dot_units": _valid_status_count() if session != null else 0, "warning_cell": warning_cell}
	metrics["initial_units"] = requested_unit_count
	metrics["minimum_alive"] = minimum_alive_count
	metrics["arguments"] = {"rounds": rounds, "idle_frames": idle_frames, "units": requested_unit_count, "uncapped": uncapped}
	metrics["runtime"] = _runtime_metadata()
	metrics["startup_frames"] = _timing_summary(startup_frame_ms)
	metrics["steady_idle_frames"] = _timing_summary(steady_idle_frame_ms)
	metrics["combat_frames"] = _timing_summary(combat_frame_ms)
	metrics["test_planning_frames"] = _timing_summary(test_planning_frame_ms)
	metrics["round_lifecycle"] = round_lifecycle
	metrics["actions"] = action_metrics
	metrics["frame_trace"] = soak_trace
	metrics["window_focus_coverage"] = _window_focus_coverage()
	metrics["hardware_input_counts"] = input_guard.event_counts.duplicate(true) if input_guard != null else {}
	metrics["view_state"] = {"initial": initial_view_state, "final": _view_state_snapshot()}
	metrics["receipts"] = {"applied_commands": applied_command_count, "receipt_steps": receipt_step_count,
		"dot_damage_events": mass_dot_count, "dot_targets": status_damage_target_ids.size(),
		"fire_entry_damage_events": environment_damage_count, "environment_cleanup_events": environment_cleanup_count}
	metrics["final_projection"] = final_state
	metrics["diagnostic_only"] = true
	metrics["limits"] = "Rendered local run; timing is diagnostic and machine/renderer dependent. Statuses and fire are seeded once before display; combat thereafter changes only through session commands and demo worker/AI. Test planning runs synchronous path and command admission oracles, is included in the global trace and reported in its own bucket; hardware UI input is counted and consumed by a root guard."
	_write_soak_report()
	if process_frame.is_connected(_on_process_frame): process_frame.disconnect(_on_process_frame)
	if demo != null:
		demo.set_process(false)
		demo.queue_free()
	if session != null: session.close()
	await process_frame
	print("BATTLE SOAK PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _prepare_soak_state() -> void:
	var source := DamageSource.new(&"mage", 26, Vector2i(-1, -1)).to_dict()
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 10000.0)
		unit.vitals.set_hp(10000.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 10000.0)
		unit.vitals.set_balance(10000.0)
		unit.guard_stance = false
		if unit.elemental == null: unit.elemental = ElementalState.new()
		var elemental := ElementalState.new()
		elemental.authored = true
		if unit.id % 2 == 0:
			var burning: Dictionary = ElementalRules.transition(elemental.to_dict(), &"burning", 1, source).after
			unit.elemental = ElementalState.from_dict(burning)
		else:
			var poison: Dictionary = ElementalRules.transition(elemental.to_dict(), &"poison", 1, source).after
			unit.elemental = ElementalState.from_dict(poison)
	var board := session.board
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			if session.state.environment.fires.size() >= FIRE_CELL_COUNT: break
			if board.get_terrain(cell) != TerrainType.Type.FLOOR or board.is_lethal(cell): continue
			if not session.state.environment.fire_at(cell).is_empty(): continue
			if session.state.environment.ignite(cell, "bleeding").is_empty(): continue
		if session.state.environment.fires.size() >= FIRE_CELL_COUNT: break
	var warning_turn: int = maxi(1, int(session.state.environment.collapse.get("turn", 0)))
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			if board.get_terrain(cell) == TerrainType.Type.FLOOR and not board.is_occupied(cell) \
				and session.state.environment.fire_at(cell).is_empty():
				warning_cell = cell
				session.state.environment.collapse = {"turn": warning_turn, "marked": [cell]}
				return

func _rebalance_factions(value: BattleCoreReactionsSession) -> String:
	# Дополнительные игроки занимают клетки расстановки до штатного refill.
	var converted := 0
	var player_target: int = floori(float(requested_unit_count) / 2.0)
	var required_conversions := player_target - value.living_ids(Faction.Type.PLAYER).size()
	for index: int in range(7, value.units.size()):
		if converted >= required_conversions: break
		var unit: UnitState = value.units[index]
		if unit.id == stress_target_id or unit.faction != Faction.Type.ENEMY: continue
		var cell := _find_player_deployment_cell(value)
		if cell.x < 0: return "not enough legal player deployment cells for cloned actors"
		unit.faction = Faction.Type.PLAYER
		if not value.board.move_unit(unit, cell): return "BattleBoard refused a cloned player's setup position"
		converted += 1
	if converted != required_conversions:
		return "converted %d enemy clones instead of %d" % [converted, required_conversions]
	value._enemy_ids = value.living_ids(Faction.Type.ENEMY)
	if value.living_ids(Faction.Type.PLAYER).size() != player_target or value.living_ids(Faction.Type.ENEMY).size() != player_target:
		return "fixture faction split is not %d/%d" % [player_target, player_target]
	for unit: UnitState in value.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 10000.0)
		unit.vitals.set_hp(10000.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 10000.0)
		unit.vitals.set_balance(10000.0)
	if not value._refill(Faction.Type.ENEMY): return "native enemy refill failed: " + value.phase_text()
	if not value._refill(Faction.Type.PLAYER): return "native player refill failed: " + value.phase_text()
	value.selected_id = stress_actor_id
	if not value.select_unit(stress_actor_id): return "original stress actor could not be reselected after refill"
	value._setup_revision = value.context.get_revision()
	if value.state.deck != null and not MageDeckRules.references_valid(value.context):
		return "balanced player clones invalidated mage deck bindings"
	return ""

func _expand_roster(value: BattleCoreReactionsSession) -> String:
	if value.units.size() > requested_unit_count: return "factory roster exceeds requested unit count"
	if value.units.size() == requested_unit_count: return ""
	var enemy_source: UnitState
	for unit: UnitState in value.units:
		if unit.faction == Faction.Type.ENEMY:
			enemy_source = unit
			break
	if enemy_source == null: return "no enemy exemplar for roster expansion"
	var owners := value.state.get_owners()
	var inventories := value.state.get_inventories()
	var equipment := value.state.get_equipment_facades()
	while value.units.size() < requested_unit_count:
		var stress_target := value.board.get_unit_by_id(stress_target_id)
		if stress_target == null: return "original stress target disappeared during roster expansion"
		var cell := _find_free_cell(value, stress_target.cell)
		if cell.x < 0: return "no legal board cell for requested extra unit"
		if _clone_unit(enemy_source, cell, owners, inventories, equipment, value) == null:
			return "unit clone rejected while expanding roster"
	value.state = _replace_state(value.state, owners, inventories, equipment)
	var ids: Array[int] = []
	for unit: UnitState in value.units: ids.append(unit.id)
	var pairs: Array[Dictionary] = []
	for actor_id: int in ids:
		for target_id: int in ids:
			if actor_id != target_id: pairs.append({"actor_unit_id": actor_id, "target_unit_id": target_id})
	var prior_rules := value.context.get_attack_rules()
	value.context = ActionContext.new(value.state, value.context.get_rng(), value.context.get_sink(),
		value.context.get_unsupported_runtime_ids(), MoveRules.new(ids, 1, &"spatial_move_v1"),
		AttackRules.new(ids, pairs, prior_rules.get_definitions()))
	value._enemy_ids = value.living_ids(Faction.Type.ENEMY)
	value._setup_revision = value.context.get_revision()
	if value.state.deck != null and not MageDeckRules.references_valid(value.context):
		return "mage deck audit rejected expanded roster"
	return ""

func _find_player_deployment_cell(value: BattleCoreReactionsSession) -> Vector2i:
	for y: int in range(2, 6):
		for x: int in 6:
			var cell := Vector2i(x, y)
			if value.board.is_terrain_walkable(cell) and not value.board.is_lethal(cell) \
				and not value.board.is_occupied(cell) and value.state.environment.fire_at(cell).is_empty():
				return cell
	return Vector2i(-1, -1)

func _fixture_validity_reason() -> String:
	if not CombatEnvironmentState.valid(session.state.environment.to_dict()): return "environment schema rejected fixture"
	for unit: UnitState in session.units:
		if unit.elemental == null or not ElementalState.valid(unit.elemental.to_dict()):
			return "elemental schema rejected unit %d" % unit.id
	var snapshot := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	if snapshot.code != ItemSnapshotResult.Code.OK or snapshot.snapshot == null:
		return "snapshot code %d: %s" % [snapshot.code, snapshot.reason]
	if not MageDeckRules.references_valid(session.context): return "mage deck reference audit rejected fixture"
	return ""

func _valid_status_count() -> int:
	if session == null: return 0
	var count := 0
	for unit: UnitState in session.units:
		if unit.is_alive() and unit.elemental != null and ElementalState.valid(unit.elemental.to_dict()):
			if unit.elemental.burning_ticks > 0 or unit.elemental.poison_ticks > 0: count += 1
	return count

func _find_fire_entry_candidate() -> Vector2i:
	if session == null: return Vector2i(-1, -1)
	var actor := session.board.get_unit_by_id(stress_actor_id)
	if actor == null: return Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var cell := actor.cell + offset
		if not session.board.is_in_bounds(cell) or session.board.get_terrain(cell) != TerrainType.Type.FLOOR: continue
		if session.board.is_occupied(cell) or session.path_to(cell).size() < 2: continue
		if session.state.environment.fire_at(cell).is_empty():
			# В fixture до показа переносим fire record на соседнюю клетку маршрута.
			var fire: Dictionary = session.state.environment.fires.back()
			fire.cell = cell
			return cell
	return Vector2i(-1, -1)

func _perform_player_action() -> bool:
	if session == null: return false
	trace_bucket = "test_planning"
	trace_phase = "test_planning"
	last_action_reason = "no player actor has an admitted main action"
	for actor: UnitState in session.units:
		if actor.faction != Faction.Type.PLAYER or not actor.is_alive() or actor.action_resources == null \
			or actor.action_resources.get_main_left() <= 0 or ControlRules.action_reason(actor) != &"": continue
		trace_phase = "test_planning"
		if not session.select_unit(actor.id):
			last_action_reason = "select_unit rejected %d" % actor.id
			continue
		for enemy: UnitState in session.units:
			if enemy.faction != Faction.Type.ENEMY or not enemy.is_alive(): continue
			if AttackReachCheck.inspect_spatial(session.board, actor, enemy,
				actor.stats.get_value(StatTypes.StatType.ATTACK_RANGE)) != &"":
				await process_frame
				continue
			var attack: AttackCommand = session._command_for(enemy.id)
			if attack == null:
				await process_frame
				continue
			var attack_reason := attack.validate(session.context)
			if attack_reason != &"":
				last_action_reason = "attack %d: %s" % [enemy.id, String(attack_reason)]
				await process_frame
				continue
			await process_frame
			var hp_before := enemy.vitals.get_hp()
			var attacked := await _execute_live(&"attack_unit", [enemy.id], "attack")
			if not attacked: return false
			var target := session.board.get_unit_by_id(enemy.id)
			return target != null and target.vitals.get_hp() < hp_before
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var cell := actor.cell + offset
			if not session.board.is_in_bounds(cell) or session.board.is_occupied(cell) \
				or not session.board.is_terrain_walkable(cell) or session.board.is_lethal(cell): continue
			var path := session.path_to(cell)
			await process_frame
			if path.size() < 2: continue
			var movement := MoveCommand.new(actor.id, path, session.context.get_revision())
			var move_reason := movement.validate(session.context)
			await process_frame
			if move_reason != &"":
				last_action_reason = "move %s: %s" % [cell, String(move_reason)]
				continue
			return await _execute_live(&"move_to", [cell], "move")
	trace_phase = "test_planning"
	await process_frame
	return false

func _execute_live(method: StringName, args: Array, phase_label: String) -> bool:
	if session == null or demo.session == null or demo.is_execution_pending(): return false
	trace_bucket = "combat"
	trace_phase = "dispatch_" + phase_label
	var start_frame := Engine.get_process_frames()
	var trace_start := soak_trace.size()
	var dispatch_started := Time.get_ticks_usec()
	demo._execute_live(method, args)
	var dispatch_ms := float(Time.get_ticks_usec() - dispatch_started) / 1000.0
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if not demo.is_execution_pending(): break
		trace_phase = "worker" if demo._execution_worker.is_started() else "presentation"
		await process_frame
	check(Engine.get_process_frames() > start_frame, phase_label + " advanced natural rendered frames")
	var elapsed: Array[float] = []
	for index: int in range(trace_start, soak_trace.size()): elapsed.append(float(soak_trace[index]["ms"]))
	if not elapsed.is_empty(): action_metrics.append({"phase": phase_label, "timing": _timing_summary(elapsed),
		"dispatch_ms": dispatch_ms, "frame_count": elapsed.size(), "trace_start": trace_start})
	if not demo.is_execution_pending() and demo.session != null:
		session = demo.session as BattleCoreReactionsSession
		_collect_receipt_metrics(session)
	var applied := not demo.is_execution_pending() and session != null and session.last_receipt != null \
		and session.last_receipt.status == ActionReceipt.APPLIED
	if not applied and session != null and session.last_receipt != null:
		last_action_reason = String(session.last_receipt.reason)
	return applied

func _wait_for_player_turn(timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not demo.is_execution_pending() and demo.session != null:
			session = demo.session as BattleCoreReactionsSession
			_collect_receipt_metrics(session)
			if session != null and session.phase == BattleTacticalSession.Phase.PLAYER_TURN: return true
		trace_bucket = "combat"
		trace_phase = "ai_or_refresh"
		await process_frame
	return false

func _sample_idle(_metric_name: String, frames: int, bucket: String) -> void:
	trace_bucket = bucket
	trace_phase = bucket
	for _index: int in frames: await process_frame
	trace_bucket = "combat"
	trace_phase = "test_planning"

func _timing_summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {"samples": 0}
	var summary := _summarize(samples)
	summary["p50_ms"] = summary.get("median_ms", 0.0)
	return summary

func _on_process_frame() -> void:
	var now_usec := Time.get_ticks_usec()
	var elapsed_ms := float(now_usec - previous_frame_usec) / 1000.0
	previous_frame_usec = now_usec
	if not is_finite(elapsed_ms) or elapsed_ms < 0.0: return
	match trace_bucket:
		"startup_frames": startup_frame_ms.append(elapsed_ms)
		"steady_idle_frames": steady_idle_frame_ms.append(elapsed_ms)
		"test_planning": test_planning_frame_ms.append(elapsed_ms)
		_: combat_frame_ms.append(elapsed_ms)
	var round_number := last_round
	var alive := last_alive.duplicate(true)
	var window_focused: bool = false
	var window_focus_available: bool = DisplayServer.get_name() != "headless"
	if window_focus_available:
		window_focused = root.has_focus()
	if demo != null and demo.session != null:
		var active := demo.session as BattleCoreReactionsSession
		if active != null:
			_collect_receipt_metrics(active)
			# UI очищает turn_events при refresh; читаем принадлежащую сессии проекцию до этого шага.
			for event: Dictionary in active.turn_events: _count_event_metrics(event)
			round_number = active.round_number
			alive = {"player": active.living_ids(Faction.Type.PLAYER).size(), "enemy": active.living_ids(Faction.Type.ENEMY).size()}
			minimum_alive_count = mini(minimum_alive_count, int(alive.player) + int(alive.enemy))
			last_round = round_number
			last_alive = alive.duplicate(true)
	soak_trace.append({"process_frame": Engine.get_process_frames(), "ms": elapsed_ms, "phase": trace_phase,
		"bucket": trace_bucket, "window_focused": window_focused,
		"window_focus_available": window_focus_available,
		"round": round_number, "alive": alive, "receipt_steps": receipt_step_count})

func _window_focus_coverage() -> Dictionary:
	var coverage := {
		"startup_frames": {"samples": 0, "focused": 0, "unfocused": 0, "unavailable": 0},
		"steady_idle_frames": {"samples": 0, "focused": 0, "unfocused": 0, "unavailable": 0},
		"test_planning": {"samples": 0, "focused": 0, "unfocused": 0, "unavailable": 0},
		"combat": {"samples": 0, "focused": 0, "unfocused": 0, "unavailable": 0},
	}
	for sample: Dictionary in soak_trace:
		var bucket: String = str(sample.get("bucket", ""))
		if not coverage.has(bucket):
			continue
		var entry: Dictionary = coverage[bucket]
		entry["samples"] = int(entry["samples"]) + 1
		if not bool(sample.get("window_focus_available", false)):
			entry["unavailable"] = int(entry["unavailable"]) + 1
		elif bool(sample.get("window_focused", false)):
			entry["focused"] = int(entry["focused"]) + 1
		else:
			entry["unfocused"] = int(entry["unfocused"]) + 1
	return coverage

func _collect_receipt_metrics(active: BattleCoreReactionsSession) -> void:
	if active == null or active.last_receipt == null: return
	var receipt := active.last_receipt
	var receipt_id := receipt.get_instance_id()
	if seen_receipt_ids.has(receipt_id): return
	seen_receipt_ids[receipt_id] = true
	if receipt.status != ActionReceipt.APPLIED: return
	applied_command_count += 1
	receipt_step_count += receipt.get_steps().size()
	for event: Dictionary in receipt.get_events(): _count_event_metrics(event)

func _count_event_metrics(event: Dictionary) -> void:
	var event_seq: int = int(event.get("event_seq", 0))
	if event_seq > 0:
		if seen_event_sequences.has(event_seq): return
		seen_event_sequences[event_seq] = true
	if event.get("kind") == &"hit_resolved":
		var source: Dictionary = event.get("source", {})
		if source.get("kind") in [&"status", &"status_snapshot"]:
			mass_dot_count += 1
			status_damage_target_ids[int(event.get("target_unit_id", UnitId.NONE))] = true
		if source.get("kind") == &"cell": environment_damage_count += 1
	if event.get("kind") in [&"support_collapsed", &"corpse_created", &"fire_removed", &"environment_cleanup"]:
		environment_cleanup_count += 1

func _alive_counts() -> Dictionary:
	return {"player": session.living_ids(Faction.Type.PLAYER).size(), "enemy": session.living_ids(Faction.Type.ENEMY).size()}

func _record_round_lifecycle(round_number: int) -> void:
	if session == null or demo.board_view == null: return
	var ids := _living_visual_instance_ids(demo.board_view)
	var counts := demo.board_view.visual_lifecycle_counts()
	var previous_ids: Dictionary = round_lifecycle.back().get("visual_ids", {}) if not round_lifecycle.is_empty() else ids
	var shared_ids_retained := true
	for id: int in ids:
		if previous_ids.has(id) and previous_ids[id] != ids[id]: shared_ids_retained = false
	check(shared_ids_retained, "living visual instance IDs are retained through round %d" % round_number)
	round_lifecycle.append({"round": round_number, "alive": _alive_counts(), "visual_ids": ids,
		"visual_lifecycle": counts, "receipt_steps": receipt_step_count})

func _living_visual_instance_ids(board: BattleDemoBoard) -> Dictionary:
	var ids: Dictionary = {}
	for id: int in session.living_ids(Faction.Type.PLAYER) + session.living_ids(Faction.Type.ENEMY):
		if board._unit_visuals.has(id): ids[id] = board._unit_visuals[id].get_instance_id()
	return ids

func _live_summary() -> Dictionary:
	if demo == null or demo.session == null: return {"available": false}
	var live := demo.session as BattleCoreReactionsSession
	if live == null: return {"available": false}
	return {"round": live.round_number, "phase": live.phase, "alive": _alive_counts(),
		"fire_cells": live.state.environment.fires.size(), "valid_dot_units": _valid_status_count(),
		"pending_worker": demo.is_execution_pending(), "pending_presentation": demo.is_presentation_pending()}

func _write_soak_report() -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		check(false, "machine-readable soak report opens in user data directory")
		return
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "diagnostic_only": true, "measurements": metrics}, "\t"))
	file.close()

func _view_state_snapshot() -> Dictionary:
	if demo == null or demo.board_view == null: return {"available": false}
	var board: BattleDemoBoard = demo.board_view
	var view_rect := board.get_viewport_rect()
	return {"viewport_size": [view_rect.size.x, view_rect.size.y],
		"board_size": [board.size.x, board.size.y], "camera_zoom": board.camera_view.zoom,
		"camera_offset": [board.camera_view.offset.x, board.camera_view.offset.y],
		"display": _display_metadata()}

func _argument_int(args: PackedStringArray, name: String, fallback: int, minimum: int, maximum: int) -> int:
	for index: int in args.size():
		var argument: String = args[index]
		if argument.begins_with(name + "="):
			var parsed := argument.trim_prefix(name + "=").to_int()
			return clampi(parsed, minimum, maximum)
		if argument == name and index + 1 < args.size(): return clampi(args[index + 1].to_int(), minimum, maximum)
	return fallback
