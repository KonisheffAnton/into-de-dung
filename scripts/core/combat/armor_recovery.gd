extends RefCounted
class_name ArmorRecovery

## Восстановление распределяется по недостаче, а не случайным весам расхода.
static func restore(view: Dictionary, volume: Variant, source: String, persistent: bool = false) -> Dictionary:
	if source.is_empty() or view.is_empty(): return {"reason": &"armor/zero_restore"}
	if typeof(volume) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(volume)): return {"reason": &"armor/overflow"}
	var numeric_volume: float = float(volume)
	if numeric_volume <= 0.0: return {"reason": &"armor/zero_restore"}
	if not CombatAmount.valid(volume): return {"reason": &"armor/overflow"}
	if view.get("state", {}).get("fractional", false): return _restore_fractional(view, numeric_volume, source, persistent)
	if numeric_volume != floorf(numeric_volume): return {"reason": &"armor/overflow"}
	# Целевой путь переводит множитель 1.0 обратно в int, сохраняя legacy DTO-типы.
	var integer_volume: int = int(volume)
	var after := view.duplicate(true)
	var indices: Array[int] = []
	var weights: Array[int] = []
	var missing := 0
	for index: int in after["items"].size():
		var item: Dictionary = after["items"][index]
		if item["placement"] < ItemOwnerState.EQUIPMENT_BASE: continue
		var gap: int = item["maximum"] - item["remaining"]
		if gap < 0 or missing > ActionContext.MAX_ID - gap: return {"reason": &"armor/overflow"}
		missing += gap
		indices.append(index); weights.append(gap)
	var restored := mini(integer_volume, missing)
	var in_battle: bool = after["state"]["in_battle"]
	if not in_battle and restored == 0: return {"reason": &"armor/full"}
	var allocations: Array[int] = []
	if restored > 0: allocations = ArmorHitCalculation.distribute(restored, weights)
	if restored > 0 and allocations.size() != indices.size(): return {"reason": &"armor/overflow"}
	var changes: Array[Dictionary] = []
	for offset: int in allocations.size():
		if allocations[offset] == 0: continue
		var item: Dictionary = after["items"][indices[offset]]
		changes.append({"id": item["item_id"], "before": item["remaining"], "after": int(item["remaining"]) + allocations[offset]})
		item["remaining"] += allocations[offset]
	var extra := integer_volume - restored if in_battle else 0
	var grant: Dictionary = {}
	if extra > 0:
		var state: Dictionary = after["state"]
		if state["next_grant_id"] >= ActionContext.MAX_ID - 1 or state["grants"].size() >= 4096: return {"reason": &"armor/overflow"}
		grant = {"grant_id": state["next_grant_id"], "source": source, "remaining": extra, "expires": "persistent" if persistent else "battle", "battle_id": state["battle_id"]}
		state["next_grant_id"] += 1
		state["grants"].append(grant)
	if ArmorRuntime.totals(after).is_empty(): return {"reason": &"armor/overflow"}
	return {"reason": &"", "after": after, "items": changes, "grant": grant, "restored": restored, "extra": extra}

static func _restore_fractional(view: Dictionary, volume: float, source: String, persistent: bool) -> Dictionary:
	if not CombatAmount.valid(volume): return {"reason": &"armor/overflow"}
	# Отдельный путь сохраняет дробные остатки и не меняет integer-распределение legacy.
	var after := view.duplicate(true)
	var indices: Array[int] = []
	var weights: Array[float] = []
	var missing := 0.0
	for index: int in after["items"].size():
		var item: Dictionary = after["items"][index]
		if item["placement"] < ItemOwnerState.EQUIPMENT_BASE: continue
		var maximum := float(item["maximum"])
		var current := float(item["remaining"])
		if not CombatAmount.valid(maximum) or not CombatAmount.valid(current) or current > maximum: return {"reason": &"armor/overflow"}
		var gap := maximum - current
		missing += gap
		if not CombatAmount.valid(missing): return {"reason": &"armor/overflow"}
		indices.append(index)
		weights.append(gap)
	var restored := minf(float(volume), missing)
	var in_battle: bool = after["state"]["in_battle"]
	if not in_battle and restored == 0.0: return {"reason": &"armor/full"}
	var allocations: Array[float] = []
	if restored > 0.0:
		allocations = _distribute_fractional(restored, weights)
		if allocations.size() != indices.size(): return {"reason": &"armor/overflow"}
	var changes: Array[Dictionary] = []
	for offset: int in allocations.size():
		var allocation := allocations[offset]
		if allocation <= 0.0: continue
		var item: Dictionary = after["items"][indices[offset]]
		var before := float(item["remaining"])
		var next := before + allocation
		if not CombatAmount.valid(next) or next > float(item["maximum"]): return {"reason": &"armor/overflow"}
		changes.append({"id": item["item_id"], "before": item["remaining"], "after": next})
		item["remaining"] = next
	var extra := maxf(0.0, float(volume) - restored) if in_battle else 0.0
	var grant: Dictionary = {}
	if extra > 0.0:
		var state: Dictionary = after["state"]
		if state["next_grant_id"] >= ActionContext.MAX_ID - 1 or state["grants"].size() >= 4096: return {"reason": &"armor/overflow"}
		grant = {"grant_id": state["next_grant_id"], "source": source, "remaining": extra, "expires": "persistent" if persistent else "battle", "battle_id": state["battle_id"]}
		state["next_grant_id"] += 1
		state["grants"].append(grant)
	if ArmorRuntime.totals(after).is_empty(): return {"reason": &"armor/overflow"}
	return {"reason": &"", "after": after, "items": changes, "grant": grant, "restored": restored, "extra": extra}

static func _distribute_fractional(total: float, weights: Array[float]) -> Array[float]:
	var result: Array[float] = []
	var sum := 0.0
	var last_nonzero := -1
	for index: int in weights.size():
		var weight := weights[index]
		if not CombatAmount.valid(weight): return []
		sum += weight
		if not CombatAmount.valid(sum): return []
		result.append(0.0)
		if weight > 0.0: last_nonzero = index
	if total <= 0.0: return result
	if sum <= 0.0 or last_nonzero < 0: return []
	var assigned := 0.0
	for index: int in weights.size():
		var weight := weights[index]
		if weight <= 0.0: continue
		var share := clampf(total - assigned, 0.0, weight) if index == last_nonzero else clampf(total * (weight / sum), 0.0, weight)
		result[index] = share
		assigned += share
	if not CombatAmount.valid(assigned): return []
	return result

## Экономика хаба появится в D4; этот план задаёт оплату по факту для выбранных вещей.
static func repair(view: Dictionary, selected: Array[int], budget: int, materials: int) -> Dictionary:
	if view.is_empty() or budget < 0 or materials < 0: return {"reason": &"armor/invalid_repair"}
	var chosen: Dictionary = {}
	for id: int in selected:
		if id < 1 or chosen.has(id): return {"reason": &"armor/invalid_repair"}
		chosen[id] = true
	var restricted := view.duplicate(true)
	restricted["state"]["in_battle"] = false
	# persistent E сохраняется, обычные grants не участвуют в ремонте.
	var found: Dictionary = {}
	for item: Dictionary in restricted["items"]:
		if chosen.has(item["item_id"]):
			if item["placement"] < ItemOwnerState.EQUIPMENT_BASE: return {"reason": &"armor/invalid_repair"}
			found[item["item_id"]] = true
		else: item["placement"] = 0
	if found.size() != chosen.size(): return {"reason": &"armor/invalid_repair"}
	var result := restore(restricted, mini(budget, materials), "repair")
	if result.get("reason") in [&"armor/zero_restore", &"armor/full"]: return {"reason": &"", "cost": 0, "items": []}
	if result.get("reason") != &"": return result
	return {"reason": &"", "cost": result["restored"], "items": result["items"]}
