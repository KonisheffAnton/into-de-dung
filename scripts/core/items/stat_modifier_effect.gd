extends ItemEffect
class_name StatModifierEffect

## Эффект предмета, применяющий `StatModifier` к характеристике владельца при
## экипировке и снимающий его при потере. `source_id` модификатора берётся из
## `item_id`, поэтому `remove_modifiers_by_source()` гарантированно снимает
## именно то, что дал этот предмет. (Сохранённое решение модуля 5.)

@export var stat_type: StatTypes.StatType = StatTypes.StatType.STRENGTH
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_FLAT
@export var value: float = 0.0

## Заполняется владельцем `Item` (id самого предмета).
## ⚠️ Запись в это поле — мутация разделяемого `Resource` (часть C-3).
## Будет заменено на `ItemEffectRuntime` на шаге 0.8.
var item_id: StringName = &""


func on_equip(unit: UnitState) -> void:
	if unit == null or unit.stats == null:
		return
	var modifier := StatModifier.new(item_id, operation, value)
	unit.stats.add_modifier(stat_type, modifier)


func on_unequip(unit: UnitState) -> void:
	if unit == null or unit.stats == null:
		return
	unit.stats.remove_modifiers_by_source(item_id)
