extends RefCounted

const BoardClone = preload("res://tools/demo/board_clone_probe.gd")

class Result extends RefCounted:
	var admission: ItemSnapshotResult
	var state: ItemSimulationState = null
	var phases_usec: Dictionary = {}

static func clone_state(source: ItemSimulationState, unsupported_runtime_ids: Array[StringName] = []) -> Result:
	var result := Result.new()
	var total_started := Time.get_ticks_usec()
	var capture_started := total_started
	var captured := ItemSimulationSnapshot.capture(source, unsupported_runtime_ids)
	result.phases_usec["capture"] = Time.get_ticks_usec() - capture_started
	result.admission = captured
	if captured.code != ItemSnapshotResult.Code.OK:
		result.phases_usec["total"] = Time.get_ticks_usec() - total_started
		return result

	# Capture синхронно проверил и зафиксировал live-граф; доска копируется сразу,
	# чтобы последующая сборка целиком читала собственный DTO и каталог.
	var board_started := Time.get_ticks_usec()
	var board := BoardClone.copy_board_unchecked(source.get_board())
	var board_usec := Time.get_ticks_usec() - board_started
	var catalogue_started := Time.get_ticks_usec()
	var catalogue: Dictionary = {}
	for owner: ItemOwnerState in source.get_owners():
		for id: StringName in owner._definitions:
			catalogue[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	result.phases_usec["catalogue"] = Time.get_ticks_usec() - catalogue_started

	var build_started := Time.get_ticks_usec()
	result.state = _build_captured_state(captured.snapshot._data, catalogue, board)
	result.phases_usec["build"] = board_usec + Time.get_ticks_usec() - build_started
	result.admission = ItemSnapshotResult.new()
	result.admission.code = ItemSnapshotResult.Code.OK
	result.phases_usec["total"] = Time.get_ticks_usec() - total_started
	return result

static func _build_captured_state(data: Dictionary, catalogue: Dictionary, board: BattleBoard) -> ItemSimulationState:
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	for record: Dictionary in data["owners"]:
		var owner := ItemOwnerState.new(board.get_unit_by_id(record["owner_unit_id"]))
		owner._next_item_id = record["next_item_id"]
		owner._next_effect_id = record["next_effect_id"]
		owner._closed = record["closed"]
		owner._inventory_registered = record["inventory_lifecycle"] == 1
		owner._inventory_retired = record["inventory_lifecycle"] == 2
		owner._equipment_registered = record["equipment_lifecycle"] == 1
		owner._equipment_retired = record["equipment_lifecycle"] == 2
		owner._inventory_order.assign(record["inventory_order"])
		for descriptor: Dictionary in record["definitions"]:
			var id := StringName(descriptor["id"])
			var definition: ItemDef = catalogue[id]
			owner._definitions[id] = definition.duplicate(true) as ItemDef if definition.use_summon else definition
		for item_record: Dictionary in record["items"]:
			var effects: Array[ItemEffectRuntime] = []
			effects.resize(item_record["effects"].size())
			for effect: Dictionary in item_record["effects"]:
				var runtime: ItemEffectRuntime
				if effect["kind"] == "stat_modifier":
					runtime = StatModifierEffectRuntime.new(record["owner_unit_id"], item_record["item_instance_id"], effect["effect_instance_id"], effect["effect_index"], effect["stat_type"] as StatTypes.StatType, effect["operation"] as StatModifier.Operation, effect["value"])
				else:
					runtime = HealOnDamageEffectRuntime.new(record["owner_unit_id"], item_record["item_instance_id"], effect["effect_instance_id"], effect["effect_index"], effect["heal_amount"], effect["trigger_event"] as TriggeredEffect.TriggerEvent)
				runtime._active = effect["active"]
				effects[effect["effect_index"]] = runtime
			var item := ItemInstance.new(owner._definitions[StringName(item_record["definition_id"])], record["owner_unit_id"], item_record["item_instance_id"], effects, item_record["charges_left"])
			item._placement = item_record["placement"]
			item._active = item_record["active"]
			item.armor_remaining = item_record["armor_remaining"]
			item.armor_origin_owner = item_record["armor_origin_owner"]
			item.armor_origin_item = item_record["armor_origin_item"]
			owner._items[item._item_id] = item
			owner._placements[item._item_id] = item._placement
		owners.append(owner)
		if owner._inventory_registered: inventories.append(InventoryState._restore_registered(owner))
		if owner._equipment_registered: equipment.append(EquipmentState._restore_registered(owner))

	var state := ItemSimulationState.new(board, owners, inventories, equipment)
	for summon: Dictionary in data["summons"]:
		state._summons.append(summon.duplicate(true))
	if data.has("abilities"): state.abilities = BattleAbilityState.from_dict(data["abilities"])
	if data.has("environment"): state.environment = CombatEnvironmentState.from_dict(data["environment"])
	if data.has("artifacts"): state.artifacts = BattleArtifactState.from_dict(data["artifacts"])
	if data.has("deck"):
		state.deck = BattleDeckState.from_dict(data["deck"])
		state.card_effects = BattleCardEffectState.from_dict(data["card_effects"])
	return state
