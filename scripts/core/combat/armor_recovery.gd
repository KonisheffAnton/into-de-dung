extends RefCounted
class_name ArmorRecovery

## Восстановление распределяется по недостаче, а не случайным весам расхода.
static func restore(view: Dictionary, volume: int, source: String, persistent: bool = false) -> Dictionary:
	if volume <= 0 or source.is_empty() or view.is_empty(): return {"reason": &"armor/zero_restore"}
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
	var restored := mini(volume, missing)
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
	var extra := volume - restored if in_battle else 0
	var grant: Dictionary = {}
	if extra > 0:
		var state: Dictionary = after["state"]
		if state["next_grant_id"] >= ActionContext.MAX_ID - 1 or state["grants"].size() >= 4096: return {"reason": &"armor/overflow"}
		grant = {"grant_id": state["next_grant_id"], "source": source, "remaining": extra, "expires": "persistent" if persistent else "battle", "battle_id": state["battle_id"]}
		state["next_grant_id"] += 1
		state["grants"].append(grant)
	if ArmorRuntime.totals(after).is_empty(): return {"reason": &"armor/overflow"}
	return {"reason": &"", "after": after, "items": changes, "grant": grant, "restored": restored, "extra": extra}

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
