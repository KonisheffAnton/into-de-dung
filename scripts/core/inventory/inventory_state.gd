extends RefCounted
class_name InventoryState

signal item_added(item: ItemInstance)
signal item_removed(item: ItemInstance)

var _state: ItemOwnerState
var _closed := false

func _init(state: ItemOwnerState) -> void:
	_state = state
	if state == null or not state.register_inventory(): _closed = true

func is_closed() -> bool:
	return _closed or _state == null or _state.is_closed()

func add_item(item: ItemInstance) -> bool:
	if is_closed() or not _state._begin_guard(): return false
	var already_here := _state._is_registered_item(item) and item._get_placement() == ItemOwnerState.INVENTORY_PLACEMENT
	var accepted := _state._place_while_guard(item, ItemOwnerState.INVENTORY_PLACEMENT)
	if accepted and not already_here: item_added.emit(item)
	_state._end_guard()
	return accepted

func remove_item(item: ItemInstance) -> bool:
	if is_closed() or not _state._begin_guard(): return false
	var removed := _state._is_registered_item(item) and item._get_placement() == ItemOwnerState.INVENTORY_PLACEMENT and _state._detach_while_guard(item)
	if removed: item_removed.emit(item)
	_state._end_guard()
	return removed

func get_items() -> Array[ItemInstance]:
	if is_closed(): return []
	return _state.get_items_for(ItemOwnerState.INVENTORY_PLACEMENT)

func size() -> int: return get_items().size()
func count_of(id: StringName) -> int:
	return 0 if is_closed() else _state.get_item_count(id, ItemOwnerState.INVENTORY_PLACEMENT)
func has_item(id: StringName) -> bool: return count_of(id) > 0

func clear() -> void:
	if is_closed() or not _state._begin_guard(): return
	var removed := _state._clear_placement_while_guard(ItemOwnerState.INVENTORY_PLACEMENT)
	# Все размещения уже сняты: callbacks видят согласованное пустое состояние.
	for item in removed: item_removed.emit(item)
	_state._end_guard()

func close() -> void:
	if _closed or _state == null or _state.is_closed() or not _state._begin_guard(): return
	_state._close_container_while_guard(ItemOwnerState.INVENTORY_PLACEMENT)
	_state._retire_inventory()
	_closed = true
	_state._end_guard()

func to_dict() -> Dictionary:
	var paths: Array[String] = []
	for item in get_items():
		var path := item.get_definition().resource_path
		if path.is_empty():
			push_warning("InventoryState: предмет '%s' не имеет resource_path и не будет сохранён" % item.get_definition_id())
		else:
			paths.append(path)
	return {"item_paths": paths}

static func from_dict(data: Dictionary, state: ItemOwnerState) -> InventoryState:
	var inventory := InventoryState.new(state)
	if inventory.is_closed(): return null
	if not state._begin_guard(): return null
	var values: Variant = data.get("item_paths", [])
	if typeof(values) == TYPE_ARRAY:
		for raw in values:
			if typeof(raw) != TYPE_STRING: continue
			if not ResourceLoader.exists(raw): continue
			var definition := ResourceLoader.load(raw) as ItemDef
			if definition != null: state._legacy_create_and_place_while_guard(definition, ItemOwnerState.INVENTORY_PLACEMENT)
	state._end_guard()
	return inventory
