extends SceneTree

class UnsupportedItem extends ItemDef:
	pass

class UnsupportedAction extends ItemUseAction:
	pass

class CustomSummonSession extends BattleTacticalSession:
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		definition.summon_definition.name_prefix = "Спутник · "
		definition.summon_definition.hp_max = 21.0
		return definition

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ITEM USE: " + label)

func _run() -> void:
	_test_definitions()
	_test_legacy_heal_snapshot()
	_test_healing()
	_test_summoning()
	print("ITEM USE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_definitions() -> void:
	var passive := ItemDef.new()
	passive.max_charges = 1
	check(ItemUseAction.from_definition(passive) == null, "passive rejected")
	var unsupported_item := UnsupportedItem.new()
	unsupported_item.use_heal_amount = 1.0
	unsupported_item.max_charges = 1
	check(ItemUseAction.from_definition(unsupported_item) == null, "unsupported item script rejected")
	var mixed := ItemDef.new()
	mixed.max_charges = 1
	mixed.use_heal_amount = 1.0
	mixed.use_summon = true
	mixed.summon_definition = SummonDefinition.new()
	check(ItemUseAction.from_definition(mixed) == null, "mixed rejected")
	var invalid := ItemDef.new()
	invalid.max_charges = 1
	invalid.use_heal_amount = NAN
	check(ItemUseAction.from_definition(invalid) == null, "nonfinite rejected")
	invalid.use_heal_amount = 1.0
	invalid.max_charges = 0
	check(ItemUseAction.from_definition(invalid) == null, "no capacity rejected")
	var heal := ItemDef.new()
	heal.use_heal_amount = 4.0
	heal.max_charges = 3
	var action := ItemUseAction.from_definition(heal)
	check(action != null and action.get_kind() == ItemUseAction.Kind.HEAL_SELF and action.get_target_mode() == ItemUseAction.TargetMode.SELF, "heal descriptor")
	check(action.get_heal_amount() == 4.0 and action.get_summon_definition() == null and action.get_max_charges() == 3 and action.get_main_cost() == 1 and action.get_charge_cost() == 1, "heal values and costs")
	var seal := Item.new()
	seal.use_summon = true
	seal.max_charges = 2
	seal.summon_definition = SummonDefinition.new()
	var summon_action := ItemUseAction.from_definition(seal)
	check(summon_action != null and summon_action.get_kind() == ItemUseAction.Kind.SUMMON_ADJACENT and summon_action.get_target_mode() == ItemUseAction.TargetMode.ADJACENT_CELL, "summon descriptor")
	var original := seal.summon_definition
	var retrieved := summon_action.get_summon_definition()
	retrieved.hp_max = 88.0
	check(original.hp_max == SummonDefinition.DEFAULT_HP_MAX and summon_action.get_summon_definition().hp_max == SummonDefinition.DEFAULT_HP_MAX, "action getter isolated")
	original.name_prefix = "Изменённый · "
	check(summon_action.get_summon_definition().name_prefix == SummonDefinition.DEFAULT_NAME_PREFIX, "source definition isolated")
	var unsupported_action := UnsupportedAction.new()
	check(unsupported_action.create_command(1, 1, -1) == null, "unsupported action script rejected")
	var bad_summon := ItemDef.new()
	bad_summon.use_summon = true
	bad_summon.max_charges = 1
	bad_summon.summon_definition = SummonDefinition.new()
	bad_summon.summon_definition.hp_max = NAN
	check(ItemUseAction.from_definition(bad_summon) == null, "invalid summon rejected")

func _test_healing() -> void:
	var session := BattleTacticalSession.new()
	var actor := session.selected_unit()
	var item := session.healing_item()
	var action := ItemUseAction.from_definition(item.get_definition())
	check(action != null and action.create_command(actor.id, item.get_item_instance_id(), session.context.get_revision()) is UseHealingItemCommand, "heal command factory")
	var seal_id := -1
	for candidate: ItemInstance in session.state.get_owner(actor.id).get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if candidate.get_definition().use_summon: seal_id = candidate.get_item_instance_id()
	check(action.availability_reason(session.context, actor.id, seal_id) == &"item/not_usable", "descriptor respects live item kind")
	actor.vitals.apply_damage(12.0)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var counters := session.context.simulation_counters()
	var last := session.last_receipt
	check(action.availability_reason(session.context, actor.id, item.get_item_instance_id()) == &"", "heal availability")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and session.last_receipt == last, "availability pure")
	var stale: Command = action.create_command(actor.id, item.get_item_instance_id(), session.context.get_revision())
	var receipt := session._submit(action.create_command(actor.id, item.get_item_instance_id(), session.context.get_revision()))
	check(receipt.status == ActionReceipt.APPLIED and actor.vitals.get_hp() == 32.0 and item.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0, "factory heals and spends resources")
	check(action.availability_reason(session.context, actor.id, item.get_item_instance_id()) == &"item/insufficient_main", "descriptor respects spent resource")
	check(stale.validate(session.context) == &"item/stale_revision", "stale factory command")
	session.close()
	check(stale.validate(session.context) == &"item/invalid_runtime", "closed state rejected")

func _test_legacy_heal_snapshot() -> void:
	var session := BattleDemoSession.new()
	var owner := session.state.get_owner(session.selected_id)
	var definition := ItemDef.new()
	definition.id = &"item_use_legacy_heal"
	definition.use_heal_amount = 7.0
	definition.max_charges = 2
	var item := owner.create_item(definition)
	session.state.get_inventory(session.selected_id).add_item(item)
	var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot
	var definitions: Dictionary = {}
	for source: ItemOwnerState in session.state.get_owners():
		for key: StringName in source._definitions:
			definitions[key] = (source._definitions[key] as ItemDef).duplicate(true)
	var restored := snapshot.instantiate(definitions)
	var restored_item: ItemInstance = restored.state.get_owner(session.selected_id)._items[item.get_item_instance_id()]
	var original_action := ItemUseAction.from_definition(item.get_definition())
	var restored_action := ItemUseAction.from_definition(restored_item.get_definition())
	check(restored.code == ItemSnapshotResult.Code.OK and snapshot.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and original_action != null and restored_action != null and original_action.get_kind() == restored_action.get_kind() and original_action.get_heal_amount() == restored_action.get_heal_amount() and original_action.get_max_charges() == restored_action.get_max_charges(), "heal descriptor roundtrip")
	AttackForecast._close(restored.state)
	session.close()

func _test_summoning() -> void:
	var session := CustomSummonSession.new()
	var actor := session.selected_unit()
	var item: ItemInstance
	for candidate: ItemInstance in session.state.get_owner(actor.id).get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if candidate.get_definition().use_summon: item = candidate
	var action := ItemUseAction.from_definition(item.get_definition())
	check(action != null and action.create_command(actor.id, item.get_item_instance_id(), session.context.get_revision(), Vector2i(0, 1)) is UseSummoningItemCommand, "summon command factory")
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var counters := session.context.simulation_counters()
	var last := session.last_receipt
	check(action.availability_reason(session.context, actor.id, item.get_item_instance_id(), Vector2i(0, 1)) == &"", "summon availability")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and session.last_receipt == last, "summon availability pure")
	var cells := action.target_cells(session.board, actor.cell)
	check(cells.has(Vector2i(0, 1)) and cells.size() == 2 and ItemUseAction.from_definition(session.healing_item().get_definition()).target_cells(session.board, actor.cell).is_empty(), "adjacent target cells and heal empty")
	var receipt := session._submit(action.create_command(actor.id, item.get_item_instance_id(), session.context.get_revision(), Vector2i(0, 1)))
	check(receipt.status == ActionReceipt.APPLIED and session.state.active_summon(actor.id) != null and item.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0, "factory summons and spends resources")
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	if captured.code != ItemSnapshotResult.Code.OK:
		check(false, "custom v6 snapshot capture: " + captured.reason)
		session.close()
		return
	var snapshot := captured.snapshot
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for key: StringName in owner._definitions:
			definitions[key] = (owner._definitions[key] as ItemDef).duplicate(true)
	var restored := snapshot.instantiate(definitions)
	if restored.code != ItemSnapshotResult.Code.OK or restored.state == null:
		check(false, "custom v6 snapshot restore: " + restored.reason)
		session.close()
		return
	var restored_item: ItemInstance = restored.state.get_owner(actor.id)._items[item.get_item_instance_id()]
	var restored_action := ItemUseAction.from_definition(restored_item.get_definition())
	check(restored.code == ItemSnapshotResult.Code.OK and snapshot.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and restored_action != null and restored_action.get_kind() == action.get_kind() and restored_action.get_summon_definition().to_dict() == action.get_summon_definition().to_dict(), "custom restored descriptor parity")
	AttackForecast._close(restored.state)
	session.close()
