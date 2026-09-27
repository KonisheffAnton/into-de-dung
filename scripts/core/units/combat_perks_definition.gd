extends Resource
class_name CombatPerksDefinition

## Перки остаются отдельными флагами, чтобы оглушение и иммунитеты не меняли реакционную систему.
@export var sneak_attack: bool = false
@export var tank_reactions: bool = false
@export var stunning_strike: bool = false
@export var stun_immune: bool = false
@export var entangle_immune: bool = false
@export var counterattack: bool = false
@export var burning_bypass_hp_gate: bool = false

func get_ability_definitions() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	if get_script() != CombatPerksDefinition: return result
	for field: StringName in [&"sneak_attack", &"tank_reactions", &"stunning_strike", &"stun_immune", &"entangle_immune", &"counterattack", &"burning_bypass_hp_gate"]:
		var value := AbilityDefinition.new(); value.ability_id = StringName("perk:%s" % String(field)); result.append(value)
	for capability: StringName in [&"stun", &"entangle", &"bleeding", &"freeze"]:
		var immunity := AbilityDefinition.new(); immunity.ability_id = StringName("immunity:%s" % String(capability)); result.append(immunity)
	return result
