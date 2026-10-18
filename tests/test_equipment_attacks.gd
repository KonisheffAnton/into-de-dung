extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

class CallbackDefinition extends ItemDef:
	var calls: int = 0
	func equipment_perks_valid() -> bool:
		calls += 1
		return true

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL EQUIPMENT ATTACKS: " + label)

func _run() -> void:
	for count: int in range(4): _counted_attacks(count)
	_item_placement()
	_death_and_reach_gates()
	_counterattack_once()
	_separate_hits_and_armor()
	_public_boundary_and_special_attack()
	_snapshot_codec()
	_factory_rogue()
	_command_limit()
	await _worker_parity()
	_execution_worker_parity()
	print("EQUIPMENT ATTACKS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fixture() -> BattleCoreReactionsSession:
	var session := PlayerTurnFixture.create()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	session.state.environment.fires.clear()
	for index: int in 6:
		var unit: UnitState = session.units[index]
		session.board.move_unit(unit, Vector2i(index, 0))
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
		unit.armor.natural.physical = 0
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	session.board.move_unit(session.units[0], Vector2i(2, 3))
	session.board.move_unit(session.units[1], Vector2i(3, 3))
	session.select_unit(session.units[0].id)
	return session

func _equip_perks(session: BattleCoreReactionsSession, unit: UnitState, count: int) -> void:
	var owner := session.state.get_owner(unit.id)
	var equipment := session.state.get_equipment(unit.id)
	var armor_was_in_battle: bool = unit.armor.in_battle
	# Fixture уже в бою; временно снимаем только тестовый slot guard при сборке начального снаряжения.
	unit.armor.in_battle = false
	for index: int in count:
		var definition := ItemDef.new()
		definition.id = StringName("test_extra_attack_%d_%d" % [unit.id, index])
		definition.equipment_perks = [&"extra_attack"]
		var item := owner.create_item(definition)
		var equipped := false
		match index:
			0: equipped = equipment.equip(EquipmentState.EquipSlot.WEAPON, item)
			1: equipped = equipment.equip(EquipmentState.EquipSlot.ARMOR, item)
			2: equipped = equipment.equip(EquipmentState.EquipSlot.TRINKET, item)
		check(item != null and equipped, "test equipment created and equipped in slot %d" % index)
	unit.armor.in_battle = armor_was_in_battle

func _command(session: BattleCoreReactionsSession, actor: UnitState = null, target: UnitState = null, definition_id: StringName = &"demo_strike") -> AttackCommand:
	var source := actor if actor != null else session.units[0]
	var victim := target if target != null else session.units[1]
	return AttackCommand.new(source.id, victim.id, source.cell, victim.cell, definition_id, session.context.get_revision())

func _attack_events(receipt: ActionReceipt) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"attacked": result.append(event)
	return result

func _extra_events(receipt: ActionReceipt) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in _attack_events(receipt):
		if event.get("extra_attack", false): result.append(event)
	return result

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "state snapshot captured: " + capture.reason)
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func _parity(session: BattleCoreReactionsSession, attack: AttackCommand, label: String) -> ActionReceipt:
	var before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var forecast := ForecastSimulation.run(session.context, session._queue, attack)
	check(_snapshot(session) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before, label + " preview isolation")
	var receipt := session._queue.submit(attack, session.context)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, label + " preview/live events and steps")
	check(_snapshot(session) == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, label + " preview/live final state and counters")
	return receipt

func _counted_attacks(perks: int) -> void:
	var session := _fixture()
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[1]
	_equip_perks(session, actor, perks)
	var inspection := BattleInspectionText.build_live(actor, session.state, BattleInspectionText.Options.new())
	check(inspection.contains("Последовательные атаки от экипировки: +%d; всего %d" % [perks, perks + 1]) if perks > 0 else not inspection.contains("Последовательные атаки от экипировки:"), "inspection reflects equipped attack count")
	var receipt := _parity(session, _command(session), "%d perks" % perks)
	var attacks := _attack_events(receipt)
	var extras := _extra_events(receipt)
	check(receipt.status == ActionReceipt.APPLIED and attacks.size() == perks + 1 and extras.size() == perks, "%d perks produce %d total ordinary attacks" % [perks, perks + 1])
	var single_main_cost: bool = attacks.size() > 0 and attacks[0].main_cost == 1 and actor.action_resources.get_main_left() == 0
	for index: int in attacks.size():
		var event: Dictionary = attacks[index]
		if index > 0: single_main_cost = single_main_cost and event.get("main_cost", -1) == 0 and event.get("extra_attack", false)
		single_main_cost = single_main_cost and event.actor_unit_id == actor.id and event.target_unit_id == target.id
	check(single_main_cost, "%d perks retain one paid main action and the same target" % perks)
	if not extras.is_empty():
		check(BattleEventText.format_event(extras[0], {}, true, true, "").contains("перк экипировки"), "extra attack event explains equipment source")
	session.close()

func _item_placement() -> void:
	var session := _fixture()
	var actor: UnitState = session.units[0]
	var owner := session.state.get_owner(actor.id)
	var equipment := session.state.get_equipment(actor.id)
	var inventory := session.state.get_inventory(actor.id)
	var definition := ItemDef.new()
	definition.id = &"inventory_extra_attack"
	definition.equipment_perks = [&"extra_attack"]
	var item := owner.create_item(definition)
	check(owner.equipment_perk_count(&"extra_attack") == 0, "detached item grants no equipment attack")
	check(inventory.add_item(item) and owner.equipment_perk_count(&"extra_attack") == 0, "inventory item grants no equipment attack")
	var equipment_item := owner.create_item(_perk_definition(&"remove_extra_attack"))
	var armor_was_in_battle: bool = actor.armor.in_battle
	# Изменение слота проверяется в тестовой подготовке; live battle продолжает запрещать его.
	actor.armor.in_battle = false
	check(equipment.equip(EquipmentState.EquipSlot.WEAPON, equipment_item) and owner.equipment_perk_count(&"extra_attack") == 1, "equipped item grants one equipment attack")
	var removed := equipment.unequip(EquipmentState.EquipSlot.WEAPON)
	check(removed == equipment_item and owner.equipment_perk_count(&"extra_attack") == 0, "unequipping disables the equipment attack")
	actor.armor.in_battle = armor_was_in_battle
	session.close()

func _perk_definition(id: StringName) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = id
	definition.equipment_perks = [&"extra_attack"]
	return definition

func _death_and_reach_gates() -> void:
	var session := _fixture()
	_equip_perks(session, session.units[0], 3)
	session.units[1].vitals.set_hp(1.0)
	var receipt := _parity(session, _command(session), "first-hit death")
	check(receipt.status == ActionReceipt.APPLIED and _attack_events(receipt).size() == 1 and _extra_events(receipt).is_empty(), "first hit killing the target stops the follow-up chain")
	session.close()

	session = _fixture()
	var rng_start := session.context.get_rng().to_dict()
	_equip_perks(session, session.units[0], 3)
	var baseline := ForecastSimulation.run(session.context, session._queue, _command(session))
	var first_hit_damage: float = 0.0
	for event: Dictionary in baseline.events:
		if event.get("kind") != &"hit_resolved": continue
		for row: Dictionary in event.hit.rows: first_hit_damage += float(row.hp_damage)
		break
	check(baseline.status == ActionReceipt.APPLIED and first_hit_damage > 0.0, "three-perk preview measures first-strike damage for later lethal hit")
	session.close()
	session = _fixture()
	check(session.context.get_rng().from_dict(rng_start), "restore deterministic attack RNG for later lethal hit")
	_equip_perks(session, session.units[0], 3)
	session.units[1].vitals.set_hp(first_hit_damage + 1.0)
	receipt = _parity(session, _command(session), "later-hit death")
	check(receipt.status == ActionReceipt.APPLIED and _attack_events(receipt).size() == 2 and _extra_events(receipt).size() == 1 and not session.units[1].is_alive(), "later follow-up that kills target ends the remaining chain")
	session.close()

	session = _fixture()
	_equip_perks(session, session.units[0], 2)
	var attacker: UnitState = session.units[0]
	var victim: UnitState = session.units[1]
	var apply_control := func(_old: float, _new: float) -> void: attacker.control.stunned_turns = 1
	victim.vitals.hp_changed.connect(apply_control)
	receipt = session._queue.submit(_command(session), session.context)
	victim.vitals.hp_changed.disconnect(apply_control)
	check(receipt.status == ActionReceipt.FAULTED and _attack_events(receipt).size() == 1 and _extra_events(receipt).is_empty() and attacker.control.stunned_turns == 1, "control callback faults the completed root prefix before equipment follow-ups")
	session.close()

	session = _fixture()
	_equip_perks(session, session.units[0], 2)
	attacker = session.units[0]
	victim = session.units[1]
	var owner := session.state.get_owner(attacker.id)
	var equipped_item := owner.get_item_at(ItemOwnerState.EQUIPMENT_BASE + EquipmentState.EquipSlot.WEAPON)
	var equipment_definition := equipped_item.get_definition()
	var remove_equipment_perk := func(_old: float, _new: float) -> void: equipment_definition.equipment_perks.clear()
	victim.vitals.hp_changed.connect(remove_equipment_perk)
	receipt = session._queue.submit(_command(session), session.context)
	victim.vitals.hp_changed.disconnect(remove_equipment_perk)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"attack/equipment_checkpoint" and _attack_events(receipt).size() == 1 and _extra_events(receipt).is_empty(), "equipment perk mutation callback faults before follow-ups")
	session.close()

	session = _fixture()
	_equip_perks(session, session.units[0], 3)
	session.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	session.units[1].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
	session.units[1].vitals.set_balance(0.0)
	session.units[0].stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
	receipt = _parity(session, _command(session), "push leaves target out of reach")
	check(receipt.status == ActionReceipt.APPLIED and _attack_events(receipt).size() == 1 and session.units[1].cell != Vector2i(3, 3), "follow-ups stop when the first hit pushes target away")
	session.close()

func _counterattack_once() -> void:
	var session := _fixture()
	var attacker: UnitState = session.units[0]
	var defender: UnitState = session.units[1]
	_equip_perks(session, attacker, 2)
	_equip_perks(session, defender, 1)
	var guard := session._queue.submit(GuardCommand.new(defender.id, session.context.get_revision(), CombatPerksState.Mode.COUNTERATTACK), session.context)
	check(guard.status == ActionReceipt.APPLIED, "defender arms one counterattack")
	var receipt := _parity(session, _command(session), "follow-ups before one counterattack")
	var extras := _extra_events(receipt)
	var replies: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"counterattacked": replies.append(event)
	var last_extra_seq: int = int(extras[-1].event_seq) if not extras.is_empty() else -1
	check(receipt.status == ActionReceipt.APPLIED and replies.size() == 1 and replies[0].event_seq > last_extra_seq, "one counterattack occurs after the complete follow-up chain")
	check(not replies.is_empty() and not replies[0].has("extra_attack"), "counterattack never receives equipment follow-ups")
	session.close()

func _public_boundary_and_special_attack() -> void:
	var session := _fixture()
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[1]
	_equip_perks(session, actor, 1)
	var forged := AttackCommand.equipment_followup(actor, target, &"demo_strike", session.context.get_revision())
	var rejected := session._queue.submit(forged, session.context)
	check(rejected.status == ActionReceipt.REJECTED and rejected.reason == &"attack/internal_followup", "public submit cannot forge an equipment follow-up")
	actor.combat_perks.definition.stunning_strike = true
	target.combat_perks.definition.stun_immune = true
	var special := _parity(session, _command(session, actor, target, &"stunning_strike"), "special strike")
	check(special.status == ActionReceipt.APPLIED and _attack_events(special).size() == 1 and _extra_events(special).is_empty(), "special attack does not multiply through equipment")
	session.close()

	session = _fixture()
	actor = session.units[0]
	target = session.units[1]
	_equip_perks(session, actor, 1)
	var rune := _parity(session, _command(session, actor, target, &"blood_rune"), "blood rune")
	check(rune.status == ActionReceipt.APPLIED and _attack_events(rune).size() == 1 and _extra_events(rune).is_empty(), "rune attack does not multiply through equipment")
	session.close()

	session = _fixture()
	actor = session.units[0]
	target = session.units[1]
	_equip_perks(session, actor, 1)
	_equip_perks(session, target, 1)
	var direct_reaction := session._queue.submit(AttackCommand.counterattack(actor, target, session.context.get_revision()), session.context)
	check(direct_reaction.status == ActionReceipt.REJECTED, "public submit cannot forge a reaction attack")
	session.close()

func _separate_hits_and_armor() -> void:
	var session := _fixture()
	_equip_perks(session, session.units[0], 2)
	var target: UnitState = session.units[1]
	target.armor.raised_shield = RaisedShield.make()
	target.armor.raised_shield.active = true
	for item: ItemInstance in session.state.get_owner(target.id)._items.values():
		item.armor_remaining = mini(3, item.get_definition().armor_max)
	var receipt := _parity(session, _command(session), "separate groups and current armor")
	var hits: Array[Dictionary] = []
	var ids: Dictionary = {}
	for event: Dictionary in receipt.get_events():
		if event.kind == &"hit_resolved" and event.actor_unit_id == session.units[0].id:
			hits.append(event.hit)
			ids[event.hit_id] = true
	check(receipt.status == ActionReceipt.APPLIED and hits.size() == 3 and ids.size() == 3, "three separate hit identities")
	if hits.size() == 3:
		check(hits[0].raised_shield.blocked and not hits[1].raised_shield.blocked and not hits[2].raised_shield.blocked, "raised shield blocks only first attack group")
		check(hits[0].after.items == hits[1].before.items and hits[1].after.items == hits[2].before.items, "each strike reads previous armor result")
		check(float(hits[0].armor_spent) + float(hits[1].armor_spent) + float(hits[2].armor_spent) > 0.0, "series really consumes armor")
	session.close()

func _snapshot_codec() -> void:
	var session := _fixture()
	var actor: UnitState = session.units[0]
	_equip_perks(session, actor, 1)
	var definition_id := StringName("test_extra_attack_%d_0" % actor.id)
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	var data := captured.snapshot.to_dict() if captured.snapshot != null else {}
	var decoded := ItemSimulationSnapshot.from_dict(data)
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := decoded.snapshot.instantiate(definitions) if decoded.snapshot != null else null
	check(decoded.code == ItemSnapshotResult.Code.OK and restored != null and restored.code == ItemSnapshotResult.Code.OK, "snapshot restore accepts equipment perk definitions")
	if restored != null and restored.state != null:
		var restored_owner := restored.state.get_owner(actor.id)
		check(restored_owner != null and restored_owner.equipment_perk_count(&"extra_attack") == 1, "restored catalogue preserves active equipment perk")
		ForecastSimulation.close(restored.state)
	var malformed := data.duplicate(true)
	for row: Dictionary in malformed.owners:
		for definition: Dictionary in row.definitions:
			if definition.id == String(definition_id): definition.equipment_perks = [7]
	check(ItemSimulationSnapshot.from_dict(malformed).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "malformed optional equipment perks are rejected")
	var changed_catalog := definitions.duplicate(true)
	var changed := changed_catalog[definition_id] as ItemDef
	if changed != null: changed.equipment_perks.clear()
	var mismatch := decoded.snapshot.instantiate(changed_catalog) if decoded.snapshot != null else null
	check(mismatch != null and mismatch.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "changed equipment perk catalogue is rejected by snapshot restore")
	var unsupported := CallbackDefinition.new()
	unsupported.id = definition_id
	unsupported.equipment_perks = [&"extra_attack"]
	var owner := session.state.get_owner(actor.id)
	owner._definitions[definition_id] = unsupported
	for item: ItemInstance in owner._items.values():
		if item.get_definition_id() == definition_id: item._definition = unsupported
	var rejected := ItemSimulationSnapshot.capture(session.state, [])
	check(rejected.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and unsupported.calls == 0, "capture rejects subclass without invoking perk callback")
	check(ItemSimulationSnapshot._definition_error(unsupported, "test").begins_with("UNSUPPORTED:") and unsupported.calls == 0, "definition validation never dispatches unsupported perk method")
	session.close()

func _factory_rogue() -> void:
	var profile := HeroHubState.create(8821)
	var rogue_id: int = 0
	for hero_id: int in profile.heroes:
		var hero: HeroProgression = profile.heroes[hero_id]
		if hero.class_id == &"rogue": rogue_id = hero_id
	check(rogue_id > 0 and profile.start_battle(), "fresh profile starts battle with its Rogue starter gear")
	if rogue_id <= 0 or profile.phase != "battle": return
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "production battle factory creates Rogue combat runtime")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var rogue_unit_id: int = bundle.hero_units[rogue_id]
	var rogue := session.board.get_unit_by_id(rogue_unit_id)
	var target_id: int = session.living_ids(Faction.Type.ENEMY)[0]
	var target := session.board.get_unit_by_id(target_id)
	var owner := session.state.get_owner(rogue_unit_id)
	check(rogue != null and target != null and owner != null and owner.equipment_perk_count(&"extra_attack") == 1, "production Rogue weapon supplies one active extra attack")
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	session.state.environment.fires.clear()
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
		unit.armor.natural.physical = 0
	session.board.move_unit(rogue, Vector2i(2, 3))
	var battle_started := session.start_battle()
	check(battle_started, "production battle leaves deployment")
	if not battle_started:
		session.close()
		return
	var guard: int = 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and guard < 20:
		session.step_enemy()
		guard += 1
	var rogue_selected: bool = session.can_player_act() and session.select_unit(rogue_unit_id)
	check(rogue_selected, "production enemy turn reaches selected Rogue")
	if not rogue_selected:
		session.close()
		return
	target = session.board.get_unit_by_id(target_id)
	var adjacent_cell := Vector2i(-1, -1)
	for candidate: Vector2i in [rogue.cell + Vector2i.RIGHT, rogue.cell + Vector2i.LEFT, rogue.cell + Vector2i.UP, rogue.cell + Vector2i.DOWN]:
		if session.board.is_in_bounds(candidate) and not session.board.is_occupied(candidate):
			adjacent_cell = candidate
			break
	var target_positioned: bool = target != null and target.is_alive() and adjacent_cell != Vector2i(-1, -1) and session.board.move_unit(target, adjacent_cell)
	check(target_positioned, "production enemy is placed adjacent for attack test")
	if not target_positioned:
		session.close()
		return
	var before := _snapshot(session)
	var forecast := session.preview_attack(target_id)
	check(_snapshot(session) == before, "production Rogue forecast leaves live battle isolated")
	var receipt := session.attack_unit(target_id)
	if receipt.status != forecast.status or receipt.get_events() != forecast.events:
		printerr("EQUIPMENT ATTACKS DIAGNOSTIC: production Rogue status=%s reason=%s attacks=%d extras=%d forecast_status=%s forecast_reason=%s" % [receipt.status, receipt.reason, _attack_events(receipt).size(), _extra_events(receipt).size(), forecast.status, forecast.reason])
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and _snapshot(session) == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, "production personal hero attack forecast/live parity")
	check(receipt.status == ActionReceipt.APPLIED and _attack_events(receipt).size() == 2 and _extra_events(receipt).size() == 1 and rogue.action_resources.get_main_left() == 0, "production Rogue knife makes two attacks for one main action")
	session.close()

func _command_limit() -> void:
	var session := _fixture()
	_equip_perks(session, session.units[0], 3)
	var baseline := ForecastSimulation.run(session.context, session._queue, _command(session))
	var before_followup: int = 0
	var found_followup := false
	for step: Dictionary in baseline.steps:
		if found_followup: break
		if step.get("kind") == &"attack":
			if before_followup > 0: found_followup = true
			else: before_followup += 1
		else: before_followup += 1
	check(baseline.status == ActionReceipt.APPLIED and found_followup and before_followup > 1, "baseline locates first follow-up command")
	session._queue._max_commands = before_followup
	var receipt := session._queue.submit(_command(session), session.context)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"command_limit" and _attack_events(receipt).size() == 1 and _extra_events(receipt).is_empty(), "command limit faults after root attack without unexecuted follow-ups")
	session.close()

func _worker_parity() -> void:
	var session := _fixture()
	_equip_perks(session, session.units[0], 2)
	var attack := _command(session)
	var prepared := ForecastSimulation.prepare(session.context, session._queue, attack)
	var worker := AttackForecastWorker.new()
	worker.start(prepared)
	check(worker.is_started(), "prepared attack worker starts")
	if not worker.is_started():
		worker.close()
		session.close()
		return
	var threaded: AttackForecast = null
	while threaded == null:
		threaded = worker.take_finished()
		if threaded == null: await process_frame
	var local := AttackForecast.build(session.context, session._queue, attack)
	check(threaded.status == local.status and threaded.reason == local.reason and threaded.events == local.events and threaded.steps == local.steps and threaded.snapshot_after == local.snapshot_after and threaded.rng_after == local.rng_after and threaded.counters_after == local.counters_after, "prepared worker attack forecast matches local forecast")
	worker.close()
	session.close()

func _execution_worker_parity() -> void:
	var initial_id := UnitId.get_counter()
	var session := _fixture()
	_equip_perks(session, session.units[0], 2)
	var before := ActionPresentationState.capture(session.state)
	session.begin_presentation_capture()
	var expected := session.attack_unit(session.units[1].id)
	var expected_packets := session.take_presentation_capture()
	var expected_state := _snapshot(session)
	var expected_rng := session.context.get_rng().to_dict()
	var expected_counters := session.context.simulation_counters()
	check(expected.status == ActionReceipt.APPLIED and _attack_events(expected).size() == 3, "session executes three-hit series")
	var frames: Array[Dictionary] = expected.get_presentation_frames()
	var shown_attacks: int = 0
	for frame: Dictionary in frames:
		for event: Dictionary in frame.events:
			if event.kind == &"attacked": shown_attacks += 1
	check(shown_attacks == 3, "playback receives three distinct ordered attack frames")
	session.close()
	UnitId.set_counter(initial_id)
	session = _fixture()
	_equip_perks(session, session.units[0], 2)
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"attack_unit", [session.units[1].id], false, true), "three-hit live worker starts")
	if not worker.is_started():
		session.close()
		return
	check(worker.take_presentation_before() == before, "live worker detaches initial view")
	var completed := worker.take_finished(true)
	var actual: ActionReceipt = completed.result
	check(actual.status == expected.status and actual.reason == expected.reason and actual.get_events() == expected.get_events() and actual.get_steps() == expected.get_steps(), "live worker keeps exact series receipt")
	check(session.take_presentation_capture() == expected_packets, "live worker keeps ordered playback packets")
	check(_snapshot(session) == expected_state and session.context.get_rng().to_dict() == expected_rng and session.context.simulation_counters() == expected_counters, "live worker keeps series state RNG and counters")
	session.close()
