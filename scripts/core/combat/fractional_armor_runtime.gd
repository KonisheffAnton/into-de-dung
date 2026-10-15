extends RefCounted
class_name FractionalArmorRuntime

## Отдельная точная по дробям ветвь сохраняет прежние целочисленные fixtures.
static func plan(view: Dictionary, raw: Array[Dictionary], hp: float, hp_max: float, rng: ActionRngPort) -> Dictionary:
	var failed := {"reason": &"armor/invalid_hit"}
	if not CombatAmount.valid(hp) or not CombatAmount.valid(hp_max) or hp > hp_max: return failed
	var values := ArmorRuntime.totals(view)
	var prepared := ArmorRuntime.components(raw)
	if values.is_empty() or prepared.is_empty(): return failed
	var shield_plan: Dictionary = {}
	var multiplier := 1.0
	if view.state.has("shield"):
		var neutral := {&"physical": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}, &"fire": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}}
		var unprotected := FractionalArmorHitCalculation.calculate(prepared, 0.0, 0.0, hp, hp_max, neutral)
		if unprotected.reason != &"": return unprotected
		var shield: Dictionary = view.state.shield
		if not SpellShield.valid(shield): return failed
		var absorbed := minf(unprotected.total_damage, shield.hp)
		var shield_after := shield.duplicate(true)
		if absorbed > 0.0:
			shield_after.hp = maxf(0.0, float(shield.hp) - absorbed)
			shield_after.hits_left -= 1
			if shield_after.hp == 0.0 or shield_after.hits_left == 0: shield_after = {}
			multiplier = maxf(0.0, 1.0 - absorbed / float(unprotected.total_damage))
		shield_plan = {"reason": &"", "raw": raw.duplicate(true), "before": shield.duplicate(true), "after": shield_after, "absorbed": absorbed}
	var calculation := FractionalArmorHitCalculation.calculate(prepared, values.current, values.maximum, hp, hp_max, values.defenses, multiplier)
	if calculation.reason != &"": return calculation
	var after := view.duplicate(true)
	if not shield_plan.is_empty(): SpellShield.write_state(after.state, shield_plan.after)
	var remaining: float = calculation.armor_spent
	var exhaust_armor: bool = remaining > 0.0 and remaining == float(values.current)
	var order: Array = after.state.grants.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.expires != b.expires: return a.expires == "battle"
		if a.battle_id != b.battle_id: return a.battle_id < b.battle_id
		return a.grant_id < b.grant_id)
	var grant_changes: Array[Dictionary] = []
	for grant: Dictionary in order:
		var spent: float = grant.remaining if exhaust_armor else minf(remaining, grant.remaining)
		if spent <= 0.0: continue
		var next := maxf(0.0, float(grant.remaining) - spent)
		grant_changes.append({"id": grant.grant_id, "before": grant.remaining, "after": next})
		grant.remaining = next
		remaining = maxf(0.0, remaining - spent)
	var rng_copy: ActionRngPort = null
	var rng_before: Dictionary = rng.to_dict().duplicate(true) if rng != null else {}
	var draws := 0
	while remaining > 0.0 or exhaust_armor:
		var candidates: Array[Dictionary] = []
		var weight := 0
		for item: Dictionary in after.items:
			if item.placement < ItemOwnerState.EQUIPMENT_BASE or item.remaining <= 0: continue
			if weight > ActionContext.MAX_ID - item.maximum: return failed
			weight += int(item.maximum)
			candidates.append(item)
		if candidates.is_empty():
			if exhaust_armor: break
			return failed
		var chosen: Dictionary = candidates[0]
		if candidates.size() > 1:
			if rng_copy == null:
				if rng == null: return {"reason": &"armor/rng_missing"}
				rng_copy = rng.clone()
				if rng_copy == null or rng_copy == rng or rng_copy.get_script() != rng.get_script() or rng_copy.to_dict() != rng_before: return {"reason": &"armor/rng_not_cloneable"}
			var roll := rng_copy.next_int(&"combat", weight)
			if roll < 0 or roll >= weight: return {"reason": &"armor/rng_failure"}
			draws += 1
			for candidate: Dictionary in candidates:
				if roll < candidate.maximum:
					chosen = candidate
					break
				roll -= int(candidate.maximum)
		var spent: float = chosen.remaining if exhaust_armor else minf(remaining, chosen.remaining)
		chosen.remaining = maxf(0.0, float(chosen.remaining) - spent)
		remaining = maxf(0.0, remaining - spent)
	var item_changes: Array[Dictionary] = []
	for index: int in after.items.size():
		var before: Dictionary = view.items[index]
		var item: Dictionary = after.items[index]
		if item.remaining != before.remaining: item_changes.append({"id": item.item_id, "before": before.remaining, "after": item.remaining})
	var result := {"reason": &"", "before": view.duplicate(true), "after": after, "raw": raw.duplicate(true), "p_num": calculation.p_num, "p_den": calculation.p_den, "rows": calculation.rows.duplicate(true), "armor_spent": calculation.armor_spent, "hp_before": hp, "hp_after": calculation.hp_after, "hp_loss": maxf(0.0, hp - calculation.hp_after), "hp_gain": maxf(0.0, calculation.hp_after - hp), "total_damage": calculation.total_damage, "total_healing": calculation.total_healing, "grant_changes": grant_changes, "item_changes": item_changes, "draws": draws, "rng_before": rng_before, "rng_after": rng_copy.to_dict().duplicate(true) if rng_copy != null else rng_before}
	if not shield_plan.is_empty(): result["shield"] = shield_plan
	return result
