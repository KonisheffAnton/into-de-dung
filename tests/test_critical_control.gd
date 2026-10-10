extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CRITICAL CONTROL: " + label)

func _run() -> void:
	_test_formulas()
	_test_state()
	_test_session()
	_test_rejections_and_expiry()
	_test_blocked_push()
	_test_blocker_death_push()
	_test_snapshots()
	_test_hostile_callbacks()
	_test_limits()
	_test_contract_edges()
	_test_helper_backstab()
	print("Critical control: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_formulas() -> void:
	var plain := AttackDamageCalculation.calculate(8.0, 2.0, 0.0, true, 2, false, 50)
	var critical := AttackDamageCalculation.calculate(8.0, 2.0, 0.0, true, 2, false, 50, 2)
	check(plain.scaled == 17.0 and critical.scaled == 34.0, "height/backstab/critical 17/34")
	var extras: Array[Dictionary] = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "test", "factor_num": 1, "factor_den": 1}]
	var components := ArmorAttack.components(8.0, 2.0, 2, false, extras, 50, 2)
	check(components.size() == 2 and float(components[0]["numerator"]) / float(components[0]["denominator"]) == 34.0, "armor direct critical")
	check(components.size() == 2 and float(components[1]["numerator"]) / float(components[1]["denominator"]) == 24.0, "extra critical without backstab")
	check(ArmorAttack.components(8.0, 2.0, 2, false, extras, 50, 3).is_empty(), "invalid multiplier rejected")

func _test_state() -> void:
	var control := ControlState.new()
	control.stunned_turns = 1
	control.entangled_turns = 1
	check(ControlState.valid(control.to_dict()), "valid control DTO")
	var copied := ControlState.from_dict(control.to_dict())
	check(copied != control and copied.to_dict() == control.to_dict(), "control copied")
	var malformed := control.to_dict()
	malformed["foreign"] = 1
	check(not ControlState.valid(malformed), "extra control field rejected")
	var subclass := ControlState.new()
	check(subclass.get_script() == ControlState, "exact class")
	var unit := UnitState.new()
	unit.control = control
	check(ControlRules.action_reason(unit) == &"control/stunned", "stun blocks action")
	check(ControlRules.action_reason(unit, true) == &"control/stunned", "stun blocks movement")
	check(ControlRules.critical_target(unit), "two flags yield one critical")
	check(ControlRules.balance_maximum(unit, 5.0) == 10.0 and ControlRules.balance_maximum(unit, 0.0) == 0.0, "entangle doubles nonzero threshold")
	control.stunned_turns = 0
	check(ControlRules.action_reason(unit) == &"" and ControlRules.action_reason(unit, true) == &"control/entangled", "entangle only blocks movement")

func _test_session() -> void:
	var session := BattleControlSession.new()
	check(session.context.get_attack_rules().validate() == &"", "definition valid")
	check(session.units[0].cell == Vector2i(2, 2) and session.units[1].cell == Vector2i(3, 2), "front pair")
	check(session.units[2].cell == Vector2i(5, 4) and session.units[3].cell == Vector2i(4, 4), "rear pair")
	check(not AttackModifiers.is_backstab(session.units[0].cell, session.units[1].cell, session.units[1].faction), "front geometry")
	check(AttackModifiers.is_backstab(session.units[2].cell, session.units[3].cell, session.units[3].faction), "rear geometry")
	var snapshot := session.units[1].to_snapshot_dict()
	check(snapshot.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and UnitState.validate_snapshot_dict(snapshot), "schema nine control valid")
	var restored := UnitState.from_snapshot_dict(snapshot)
	check(restored != null and restored.control != session.units[1].control and restored.control.to_dict() == session.units[1].control.to_dict(), "unit control isolated")
	var invalid := snapshot.duplicate(true)
	invalid["control"]["stunned_turns"] = 2
	check(not UnitState.validate_snapshot_dict(invalid), "invalid control snapshot rejected")
	var attacker := session.units[0]
	var target := session.units[1]
	var command := AttackCommand.new(attacker.id, target.id, attacker.cell, target.cell, &"demo_strike", session.context.get_revision())
	var preview := AttackForecast.build(session.context, session._queue, command)
	check(preview.status == ActionReceipt.APPLIED, "critical preview applied")
	check(target.vitals.get_hp() == 32.0 and attacker.action_resources.get_main_left() == 1, "preview isolated")
	var receipt := session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.APPLIED, "critical live applied")
	check(preview.events == receipt.get_events(), "preview/live events equal")
	var attack_events: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"attacked")
	check(attack_events.size() == 1 and attack_events[0].get("modifiers") == {"backstab_percent": 0, "critical": true}, "front critical metadata")
	session.close()
	var rear := BattleControlSession.new()
	var rear_actor := rear.units[2]
	var rear_target := rear.units[3]
	var rear_command := AttackCommand.new(rear_actor.id, rear_target.id, rear_actor.cell, rear_target.cell, &"demo_strike", rear.context.get_revision())
	var rear_preview := AttackForecast.build(rear.context, rear._queue, rear_command)
	check(rear_preview.status == ActionReceipt.APPLIED, "rear preview applied")
	var rear_receipt := rear._queue.submit(rear_command, rear.context)
	check(rear_receipt.status == ActionReceipt.APPLIED, "rear live applied")
	check(rear_preview.events == rear_receipt.get_events(), "rear preview/live events equal")
	var rear_events := rear_receipt.get_events()
	var control_events: Array = rear_events.filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(control_events.size() == 1 and control_events[0].get("reason") == &"push", "push clears root")
	check(rear_target.control.entangled_turns == 0 and rear_target.cell != Vector2i(4, 4), "root cleared only after move")
	rear.close()

func _test_rejections_and_expiry() -> void:
	var session := BattleControlSession.new()
	var stunned := session.units[1]
	var rooted := session.units[3]
	var before_main := stunned.action_resources.get_main_left()
	var before_rng := session.context.get_rng().to_dict()
	var attack := AttackCommand.new(stunned.id, session.units[0].id, stunned.cell, session.units[0].cell, &"demo_strike", session.context.get_revision())
	check(attack.validate(session.context) == &"control/stunned", "stun blocks attack")
	check(GuardCommand.new(stunned.id, session.context.get_revision()).validate(session.context) == &"control/stunned", "stun blocks guard")
	check(RestoreArmorCommand.new(stunned.id, 20, session.context.get_revision()).validate(session.context) == &"control/stunned", "stun blocks restore")
	check(UseSummoningItemCommand.new(stunned.id, 1, stunned.cell + Vector2i(0, 1), session.context.get_revision()).validate(session.context) == &"control/stunned", "stun blocks summon")
	var move_path: Array[Vector2i] = [rooted.cell, rooted.cell + Vector2i(0, 1)]
	check(MoveCommand.new(rooted.id, move_path, session.context.get_revision()).validate(session.context) == &"control/entangled", "root blocks voluntary move")
	check(GuardCommand.new(rooted.id, session.context.get_revision()).validate(session.context) != &"control/entangled", "root permits nonmove")
	var rejected := session._queue.submit(attack, session.context)
	check(rejected.status == ActionReceipt.REJECTED and stunned.action_resources.get_main_left() == before_main and session.context.get_rng().to_dict() == before_rng, "rejected stun spends nothing")
	var player_end := session._queue.submit(ControlTurnEndCommand.new(Faction.Type.PLAYER, session.context.get_revision()), session.context)
	check(player_end.status == ActionReceipt.APPLIED and stunned.control.stunned_turns == 1 and rooted.control.entangled_turns == 1, "other team end does not expire")
	var enemy_end := session._queue.submit(ControlTurnEndCommand.new(Faction.Type.ENEMY, session.context.get_revision()), session.context)
	check(enemy_end.status == ActionReceipt.APPLIED and stunned.control.stunned_turns == 0 and rooted.control.entangled_turns == 0, "own team end expires")
	check(stunned.action_resources.get_main_left() == before_main, "expiry preserves resources")
	var expired: Array = enemy_end.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(expired.size() == 2 and expired[0]["target_unit_id"] < expired[1]["target_unit_id"], "expiry events sorted")
	session.close()

func _test_blocked_push() -> void:
	var session := BattleControlSession.new()
	var blocker := session.units[4]
	check(session.board.move_unit(blocker, Vector2i(3, 4)), "place collision blocker")
	var actor := session.units[2]
	var target := session.units[3]
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	var receipt := session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.APPLIED, "collision attack applied")
	check(target.cell == Vector2i(4, 4) and target.control.entangled_turns == 1, "collision without move retains root")
	var controls: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(controls.is_empty(), "collision emits no root clear")
	session.close()

func _test_blocker_death_push() -> void:
	var session := BattleControlSession.new()
	var blocker := session.units[4]
	check(session.board.move_unit(blocker, Vector2i(3, 4)), "place weak blocker")
	for item: ItemInstance in session.state.get_owner(blocker.id)._items.values():
		if item.get_definition().armor_max > 0: item.armor_remaining = 0
	blocker.vitals.set_hp(1.0)
	var actor := session.units[2]
	var target := session.units[3]
	var receipt := session._queue.submit(AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision()), session.context)
	check(receipt.status == ActionReceipt.APPLIED, "blocker death attack applied")
	check(not blocker.is_alive() and target.cell == Vector2i(3, 4) and target.control.entangled_turns == 0, "blocker death permits move and root clear")
	session.close()

func _test_snapshots() -> void:
	var session := BattleControlSession.new()
	var board_capture := SimulationSnapshot.capture_board(session.board, [])
	check(board_capture.code == BoardSnapshotResult.Code.OK, "board capture with control")
	if board_capture.code == BoardSnapshotResult.Code.OK:
		var restored_board := board_capture.snapshot.instantiate_board()
		check(restored_board != null and restored_board.get_unit_by_id(session.units[1].id).control.stunned_turns == 1, "board restore control")
		if restored_board != null: restored_board.resize(0, 0)
	var item_capture := ItemSimulationSnapshot.capture(session.state, [])
	check(item_capture.code == ItemSnapshotResult.Code.OK, "item capture with control")
	if item_capture.code == ItemSnapshotResult.Code.OK:
		var data := item_capture.snapshot.to_dict()
		var copied := ItemSimulationSnapshot.from_dict(data)
		check(copied.code == ItemSnapshotResult.Code.OK and copied.snapshot.canonical_bytes() == item_capture.snapshot.canonical_bytes(), "item canonical roundtrip")
		var bad := data.duplicate(true)
		bad["board_snapshot"]["board"]["units"][1]["control"]["stunned_turns"] = 2
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "item invalid control rejected")
		var downgrade := data.duplicate(true)
		downgrade["board_snapshot"]["board"]["units"][1]["schema_version"] = 5
		check(ItemSimulationSnapshot.from_dict(downgrade).code != ItemSnapshotResult.Code.OK, "control cannot downgrade")
	session.close()

func _test_hostile_callbacks() -> void:
	var moved := BattleControlSession.new()
	var target := moved.units[3]
	var move_callback := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == target: target.control.stunned_turns = 1
	moved.board.unit_position_changed.connect(move_callback)
	var actor := moved.units[2]
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", moved.context.get_revision())
	var receipt := moved._queue.submit(command, moved.context)
	check(receipt.status == ActionReceipt.FAULTED, "hostile move callback faults")
	var moves: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"moved")
	check(moves.size() == 1 and target.cell == Vector2i(3, 4) and target.control.entangled_turns == 1, "move prefix retained, root not cleared")
	moved.board.unit_position_changed.disconnect(move_callback)
	moved.close()
	var damaged := BattleControlSession.new()
	var hp_target := damaged.units[1]
	var hp_callback := func(_before: float, _after: float) -> void: hp_target.control.stunned_turns = 0
	hp_target.vitals.hp_changed.connect(hp_callback)
	var hp_actor := damaged.units[0]
	var hp_command := AttackCommand.new(hp_actor.id, hp_target.id, hp_actor.cell, hp_target.cell, &"demo_strike", damaged.context.get_revision())
	var hp_receipt := damaged._queue.submit(hp_command, damaged.context)
	check(hp_receipt.status == ActionReceipt.FAULTED, "hostile HP callback faults")
	check(hp_target.vitals.get_hp() < 32.0 and hp_actor.action_resources.get_main_left() == 0, "HP and payment prefix retained")
	hp_target.vitals.hp_changed.disconnect(hp_callback)
	damaged.close()

func _test_limits() -> void:
	var session := BattleControlSession.new()
	var actor := session.units[2]
	var target := session.units[3]
	var limited := ActionQueue.new(256, 1, 32)
	var receipt := limited.submit(AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision()), session.context)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"event_limit", "event limit faults")
	check(actor.action_resources.get_main_left() == 0, "event limit retains paid prefix")
	session.close()

class ForeignControl extends ControlState:
	pass

func _test_contract_edges() -> void:
	# Проверяем численные величины независимо: одинаковое ошибочное масштабирование
	# impact и порога могло бы сохранить исход толчка и пройти тест только позиции.
	for condition in [&"none", &"stun", &"root", &"both"]:
		var session := BattleControlSession.new()
		var actor := session.units[2]
		var target := session.units[3]
		target.control.stunned_turns = 1 if condition in [&"stun", &"both"] else 0
		target.control.entangled_turns = 1 if condition in [&"root", &"both"] else 0
		var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.canonical_bytes()
		var rng_before := session.context.get_rng().to_dict()
		var counters_before := session.context.simulation_counters()
		var id_before := UnitId.get_counter()
		var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
		var preview := AttackForecast.build(session.context, session._queue, command)
		check(preview.status == ActionReceipt.APPLIED, "condition preview " + String(condition))
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.canonical_bytes() == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before and UnitId.get_counter() == id_before, "full preview isolation " + String(condition))
		var receipt := session._queue.submit(command, session.context)
		check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after, "complete preview/live parity " + String(condition))
		var expected_impact := 5.0 if condition == &"none" else 10.0
		var expected_max := 10.0 if condition in [&"root", &"both"] else 5.0
		var balances: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"balance_changed")
		# При before=after=0 публикуется только balance_broken.
		if balances.is_empty(): balances = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"balance_broken")
		check(not balances.is_empty() and balances[0]["impact"] == expected_impact and balances[0]["balance_max"] == expected_max, "independent impact and threshold " + String(condition))
		var hits: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved" and event["source"]["kind"] == &"attack")
		if not hits.is_empty():
			var rows: Array = hits[0]["hit"]["rows"]
			var expected_physical: int = 15 if condition == &"none" else 30
			check(rows[0]["D"] == expected_physical, "direct multiplier once " + String(condition))
		else: check(false, "direct hit present")
		session.close()
	var wall := BattleControlSession.new()
	var wall_actor := wall.units[2]
	var wall_target := wall.units[3]
	wall.board.set_terrain(Vector2i(3, 4), TerrainType.Type.WALL)
	var wall_receipt := wall._queue.submit(AttackCommand.new(wall_actor.id, wall_target.id, wall_actor.cell, wall_target.cell, &"demo_strike", wall.context.get_revision()), wall.context)
	check(wall_receipt.status == ActionReceipt.APPLIED and wall_target.control.entangled_turns == 1 and wall_target.cell == Vector2i(4, 4), "wall does not clear roots")
	var collisions: Array = wall_receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved" and event["source"]["kind"] == &"collision")
	check(collisions.size() == 1 and collisions[0]["hit"]["rows"][0]["D"] == 10, "wall collision uses original B10 without rear/critical")
	wall.close()
	var resistant := BattleControlSession.new()
	var resistant_actor := resistant.units[2]
	var resistant_target := resistant.units[3]
	resistant_actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 3.0)
	var resisted := resistant._queue.submit(AttackCommand.new(resistant_actor.id, resistant_target.id, resistant_actor.cell, resistant_target.cell, &"demo_strike", resistant.context.get_revision()), resistant.context)
	check(resisted.status == ActionReceipt.APPLIED and resistant_target.cell == Vector2i(4, 4) and resistant_target.control.entangled_turns == 1 and resistant_target.vitals.get_balance() == 6.0, "impact6 stays below doubled threshold10")
	check(resistant_target.stats.get_base_value(StatTypes.StatType.BALANCE_MAX) == 5.0, "root never mutates base threshold")
	resistant.close()
	var legacy := BattleTacticalSession.new()
	var legacy_unit := legacy.units[0]
	legacy_unit.control = ControlState.new()
	legacy_unit.control.entangled_turns = 1
	check(legacy_unit.armor == null and legacy_unit.to_snapshot_dict().get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION, "control independent of armor")
	var independent := ItemSimulationSnapshot.capture(legacy.state, [])
	check(independent.code == ItemSnapshotResult.Code.OK, "item captures control without armor")
	check(legacy_unit.to_dict().is_empty(), "legacy exporter refuses losing control")
	legacy_unit.control = ForeignControl.new()
	check(ItemSimulationSnapshot.capture(legacy.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "foreign control is unsupported")
	legacy_unit.control = ControlState.new()
	legacy_unit.control.stunned_turns = 3
	check(ItemSimulationSnapshot.capture(legacy.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "raw malformed control is invalid")
	legacy.close()
	var gates := BattleEnvironmentSession.new()
	var gated_actor := gates.units[0]
	gated_actor.control = ControlState.new()
	gated_actor.control.stunned_turns = 1
	check(UseHealingItemCommand.new(gated_actor.id, 1, gates.context.get_revision()).validate(gates.context) == &"control/stunned", "stun blocks healing")
	check(RaiseCorpseCommand.new(gated_actor.id, 1, gates.context.get_revision()).validate(gates.context) == &"control/stunned", "stun blocks raising")
	gates.close()

func _test_helper_backstab() -> void:
	var session := BattleTacticalSession.new()
	var old_rules := session.context.get_attack_rules()
	var definition := old_rules.get_definition(&"demo_strike")
	definition.backstab_bonus_percent = 50
	session.context._attack_rules = AttackRules.new(old_rules._actors, old_rules._pairs, [definition])
	var owner := session.selected_unit()
	check(session.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "summon with backstab definition")
	var helper := session.state.active_summon(owner.id)
	if helper == null:
		check(false, "helper exists")
		session.close()
		return
	var enemy := session.units[1]
	check(session.board.move_unit(helper, Vector2i(2, 4)) and session.board.move_unit(enemy, Vector2i(1, 4)), "helper moved away from spawn")
	var attack := AttackCommand.new(enemy.id, helper.id, enemy.cell, helper.cell, &"demo_strike", session.context.get_revision())
	var preview := AttackForecast.build(session.context, session._queue, attack)
	var receipt := session._queue.submit(attack, session.context)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events, "helper rear preview/live")
	var attacked: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"attacked")
	check(not attacked.is_empty() and attacked[0]["modifiers"]["backstab_percent"] == 50 and helper.faction == Faction.Type.PLAYER, "helper inherits team rear after movement")
	session.close()
