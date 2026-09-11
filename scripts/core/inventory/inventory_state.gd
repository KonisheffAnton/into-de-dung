extends RefCounted
class_name InventoryState

## Предметы, которые владелец НЕСЁТ. В стиле Isaac — пассивные предметы
## применяют свои эффекты сразу при получении. (Решение модуля 5.)
##
## ЗАМЕНЯЕТ `InventoryComponent : Node` (R-1/R-3): инвентарь — это состояние
## юнита, а не узел сцены. Прежняя версия связывалась с владельцем вручную
## через `@export owner_node` + `@export stats` в редакторе, и ничто не
## гарантировало, что они указывают на одного и того же юнита (часть C-1).
## Теперь владелец передаётся явно и всегда один.
##
## ДОБАВЛЕНО (фикс D-5.2): счётчик КОПИЙ предмета. Для синергий в стиле Isaac
## это обязательно — механики вида "каждая копия даёт +1" и условия "если у
## тебя 3 таких" невыразимы, если инвентарь не умеет считать дубликаты.

signal item_added(item: Item)
signal item_removed(item: Item)

var _owner: UnitState
var _items: Array[Item] = []


func _init(p_owner: UnitState) -> void:
	_owner = p_owner


func add_item(item: Item) -> void:
	if item == null or _owner == null:
		return
	_items.append(item)
	item.apply_to(_owner)
	item_added.emit(item)


func remove_item(item: Item) -> bool:
	if item == null or not _items.has(item):
		return false
	_items.erase(item)
	item.remove_from(_owner)
	item_removed.emit(item)
	return true


func has_item(id: StringName) -> bool:
	return count_of(id) > 0


## Сколько копий предмета с таким id несёт владелец (D-5.2).
func count_of(id: StringName) -> int:
	var n := 0
	for item in _items:
		if item.id == id:
			n += 1
	return n


func get_items() -> Array[Item]:
	return _items.duplicate()


func size() -> int:
	return _items.size()


# --- Сериализация (R-4) ----------------------------------------------------
## Сохраняются пути к ресурсам-определениям, а не сами объекты: определение
## предмета — это ассет, он не должен дублироваться в сейве.

func to_dict() -> Dictionary:
	var paths: Array[String] = []
	for item in _items:
		if item.resource_path.is_empty():
			push_warning("InventoryState: предмет '%s' не имеет resource_path и не будет сохранён" % item.id)
			continue
		paths.append(item.resource_path)
	return {"item_paths": paths}


static func from_dict(data: Dictionary, p_owner: UnitState) -> InventoryState:
	var inventory := InventoryState.new(p_owner)
	var paths: Array = data.get("item_paths", [])
	for path_variant in paths:
		var path := String(path_variant)
		if not ResourceLoader.exists(path):
			push_warning("InventoryState: ресурс '%s' не найден, предмет пропущен" % path)
			continue
		var item := load(path) as Item
		if item != null:
			inventory.add_item(item)
	return inventory
