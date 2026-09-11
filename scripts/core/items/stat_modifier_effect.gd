extends ItemEffect
class_name StatModifierEffect

## Эффект предмета, который применяет StatModifier к конкретной
## характеристике владельца при экипировке и снимает при потере предмета.
## source_id модификатора автоматически берётся из item_id, переданного
## при создании — так remove_modifiers_by_source() гарантированно снимает
## именно то, что дал этот предмет.

@export var stat_type: StatTypes.StatType = StatTypes.StatType.STRENGTH
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_FLAT
@export var value: float = 0.0

## Заполняется владельцем Item при создании эффекта (id самого предмета),
## чтобы модификатор можно было однозначно снять при потере предмета.
var item_id: StringName = &""


func on_equip(_owner: Node, stats: StatsComponent) -> void:
	if stats == null:
		return
	var modifier := StatModifier.new(item_id, operation, value)
	stats.add_modifier(stat_type, modifier)


func on_unequip(_owner: Node, stats: StatsComponent) -> void:
	if stats == null:
		return
	stats.remove_modifiers_by_source(item_id)
