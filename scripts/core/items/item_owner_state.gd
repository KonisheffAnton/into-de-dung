extends RefCounted
class_name ItemOwnerState

## Единственный ledger размещения. Контейнеры не держат собственных списков,
## иначе замена слота и reentrant-сигналы могли бы увидеть разные состояния.
const INVENTORY_PLACEMENT := 1
const EQUIPMENT_BASE := 100
const MAX_ID := 9223372036854775807

var _owner: UnitState
var _items: Dictionary = {} # int -> ItemInstance
var _placements: Dictionary = {} # int -> int
var _definitions: Dictionary = {} # StringName -> ItemDef
var _inventory_order: Array[int] = []
var _next_item_id := 1
var _next_effect_id := 1
var _inventory_registered := false
var _equipment_registered := false
var _inventory_retired := false
var _equipment_retired := false
var _closed := false
var _guard := false

func _init(owner: UnitState) -> void:
	_owner = owner

func get_owner() -> UnitState: return _owner
func is_closed() -> bool: return _closed

func register_inventory() -> bool:
	if _guard or _closed or _inventory_registered or _inventory_retired: return false
	_inventory_registered = true
	return true

func register_equipment() -> bool:
	if _guard or _closed or _equipment_registered or _equipment_retired: return false
	_equipment_registered = true
	return true

func create_item(definition: ItemDef) -> ItemInstance:
	if not _begin_guard(): return null
	var item := _create_item_unplaced(definition)
	_end_guard()
	return item

func _begin_guard() -> bool:
	if _guard or _closed: return false
	_guard = true
	return true

func _end_guard() -> void:
	_guard = false

func _is_registered_item(item: ItemInstance) -> bool:
	if item == null or _owner == null or item.get_owner_unit_id() != _owner.id: return false
	var item_id := item.get_item_instance_id()
	return _items.has(item_id) and _items[item_id] == item

func _is_valid_equipment_placement(placement: int) -> bool:
	return placement >= EQUIPMENT_BASE and placement <= EQUIPMENT_BASE + 2

func _can_place(item: ItemInstance, placement: int) -> bool:
	if not _is_registered_item(item) or (placement != INVENTORY_PLACEMENT and not _is_valid_equipment_placement(placement)): return false
	var item_id := item.get_item_instance_id()
	if _placements[item_id] == placement: return true
	if not _can_activate_detached(item): return false
	if _is_valid_equipment_placement(placement) and get_item_at(placement) != null: return false
	return true

func _can_activate_detached(item: ItemInstance) -> bool:
	if not _is_registered_item(item): return false
	var item_id := item.get_item_instance_id()
	return _placements[item_id] == 0 and not item.is_active() and _sources_available(item)

func _sources_available(item: ItemInstance) -> bool:
	for runtime in item.get_effects():
		if runtime is StatModifierEffectRuntime and _owner.stats.has_modifiers_from_source((runtime as StatModifierEffectRuntime).get_source_key()):
			return false
	return true

func _prospective_sources_available(definition: ItemDef) -> bool:
	if not _validate_definition(definition): return false
	for effect_index in definition.effects.size():
		if definition.effects[effect_index].get_script() == StatModifierEffect:
			var source := StringName("p03a/o%d/i%d/e%d" % [_owner.id, _next_item_id, _next_effect_id + effect_index])
			if _owner.stats.has_modifiers_from_source(source): return false
	return true

func _legacy_create_and_place_while_guard(definition: ItemDef, placement: int) -> ItemInstance:
	if not _guard or not _prospective_sources_available(definition): return null
	if placement != INVENTORY_PLACEMENT and not _is_valid_equipment_placement(placement): return null
	if _is_valid_equipment_placement(placement) and get_item_at(placement) != null: return null
	var item := _create_item_unplaced(definition)
	if item == null or not _place_while_guard(item, placement): return null
	return item

func _place_while_guard(item: ItemInstance, placement: int) -> bool:
	if not _guard or not _can_place(item, placement): return false
	if _placements[item.get_item_instance_id()] == placement: return true
	_activate_while_guard(item)
	_placements[item.get_item_instance_id()] = placement
	item._set_placement(placement)
	if placement == INVENTORY_PLACEMENT: _inventory_order.append(item.get_item_instance_id())
	return true

func _detach_while_guard(item: ItemInstance) -> bool:
	if not _guard or not _is_registered_item(item): return false
	var item_id := item.get_item_instance_id()
	if _placements[item_id] == 0 or not item.is_active(): return false
	_deactivate_while_guard(item)
	if _placements[item_id] == INVENTORY_PLACEMENT: _inventory_order.erase(item_id)
	_placements[item_id] = 0
	item._set_placement(0)
	return true

func _activate_while_guard(item: ItemInstance) -> void:
	for runtime in item.get_effects():
		if runtime is StatModifierEffectRuntime:
			var stat_runtime := runtime as StatModifierEffectRuntime
			_owner.stats.add_modifier(stat_runtime.get_stat_type(), StatModifier.new(stat_runtime.get_source_key(), stat_runtime.get_operation(), stat_runtime.get_value()))
		runtime._set_active(true)
	item._set_active(true)

func _deactivate_while_guard(item: ItemInstance) -> void:
	for runtime in item.get_effects():
		if runtime is StatModifierEffectRuntime: _owner.stats.remove_modifiers_by_source((runtime as StatModifierEffectRuntime).get_source_key())
		runtime._set_active(false)
	item._set_active(false)

func _create_item_unplaced(definition: ItemDef) -> ItemInstance:
	if not _guard or not _validate_definition(definition): return null
	var item_id := _next_item_id
	var effect_id := _next_effect_id
	var runtimes: Array[ItemEffectRuntime] = []
	for effect_index in definition.effects.size():
		var runtime := definition.effects[effect_index].create_runtime(_owner.id, item_id, effect_id, effect_index)
		if runtime == null: return null
		runtimes.append(runtime)
		effect_id += 1
	_next_item_id += 1
	_next_effect_id = effect_id
	_definitions[definition.id] = definition
	var item := ItemInstance.new(definition, _owner.id, item_id, runtimes)
	_items[item_id] = item
	_placements[item_id] = 0
	return item

func _validate_definition(definition: ItemDef) -> bool:
	if _owner == null or _owner.id <= 0 or _owner.stats == null or _owner.vitals == null: return false
	if definition == null or definition.id == &"" or _next_item_id >= MAX_ID: return false
	# Параметры лечения валидируются вместе: нули сохраняют старые предметы,
	# а частично заданная пара не должна превращаться в usable предмет.
	if not is_finite(definition.use_heal_amount): return false
	if definition.use_heal_amount == 0.0 and not definition.use_summon:
		if definition.max_charges != 0: return false
	else:
		if definition.use_heal_amount < 0.0 or definition.max_charges < 1 or definition.max_charges > 4096: return false
	if definition.use_heal_amount > 0.0 and definition.use_summon: return false
	if _definitions.has(definition.id) and _definitions[definition.id] != definition: return false
	var count := definition.effects.size()
	if count > 0 and _next_effect_id > MAX_ID - count: return false
	for effect in definition.effects:
		if effect == null: return false
		if effect.get_script() == StatModifierEffect:
			var stat_effect := effect as StatModifierEffect
			if int(stat_effect.stat_type) < 0 or int(stat_effect.stat_type) > 10: return false
			if int(stat_effect.operation) < 0 or int(stat_effect.operation) > 2 or not is_finite(stat_effect.value): return false
		elif effect.get_script() == HealOnDamageEffect:
			var heal_effect := effect as HealOnDamageEffect
			if int(heal_effect.trigger_event) != int(TriggeredEffect.TriggerEvent.UNIT_DAMAGED): return false
			if heal_effect.heal_amount < 0.0 or not is_finite(heal_effect.heal_amount): return false
		else:
			return false
	return true

func get_items_for(placement: int) -> Array[ItemInstance]:
	if _closed: return []
	var result: Array[ItemInstance] = []
	if placement == INVENTORY_PLACEMENT:
		for item_id in _inventory_order:
			if _placements.get(item_id, 0) == placement: result.append(_items[item_id] as ItemInstance)
		return result
	for item_id in _items.keys():
		if _placements[item_id] == placement: result.append(_items[item_id] as ItemInstance)
	return result

func get_item_at(placement: int) -> ItemInstance:
	if _closed: return null
	for item_id in _items.keys():
		if _placements[item_id] == placement: return _items[item_id] as ItemInstance
	return null

func get_item_count(definition_id: StringName, placement: int) -> int:
	if _closed: return 0
	var count := 0
	for item in get_items_for(placement):
		if item.get_definition_id() == definition_id: count += 1
	return count

func get_definition_id_for_item(item_id: int) -> StringName:
	if not _items.has(item_id): return &""
	return (_items[item_id] as ItemInstance).get_definition_id()

func get_active_heal_effects() -> Array[HealOnDamageEffectRuntime]:
	var result: Array[HealOnDamageEffectRuntime] = []
	if _closed: return result
	for item in _items.values():
		var instance := item as ItemInstance
		if not instance.is_active(): continue
		for runtime in instance.get_effects():
			if runtime is HealOnDamageEffectRuntime and runtime.is_active(): result.append(runtime as HealOnDamageEffectRuntime)
	result.sort_custom(func(a: HealOnDamageEffectRuntime, b: HealOnDamageEffectRuntime) -> bool: return a.get_effect_instance_id() < b.get_effect_instance_id())
	return result

func _clear_placement_while_guard(placement: int) -> Array[ItemInstance]:
	var removed := get_items_for(placement)
	removed.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.get_item_instance_id() < b.get_item_instance_id())
	for item in removed: _detach_while_guard(item)
	return removed

func _close_container_while_guard(placement: int) -> void:
	_clear_placement_while_guard(placement)

func _retire_inventory() -> void:
	_inventory_registered = false
	_inventory_retired = true

func _retire_equipment() -> void:
	_equipment_registered = false
	_equipment_retired = true

func close() -> void:
	if not _begin_guard(): return
	var all_items: Array[ItemInstance] = []
	for item in _items.values(): all_items.append(item as ItemInstance)
	all_items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.get_item_instance_id() < b.get_item_instance_id())
	for item in all_items:
		if item.is_active(): _deactivate_while_guard(item)
		_placements[item.get_item_instance_id()] = 0
		item._set_placement(0)
	_inventory_order.clear()
	_inventory_registered = false
	_equipment_registered = false
	_inventory_retired = true
	_equipment_retired = true
	_closed = true
	_end_guard()
