extends Resource
class_name HeroClassDefinition

@export var id: StringName = &""
@export var display_name: String = ""
@export var base_attributes: Array[int] = []
@export var attack_range: int = 1
@export var weapon_damage: int = 0
@export var armor_max: int = 0
@export_multiline var abilities_text: String = ""
@export_multiline var equipment_text: String = ""
