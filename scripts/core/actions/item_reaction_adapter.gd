extends RefCounted
class_name ItemReactionAdapter

# Только pending держит identity. Ни receipt, ни value event не видят эти ссылки.
class Binding extends RefCounted:
	var description: Dictionary
	var unit: UnitState
	var owner: ItemOwnerState
	var item: ItemInstance
	var effect: HealOnDamageEffectRuntime
	var definition: ItemDef
	var definition_value: Dictionary
	var definition_effects: Array[ItemEffect]
	var effect_index: int

static func bind(description: Dictionary, context: ActionContext) -> HealCommand:
	if not ItemSimulationSnapshot._shape(description, {"kind": TYPE_STRING, "event_seq": TYPE_INT, "priority": TYPE_INT, "owner_unit_id": TYPE_INT, "item_instance_id": TYPE_INT, "effect_instance_id": TYPE_INT, "local_index": TYPE_INT, "target_unit_id": TYPE_INT, "definition_id": TYPE_STRING, "heal_amount": TYPE_FLOAT}): return null
	if description["kind"] != "heal" or description["target_unit_id"] != description["owner_unit_id"] or not is_finite(description["heal_amount"]) or description["heal_amount"] < 0.0: return null
	for key: String in ["event_seq", "owner_unit_id", "target_unit_id", "item_instance_id", "effect_instance_id"]:
		if description[key] <= 0 or description[key] >= ItemSimulationSnapshot.MAX_ID: return null
	if description["local_index"] < 0: return null
	var state := context.get_state()
	var binding := Binding.new()
	binding.description = description.duplicate(true)
	binding.unit = state.get_board().get_unit_by_id(description["owner_unit_id"])
	binding.owner = state.get_owner(description["owner_unit_id"])
	if binding.unit == null or binding.owner == null: return null
	binding.item = binding.owner._items.get(description["item_instance_id"]) as ItemInstance
	if binding.item == null: return null
	binding.definition = binding.item.get_definition()
	if ItemSimulationSnapshot._definition_error(binding.definition, "binding") != "": return null
	binding.definition_value = ItemSimulationSnapshot._definition_value(binding.definition)
	binding.definition_effects = binding.definition.effects.duplicate()
	var matches := 0
	for effect in binding.item.get_effects():
		if effect != null and effect.get_effect_instance_id() == description["effect_instance_id"]:
			matches += 1
			binding.effect = effect as HealOnDamageEffectRuntime
	if matches != 1 or binding.effect == null: return null
	binding.effect_index = binding.effect.get_effect_index()
	if revalidate(binding, context) != &"": return null
	var source := DamageSource.new(&"item", description["item_instance_id"], binding.unit.cell, binding.unit.id, binding.unit.id)
	var command := HealCommand.new(description["target_unit_id"], description["heal_amount"], source)
	command._reaction_binding = binding
	return command

static func revalidate(raw: RefCounted, context: ActionContext) -> StringName:
	var binding := raw as Binding
	if binding == null: return &"invalid_reaction_binding"
	var d := binding.description
	var state := context.get_state()
	var owner := binding.owner
	var item := binding.item
	var effect := binding.effect
	if state.get_board().get_unit_by_id(d["target_unit_id"]) != binding.unit or state.get_owner(d["owner_unit_id"]) != owner or owner.get_owner() != binding.unit: return &"stale_reaction"
	if not binding.unit.is_alive() or owner.is_closed(): return &"stale_reaction"
	if owner._guard: return &"reaction_owner_busy"
	if owner._items.get(d["item_instance_id"]) != item: return &"stale_reaction"
	if item.get_definition() != binding.definition: return &"stale_reaction"
	if not owner._is_registered_item(item) or item.get_owner_unit_id() != d["owner_unit_id"] or item.get_item_instance_id() != d["item_instance_id"]: return &"reaction_ledger"
	if ItemSimulationSnapshot._definition_error(binding.definition, "binding") != "": return &"reaction_definition"
	if item.get_definition_id() != StringName(d["definition_id"]) or owner._definitions.get(item.get_definition_id()) != binding.definition or ItemSimulationSnapshot._definition_value(binding.definition) != binding.definition_value or binding.definition.effects != binding.definition_effects: return &"reaction_definition"
	var matches := 0
	var current: ItemEffectRuntime = null
	for candidate in item.get_effects():
		if candidate == null: return &"reaction_ledger"
		if candidate.get_effect_instance_id() == d["effect_instance_id"]:
			matches += 1
			current = candidate
	if matches == 0 or (matches == 1 and current != effect): return &"stale_reaction"
	if matches != 1: return &"reaction_ledger"
	if effect.get_script() != HealOnDamageEffectRuntime or effect.get_owner_unit_id() != d["owner_unit_id"] or effect.get_item_instance_id() != d["item_instance_id"] or effect.get_effect_index() != binding.effect_index: return &"reaction_ledger"
	if not is_finite(effect.get_heal_amount()) or effect.get_heal_amount() != d["heal_amount"] or effect.get_trigger_event() != TriggeredEffect.TriggerEvent.UNIT_DAMAGED: return &"reaction_definition"
	if not item.is_active() or not effect.is_active() or item._get_placement() == 0: return &"stale_reaction"
	var placement := item._get_placement()
	if owner._placements.get(item.get_item_instance_id(), -1) != placement: return &"reaction_ledger"
	if placement == ItemOwnerState.INVENTORY_PLACEMENT:
		var inventory := state.get_inventory(binding.unit.id)
		if inventory == null or inventory.is_closed() or not owner._inventory_registered or owner._inventory_retired: return &"stale_reaction"
		if inventory._state != owner or owner._inventory_order.count(item.get_item_instance_id()) != 1: return &"reaction_ledger"
	elif owner._is_valid_equipment_placement(placement):
		var equipment := state.get_equipment(binding.unit.id)
		if equipment == null or equipment.is_closed() or not owner._equipment_registered or owner._equipment_retired: return &"stale_reaction"
		if equipment._state != owner or owner.get_items_for(placement).size() != 1: return &"reaction_ledger"
	else: return &"reaction_ledger"
	return &""
