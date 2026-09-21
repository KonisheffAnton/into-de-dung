extends Resource
class_name ItemDef

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var effects: Array[ItemEffect] = []
@export var use_heal_amount: float = 0.0
@export var use_summon: bool = false
@export var max_charges: int = 0
@export var armor_max: int = 0
@export var armor_resistances: Dictionary = {"physical": 0, "fire": 0}
