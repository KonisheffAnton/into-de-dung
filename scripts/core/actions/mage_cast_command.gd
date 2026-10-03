extends Command
class_name MageCastCommand

var spell_id: StringName
var target_id: int
var revision: int
var target_cell: Vector2i
func _init(spell: StringName = &"", target: int = 0, rev: int = 0, cell: Vector2i = Vector2i(-1, -1)) -> void:
	spell_id = spell; target_id = target; revision = rev; target_cell = cell
func get_kind() -> StringName: return &"mage_cast"
func copy_for_queue() -> Command: return MageCastCommand.new(spell_id, target_id, revision, target_cell)
func projected_after(context: ActionContext) -> Dictionary:
	return context.get_state().abilities.paid(spell_id) if context != null and context.get_state() != null and context.get_state().abilities != null else {}
func validate(context: ActionContext) -> StringName: return _prepare(context).get("reason", &"")
func _prepare(context: ActionContext) -> Dictionary:
	if context == null or context.is_faulted() or context.get_state() == null or revision != context.get_revision() or revision < 0 or revision >= ActionContext.MAX_ID - 1: return {"reason": &"mage/invalid_context"}
	var state := context.get_state()
	var ability := state.abilities
	if ability == null or ability.get_script() != BattleAbilityState or not BattleAbilityState.valid(ability.to_dict()): return {"reason": &"mage/capability_required"}
	if not ability.mage_allowed or ability.team != Faction.Type.PLAYER or ability.stage != "active": return {"reason": &"mage/window_closed"}
	var spell := ability.definition(spell_id)
	if AbilityDefinition.mage_source_id(spell_id) == 0 or spell == null: return {"reason": &"mage/unknown_spell"}
	if ability.remaining(spell_id) > 0: return {"reason": &"mage/cooldown"}
	if ability.mana < spell.mana_cost: return {"reason": &"mage/insufficient_mana"}
	var board := state.get_board()
	var teams: Array[bool] = [false, false]
	for unit: UnitState in board.get_all_units():
		if unit.is_alive() and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]: teams[unit.faction] = true
	if not teams[0] or not teams[1]: return {"reason": &"mage/terminal"}
	var source := DamageSource.new(&"mage", AbilityDefinition.mage_source_id(spell_id), Vector2i(-1, -1), 0, 0)
	var plan := MageEffectExecutor.prepare(context, target_id, target_cell, spell.effect, spell.amount, spell.shield_hits, source, ability.paid(spell_id), spell_id)
	if plan.get("reason", &"") != &"": return plan
	if context._next_event_seq > ActionContext.MAX_ID - 8: return {"reason": &"sequence_exhausted"}
	return plan

func execute(context: ActionContext) -> CommandStepResult:
	var plan := _prepare(context)
	if plan["reason"] != &"": return CommandStepResult.faulted(plan["reason"])
	var seal: Array = [spell_id, target_id, revision, target_cell]
	var ability := context.get_state().abilities
	var before := ability.to_dict()
	var target: UnitState = plan.target
	var source: DamageSource = plan.source
	var guard: SpatialRules.Guard = plan.guard.ability_phase(plan.paid)
	# Обе части оплаты записываются без callback; baseline вычислен до первой записи.
	ability.apply_values(plan.paid)
	var result := CommandStepResult.applied([], [], [], null, true)
	result.events.append({"kind": &"mage_cast", "spell_id": String(spell_id), "actor_unit_id": 0, "target_unit_id": target.id, "source": source.to_dict(), "mana_before": before.mana, "mana_after": ability.mana, "cooldown_before": 0, "cooldown_after": ability.remaining(spell_id)})
	if not guard.check(context) or [spell_id, target_id, revision, target_cell] != seal:
		result.status = &"FAULTED"; result.reason = &"mage/checkpoint"; return result
	var effect_result := MageEffectExecutor.apply(context, plan, guard, func() -> bool: return [spell_id, target_id, revision, target_cell] == seal)
	result.events.append_array(effect_result.events); result.status = effect_result.status; result.reason = effect_result.reason
	return result

static func valid_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "spell_id": TYPE_STRING, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY, "mana_before": TYPE_INT, "mana_after": TYPE_INT, "cooldown_before": TYPE_INT, "cooldown_after": TYPE_INT}): return false
	var source_id := AbilityDefinition.mage_source_id(StringName(draft.spell_id))
	if source_id == 0 or draft.actor_unit_id != 0 or draft.target_unit_id <= 0 or draft.target_unit_id >= ActionContext.MAX_ID: return false
	var cost := 2 if source_id == 1 else 3 if source_id == 2 else 1
	if draft.mana_before < 0 or draft.mana_before > 6 or draft.mana_after < 0 or draft.mana_before - draft.mana_after != cost or draft.cooldown_before != 0 or draft.cooldown_after < 0 or (source_id > 2 and draft.cooldown_after != 0): return false
	return draft.source == DamageSource.new(&"mage", source_id, Vector2i(-1, -1), 0, 0).to_dict()
