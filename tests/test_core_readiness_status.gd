extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_team_status_boundary()
	_test_expiry_callback_fault()
	_test_real_collision_shatter()
	_test_real_fall_shatter_after_collision()
	print("CORE READINESS STATUS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_team_status_boundary() -> void:
	var session := _fixture()
	var bleeding_unit: UnitState = session.units[3]
	var burning_unit: UnitState = session.units[5]
	bleeding_unit.elemental.wet_turns = 2
	bleeding_unit.elemental.frozen_turns = 2
	bleeding_unit.control.stunned_turns = 1
	bleeding_unit.control.entangled_turns = 1
	_bleed(session, bleeding_unit, 2, 1)
	burning_unit.elemental.burning_stacks = 1
	burning_unit.elemental.burning_ticks = 2
	burning_unit.elemental.burning_source = DamageSource.new(&"attack", 0, session.units[0].cell, session.units[0].id, session.units[0].id).to_dict()
	var enemy_hp := bleeding_unit.vitals.get_hp()
	var expiry_reason := ControlTurnEndCommand.new(Faction.Type.PLAYER, session.context.get_revision()).validate(session.context)
	var before_enemy_boundary := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var boundary_forecast := TurnForecast.build(session)
	_check(boundary_forecast.status == ActionReceipt.APPLIED and boundary_forecast.phase_after == BattleTacticalSession.Phase.ENEMY_TURN and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before_enemy_boundary, "enemy boundary forecast applies in isolation")
	var entered_enemy := session.end_player_turn()
	_check(expiry_reason == &"" and entered_enemy and session.phase == BattleTacticalSession.Phase.ENEMY_TURN, "player completion enters enemy turn: " + String(expiry_reason))
	if not entered_enemy:
		session.close()
		return
	_check(bleeding_unit.bleeding.ticks_left == 0 and bleeding_unit.vitals.get_hp() == enemy_hp - 2.0, "enemy start runs cell, burning, then bleeding status stages")
	_check(burning_unit.elemental.burning_ticks == 1 and burning_unit.vitals.get_hp() == 99.0, "enemy start applies one burning tick")
	_check(bleeding_unit.elemental.wet_turns == 2 and bleeding_unit.elemental.frozen_turns == 2 and bleeding_unit.control.stunned_turns == 1, "duration remains until the target team's end boundary")
	_check(boundary_forecast.events == session.turn_events + session.last_receipt.get_events() and boundary_forecast.steps.size() > 0, "enemy boundary forecast events match live receipts and trace contains steps")
	_check(boundary_forecast.snapshot_after == ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() and boundary_forecast.rng_after == session.context.get_rng().to_dict() and boundary_forecast.counters_after == session.context.simulation_counters(), "enemy boundary forecast matches live snapshot, RNG, and counters")
	# Фикстура пропускает выбор ИИ: проверяется только реальная граница команды.
	session._enemy_ids.clear()
	session.step_enemy()
	_check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN, "empty enemy phase returns through the team boundary")
	_check(bleeding_unit.elemental.wet_turns == 1 and bleeding_unit.elemental.frozen_turns == 1, "enemy end boundary expires wet and frozen duration")
	_check(bleeding_unit.control.stunned_turns == 0 and bleeding_unit.control.entangled_turns == 0, "enemy end boundary expires legacy control alongside elemental duration")
	var old_environment_turn: int = session.state.environment.collapse["turn"]
	var before_boundary := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	_check(session.end_player_turn() and session.phase == BattleTacticalSession.Phase.ENEMY_TURN, "second player completion crosses the round boundary")
	_check(session.state.environment.collapse["turn"] == old_environment_turn + 1, "player completion runs environment before the next enemy refill")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() != before_boundary, "round boundary advances captured battle state")
	var post_boundary := ItemSimulationSnapshot.capture(session.state, [])
	var parsed: ItemSnapshotResult = ItemSimulationSnapshot.from_dict(post_boundary.snapshot.to_dict()) if post_boundary.snapshot != null else ItemSnapshotResult.new()
	_check(parsed.code == ItemSnapshotResult.Code.OK, "post-boundary status snapshot restores")
	if parsed.code == ItemSnapshotResult.Code.OK:
		var state_result := parsed.snapshot.instantiate(_definitions(session))
		_check(state_result.code == ItemSnapshotResult.Code.OK, "post-boundary status runtime instantiates")
		if state_result.state != null:
			var restored_unit := state_result.state.get_board().get_unit_by_id(bleeding_unit.id)
			_check(restored_unit.elemental != bleeding_unit.elemental and restored_unit.control != bleeding_unit.control and restored_unit.bleeding != bleeding_unit.bleeding, "restored status runtimes are detached")
			_check(restored_unit.elemental.to_dict() == bleeding_unit.elemental.to_dict() and restored_unit.control.to_dict() == bleeding_unit.control.to_dict(), "restored status values survive the command boundary")
			AttackForecast._close(state_result.state)
	session.close()

func _test_expiry_callback_fault() -> void:
	var session := _fixture()
	var owner := session.units[0]
	owner.elemental.wet_turns = 1
	var mutate_other_capability := func() -> void: owner.bleeding.immune = true
	owner.elemental.changed.connect(mutate_other_capability)
	var entered := session.end_player_turn()
	_check(not entered and session.phase == BattleTacticalSession.Phase.FAULTED, "elemental expiry callback faults the real turn boundary")
	_check(owner.elemental.wet_turns == 0 and owner.bleeding.immune, "fault retains the executed expiry prefix and callback mutation")
	_check(session.units[3].action_resources.get_main_left() == 10, "fault prevents incoming team refill after the status prefix")
	owner.elemental.changed.disconnect(mutate_other_capability)
	session.close()

func _test_real_collision_shatter() -> void:
	var session := _fixture()
	var attacker: UnitState = session.units[0]
	var target: UnitState = session.units[1]
	var frozen_middle: UnitState = session.units[2]
	var last: UnitState = session.units[5]
	for i: int in 6:
		var unit: UnitState = session.units[i]
		session.board.move_unit(unit, Vector2i(i, 0))
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	session.board.move_unit(attacker, Vector2i(1, 3))
	session.board.move_unit(target, Vector2i(2, 3))
	session.board.move_unit(frozen_middle, Vector2i(3, 3))
	session.board.move_unit(last, Vector2i(4, 3))
	frozen_middle.elemental.frozen_turns = 1
	frozen_middle.vitals._hp = 20.0
	var command := AttackCommand.new(attacker.id, target.id, attacker.cell, target.cell, &"demo_strike", session.context.get_revision())
	var forecast := AttackForecast.build(session.context, session._queue, command)
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	var restored := captured.snapshot.instantiate(_definitions(session)) if captured.code == ItemSnapshotResult.Code.OK else ItemSnapshotResult.new()
	var restored_forecast: AttackForecast
	if restored.code == ItemSnapshotResult.Code.OK:
		var restored_context := session.context.copy_for_simulation(restored.state, session.context.get_rng().clone())
		restored_forecast = AttackForecast.build(restored_context, session._queue.copy_for_simulation(), command)
		AttackForecast._close(restored.state)
	var receipt := session.attack_unit(target.id)
	var collision_shatter := false
	var collision_hp_without_shatter := -1
	for event: Dictionary in receipt.get_events():
		if event.get("kind") != &"hit_resolved" or int(event.get("target_unit_id", 0)) != frozen_middle.id: continue
		if event.get("source", {}).get("kind", &"") == &"collision":
			collision_shatter = bool(event.get("hit", {}).get("shattered", false))
			collision_hp_without_shatter = int(event.get("hit", {}).get("hp_without_shatter", -1))
	_check(receipt.status == ActionReceipt.APPLIED, "real chain collision command applies: " + String(receipt.reason))
	_check(collision_shatter and collision_hp_without_shatter == 8 and not frozen_middle.is_alive(), "real forced collision damage 12 shatters HP20 instead of leaving HP8")
	_check(session.state.environment.corpses_at(frozen_middle.cell).size() == 1 and session.board.occupant_at(frozen_middle.cell) == null and last.cell == Vector2i(5, 3), "collision shatter leaves one body and completes the forced chain")
	_check(restored_forecast != null and restored_forecast.status == ActionReceipt.APPLIED and forecast.status == ActionReceipt.APPLIED and restored_forecast.events == forecast.events and restored_forecast.steps == forecast.steps and restored_forecast.snapshot_after == forecast.snapshot_after and restored_forecast.rng_after == forecast.rng_after and restored_forecast.counters_after == forecast.counters_after, "restored collision command reproduces full forecast")
	_check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, "collision shatter forecast matches live state, events, steps, RNG, and counters")
	session.close()

func _test_real_fall_shatter_after_collision() -> void:
	var session := _fixture()
	var attacker: UnitState = session.units[0]
	var target: UnitState = session.units[1]
	var middle: UnitState = session.units[2]
	var frozen_terminal: UnitState = session.units[5]
	for i: int in 6:
		var unit: UnitState = session.units[i]
		session.board.move_unit(unit, Vector2i(i, 0))
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	session.board.move_unit(attacker, Vector2i(1, 3))
	session.board.move_unit(target, Vector2i(2, 3))
	session.board.move_unit(middle, Vector2i(3, 3))
	session.board.move_unit(frozen_terminal, Vector2i(4, 3))
	session.board.set_height_steps(Vector2i(5, 3), -2)
	frozen_terminal.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
	frozen_terminal.vitals._hp = 40.0
	frozen_terminal.elemental.frozen_turns = 1
	var forecast := session.preview_attack(target.id)
	var receipt := session.attack_unit(target.id)
	var collision_hp_after := -1
	var collision_shattered := false
	var fall_hp_without_shatter := -1
	var fall_shattered := false
	for event: Dictionary in receipt.get_events():
		if event.get("kind") != &"hit_resolved" or int(event.get("target_unit_id", 0)) != frozen_terminal.id: continue
		var source_kind: StringName = event.get("source", {}).get("kind", &"")
		if source_kind == &"collision":
			collision_hp_after = int(event["hit"]["hp_after"])
			collision_shattered = bool(event["hit"].get("shattered", false))
		if source_kind == &"fall":
			fall_hp_without_shatter = int(event.get("hit", {}).get("hp_without_shatter", -1))
			fall_shattered = bool(event.get("hit", {}).get("shattered", false))
	_check(receipt.status == ActionReceipt.APPLIED and forecast.status == ActionReceipt.APPLIED, "real forced fall command and forecast apply")
	_check(collision_hp_after == 31 and not collision_shattered, "collision leaves HP31 before the distinct fall hit")
	_check(fall_hp_without_shatter == 6 and fall_shattered and not frozen_terminal.is_alive(), "real two-step fall shatters frozen terminal instead of leaving HP6")
	_check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after, "real fall shatter forecast matches live result")
	session.close()

func _fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_height_steps(Vector2i(x, y), 0)
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	# Старый fixture проверяет прежний срез без capability K18.
	session.state.abilities = null
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	session.state.environment.fires.clear()
	for unit: UnitState in session.units:
		unit.elemental = ElementalState.new()
		if unit.control != null:
			unit.control.stunned_turns = 0
			unit.control.entangled_turns = 0
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
		if unit.is_alive():
			unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
			unit.vitals._hp = 100.0
			unit.action_resources._main_left = 10
			unit.move_points_left = 20.0
	session.board.move_unit(session.units[1], Vector2i(2, 2))
	session.board.move_unit(session.units[3], Vector2i(4, 2))
	session.board.move_unit(session.units[5], Vector2i(5, 2))
	return session

func _bleed(session: BattleCoreReactionsSession, unit: UnitState, stacks: int, ticks: int) -> void:
	unit.bleeding.stacks = stacks
	unit.bleeding.ticks_left = ticks
	unit.bleeding.source = DamageSource.new(&"attack", 0, session.units[0].cell, session.units[0].id, session.units[0].id).to_dict()
	unit.bleeding.hit_id = "readiness-status"

func _definitions(session: BattleCoreReactionsSession) -> Dictionary:
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for item: ItemInstance in owner._items.values():
			var definition := item.get_definition()
			if definition != null: definitions[definition.id] = definition
	return definitions

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: " + label)
