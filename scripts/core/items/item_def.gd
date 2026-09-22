extends Resource
class_name ItemDef

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var effects: Array[ItemEffect] = []
@export var use_heal_amount: float = 0.0
@export var use_summon: bool = false
@export var summon_definition: SummonDefinition = null
@export var max_charges: int = 0
@export var armor_max: int = 0
@export var armor_resistances: Dictionary = {"physical": 0, "fire": 0}

func summon_definition_valid() -> bool:
	return summon_definition == null or (use_summon and SummonDefinition.valid_definition(summon_definition))

func get_summon_definition() -> SummonDefinition:
	if summon_definition == null:
		return SummonDefinition.new()
	return summon_definition.duplicate(true) as SummonDefinition

func has_custom_summon_definition() -> bool:
	return summon_definition != null and SummonDefinition.valid_definition(summon_definition) and not summon_definition.is_default()
