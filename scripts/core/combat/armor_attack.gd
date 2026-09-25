extends RefCounted
class_name ArmorAttack

static func valid_extras(extras: Array[Dictionary]) -> bool:
	if extras.size() > 127: return false
	for extra: Dictionary in extras:
		if not ItemSimulationSnapshot._shape(extra, {"type": TYPE_STRING, "policy": TYPE_STRING, "numerator": TYPE_INT, "denominator": TYPE_INT, "source": TYPE_STRING, "factor_num": TYPE_INT, "factor_den": TYPE_INT}): return false
		if extra["type"] not in ["physical", "fire"] or extra["policy"] not in ["standard", "hp_only_natural", "hp_only_unresisted"] or extra["source"].is_empty() or extra["source"].to_utf8_buffer().size() > 4096 or extra["denominator"] <= 0 or extra["factor_den"] <= 0 or extra["factor_num"] < 0: return false
	return true

static func components(strength: float, weapon: float, signed_steps: int, guarded: bool, extras: Array[Dictionary], backstab_bonus_percent: int = 0, critical_multiplier: int = 1, physical_piercing_percent: int = 0, cover_percent: int = 0) -> Array[Dictionary]:
	if cover_percent not in [0, 30]: return []
	if backstab_bonus_percent < 0 or backstab_bonus_percent > 1000 or critical_multiplier not in [1, 2] or physical_piercing_percent < 0 or physical_piercing_percent > 100: return []
	if not valid_extras(extras): return []
	# Две политики базы занимают два места в прежнем лимите 128 компонентов.
	if physical_piercing_percent > 0 and physical_piercing_percent < 100 and extras.size() > 126: return []
	var base := ArmorFraction.from_decimal(strength).add(ArmorFraction.from_decimal(weapon))
	if not base.valid: return []
	if base.numerator < 0: base = ArmorFraction.make(0)
	var height := ArmorFraction.make(maxi(0, 10 + signed_steps), 10)
	var multiplier := height.multiply(ArmorFraction.make(7, 10) if guarded else ArmorFraction.make(1))
	var physical := base.multiply(multiplier)
	if backstab_bonus_percent > 0:
		physical = base.multiply(height).add(base.multiply(ArmorFraction.make(backstab_bonus_percent, 100)))
		physical = physical.multiply(ArmorFraction.make(7, 10) if guarded else ArmorFraction.make(1))
	if not physical.valid: return []
	if critical_multiplier == 2:
		physical = physical.multiply(ArmorFraction.make(2))
		if not physical.valid: return []
	# Бонус входит только в физическую базу: предметные компоненты наследуют высоту и защиту, но не удар в спину.
	var result: Array[Dictionary] = []
	if physical_piercing_percent == 0:
		result = ArmorRuntime.physical(physical, "strength+weapon")
		if result.is_empty(): return []
	else:
		var standard := physical.multiply(ArmorFraction.make(100 - physical_piercing_percent, 100))
		var piercing := physical.multiply(ArmorFraction.make(physical_piercing_percent, 100))
		if not standard.valid or not piercing.valid: return []
		# Доли сохраняют точность до D0: округление каждой политики делает сам расчёт попадания.
		if physical_piercing_percent < 100:
			result.append({"type": "physical", "policy": "standard", "numerator": standard.numerator, "denominator": standard.denominator, "source": "strength+weapon"})
		if physical_piercing_percent > 0:
			result.append({"type": "physical", "policy": "hp_only_natural", "numerator": piercing.numerator, "denominator": piercing.denominator, "source": "strength+weapon"})
	for extra: Dictionary in extras:
		if not ItemSimulationSnapshot._shape(extra, {"type": TYPE_STRING, "policy": TYPE_STRING, "numerator": TYPE_INT, "denominator": TYPE_INT, "source": TYPE_STRING, "factor_num": TYPE_INT, "factor_den": TYPE_INT}): return []
		var amount := ArmorFraction.make(maxi(0, extra["numerator"]), extra["denominator"])
		var factor := ArmorFraction.make(extra["factor_num"], extra["factor_den"])
		if not factor.valid or factor.numerator < 0: return []
		amount = amount.multiply(factor).multiply(multiplier)
		if critical_multiplier == 2: amount = amount.multiply(ArmorFraction.make(2))
		if not amount.valid: return []
		result.append({"type": extra["type"], "policy": extra["policy"], "numerator": amount.numerator, "denominator": amount.denominator, "source": extra["source"]})
	if cover_percent > 0:
		# Прикрытие уменьшает каждый компонент до единственного округления D0.
		for row: Dictionary in result:
			var protected := ArmorFraction.make(row["numerator"], row["denominator"]).multiply(ArmorFraction.make(7, 10))
			if not protected.valid: return []
			row["numerator"] = protected.numerator
			row["denominator"] = protected.denominator
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
