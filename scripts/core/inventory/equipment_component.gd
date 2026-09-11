extends Node
class_name EquipmentComponent

## Слоты экипировки владельца (оружие/броня/трофей и т.п.). В отличие от
## InventoryComponent, здесь явное понятие "слот" — предмет активен только
## пока занимает слот, при equip() старый предмет в этом слоте автоматически
## снимается (эффекты откатываются) и возвращается вызывающему коду.

enum EquipSlot { WEAPON, ARMOR, TRINKET }

signal item_equipped(slot: EquipSlot, item: Item)
signal item_unequipped(slot: EquipSlot, item: Item)

@export var owner_node: Node
@export var stats: StatsComponent

var _slots: Dictionary = {} # EquipSlot -> Item


## Экипирует предмет в слот. Возвращает предмет, который был в слоте
## ранее (или null, если слот был пуст) — вызывающий код решает, что с
## ним делать (вернуть в инвентарь, выбросить и т.п.).
func equip(slot: EquipSlot, item: Item) -> Item:
	var previous: Item = unequip(slot)

	_slots[slot] = item
	item.apply_to(owner_node, stats)
	item_equipped.emit(slot, item)
	GameEventBus.item_acquired.emit(item, owner_node)

	return previous


func unequip(slot: EquipSlot) -> Item:
	if not _slots.has(slot):
		return null

	var item: Item = _slots[slot]
	_slots.erase(slot)
	item.remove_from(owner_node, stats)
	item_unequipped.emit(slot, item)
	GameEventBus.item_removed.emit(item, owner_node)

	return item


func get_equipped(slot: EquipSlot) -> Item:
	return _slots.get(slot)


func is_slot_occupied(slot: EquipSlot) -> bool:
	return _slots.has(slot)
