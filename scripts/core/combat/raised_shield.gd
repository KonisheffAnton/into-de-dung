extends RefCounted
class_name RaisedShield

const MAX_ID: int = ActionContext.MAX_ID

static func make() -> Dictionary:
	return {"active": false, "ready_turn": 0, "blocked_root": 0, "blocked_group": 0}

static func valid(value: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(value, {"active": TYPE_BOOL, "ready_turn": TYPE_INT, "blocked_root": TYPE_INT, "blocked_group": TYPE_INT}): return false
	if value.ready_turn < 0 or value.ready_turn >= MAX_ID or value.blocked_root < 0 or value.blocked_root >= MAX_ID or value.blocked_group < 0 or value.blocked_group >= MAX_ID: return false
	if (value.blocked_root == 0) != (value.blocked_group == 0): return false
	if value.active and value.blocked_root != 0: return false
	return true

static func write_state(state: Dictionary, value: Dictionary) -> void:
	if value.is_empty():
		state.erase("raised_shield")
	else:
		state["raised_shield"] = value.duplicate(true)
	state["schema_version"] = 3 if state.has("raised_shield") else (2 if state.has("shield") else 1)

static func activated(before: Dictionary, serial: int) -> Dictionary:
	if not valid(before) or before.active or serial < 1 or serial < before.ready_turn or serial > MAX_ID - 3: return {}
	var result := before.duplicate(true)
	result.active = true
	result.ready_turn = serial + 2
	result.blocked_root = 0
	result.blocked_group = 0
	return result

static func expired(before: Dictionary) -> Dictionary:
	if not valid(before): return {}
	var result := before.duplicate(true)
	result.active = false
	result.blocked_root = 0
	result.blocked_group = 0
	return result

static func intercept(raw: Array[Dictionary], before: Dictionary, root_id: int, group_id: int) -> Dictionary:
	var copied_raw: Array[Dictionary] = raw.duplicate(true)
	var unchanged := before.duplicate(true)
	var failure := {"reason": &"armor/invalid_hit", "raw": copied_raw, "before": unchanged, "after": unchanged.duplicate(true), "blocked": false}
	if not valid(before) or root_id <= 0 or root_id >= MAX_ID or group_id <= 0 or group_id >= MAX_ID: return failure
	if ArmorRuntime.components(raw).is_empty(): return failure
	var positive := false
	for component: Dictionary in raw:
		if int(component["numerator"]) > 0:
			positive = true
			break
	if not positive: return {"reason": &"", "raw": copied_raw, "before": unchanged, "after": unchanged.duplicate(true), "blocked": false}
	var should_reduce: bool = before.active or (before.blocked_root == root_id and before.blocked_group == group_id)
	if not should_reduce: return {"reason": &"", "raw": copied_raw, "before": unchanged, "after": unchanged.duplicate(true), "blocked": false}
	# Одна команда может породить несколько попаданий; пара root/group удерживает эффект до конца этой команды.
	var reduced: Array[Dictionary] = []
	for component: Dictionary in raw:
		var amount := ArmorFraction.make(int(component["numerator"]), int(component["denominator"]))
		# Масштабируем до округления брони, иначе дробные компоненты потеряли бы точность.
		var adjusted := amount.multiply(ArmorFraction.make(1, 10))
		if not adjusted.valid:
			failure["reason"] = &"armor/overflow"
			return failure
		var copy := component.duplicate(true)
		copy["numerator"] = adjusted.numerator
		copy["denominator"] = adjusted.denominator
		reduced.append(copy)
	var after := before.duplicate(true)
	if before.active:
		after["active"] = false
		after["blocked_root"] = root_id
		after["blocked_group"] = group_id
	return {"reason": &"", "raw": reduced, "before": unchanged, "after": after, "blocked": true}
