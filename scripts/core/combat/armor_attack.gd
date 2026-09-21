extends RefCounted
class_name ArmorAttack

static func valid_extras(extras: Array[Dictionary]) -> bool:
	if extras.size() > 127: return false
	for extra: Dictionary in extras:
		if not ItemSimulationSnapshot._shape(extra, {"type": TYPE_STRING, "policy": TYPE_STRING, "numerator": TYPE_INT, "denominator": TYPE_INT, "source": TYPE_STRING, "factor_num": TYPE_INT, "factor_den": TYPE_INT}): return false
		if extra["type"] not in ["physical", "fire"] or extra["policy"] not in ["standard", "hp_only_natural", "hp_only_unresisted"] or extra["source"].is_empty() or extra["source"].to_utf8_buffer().size() > 4096 or extra["denominator"] <= 0 or extra["factor_den"] <= 0 or extra["factor_num"] < 0: return false
	return true

static func components(strength: float, weapon: float, signed_steps: int, guarded: bool, extras: Array[Dictionary]) -> Array[Dictionary]:
	if not valid_extras(extras): return []
	var base := ArmorFraction.from_decimal(strength).add(ArmorFraction.from_decimal(weapon))
	if not base.valid: return []
	if base.numerator < 0: base = ArmorFraction.make(0)
	var height := ArmorFraction.make(maxi(0, 10 + signed_steps), 10)
	var multiplier := height.multiply(ArmorFraction.make(7, 10) if guarded else ArmorFraction.make(1))
	var result := ArmorRuntime.physical(base.multiply(multiplier), "strength+weapon")
	if result.is_empty(): return []
	for extra: Dictionary in extras:
		if not ItemSimulationSnapshot._shape(extra, {"type": TYPE_STRING, "policy": TYPE_STRING, "numerator": TYPE_INT, "denominator": TYPE_INT, "source": TYPE_STRING, "factor_num": TYPE_INT, "factor_den": TYPE_INT}): return []
		var amount := ArmorFraction.make(maxi(0, extra["numerator"]), extra["denominator"])
		var factor := ArmorFraction.make(extra["factor_num"], extra["factor_den"])
		if not factor.valid or factor.numerator < 0: return []
		amount = amount.multiply(factor).multiply(multiplier)
		if not amount.valid: return []
		result.append({"type": extra["type"], "policy": extra["policy"], "numerator": amount.numerator, "denominator": amount.denominator, "source": extra["source"]})
	return result

static func request(id: int, raw: Array[Dictionary], source: DamageSource) -> DamageRequest:
	var result := DamageRequest.new(id, 0.0, &"physical", &"armor", source)
	result.armor_components.assign(raw.duplicate(true))
	return result

static func fall(hp_max: float, steps: int, voluntary: bool) -> ArmorFraction:
	if steps < 2 or (voluntary and steps <= 2): return ArmorFraction.make(0)
	@warning_ignore("integer_division")
	var levels: int = steps / 2
	return ArmorFraction.from_decimal(hp_max).multiply(ArmorFraction.make(levels, 4))
