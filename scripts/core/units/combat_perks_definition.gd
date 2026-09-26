extends Resource
class_name CombatPerksDefinition

## Перки остаются отдельными флагами, чтобы оглушение и иммунитеты не меняли реакционную систему.
@export var sneak_attack: bool = false
@export var tank_reactions: bool = false
@export var stunning_strike: bool = false
@export var stun_immune: bool = false
@export var entangle_immune: bool = false
