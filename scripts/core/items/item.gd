extends Resource
class_name Item

## Данные предмета: идентичность + список эффектов (композиция). Не
## содержит игровой логики применения — этим занимаются EquipmentComponent/
## InventoryComponent, вызывая on_equip/on_unequip у каждого эффекта.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var effects: Array[ItemEffect] = []


## Применяет все эффекты предмета к владельцу. Прокидывает item_id в
## эффекты, которые в нём нуждаются (StatModifierEffect/TriggeredEffect),
## чтобы модификаторы/подписки можно было однозначно снять при unequip.
func apply_to(owner: Node, stats: StatsComponent) -> void:
	for effect in effects:
		if effect is StatModifierEffect:
			(effect as StatModifierEffect).item_id = id
		elif effect is TriggeredEffect:
			(effect as TriggeredEffect).item_id = id
		effect.on_equip(owner, stats)


func remove_from(owner: Node, stats: StatsComponent) -> void:
	for effect in effects:
		effect.on_unequip(owner, stats)
