extends RefCounted
class_name MageEffectExecutor

## Единый исполнитель эффектов: оплата остаётся у команды, поэтому карта не проходит paid() K18.
static func prepare(context: ActionContext, target_id: int, target_cell: Vector2i, effect: StringName, amount: int, shield_hits: int, source: DamageSource, paid: Dictionary, spell_id: StringName, card_instance_id: int = 0, deck_after: Dictionary = {}, effects_after: Dictionary = {}) -> Dictionary:
	# Каталог K18 хранит короткий effect, каталог карт — имя обработчика.
	match effect:
		&"fire": effect = &"mage.fire"
		&"heal": effect = &"mage.heal"
		&"shield": effect = &"mage.shield"
		&"summon": effect = &"mage.test_summon"
		&"raise": effect = &"mage.test_raise"
	var state := context.get_state()
	var board := state.get_board()
	if effect in [&"mage.test_summon", &"mage.test_raise"]:
		var summon_id: StringName = spell_id
		var summon_plan := MageSummonEffect.prepare(context, target_id, target_cell, summon_id, paid, deck_after, effects_after)
		if summon_plan.get("reason", &"") != &"": return summon_plan
		return {"reason": &"", "target": summon_plan.target, "guard": summon_plan.guard, "source": source, "paid": paid, "summon_plan": summon_plan, "effect": effect, "spell_id": spell_id, "effects_after": summon_plan.effects_after}
	var target := board.get_unit_by_id(target_id)
	if target == null or not target.is_alive() or not board.is_in_bounds(target.cell) or state.is_summon_pending(target_id): return {"reason": &"mage/invalid_target"}
	if target.faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return {"reason": &"mage/invalid_target"}
	if effect == &"mage.fire" and target.faction != Faction.Type.ENEMY: return {"reason": &"mage/invalid_target"}
	if effect in [&"mage.heal", &"mage.test_heal", &"mage.shield", &"fire_imbue"] and target.faction != Faction.Type.PLAYER: return {"reason": &"mage/invalid_target"}
	var guard := SpatialRules.capture_guard(context, [target], [target.cell], {target_id: [StatTypes.StatType.HP_MAX]})
	if guard == null or target.armor == null: return {"reason": &"mage/invalid_runtime"}
	var request: DamageRequest = null
	var status_plan: Dictionary = {}
	var maximum := ActionHpExecutor._stat_value(target, StatTypes.StatType.HP_MAX)
	var hp_after := minf(maximum, target.vitals.get_hp() + float(amount))
	if effect in [&"mage.heal", &"mage.test_heal"]:
		if target.vitals.get_hp() >= maximum or ActionHpExecutor.validate_heal(target_id, float(amount), source, context) != &"": return {"reason": &"mage/full_hp"}
	elif effect == &"mage.shield":
		if not target.armor.in_battle: return {"reason": &"mage/invalid_runtime"}
		status_plan = {"shield_after": SpellShield.make(spell_id, amount, shield_hits)}
		if status_plan.shield_after.is_empty(): return {"reason": &"mage/invalid_runtime"}
	elif effect == &"mage.fire":
		var extras: Array[Dictionary] = [{"type": "fire", "policy": "standard", "source": String(spell_id), "numerator": amount, "denominator": 1, "factor_num": 1, "factor_den": 1}]
		var raw := ArmorAttack.components(0.0, 0.0, 0, target.guard_stance, extras, 0, 2 if ElementalRules.is_frozen(target) else 1)
		if not raw.is_empty(): raw.remove_at(0)
		request = ArmorAttack.request(target_id, raw, source)
		var plan := ArmorHitExecutor.prepare(request, guard.values["participants"][target_id]["armor"], target.vitals.get_hp(), maximum, context.get_rng(), ElementalRules.is_frozen(target))
		if plan.get("reason", &"") != &"": return plan
		if plan["hp_after"] == 0 and board.board_version >= ActionContext.MAX_ID: return {"reason": &"push/board_version_exhausted"}
	elif effect == &"fire_imbue":
		if state.card_effects == null or card_instance_id <= 0: return {"reason": &"mage/invalid_runtime"}
		var imbue := state.card_effects.imbue(target.id, card_instance_id, state.abilities.serials[target.faction])
		if imbue.is_empty(): return {"reason": &"mage/imbue_overflow"}
		effects_after = imbue.after
	else:
		status_plan = MageStatusEffect.prepare(target, effect, source, "mage:%d:%d" % [source.source_instance_id, context.get_revision()], guard.values["participants"][target_id]["armor"])
		if status_plan.get("reason", &"") != &"": return status_plan
	return {"reason": &"", "target": target, "guard": guard, "source": source, "request": request, "hp_after": hp_after, "paid": paid, "effect": effect, "status_plan": status_plan, "spell_id": spell_id, "effects_after": effects_after}

static func apply(context: ActionContext, plan: Dictionary, guard: SpatialRules.Guard, seal_check: Callable) -> CommandStepResult:
	var result := CommandStepResult.applied([], [], [], null, true)
	var target: UnitState = plan.target
	var source: DamageSource = plan.source
	var target_id: int = target.id
	if plan.has("summon_plan"):
		var summoned := MageSummonEffect.apply(context, plan.summon_plan, plan.spell_id, source, seal_check)
		result.events.append_array(summoned.events); result.status = summoned.status; result.reason = summoned.reason
		return result
	if plan.request != null:
		var hit := ArmorHitExecutor.execute(plan.request, guard, context, seal_check)
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
		if not expected.check(context) or not seal_check.call():
			result.status = &"FAULTED"; result.reason = &"mage/shield_checkpoint"
	elif not plan.status_plan.is_empty():
		var status_result := MageStatusEffect.apply(target, plan.effect, plan.status_plan.after, guard, context, seal_check)
		result.events.append_array(status_result.events); result.status = status_result.status; result.reason = status_result.reason
	elif plan.effect == &"fire_imbue":
		if not guard.check(context) or not seal_check.call(): result.status = &"FAULTED"; result.reason = &"mage/checkpoint"
	else:
		var expected := guard.hit_hp_phase(target_id, plan.hp_after, false)
		var receipt := target.vitals.heal_checked(plan.hp_after - target.vitals.get_hp(), func() -> StringName: return &"" if expected.check(context) and seal_check.call() else &"mage/checkpoint")
		if receipt.hp_written: result.events.append(ActionHpExecutor._draft(&"healed", target_id, source, receipt.hp_before, receipt.hp_after, receipt.hp_after - receipt.hp_before, true, true))
		if receipt.reason != &"": result.status = &"FAULTED"; result.reason = receipt.reason
	return result
