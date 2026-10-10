extends SceneTree

var passed: int = 0
var failed: int = 0

class InvalidChainParent extends Command:
	var chain_value: Variant
	func _init(value: Variant = "invalid") -> void: chain_value = value
	func get_kind() -> StringName: return &"invalid_chain_parent_test"
	func copy_for_queue() -> Command: return InvalidChainParent.new(chain_value)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(_context: ActionContext) -> CommandStepResult:
		var binding := BalancePushRules.Binding.new()
		binding.values["chain"] = chain_value
		return CommandStepResult.applied([], [PushChainCommand.new(binding, &"pair", 0)])

class ShieldHitCommand extends DamageCommand:
	func _init(hit: DamageRequest = null) -> void:
		super(hit)

	func get_kind() -> StringName: return &"shield_hit_test"
	func copy_for_queue() -> Command: return ShieldHitCommand.new(request)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(context: ActionContext) -> CommandStepResult:
		if request == null: return CommandStepResult.faulted(&"shield/invalid_hit")
		var target := context.get_state().get_board().get_unit_by_id(request.target_unit_id)
		if target == null: return CommandStepResult.faulted(&"shield/invalid_hit")
		var guard := SpatialRules.capture_guard(context, [target], [target.cell], {target.id: [StatTypes.StatType.HP_MAX]})
		return ArmorHitExecutor.execute(request, guard, context)["result"]

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SPELL SHIELD: " + label)

func fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	var players := session.living_ids(Faction.Type.PLAYER)
	if not players.is_empty(): session.selected_id = players[0]
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.vitals.set_hp(80.0)
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	return session

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "snapshot valid: " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func events_of(receipt: ActionReceipt, kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == kind: result.append(event)
	return result

func raw_packet(physical: int, fire: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if physical >= 0: result.append({"type": "physical", "policy": "standard", "source": "test_physical", "numerator": physical, "denominator": 1})
	if fire >= 0: result.append({"type": "fire", "policy": "standard", "source": "test_fire", "numerator": fire, "denominator": 1})
	return result

func hit(session: BattleCoreReactionsSession, target: UnitState, packet: Array[Dictionary], source_kind: StringName = &"attack") -> ActionReceipt:
	var source := DamageSource.new(source_kind, 0, target.cell)
	return session._queue.submit(ShieldHitCommand.new(ArmorAttack.request(target.id, packet, source)), session.context)

func _run() -> void:
	_test_definition_and_legacy_state()
	_test_malformed_chain_reservation()
	_test_spell_forecast_live_refresh_replace_and_fault()
	_test_pure_packet_rules()
	_test_live_hit_packets_and_preview_parity()
	_test_mage_periodic_and_environment_routes()
	_test_lethal_shield_event_capacity()
	_test_burning_lethal_event_capacity()
	_test_shield_event_validation_rejects_forgery()
	print("SPELL SHIELD RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_malformed_chain_reservation() -> void:
	for malformed: Variant in ["invalid", {"links": [1]}, {"links": [{"from_id": "invalid", "to_id": 2}]}]:
		var session := fixture()
		var before := snapshot(session)
		var receipt := session._queue.submit(InvalidChainParent.new(malformed), session.context)
		check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"chain/invalid_binding", "malformed child reaches regular chain refusal")
		check(receipt.get_steps().size() == 2 and receipt.get_events().is_empty() and snapshot(session) == before, "malformed child preserves parent step without invented mutations")
		session.close()

func _test_definition_and_legacy_state() -> void:
	var session := fixture()
	var shield_spell := session.state.abilities.definition(&"mage.shield")
	check(shield_spell != null and shield_spell.effect == &"shield" and shield_spell.amount == 6 and shield_spell.mana_cost == 1 and shield_spell.cooldown_turns == 0 and shield_spell.shield_hits == 1, "catalog configures one-mana six-HP one-hit shield")
	var empty := ArmorState.new()
	var current := empty.to_dict()
	check(current.get("schema_version") == 4 and not current.has("shield") and not current.has("raised_shield"), "empty armor uses current schema with optional shields absent")
	var restored_empty := ArmorState.from_dict(current)
	check(restored_empty != null and restored_empty.to_dict() == current and restored_empty.shield.is_empty(), "empty current armor roundtrips unchanged")
	var old_armor := current.duplicate(true); old_armor.schema_version = 3
	check(not ArmorState.valid(old_armor), "old armor format is refused")
	var shielded := SpellShield.make(&"mage.shield", 6, 1)
	check(SpellShield.valid(shielded), "valid runtime shield dictionary")
	var unit := session.board.get_unit_by_id(session.selected_id)
	unit.armor.shield = shielded
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, "active shield snapshot captured")
	if captured.snapshot != null:
		var definitions: Dictionary = {}
		for owner: ItemOwnerState in session.state.get_owners():
			for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
		var restored := captured.snapshot.instantiate(definitions)
		check(restored.code == ItemSnapshotResult.Code.OK, "active shield snapshot restores: " + restored.reason)
		if restored.state != null:
			var roundtrip := ItemSimulationSnapshot.capture(restored.state, [])
			var copied := restored.state.get_board().get_unit_by_id(unit.id)
			check(roundtrip.code == ItemSnapshotResult.Code.OK and roundtrip.snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), "shield snapshot canonical roundtrip")
			check(copied.armor.shield == shielded and copied.armor.to_dict().schema_version == 4, "restored armor has active shield in schema four")
			for inventory: InventoryState in restored.state.get_inventories(): inventory.close()
			for equipment: EquipmentState in restored.state.get_equipment_facades(): equipment.close()
			for owner: ItemOwnerState in restored.state.get_owners(): owner.close()
			restored.state.get_board().resize(0, 0)
	session.close()

func _test_spell_forecast_live_refresh_replace_and_fault() -> void:
	var session := fixture()
	var target := session.board.get_unit_by_id(session.selected_id)
	var before := snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_forecast(&"mage.shield", target.id))
	check(preview.status == ActionReceipt.APPLIED, "shield forecast applies: " + String(preview.reason))
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before, "shield preview leaves state RNG and counters unchanged")
	var receipt := session.cast_mage_spell(&"mage.shield", target.id)
	var changed := events_of(receipt, &"shield_changed")
	check(receipt.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].reason == "applied" and changed[0].after == SpellShield.make(&"mage.shield", 6, 1), "live cast applies and receipts exact shield")
	check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps and snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after, "shield forecast/live parity includes events, steps, state and counters")
	target.armor.shield.hp = 1
	receipt = session.cast_mage_spell(&"mage.shield", target.id)
	changed = events_of(receipt, &"shield_changed")
	check(receipt.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].reason == "refreshed" and changed[0].before.hp == 1 and changed[0].after == SpellShield.make(&"mage.shield", 6, 1), "same spell refreshes one shield to full HP/hits")
	target.armor.shield = SpellShield.make(&"mage.other", 3, 2)
	receipt = session.cast_mage_spell(&"mage.shield", target.id)
	changed = events_of(receipt, &"shield_changed")
	check(receipt.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].reason == "replaced" and changed[0].after == SpellShield.make(&"mage.shield", 6, 1), "different spell replaces the prior shield")
	if changed.size() == 1:
		var draft := changed[0].duplicate(true)
		for key: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: draft.erase(key)
		check(SpellShield.valid_event(draft), "replace event draft validates")
	else:
		check(false, "replace event draft validates")
	session.close()

	var fault_session := fixture()
	var fault_target := fault_session.board.get_unit_by_id(fault_session.selected_id)
	var corrupt := func(kind: StringName, _key: int, _old: int, _new: int) -> void:
		if kind == &"shield": fault_target.armor.natural["physical"] += 1
	fault_target.armor.changed.connect(corrupt)
	var fault := fault_session.cast_mage_spell(&"mage.shield", fault_target.id)
	if fault_target.armor.changed.is_connected(corrupt): fault_target.armor.changed.disconnect(corrupt)
	check(fault.status == ActionReceipt.FAULTED and fault.reason == &"mage/shield_checkpoint", "armor.changed corruption faults guarded spell write")
	check(events_of(fault, &"mage_cast").size() == 1 and events_of(fault, &"shield_changed").size() == 1, "fault receipt retains paid shield prefix")
	check(fault_session.state.abilities.mana == 5 and fault_target.armor.shield == SpellShield.make(&"mage.shield", 6, 1), "fault keeps already applied spell prefix without rollback")
	fault_session.close()

func _test_pure_packet_rules() -> void:
	var shield := SpellShield.make(&"mage.shield", 4, 2)
	var mixed := raw_packet(4, 4)
	var intercepted := SpellShield.intercept(mixed, shield)
	check(intercepted.reason == &"" and intercepted.absorbed == 4 and intercepted.raw[0].numerator == 2 and intercepted.raw[1].numerator == 2, "one positive mixed packet proportionally splits shield absorption")
	check(intercepted.after.is_empty(), "zero HP shield ends even when a hit count remains")
	var zero := SpellShield.intercept(raw_packet(0, 0), shield)
	check(zero.reason == &"" and zero.absorbed == 0 and zero.after == shield, "zero packet leaves HP and hit count untouched")
	var single_hit := SpellShield.intercept(raw_packet(3, 3), SpellShield.make(&"mage.shield", 6, 2))
	check(single_hit.absorbed == 6 and single_hit.after.is_empty(), "a grouped multi-type packet consumes exactly one hit")
	var depleted_hit := SpellShield.intercept(raw_packet(2), single_hit.after if not single_hit.after.is_empty() else SpellShield.make(&"mage.shield", 1, 1))
	check(depleted_hit.after.is_empty(), "shield disappears after its final hit or HP")
	check(SpellShield.make(&"", 1, 1).is_empty() and SpellShield.make(&"invalid", 0, 1).is_empty() and SpellShield.make(&"invalid", 1, 0).is_empty(), "invalid shield definitions are refused")

func _hit_live(session: BattleCoreReactionsSession, target: UnitState, packet: Array[Dictionary]) -> ActionReceipt:
	var source := DamageSource.new(&"attack", 0, target.cell)
	var command := ShieldHitCommand.new(ArmorAttack.request(target.id, packet, source))
	return session._queue.submit(command, session.context)

func _test_live_hit_packets_and_preview_parity() -> void:
	var session := fixture()
	var target := session.board.get_unit_by_id(session.selected_id)
	var hp := target.vitals.get_hp()
	var armor_item: ItemInstance = null
	for item: ItemInstance in session.state.get_owner(target.id)._items.values():
		if item.get_definition().armor_max > 0 and item._placement >= ItemOwnerState.EQUIPMENT_BASE:
			armor_item = item
			item.armor_remaining = item.get_definition().armor_max
			break
	target.armor.shield = SpellShield.make(&"mage.shield", 6, 1)
	var absorbed := _hit_live(session, target, raw_packet(2, 2))
	var changed := events_of(absorbed, &"shield_changed")
	check(changed.size() == 1 and changed[0].absorbed == 4 and changed[0].after.is_empty(), "full absorption records one packet and depletes the one-hit shield: %s %s %s" % [absorbed.status, absorbed.reason, str(absorbed.get_events())])
	check(target.vitals.get_hp() == hp and not absorbed.get_events().any(func(e: Dictionary) -> bool: return e.kind in [&"damaged", &"healed"]) and not absorbed.get_events().any(func(e: Dictionary) -> bool: return e.kind == &"armor_changed"), "fully shielded hit does not alter HP or spend armor")
	check(armor_item != null and armor_item.armor_remaining == armor_item.get_definition().armor_max, "fully shielded hit preserves charged armor item")
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	target.armor.shield = SpellShield.make(&"mage.shield", 6, 1)
	hp = target.vitals.get_hp()
	var overflow := _hit_live(session, target, raw_packet(9))
	changed = events_of(overflow, &"shield_changed")
	check(changed.size() == 1 and changed[0].absorbed == 6 and changed[0].after.is_empty(), "partial hit exhausts shield before overflow: %s %s %s" % [overflow.status, overflow.reason, str(overflow.get_events())])
	check(target.vitals.get_hp() == hp - 3 and events_of(overflow, &"damaged").size() == 1, "overflow follows ordinary armor/HP calculation: hp %.1f -> %.1f, events %s" % [hp, target.vitals.get_hp(), str(overflow.get_events())])
	target.armor.shield = SpellShield.make(&"mage.shield", 6, 2)
	hp = target.vitals.get_hp()
	var first := _hit_live(session, target, raw_packet(4))
	check(events_of(first, &"shield_changed").size() == 1 and target.armor.shield == SpellShield.make(&"mage.shield", 2, 1) and target.vitals.get_hp() == hp, "first separate hit consumes one hit and keeps shield: %s %s %s" % [first.status, first.reason, str(first.get_events())])
	var second := _hit_live(session, target, raw_packet(4))
	changed = events_of(second, &"shield_changed")
	check(changed.size() == 1 and changed[0].absorbed == 2 and changed[0].after.is_empty() and target.vitals.get_hp() == hp - 2, "second separate hit consumes remaining shield then admits overflow: %s %s %s" % [second.status, second.reason, str(second.get_events())])
	target.armor.shield = SpellShield.make(&"mage.shield", 6, 2)
	var zero := _hit_live(session, target, raw_packet(0))
	check(events_of(zero, &"shield_changed").is_empty() and target.armor.shield == SpellShield.make(&"mage.shield", 6, 2), "zero damage receipt does not consume a shield hit")
	session.close()

func _test_mage_periodic_and_environment_routes() -> void:
	var session := fixture()
	var enemy_ids := session.living_ids(Faction.Type.ENEMY)
	var enemy := session.board.get_unit_by_id(enemy_ids[0])
	enemy.armor.shield = SpellShield.make(&"mage.test", 6, 2)
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_forecast(&"mage.fire", enemy.id))
	var fire := session.cast_mage_spell(&"mage.fire", enemy.id)
	var changed := events_of(fire, &"shield_changed")
	check(preview.status == ActionReceipt.APPLIED and fire.status == preview.status and fire.get_events() == preview.events and fire.get_steps() == preview.steps, "mage fire shield interaction matches forecast")
	check(changed.size() == 1 and changed[0].absorbed > 0 and changed[0].before.spell_id == "mage.test" and changed[0].after.hits_left == 1, "mage fire consumes one shielded hit before ordinary armor")
	if changed.size() == 1:
		var draft := changed[0].duplicate(true)
		for key: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: draft.erase(key)
		check(SpellShield.valid_event(draft), "absorbed hit event matches shield DTO")
	else:
		check(false, "absorbed hit event matches shield DTO")
	var player := session.board.get_unit_by_id(session.selected_id)
	var source_id := enemy.id
	# При переходе к стековым тикам снимок требует v3 у всех единиц, включая пустые.
	for unit: UnitState in session.units:
		unit.bleeding.stacked = true
	player.elemental.burning_stacks = 2
	player.elemental.burning_ticks = 1
	player.elemental.burning_source = DamageSource.new(&"mage", 3, Vector2i(-1, -1), 0, 0).to_dict()
	player.armor.shield = SpellShield.make(&"mage.shield", 8, 2)
	var burn_tick := session._queue.submit(BleedingTurnCommand.new(player.faction, session.context.get_revision()), session.context)
	changed = events_of(burn_tick, &"shield_changed")
	check(burn_tick.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].absorbed == 2 and player.armor.shield == SpellShield.make(&"mage.shield", 6, 1) and player.vitals.get_hp() == 80.0, "burn tick damage consumes one grouped shield hit: %s %s %s" % [burn_tick.status, burn_tick.reason, str(burn_tick.get_events())])
	player.bleeding.stacked = true
	player.bleeding.stacks = 2
	player.bleeding.ticks_left = 2
	player.bleeding.source = DamageSource.new(&"attack", 0, enemy.cell, source_id, source_id).to_dict()
	player.bleeding.hit_id = "spell_shield_fixture"
	player.armor.shield = SpellShield.make(&"mage.shield", 2, 2)
	check(ElementalState.valid(player.elemental.to_dict()) and BleedingState.valid(player.bleeding.to_dict()), "periodic damage fixture statuses are valid")
	var ticks := session._queue.submit(BleedingTurnCommand.new(player.faction, session.context.get_revision()), session.context)
	changed = events_of(ticks, &"shield_changed")
	check(ticks.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].absorbed == 2 and player.armor.shield.is_empty(), "bleeding tick consumes one grouped shield hit: %s %s %s" % [ticks.status, ticks.reason, str(ticks.get_events())])
	check(player.vitals.get_hp() == 80.0, "periodic damage is stopped before HP by the shield")
	player.bleeding.stacks = 0
	player.bleeding.ticks_left = 0
	player.bleeding.source = {}
	player.bleeding.hit_id = ""
	var destination := Vector2i(-1, -1)
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var candidate := player.cell + direction
		if session.board.is_in_bounds(candidate) and not session.board.is_occupied(candidate):
			destination = candidate
			break
	check(destination != Vector2i(-1, -1), "environment movement fixture finds adjacent cell")
	if destination != Vector2i(-1, -1):
		session.board.set_terrain(destination, TerrainType.Type.FLOOR)
		session.board.set_height_steps(destination, session.board.get_height_steps(player.cell))
		session.state.environment.fires.clear()
		var fire_cell := session.state.environment.ignite(destination)
		check(not fire_cell.is_empty(), "environment fixture creates a spike cell")
		player.armor.shield = SpellShield.make(&"mage.env", 12, 2)
		var env := session.move_to(destination)
		changed = events_of(env, &"shield_changed")
		check(env.status == ActionReceipt.APPLIED and changed.size() == 1 and changed[0].absorbed > 0 and player.armor.shield.hits_left == 1, "movement environment damage uses the same shield interception: %s %s %s" % [env.status, env.reason, str(env.get_events())])
		check(env.get_events().any(func(e: Dictionary) -> bool: return e.kind == &"hit_resolved"), "environment overflow continues through normal damage receipt")
	session.close()

func _equipped_armor_item(session: BattleCoreReactionsSession, unit: UnitState) -> ItemInstance:
	for item: ItemInstance in session.state.get_owner(unit.id)._items.values():
		if item.get_definition().armor_max >= 3 and item._placement >= ItemOwnerState.EQUIPMENT_BASE:
			return item
	return null

func _test_lethal_shield_event_capacity() -> void:
	var session := fixture()
	var target := session.board.get_unit_by_id(session.selected_id)
	var item := _equipped_armor_item(session, target)
	check(item != null, "lethal armor fixture has an equipped armor item with capacity at least three")
	if item == null:
		session.close()
		return
	item.armor_remaining = 1
	target.vitals.set_hp(1.0)
	target.armor.shield = SpellShield.make(&"mage.shield", 1, 1)
	var receipt := _hit_live(session, target, raw_packet(20))
	var kinds: Array[StringName] = []
	for event: Dictionary in receipt.get_events(): kinds.append(event.get("kind", &""))
	var expected: Array[StringName] = [&"shield_changed", &"armor_changed", &"damaged", &"died", &"hit_resolved", &"corpse_created"]
	check(receipt.status == ActionReceipt.APPLIED and receipt.reason == &"", "lethal shielded armor packet remains APPLIED: %s %s %s" % [receipt.status, receipt.reason, str(kinds)])
	check(kinds == expected, "lethal armor packet retains shield, armor, damage, death and hit events in order: %s" % str(kinds))
	check(target.vitals.get_hp() == 0.0 and not target.is_alive() and target.armor.shield.is_empty() and item.armor_remaining == 0, "lethal packet applies all guarded state changes")
	session.close()

func _test_burning_lethal_event_capacity() -> void:
	var session := fixture()
	var target := session.board.get_unit_by_id(session.selected_id)
	# Статусный тик требует каноническую стековую схему даже у пустых целей.
	for unit: UnitState in session.units: unit.bleeding.stacked = true
	var item := _equipped_armor_item(session, target)
	check(item != null, "burning lethal fixture has equipped armor")
	if item == null:
		session.close()
		return
	item.armor_remaining = 1
	target.vitals.set_hp(1.0)
	target.armor.shield = SpellShield.make(&"mage.shield", 1, 1)
	target.elemental.burning_stacks = 20
	target.elemental.burning_ticks = 1
	target.elemental.burning_source = DamageSource.new(&"mage", 3, Vector2i(-1, -1), 0, 0).to_dict()
	var receipt := session._queue.submit(BleedingTurnCommand.new(target.faction, session.context.get_revision()), session.context)
	var kinds: Array[StringName] = []
	for event: Dictionary in receipt.get_events(): kinds.append(event.get("kind", &""))
	var expected: Array[StringName] = [&"elemental_changed", &"shield_changed", &"armor_changed", &"damaged", &"died", &"hit_resolved", &"corpse_created"]
	check(receipt.status == ActionReceipt.APPLIED and receipt.reason == &"", "lethal burning turn remains APPLIED: %s %s %s" % [receipt.status, receipt.reason, str(kinds)])
	check(kinds == expected, "lethal burning retains status plus all five hit events in order: %s" % str(kinds))
	check(target.vitals.get_hp() == 0.0 and not target.is_alive() and target.armor.shield.is_empty() and item.armor_remaining == 0, "lethal burning applies shield, armor and death")
	session.close()

func _test_shield_event_validation_rejects_forgery() -> void:
	var session := fixture()
	var target := session.board.get_unit_by_id(session.selected_id)
	var receipt := session.cast_mage_spell(&"mage.shield", target.id)
	var source_event := events_of(receipt, &"shield_changed")
	check(receipt.status == ActionReceipt.APPLIED and source_event.size() == 1, "validation fixture produces a real application receipt")
	if source_event.size() != 1:
		session.close()
		return
	var draft: Dictionary = source_event[0].duplicate(true)
	for key: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: draft.erase(key)
	check(SpellShield.valid_event(draft), "real mage application event draft validates")
	var forged := draft.duplicate(true)
	forged.source.kind = &"unrecognized"
	check(not SpellShield.valid_event(forged), "shield event rejects an invalid source kind")
	forged = draft.duplicate(true)
	forged.source.instigator_unit_id = -1
	check(not SpellShield.valid_event(forged), "shield event rejects negative source IDs")
	forged = draft.duplicate(true)
	forged.actor_unit_id = target.id + 1
	check(not SpellShield.valid_event(forged), "shield event rejects actor/source mismatch")
	forged = draft.duplicate(true)
	forged.after.spell_id = "mage.test_shield"
	check(not SpellShield.valid_event(forged), "shield application rejects a non-catalog mage spell")
	session.close()
