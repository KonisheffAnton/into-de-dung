extends RefCounted
class_name CombatPerksState

enum Mode { NONE, OPPORTUNIST, COVER, COUNTERATTACK = 3 }

const MAX_ID: int = 9223372036854775807

var definition: CombatPerksDefinition = CombatPerksDefinition.new()
var mode: int = Mode.NONE
var cover_target_id: int = 0
var reaction_left: int = 0
var movement_stopped: bool = false
## Новые сессии хранят запас бонусных действий в ActionResources.
var uses_bonus_actions: bool = false

func to_dict() -> Dictionary:
	if get_script() != CombatPerksState or definition == null or definition.get_script() != CombatPerksDefinition: return {}
	var value := {"schema_version": 7, "uses_bonus_actions": uses_bonus_actions,
		"definition": {"sneak_attack": definition.sneak_attack, "tank_reactions": definition.tank_reactions,
			"stunning_strike": definition.stunning_strike, "stun_immune": definition.stun_immune,
			"entangle_immune": definition.entangle_immune, "counterattack": definition.counterattack,
			"burning_bypass_hp_gate": definition.burning_bypass_hp_gate, "passive_opportunist": definition.passive_opportunist},
		"mode": mode, "cover_target_id": cover_target_id, "reaction_left": reaction_left, "movement_stopped": movement_stopped}
	return value if valid(value) else {}

static func valid(value: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(value, {"schema_version": TYPE_INT, "uses_bonus_actions": TYPE_BOOL,
		"definition": TYPE_DICTIONARY, "mode": TYPE_INT, "cover_target_id": TYPE_INT,
		"reaction_left": TYPE_INT, "movement_stopped": TYPE_BOOL}): return false
	if value.schema_version != 7: return false
	if not ItemSimulationSnapshot._shape(value.definition, {"sneak_attack": TYPE_BOOL, "tank_reactions": TYPE_BOOL,
		"stunning_strike": TYPE_BOOL, "stun_immune": TYPE_BOOL, "entangle_immune": TYPE_BOOL,
		"counterattack": TYPE_BOOL, "burning_bypass_hp_gate": TYPE_BOOL, "passive_opportunist": TYPE_BOOL}): return false
	var perks: Dictionary = value.definition
	if value.uses_bonus_actions:
		if value.reaction_left != 0: return false
	elif perks.passive_opportunist: return false
	if value.mode not in [Mode.NONE, Mode.OPPORTUNIST, Mode.COVER, Mode.COUNTERATTACK]: return false
	if value.cover_target_id < 0 or value.cover_target_id >= MAX_ID or value.reaction_left not in [0, 1]: return false
	if value.mode == Mode.OPPORTUNIST and not perks.tank_reactions and not perks.passive_opportunist: return false
	if value.mode == Mode.COVER and not perks.tank_reactions: return false
	if value.mode == Mode.COUNTERATTACK and not perks.counterattack: return false
	if not perks.tank_reactions and not perks.counterattack and not perks.passive_opportunist and (value.mode != Mode.NONE or value.cover_target_id != 0 or value.reaction_left != 0): return false
	if (value.mode == Mode.COVER) != (value.cover_target_id != 0): return false
	return true

static func from_dict(value: Dictionary) -> CombatPerksState:
	if not valid(value): return null
	var result := CombatPerksState.new()
	var perks: Dictionary = value.definition
	result.definition.sneak_attack = perks.sneak_attack
	result.definition.tank_reactions = perks.tank_reactions
	result.definition.stunning_strike = perks.stunning_strike
	result.definition.stun_immune = perks.stun_immune
	result.definition.entangle_immune = perks.entangle_immune
	result.definition.counterattack = perks.counterattack
	result.definition.burning_bypass_hp_gate = perks.burning_bypass_hp_gate
	result.definition.passive_opportunist = perks.passive_opportunist
	result.uses_bonus_actions = value.uses_bonus_actions
	result.mode = value.mode
	result.cover_target_id = value.cover_target_id
	result.reaction_left = value.reaction_left
	result.movement_stopped = value.movement_stopped
	return result

func copy() -> CombatPerksState:
	var value := to_dict()
	if value.is_empty(): return null
	return from_dict(value)
