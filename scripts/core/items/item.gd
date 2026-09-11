extends Resource
class_name Item

## Данные предмета: идентичность + список эффектов (композиция). Не содержит
## логики применения — этим занимаются Inventory/Equipment, вызывая
## `on_equip`/`on_unequip` у каждого эффекта. (Решение модуля 5.)
##
## ⚠️ БУДЕТ ПЕРЕИМЕНОВАН В `ItemDef` НА ШАГЕ 0.8 (R-1): этот класс — ОПРЕДЕЛЕНИЕ
## предмета ("что такое Меч"), а рантайм-экземпляр ("этот меч у этого юнита
## с 3 зарядами") станет отдельным `ItemInstance : RefCounted`.

@export var id: StringName = &""

## ⚠️ D-5.4: должно стать ключом локализации (`name_key`), иначе перевод
## потребует переделки всех `.tres`. Отложено до появления UI.
@export var display_name: String = ""
@export var description: String = ""

@export var effects: Array[ItemEffect] = []


## Применяет все эффекты предмета к владельцу.
##
## ИЗМЕНЕНО (частичный фикс D-5.5): раньше здесь была цепочка проверок типа
##     if effect is StatModifierEffect: ... elif effect is TriggeredEffect: ...
## то есть каждый новый тип эффекта, которому нужен `item_id`, требовал
## правки ЭТОГО файла (нарушение OCP). Теперь `item_id` проставляется через
## общий метод-сеттер, объявленный в базовом классе поведения.
##
## ⚠️ Сама запись `item_id` в эффект — мутация разделяемого `Resource`
## (дефект C-3). Уйдёт вместе с Def/Instance split на шаге 0.8.
func apply_to(unit: UnitState) -> void:
	if unit == null:
		return
	for effect in effects:
		_assign_item_id(effect)
		effect.on_equip(unit)


func remove_from(unit: UnitState) -> void:
	if unit == null:
		return
	for effect in effects:
		effect.on_unequip(unit)


func _assign_item_id(effect: ItemEffect) -> void:
	# `set()` не падает, если у конкретного эффекта поля нет — это позволяет
	# не перечислять типы эффектов здесь.
	if effect == null:
		return
	if &"item_id" in effect:
		effect.set(&"item_id", id)
