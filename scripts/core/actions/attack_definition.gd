extends Resource
class_name AttackDefinition

@export var id: StringName = &""
@export var profile: StringName = &""
@export var damage_components: Array[Dictionary] = []
@export var bleeding_policy: StringName = &""
@export var backstab_bonus_percent: int = 0
@export var critical_on_control: bool = false
@export var entangle_on_physical_hp: bool = false
@export var stun_on_physical_hp: bool = false
@export var sneak_attack_enabled: bool = false
@export var reaction_strike: bool = false
@export var chain_push: bool = false
