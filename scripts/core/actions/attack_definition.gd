extends Resource
class_name AttackDefinition

@export var id: StringName = &""
@export var profile: StringName = &""
@export var damage_components: Array[Dictionary] = []
@export var bleeding_policy: StringName = &""
@export var backstab_bonus_percent: int = 0
@export var critical_on_control: bool = false
