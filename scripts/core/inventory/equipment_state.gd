extends RefCounted
class_name EquipmentState

enum EquipSlot { WEAPON, ARMOR, TRINKET }
signal item_equipped(slot: EquipSlot, item: ItemInstance)
signal item_unequipped(slot: EquipSlot, item: ItemInstance)

var _state: ItemOwnerState
var _closed := false

func _init(state: ItemOwnerState) -> void:
	_state = state
	if state == null or not state.register_equipment(): _closed = true

func is_closed() -> bool:
	return _closed or _state == null or _state.is_closed()

func _valid_slot(slot: EquipSlot) -> bool:
	return int(slot) >= int(EquipSlot.WEAPON) and int(slot) <= int(EquipSlot.TRINKET)

func _placement(slot: EquipSlot) -> int: return ItemOwnerState.EQUIPMENT_BASE + int(slot)
func _item(slot: EquipSlot) -> ItemInstance:
	if is_closed() or not _valid_slot(slot): return null
	return _state.get_item_at(_placement(slot))

func equip(slot: EquipSlot, item: ItemInstance) -> bool:
	if is_closed() or not _valid_slot(slot) or not _state._begin_guard(): return false
	var old := _item(slot)
	if old == item:
		_state._end_guard()
		return old != null
	# Полная проверка нового item идёт до снятия старого слота.
	if not _state._can_activate_detached(item):
		_state._end_guard()
		return false
	if old != null: _state._detach_while_guard(old)
	var equipped := _state._place_while_guard(item, _placement(slot))
	if not equipped:
		# Этот путь недостижим после preflight; не оставляем старый предмет активным
		# через частичный rollback с сигналами.
		_state._end_guard()
		return false
	if old != null: item_unequipped.emit(slot, old)
	item_equipped.emit(slot, item)
	_state._end_guard()
	return true

func unequip(slot: EquipSlot) -> ItemInstance:
	if is_closed() or not _valid_slot(slot) or not _state._begin_guard(): return null
	var item := _item(slot)
	if item == null:
		_state._end_guard()
		return null
	_state._detach_while_guard(item)
	item_unequipped.emit(slot, item)
	_state._end_guard()
	return item

func get_equipped(slot: EquipSlot) -> ItemInstance: return _item(slot)
func is_slot_occupied(slot: EquipSlot) -> bool: return _item(slot) != null

func get_occupied_slots() -> Array:
	var slots: Array = []
	if is_closed(): return slots
	for slot in [EquipSlot.WEAPON, EquipSlot.ARMOR, EquipSlot.TRINKET]:
		if _item(slot): slots.append(slot)
	return slots

func clear() -> void:
	if is_closed() or not _state._begin_guard(): return
	var removed: Array[Dictionary] = []
	for slot in [EquipSlot.WEAPON, EquipSlot.ARMOR, EquipSlot.TRINKET]:
		var item := _item(slot)
		if item != null:
			removed.append({"slot": slot, "item": item})
	removed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["item"] as ItemInstance).get_item_instance_id() < (b["item"] as ItemInstance).get_item_instance_id())
	# Сначала формируем итоговое состояние в стабильном порядке id: так
	# stat_changed не зависит от порядка слотов, а callbacks видят пустой ledger.
	for record in removed:
		_state._detach_while_guard(record["item"] as ItemInstance)
	for record in removed:
		item_unequipped.emit(record["slot"] as EquipSlot, record["item"] as ItemInstance)
	_state._end_guard()

func close() -> void:
	if _closed or _state == null or _state.is_closed() or not _state._begin_guard(): return
	var items: Array[ItemInstance] = []
	for slot in [EquipSlot.WEAPON, EquipSlot.ARMOR, EquipSlot.TRINKET]:
		var item := _item(slot)
		if item != null: items.append(item)
	items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.get_item_instance_id() < b.get_item_instance_id())
	for item in items: _state._detach_while_guard(item)
	_state._retire_equipment()
	_closed = true
	_state._end_guard()

func to_dict() -> Dictionary:
	var slots: Dictionary = {}
	for slot in get_occupied_slots():
		var item := get_equipped(slot)
		var path := item.get_definition().resource_path
		if not path.is_empty(): slots[str(int(slot))] = path
	return {"slots": slots}

static func from_dict(data: Dictionary, state: ItemOwnerState) -> EquipmentState:
	var equipment := EquipmentState.new(state)
	if equipment.is_closed(): return null
	if not state._begin_guard(): return null
	var raw_slots: Variant = data.get("slots", {})
	if typeof(raw_slots) == TYPE_DICTIONARY:
		var slots: Dictionary = raw_slots
		for slot_value in [0, 1, 2]:
			var key := str(slot_value)
			if not slots.has(key) or typeof(slots[key]) != TYPE_STRING: continue
			if not ResourceLoader.exists(slots[key]): continue
			var definition := ResourceLoader.load(slots[key]) as ItemDef
			if definition != null: state._legacy_create_and_place_while_guard(definition, ItemOwnerState.EQUIPMENT_BASE + slot_value)
	state._end_guard()
	return equipment
