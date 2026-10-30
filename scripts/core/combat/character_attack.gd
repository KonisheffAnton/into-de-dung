extends RefCounted
class_name CharacterAttack

static func enabled(stats: StatsBag) -> bool:
	return stats != null and stats.has_stat(StatTypes.StatType.POWER)

static func values(stats: StatsBag) -> Dictionary:
	if not enabled(stats): return {"power": 10.0, "mastery": 10.0}
	var result: Dictionary = {}
	for pair: Array in [["power", StatTypes.StatType.POWER], ["mastery", StatTypes.StatType.MASTERY]]:
		if not stats.has_stat(pair[1]): return {}
		var value := stats.get_value(pair[1])
		if not is_finite(value): return {}
		result[pair[0]] = maxf(0.0, value)
	return result

## Коэффициенты подготовки остаются рациональными: дробь не теряется до защиты.
static func components(strength: float, weapon: float, steps: int, guarded: bool, extras: Array[Dictionary], sneak_percent: int, critical: bool, piercing: int, cover: int, allies: int, attributes: Dictionary, scale_power: bool = true) -> Array[Dictionary]:
	if not attributes.has("power") or not attributes.has("mastery") or not ArmorAttack.valid_extras(extras): return []
	if piercing < 0 or piercing > 100 or cover not in [0, 30] or allies < 0 or allies > 3 or sneak_percent < 0 or sneak_percent > 1000: return []
	if piercing > 0 and piercing < 100 and extras.size() > 126: return []
	var power := ArmorFraction.from_decimal(attributes.power)
	var mastery := ArmorFraction.from_decimal(attributes.mastery)
	if not power.valid or not mastery.valid or power.numerator < 0 or mastery.numerator < 0: return []
	var f_power := power.add(ArmorFraction.make(40)).multiply(ArmorFraction.make(1, 50))
	# Пинок уже получает базу 2 × Мощь; повторный коэффициент усилил бы её дважды.
	if not scale_power: f_power = ArmorFraction.make(1)
	var f_mastery := mastery.multiply(ArmorFraction.make(6)).add(ArmorFraction.make(40)).multiply(ArmorFraction.make(1, 100))
	var height := ArmorFraction.make(maxi(0, steps), 10)
	if steps > 0: height = height.multiply(f_mastery)
	var position := ArmorFraction.make(1).add(height).add(ArmorFraction.make(allies, 10).multiply(f_mastery))
	if critical: position = position.add(mastery.multiply(ArmorFraction.make(1, 10)))
	var multiplier := f_power.multiply(position)
	if steps < 0: multiplier = multiplier.multiply(ArmorFraction.make(maxi(0, 10 + steps), 10))
	if guarded: multiplier = multiplier.multiply(ArmorFraction.make(7, 10))
	if cover > 0: multiplier = multiplier.multiply(ArmorFraction.make(7, 10))
	if not multiplier.valid: return []
	var base := ArmorFraction.from_decimal(strength).add(ArmorFraction.from_decimal(weapon))
	if not base.valid: return []
	if base.numerator < 0: base = ArmorFraction.make(0)
	var physical := base.multiply(multiplier).multiply(ArmorFraction.make(100 + sneak_percent, 100))
	if not physical.valid: return []
	var result: Array[Dictionary] = []
	for branch: Array in [["standard", 100 - piercing], ["hp_only_natural", piercing]]:
		if branch[1] == 0: continue
		var amount := physical.multiply(ArmorFraction.make(branch[1], 100))
		if not amount.valid: return []
		result.append({"type": "physical", "policy": branch[0], "numerator": amount.numerator, "denominator": amount.denominator, "source": "strength+weapon"})
	for extra: Dictionary in extras:
		var amount := ArmorFraction.make(maxi(0, extra.numerator), extra.denominator).multiply(ArmorFraction.make(extra.factor_num, extra.factor_den)).multiply(multiplier)
		if not amount.valid: return []
		result.append({"type": extra.type, "policy": extra.policy, "numerator": amount.numerator, "denominator": amount.denominator, "source": extra.source})
	return result
