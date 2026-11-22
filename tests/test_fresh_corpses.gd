extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL FRESH CORPSES: " + label)

func _run() -> void:
	_test_lifecycle_and_snapshot()
	await _test_queued_deaths_and_raise()
	await _test_refill_age_boundary()
	print("FRESH CORPSES RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_lifecycle_and_snapshot() -> void:
	var environment := CombatEnvironmentState.new()
	var fresh := environment.record_death(880001, Vector2i(2, 3), Faction.Type.ENEMY, "humanoid")
	var bones := environment.record_death(880002, Vector2i(3, 3), Faction.Type.ENEMY, "humanoid", true, true)
	check(fresh.remains == "fresh" and fresh.fresh_turns_left == 3 and fresh.fresh_round_pending
		and bones.remains == "bones" and bones.fresh_turns_left == 0 and not bones.fresh_round_pending,
		"ordinary death starts fresh and undead death starts as bones")
	var snapshot := environment.to_dict()
	check(snapshot.schema_version == 6 and CombatEnvironmentState.valid(snapshot), "environment schema 6 accepts freshness records")
	var clone := CombatEnvironmentState.from_dict(snapshot)
	check(clone != null and clone.to_dict() == snapshot, "environment roundtrip preserves records exactly")
	var incomplete_age := clone.age_corpses()
	check(incomplete_age.is_empty() and clone.corpses[0].fresh_round_pending == false
		and clone.corpses[0].fresh_turns_left == 3 and environment.corpses[0].fresh_round_pending,
		"first age skips incomplete death round and clone is isolated")
	var aged := clone.age_corpses()
	check(aged.size() == 1 and clone.corpses[0].fresh_turns_left == 2, "first full round leaves two fresh turns")
	clone.age_corpses()
	check(clone.corpses[0].fresh_turns_left == 1 and clone.corpses[0].remains == "fresh", "second full round leaves one turn")
	clone.age_corpses()
	check(clone.corpses[0].fresh_turns_left == 0 and clone.corpses[0].remains == "bones",
		"third full round converts flesh to bones")
	var malformed := snapshot.duplicate(true)
	malformed.corpses[0].erase("fresh_round_pending")
	check(not CombatEnvironmentState.valid(malformed) and CombatEnvironmentState.from_dict(malformed) == null,
		"snapshot rejects a missing required pending flag")
	malformed = snapshot.duplicate(true)
	malformed.corpses[0].fresh_turns_left = 0
	check(not CombatEnvironmentState.valid(malformed), "fresh record rejects zero turns")
	malformed = snapshot.duplicate(true)
	malformed.corpses[1].fresh_turns_left = 1
	check(not CombatEnvironmentState.valid(malformed), "bones reject nonzero freshness")
	malformed = snapshot.duplicate(true)
	malformed.corpses[1].fresh_round_pending = true
	check(not CombatEnvironmentState.valid(malformed), "bones reject pending freshness")
	for invalid_turns: int in [1, 2]:
		malformed = snapshot.duplicate(true)
		malformed.corpses[0].fresh_turns_left = invalid_turns
		check(not CombatEnvironmentState.valid(malformed), "pending fresh corpse requires all three turns")

func _test_queued_deaths_and_raise() -> void:
	var session := PlayerTurnFixture.create()
	session.state.environment = CombatEnvironmentState.new()
	var living := session.units[1]
	living.creature_kind = &"living"
	var living_receipt := session._queue.submit(DeathCommand.new(living.id,
		DamageSource.new(&"test", 0, living.cell)), session.context)
	var living_corpse := _corpse_event(living_receipt)
	check(living_receipt.status == ActionReceipt.APPLIED and living_corpse.get("remains") == "fresh"
		and living_corpse.get("fresh_turns_left") == 3, "queued ordinary death creates a fresh record")
	var undead := session.units[5]
	var actor: UnitState = session.units[0]
	var raise_cell := _move_to_neighbor(session, actor, undead)
	check(raise_cell.x >= 0, "raising fixture places an undead death beside its actor")
	if raise_cell.x < 0:
		session.close(); await process_frame; return
	undead.creature_kind = &"undead"
	var undead_receipt := session._queue.submit(DeathCommand.new(undead.id,
		DamageSource.new(&"test", 0, raise_cell)), session.context)
	var undead_corpse := _corpse_event(undead_receipt)
	check(undead_receipt.status == ActionReceipt.APPLIED and undead_corpse.get("remains") == "bones"
		and undead_corpse.get("fresh_turns_left") == 0, "queued undead death creates bones immediately")
	var helper := UseSummoningItemCommand.make_helper(UseSummoningItemCommand.next_id(session.board), Faction.Type.PLAYER,
		Vector2i(7, 7), "Помощник")
	check(helper != null and helper.creature_kind == &"living", "unraised summoning item helper remains living")
	var raise := RaiseCorpseCommand.new(actor.id, int(undead_corpse.get("id", 0)), session.context.get_revision())
	var preview := ForecastSimulation.run(session.context, session._queue, raise)
	check(preview.status == ActionReceipt.APPLIED and session.state.environment.corpses_at(raise_cell).size() == 1,
		"preview accepts raising an actual queued bones record without consuming it")
	var raised := session._queue.submit(raise, session.context)
	var helper_unit: UnitState = null
	for unit: UnitState in session.board.get_all_units():
		if unit.id > 0 and unit.creature_kind == &"undead" and session.state.is_summon(unit.id): helper_unit = unit
	check(raised.status == ActionReceipt.APPLIED and session.state.environment.corpses_at(raise_cell).is_empty()
		and helper_unit != null, "live raising consumes bones and creates an undead summon")
	if helper_unit != null:
		var raised_death := session._queue.submit(DeathCommand.new(helper_unit.id,
			DamageSource.new(&"test", 0, helper_unit.cell)), session.context)
		var raised_bones := _corpse_event(raised_death)
		check(raised_bones.get("remains") == "bones" and raised_bones.get("fresh_turns_left") == 0,
			"queued death of the actual raised undead summon leaves bones")
	session.close()
	await process_frame

func _test_refill_age_boundary() -> void:
	var session := PlayerTurnFixture.create()
	session.state.environment = CombatEnvironmentState.new()
	var victim := session.units[5]
	var death := session._queue.submit(DeathCommand.new(victim.id,
		DamageSource.new(&"test", 0, victim.cell)), session.context)
	var corpse := _corpse_event(death)
	check(corpse.get("remains") == "fresh", "turn-boundary fixture records a real queued corpse")
	var enemies := _living_ids(session, Faction.Type.ENEMY)
	var players := _living_ids(session, Faction.Type.PLAYER)
	var enemy_refill := _refill(session, enemies, Faction.Type.ENEMY)
	check(enemy_refill.status == ActionReceipt.APPLIED and session.state.environment.corpses[0].fresh_turns_left == 3
		and session.state.environment.corpses[0].fresh_round_pending,
		"enemy refill does not age corpses when player is first team")
	check(_refill(session, players, Faction.Type.PLAYER).status == ActionReceipt.APPLIED and session.state.environment.corpses[0].fresh_turns_left == 3
		and not session.state.environment.corpses[0].fresh_round_pending, "first-team refill skips the incomplete death round")
	check(_refill(session, players, Faction.Type.PLAYER).status == ActionReceipt.APPLIED and session.state.environment.corpses[0].fresh_turns_left == 2,
		"next first-team refill ages one full round")
	check(_refill(session, enemies, Faction.Type.ENEMY).status == ActionReceipt.APPLIED and session.state.environment.corpses[0].fresh_turns_left == 2,
		"opposing-team refill leaves corpse age unchanged")
	check(_refill(session, players, Faction.Type.PLAYER).status == ActionReceipt.APPLIED and session.state.environment.corpses[0].fresh_turns_left == 1,
		"second full first-team round decrements freshness")
	check(_refill(session, players, Faction.Type.PLAYER).status == ActionReceipt.APPLIED and session.state.environment.corpses[0].remains == "bones"
		and session.state.environment.corpses[0].fresh_turns_left == 0, "third full first-team round turns corpse to bones")
	session.close()
	await process_frame

func _living_ids(session: BattleCoreReactionsSession, faction: Faction.Type) -> Array[int]:
	var result: Array[int] = []
	for unit: UnitState in session.board.get_all_units():
		if unit.is_alive() and unit.faction == faction: result.append(unit.id)
	return result

func _refill(session: BattleCoreReactionsSession, ids: Array[int], faction: Faction.Type) -> ActionReceipt:
	return session._queue.submit(BattleTurnRefill.new(ids, session.context.get_revision(), faction), session.context)

func _corpse_event(receipt: ActionReceipt) -> Dictionary:
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"corpse_created": return event.get("corpse", {})
	return {}

func _move_to_neighbor(session: BattleCoreReactionsSession, actor: UnitState, unit: UnitState) -> Vector2i:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var cell := actor.cell + direction
		if not session.board.is_in_bounds(cell) or session.board.occupant_at(cell) != null: continue
		session.board.set_terrain(cell, TerrainType.Type.FLOOR)
		session.board.set_height_steps(cell, session.board.get_height_steps(actor.cell))
		if session.board.is_terrain_walkable(cell) and session.board.move_unit(unit, cell): return cell
	return Vector2i(-1, -1)
