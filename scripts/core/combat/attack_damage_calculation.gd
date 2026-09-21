extends RefCounted
class_name AttackDamageCalculation

class Result extends RefCounted:
	var reason: StringName = &""
	var raw_attack: float = 0.0
	var scaled: float = 0.0
	var hit_amount: float = 0.0
	var _stages: Array[Dictionary] = []

	func get_stages() -> Array[Dictionary]:
		var copy: Array[Dictionary] = []
		for stage: Dictionary in _stages:
			copy.append({
				&"kind": stage[&"kind"] as StringName,
				&"input": float(stage[&"input"]),
				&"operand": float(stage[&"operand"]),
				&"output": float(stage[&"output"]),
			})
		return copy

static func calculate(strength: float, weapon: float, armor: float, spatial: bool, signed_height_steps: int, guarded: bool) -> Result:
	var result := Result.new()
	if not is_finite(strength) or not is_finite(weapon) or not is_finite(armor):
		result.reason = &"attack/nonfinite_damage"
		return result

	var raw_attack := strength + weapon
	if not is_finite(raw_attack):
		result.reason = &"attack/nonfinite_damage"
		return result
	result.raw_attack = raw_attack
	result._stages.append(_stage(&"base_add", strength, weapon, raw_attack))

	var scaled := raw_attack
	if spatial:
		var multiplier := SpatialRules.height_multiplier(signed_height_steps)
		scaled = raw_attack * multiplier
		if not is_finite(scaled):
			# Ошибка обнуляет стадии, чтобы наружу не просочился неполный успешный расчёт.
			result._stages.clear()
			result.reason = &"attack/nonfinite_damage"
			return result
		result._stages.append(_stage(&"height_multiply", raw_attack, multiplier, scaled))
	result.scaled = scaled

	var raw := scaled - armor
	if not is_finite(raw):
		# Ошибка обнуляет стадии, чтобы наружу не просочился неполный успешный расчёт.
		result._stages.clear()
		result.reason = &"attack/nonfinite_damage"
		return result
	result._stages.append(_stage(&"armor_subtract", scaled, armor, raw))

	var amount := maxf(1.0, raw)
	result._stages.append(_stage(&"minimum", raw, 1.0, amount))
	if guarded:
		var guarded_amount := amount * 0.7
		result._stages.append(_stage(&"guard_multiply", amount, 0.7, guarded_amount))
		amount = maxf(1.0, guarded_amount)
		result._stages.append(_stage(&"guard_minimum", guarded_amount, 1.0, amount))
	result.hit_amount = amount
	return result

static func _stage(kind: StringName, input: float, operand: float, output: float) -> Dictionary:
	return {&"kind": kind, &"input": input, &"operand": operand, &"output": output}
