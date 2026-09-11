extends RefCounted
class_name EquipmentState

## Слоты экипировки владельца. В отличие от `InventoryState`, здесь есть
## явное понятие "слот": предмет активен только пока занимает слот, при
## `equip()` предыдущий предмет автоматически снимается (эффекты
## откатываются) и возвращается вызывающему коду. (Решение модуля 5.)
##
## ЗАМЕНЯЕТ `EquipmentComponent : Node` (R-1/R-3) — см. `InventoryState`.
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (D-5.3): `EquipSlot` — жёсткий enum из трёх значений.
## Для роглайка слоты должны быть ДАННЫМИ (`SlotDef : Resource`), иначе
## "добавить слот" = правка кода + миграция сохранений. Отложено до
## работающего среза (R-7): пока в игре нет ни одного экипируемого предмета,
## проверить data-driven слоты не на чем.
##
## ВАЖНО (R-4): значения enum попадают в сейвы — только append.

enum EquipSlot { WEAPON, ARMOR, TRINKET }

signal item_equipped(slot: EquipSlot, item: Item)
signal item_unequipped(slot: EquipSlot, item: Item)

var _owner: UnitState
var _slots: Dictionary = {} # EquipSlot -> Item


func _init(p_owner: UnitState) -> void:
	_owner = p_owner


## Экипирует предмет в слот. Возвращает предмет, который был в слоте ранее
## (или null) — вызывающий код решает, вернуть его в инвентарь или выбросить.
func equip(slot: EquipSlot, item: Item) -> Item:
	if item == null or _owner == null:
		return null

	var previous := unequip(slot)

	_slots[slot] = item
	item.apply_to(_owner)
	item_equipped.emit(slot, item)

	return previous


func unequip(slot: EquipSlot) -> Item:
	if not _slots.has(slot):
		return null

	var item: Item = _slots[slot]
	_slots.erase(slot)
	item.remove_from(_owner)
	item_unequipped.emit(slot, item)

	return item


func get_equipped(slot: EquipSlot) -> Item:
	if not _slots.has(slot):
		return null
	var item: Item = _slots[slot]
	return item


func is_slot_occupied(slot: EquipSlot) -> bool:
	return _slots.has(slot)


func get_occupied_slots() -> Array:
	return _slots.keys()


# --- Сериализация (R-4) ----------------------------------------------------

func to_dict() -> Dictionary:
	var slots: Dictionary = {}
	for key in _slots.keys():
		var slot: EquipSlot = key
		var item: Item = _slots[slot]
		if item.resource_path.is_empty():
			continue
		slots[str(int(slot))] = item.resource_path
	return {"slots": slots}


static func from_dict(data: Dictionary, p_owner: UnitState) -> EquipmentState:
	var equipment := EquipmentState.new(p_owner)
	var slots: Dictionary = data.get("slots", {})
	for key in slots.keys():
		var slot_int := int(String(key))
		var path := String(slots[key])
		if not ResourceLoader.exists(path):
			continue
		var item := load(path) as Item
		if item != null:
			equipment.equip(slot_int as EquipSlot, item)
	return equipment
