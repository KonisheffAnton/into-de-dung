extends RefCounted
class_name WarriorKit

const CLEAVE: StringName = &"warrior_cleave"
const KICK: StringName = &"warrior_kick"

static func make() -> Dictionary:
	return {"ready_turn": 0}

static func valid(value: Variant) -> bool:
	return ItemSimulationSnapshot._shape(value, {"ready_turn": TYPE_INT}) and value.ready_turn >= 0 and value.ready_turn < ActionContext.MAX_ID

static func enabled(unit: UnitState) -> bool:
	return unit != null and unit.combat_perks != null and valid(unit.combat_perks.warrior)

static func recovery_factor(unit: UnitState) -> float:
	return 1.2 if enabled(unit) else 1.0

static func class_recovery_factor(class_id: StringName) -> float:
	return 1.2 if class_id == &"fighter" else 1.0

static func is_skill(id: StringName) -> bool:
	return id in [CLEAVE, KICK]

static func admission(context: ActionContext, actor: UnitState, id: StringName) -> StringName:
	if not is_skill(id): return &""
	if not enabled(actor) or actor.armor == null or not actor.armor.fractional: return &"warrior/capability_required"
	var clock := context.get_state().abilities
	if clock == null or not BattleAbilityState.valid(clock.to_dict()): return &"warrior/invalid_clock"
	if clock.stage != "active" or clock.team != actor.faction or BattleAbilityState.battle_over(context.get_state()): return &"warrior/not_active_turn"
	if id == CLEAVE:
		var serial: int = clock.serials[actor.faction]
		if serial < actor.combat_perks.warrior.ready_turn: return &"warrior/cooldown"
		if serial > ActionContext.MAX_ID - 3: return &"warrior/clock_exhausted"
	return &""

static func definition(id: StringName) -> AttackDefinition:
	if not is_skill(id): return null
	var result := AttackDefinition.new()
	result.id = id
	result.profile = AttackRules.ARMOR_PROFILE
	result.chain_push = true
	result.critical_on_control = true
	if id == CLEAVE:
		result.bleeding_policy = &"bypass_hp_gate"
		result.cooldown_turns = 1
	return result

static func valid_definition(value: AttackDefinition) -> bool:
	if not is_skill(value.id): return value.cooldown_turns == 0
	return value.profile == AttackRules.ARMOR_PROFILE and value.damage_components.is_empty() and value.backstab_bonus_percent == 0 and not value.entangle_on_physical_hp and not value.stun_on_physical_hp and not value.sneak_attack_enabled and not value.reaction_strike and value.chain_push and value.critical_on_control and value.cooldown_turns == (1 if value.id == CLEAVE else 0) and value.bleeding_policy == (&"bypass_hp_gate" if value.id == CLEAVE else &"")
