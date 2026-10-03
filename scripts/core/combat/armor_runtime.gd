extends RefCounted
class_name ArmorRuntime

const MAX_EXACT_HP: int = 9007199254740991

## Только значения: этот срез одновременно служит входом расчёта и seal guard.
static func capture(owner: ItemOwnerState) -> Dictionary:
	if owner == null or owner._closed or owner._owner == null or owner._owner.armor == null: return {}
	var state := owner._owner.armor
	if state.get_script() != ArmorState or not ArmorState.valid(state.to_dict()): return {}
	var items: Array[Dictionary] = []
	var keys: Dictionary = {}
	for id: int in owner._items:
		var item: ItemInstance = owner._items[id]
		if item == null or item.get_script() != ItemInstance or item._item_id != id or item._owner_id != owner._owner.id: return {}
		var definition := item.get_definition()
		if definition == null or definition.armor_max < 0 or not ArmorState.valid_resistances(definition.armor_resistances): return {}
		if item.armor_remaining < 0 or item.armor_remaining > definition.armor_max or item.armor_origin_owner < 1 or item.armor_origin_item < 1: return {}
		var key := [item.armor_origin_owner, item.armor_origin_item]
		if keys.has(key): return {}
		keys[key] = true
		var placement: int = owner._placements.get(id, -1)
		if item._placement != placement or item._active != (placement != 0): return {}
		items.append({"origin_owner": item.armor_origin_owner, "origin_item": item.armor_origin_item, "item_id": id, "definition_id": String(item._definition_id), "maximum": definition.armor_max, "remaining": item.armor_remaining, "resistances": definition.armor_resistances.duplicate(true), "placement": placement, "active": item._active})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["origin_owner"] < b["origin_owner"] or (a["origin_owner"] == b["origin_owner"] and a["origin_item"] < b["origin_item"]))
	return {"state": state.to_dict(), "items": items}

static func references(owner: ItemOwnerState) -> Dictionary:
	var result := {"armor": owner._owner.armor, "items": owner._items.duplicate(), "definitions": owner._definitions.duplicate(), "item_definitions": {}}
	for id: int in owner._items: result["item_definitions"][id] = (owner._items[id] as ItemInstance)._definition
	return result

static func same_references(owner: ItemOwnerState, refs: Dictionary) -> bool:
	if owner._owner.armor != refs.get("armor") or owner._items != refs.get("items") or owner._definitions != refs.get("definitions"): return false
	for id: int in owner._items:
		if (owner._items[id] as ItemInstance)._definition != refs["item_definitions"].get(id): return false
	return true

static func totals(view: Dictionary) -> Dictionary:
	if view.is_empty(): return {}
	var maximum := 0
	var current := 0
	var extra := 0
	var defenses: Dictionary = {}
	for type: String in ["physical", "fire"]:
		defenses[StringName(type)] = {"armor": 0, "natural": view["state"]["natural"][type], "limit_armor": 7500, "limit_natural": 7500}
	for item: Dictionary in view["items"]:
		if item["placement"] < ItemOwnerState.EQUIPMENT_BASE: continue
		if maximum > ActionContext.MAX_ID - item["maximum"] or current > ActionContext.MAX_ID - item["remaining"]: return {}
		maximum += int(item["maximum"]); current += int(item["remaining"])
		for type: String in ["physical", "fire"]:
			var sum := ArmorFraction.make(defenses[StringName(type)]["armor"]).add(ArmorFraction.make(item["resistances"][type]))
			if not sum.valid: return {}
			defenses[StringName(type)]["armor"] = sum.numerator
	for grant: Dictionary in view["state"]["grants"]:
		if extra > ActionContext.MAX_ID - grant["remaining"]: return {}
		extra += int(grant["remaining"])
	if current > ActionContext.MAX_ID - extra: return {}
	current += extra
	var seen: Dictionary = {}
	for perk: Dictionary in view["state"]["perks"]:
		if perk.has("kind"): continue
		if seen.has(perk["id"]): continue
		seen[perk["id"]] = true
		for branch: String in ["armor", "natural"]:
			if perk["branch"] not in [branch, "both"]: continue
			var record: Dictionary = defenses[StringName(perk["type"])]
			if record["limit_" + branch] > ActionContext.MAX_ID - perk["bonus"]: return {}
			record["limit_" + branch] += perk["bonus"]
	return {"maximum": maximum, "current": current, "extra": extra, "defenses": defenses}

static func components(raw: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw.is_empty() or raw.size() > 128: return result
	for component: Dictionary in raw:
		if not ItemSimulationSnapshot._shape(component, {"type": TYPE_STRING, "policy": TYPE_STRING, "numerator": TYPE_INT, "denominator": TYPE_INT, "source": TYPE_STRING}): return []
		var amount := ArmorFraction.make(component["numerator"], component["denominator"])
		if not amount.valid: return []
		result.append({"type": StringName(component["type"]), "policy": StringName(component["policy"]), "amount": amount, "source": StringName(component["source"])})
	return result

static func physical(amount: ArmorFraction, source: String = "physical") -> Array[Dictionary]:
	if amount == null or not amount.valid: return []
	return [{"type": "physical", "policy": "standard", "numerator": amount.numerator, "denominator": amount.denominator, "source": source}]

## Клон портов принадлежит плану; live RNG до commit не вызывается.
static func plan(view: Dictionary, raw: Array[Dictionary], hp: float, hp_max: float, rng: ActionRngPort) -> Dictionary:
	var failed := {"reason": &"armor/invalid_hit"}
	if not is_finite(hp) or not is_finite(hp_max) or hp != floorf(hp) or hp_max != floorf(hp_max) or hp < 0.0 or hp_max < 0.0 or hp > MAX_EXACT_HP or hp_max > MAX_EXACT_HP: return failed
	var values := totals(view)
	var prepared := components(raw)
	if values.is_empty() or prepared.is_empty(): return failed
	var shield_plan: Dictionary = {}
	if view.state.has("shield"):
		shield_plan = SpellShield.intercept(raw, view.state.shield)
		if shield_plan.reason != &"": return shield_plan
		prepared = components(shield_plan.raw)
	var calculation := ArmorHitCalculation.calculate(prepared, values["current"], values["maximum"], int(hp), int(hp_max), values["defenses"])
	if calculation.reason != &"": return {"reason": calculation.reason}
	var after := view.duplicate(true)
	if not shield_plan.is_empty(): SpellShield.write_state(after.state, shield_plan.after)
	var remaining: int = calculation.armor_spent
	var order: Array = after["state"]["grants"].duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["expires"] != b["expires"]: return a["expires"] == "battle"
		if a["battle_id"] != b["battle_id"]: return a["battle_id"] < b["battle_id"]
		return a["grant_id"] < b["grant_id"])
	var grant_changes: Array[Dictionary] = []
	for grant: Dictionary in order:
		var spent := mini(remaining, grant["remaining"])
		if spent == 0: continue
		grant_changes.append({"id": grant["grant_id"], "before": grant["remaining"], "after": int(grant["remaining"]) - spent})
		grant["remaining"] -= spent
		remaining -= spent
	var rng_copy: ActionRngPort = null
	var rng_before: Dictionary = rng.to_dict().duplicate(true) if rng != null else {}
	var draws := 0
	while remaining > 0:
		var candidates: Array[Dictionary] = []
		var weight := 0
		for item: Dictionary in after["items"]:
			if item["placement"] < ItemOwnerState.EQUIPMENT_BASE or item["remaining"] <= 0: continue
			if weight > ActionContext.MAX_ID - item["maximum"]: return failed
			weight += int(item["maximum"])
			candidates.append(item)
		if candidates.is_empty(): return failed
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
				if roll < candidate["maximum"]:
					chosen = candidate
					break
				roll -= int(candidate["maximum"])
		var spent := mini(remaining, chosen["remaining"])
		chosen["remaining"] -= spent
		remaining -= spent
	var item_changes: Array[Dictionary] = []
	for index: int in after["items"].size():
		var before: Dictionary = view["items"][index]
		var item: Dictionary = after["items"][index]
		if item["remaining"] != before["remaining"]: item_changes.append({"id": item["item_id"], "before": before["remaining"], "after": item["remaining"]})
	var result := {"reason": &"", "before": view.duplicate(true), "after": after, "raw": raw.duplicate(true), "p_num": calculation.p_num, "p_den": calculation.p_den, "rows": calculation.get_rows(), "armor_spent": calculation.armor_spent, "hp_before": calculation.hp_before, "hp_after": calculation.hp_after, "hp_loss": maxi(0, calculation.hp_before - calculation.hp_after), "hp_gain": maxi(0, calculation.hp_after - calculation.hp_before), "total_damage": calculation.total_damage, "total_healing": calculation.total_healing, "grant_changes": grant_changes, "item_changes": item_changes, "draws": draws, "rng_before": rng_before, "rng_after": rng_copy.to_dict().duplicate(true) if rng_copy != null else rng_before}

	if not shield_plan.is_empty(): result["shield"] = shield_plan
	return result
