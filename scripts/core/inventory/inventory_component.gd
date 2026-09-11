extends Node
class_name InventoryComponent

## Список предметов, которые владелец НЕСЁТ. В стиле Isaac — пассивные
## предметы применяют свои эффекты сразу при получении (add_item), в
## отличие от EquipmentComponent, где эффекты применяются только пока
## предмет находится в занятом слоте.

signal item_added(item: Item)
signal item_removed(item: Item)

@export var owner_node: Node
@export var stats: StatsComponent

var _items: Array[Item] = []


func add_item(item: Item) -> void:
	_items.append(item)
	item.apply_to(owner_node, stats)
	item_added.emit(item)
	GameEventBus.item_acquired.emit(item, owner_node)


func remove_item(item: Item) -> void:
	if not _items.has(item):
		return
	_items.erase(item)
	item.remove_from(owner_node, stats)
	item_removed.emit(item)
	GameEventBus.item_removed.emit(item, owner_node)


func has_item(id: StringName) -> bool:
	for item in _items:
		if item.id == id:
			return true
	return false


func get_items() -> Array[Item]:
	return _items.duplicate()
