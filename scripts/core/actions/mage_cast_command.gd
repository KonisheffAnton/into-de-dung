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
	if AbilityDefinition.is_cell_spell(spell_id):
		var summon_plan := MageSummonEffect.prepare(context, target_id, target_cell, spell_id, ability.paid(spell_id))
		if summon_plan.reason != &"": return summon_plan
		if context._next_event_seq > ActionContext.MAX_ID - 8: return {"reason": &"sequence_exhausted"}
		return {"reason": &"", "target": summon_plan.target, "guard": summon_plan.guard,
			"source": DamageSource.new(&"mage", AbilityDefinition.mage_source_id(spell_id), Vector2i(-1, -1), 0, 0),
			"paid": ability.paid(spell_id), "summon_plan": summon_plan}
	var target := board.get_unit_by_id(target_id)
	if target == null or not target.is_alive() or not board.is_in_bounds(target.cell) or state.is_summon_pending(target_id): return {"reason": &"mage/invalid_target"}
	if target.faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return {"reason": &"mage/invalid_target"}
	if spell_id in [&"mage.fire", &"mage.heal", &"mage.test_heal", &"mage.shield"] and target.faction != (Faction.Type.ENEMY if spell_id == &"mage.fire" else Faction.Type.PLAYER): return {"reason": &"mage/invalid_target"}
	var guard := SpatialRules.capture_guard(context, [target], [target.cell], {target_id: [StatTypes.StatType.HP_MAX]})
	if guard == null or target.armor == null: return {"reason": &"mage/invalid_runtime"}
	var source := DamageSource.new(&"mage", AbilityDefinition.mage_source_id(spell_id), Vector2i(-1, -1), 0, 0)
	var request: DamageRequest = null
	var status_plan: Dictionary = {}
	var maximum := ActionHpExecutor._stat_value(target, StatTypes.StatType.HP_MAX)
	var hp_after := minf(maximum, target.vitals.get_hp() + float(spell.amount))
	if spell_id in [&"mage.heal", &"mage.test_heal"]:
		if target.vitals.get_hp() >= maximum or ActionHpExecutor.validate_heal(target_id, float(spell.amount), source, context) != &"": return {"reason": &"mage/full_hp"}
	elif spell_id == &"mage.shield":
		if not target.armor.in_battle: return {"reason": &"mage/invalid_runtime"}
		status_plan = {"shield_after": SpellShield.make(spell_id, spell.amount, spell.shield_hits)}
	elif spell_id == &"mage.fire":
		var extras: Array[Dictionary] = [{"type": "fire", "policy": "standard", "source": "mage.fire", "numerator": spell.amount, "denominator": 1, "factor_num": 1, "factor_den": 1}]
		var raw := ArmorAttack.components(0.0, 0.0, 0, target.guard_stance, extras, 0, 2 if ElementalRules.is_frozen(target) else 1)
		if not raw.is_empty(): raw.remove_at(0)
		request = ArmorAttack.request(target_id, raw, source)
		var plan := ArmorHitExecutor.prepare(request, guard.values["participants"][target_id]["armor"], target.vitals.get_hp(), maximum, context.get_rng(), ElementalRules.is_frozen(target))
		if plan.get("reason", &"") != &"": return plan
		if plan["hp_after"] == 0 and board.board_version >= ActionContext.MAX_ID: return {"reason": &"push/board_version_exhausted"}
	else:
		status_plan = MageStatusEffect.prepare(target, spell.effect, source, "mage:%d:%d" % [source.source_instance_id, revision], guard.values["participants"][target_id]["armor"])
		if status_plan.get("reason", &"") != &"": return status_plan
	if context._next_event_seq > ActionContext.MAX_ID - 8: return {"reason": &"sequence_exhausted"}
	return {"reason": &"", "target": target, "guard": guard, "source": source, "request": request, "hp_after": hp_after, "paid": ability.paid(spell_id), "effect": spell.effect, "status_plan": status_plan}

func execute(context: ActionContext) -> CommandStepResult:
	var plan := _prepare(context)
	if plan["reason"] != &"": return CommandStepResult.faulted(plan["reason"])
	var seal: Array = [spell_id, target_id, revision, target_cell]
	var ability := context.get_state().abilities
	var before := ability.to_dict()
	var target: UnitState = plan.target
	var source: DamageSource = plan.source
	var guard: SpatialRules.Guard = plan.guard
	guard = guard.ability_phase(plan.paid)
	# Обе части оплаты записываются без callback; baseline вычислен до первой записи.
	ability.apply_values(plan.paid)
	var result := CommandStepResult.applied([], [], [], null, true)
	result.events.append({"kind": &"mage_cast", "spell_id": String(spell_id), "actor_unit_id": 0, "target_unit_id": target.id, "source": source.to_dict(), "mana_before": before.mana, "mana_after": ability.mana, "cooldown_before": 0, "cooldown_after": ability.remaining(spell_id)})
	if not guard.check(context) or [spell_id, target_id, revision, target_cell] != seal:
		result.status = &"FAULTED"; result.reason = &"mage/checkpoint"; return result
	if plan.has("summon_plan"):
		var summoned := MageSummonEffect.apply(context, plan.summon_plan, spell_id, source, func() -> bool: return [spell_id, target_id, revision, target_cell] == seal)
		result.events.append_array(summoned.events); result.status = summoned.status; result.reason = summoned.reason
		return result
	if plan.request != null:
		var hit := ArmorHitExecutor.execute(plan.request, guard, context, func() -> bool: return [spell_id, target_id, revision, target_cell] == seal)
		var hit_result: CommandStepResult = hit.result
		result.events.append_array(hit_result.events); result.status = hit_result.status; result.reason = hit_result.reason
	elif plan.status_plan.has("shield_after"):
		var before_shield := target.armor.shield.duplicate(true)
		var after_shield: Dictionary = plan.status_plan.shield_after
		var view: Dictionary = guard.values.participants[target_id].armor.duplicate(true)
		SpellShield.write_state(view.state, after_shield)
		var expected := guard.armor_phase(target_id, view)
		target.armor.shield = after_shield.duplicate(true)
		result.events.append({"kind": &"shield_changed", "actor_unit_id": 0, "target_unit_id": target_id, "source": source.to_dict(), "before": before_shield, "after": after_shield, "absorbed": 0, "reason": "applied" if before_shield.is_empty() else "refreshed" if before_shield.spell_id == after_shield.spell_id else "replaced"})
		target.armor.changed.emit(&"shield", 0, int(before_shield.get("hp", 0)), int(after_shield.hp))
		if not expected.check(context) or [spell_id, target_id, revision, target_cell] != seal:
			result.status = &"FAULTED"; result.reason = &"mage/shield_checkpoint"
	elif not plan.status_plan.is_empty():
		var status_result := MageStatusEffect.apply(target, plan.effect, plan.status_plan.after, guard, context, func() -> bool: return [spell_id, target_id, revision, target_cell] == seal)
		result.events.append_array(status_result.events); result.status = status_result.status; result.reason = status_result.reason
	else:
		var expected := guard.hit_hp_phase(target_id, plan.hp_after, false)
		var receipt := target.vitals.heal_checked(plan.hp_after - target.vitals.get_hp(), func() -> StringName: return &"" if expected.check(context) and [spell_id, target_id, revision, target_cell] == seal else &"mage/checkpoint")
		if receipt.hp_written: result.events.append(ActionHpExecutor._draft(&"healed", target_id, source, receipt.hp_before, receipt.hp_after, receipt.hp_after - receipt.hp_before, true, true))
		if receipt.reason != &"": result.status = &"FAULTED"; result.reason = receipt.reason
	return result

static func valid_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "spell_id": TYPE_STRING, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY, "mana_before": TYPE_INT, "mana_after": TYPE_INT, "cooldown_before": TYPE_INT, "cooldown_after": TYPE_INT}): return false
	var source_id := AbilityDefinition.mage_source_id(StringName(draft.spell_id))
	if source_id == 0 or draft.actor_unit_id != 0 or draft.target_unit_id <= 0 or draft.target_unit_id >= ActionContext.MAX_ID: return false
	var cost := 2 if source_id == 1 else 3 if source_id == 2 else 1
	if draft.mana_before < 0 or draft.mana_before > 6 or draft.mana_after < 0 or draft.mana_before - draft.mana_after != cost or draft.cooldown_before != 0 or draft.cooldown_after < 0 or (source_id > 2 and draft.cooldown_after != 0): return false
	return draft.source == DamageSource.new(&"mage", source_id, Vector2i(-1, -1), 0, 0).to_dict()
