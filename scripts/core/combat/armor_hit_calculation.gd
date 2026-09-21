extends RefCounted
class_name ArmorHitCalculation

const MAX_INT: int = 9223372036854775807
const PERCENT_DENOMINATOR: int = 10000

class Result extends RefCounted:
	var reason: StringName = &""
	var rows: Array[Dictionary] = []
	var p_num: int = 0
	var p_den: int = 1
	var armor_spent: int = 0
	var hp_before: int = 0
	var hp_after: int = 0
	var total_damage: int = 0
	var total_healing: int = 0

	func get_rows() -> Array[Dictionary]:
		var copy: Array[Dictionary] = []
		for row: Dictionary in rows:
			var row_copy: Dictionary = {}
			for key: Variant in row:
				var value: Variant = row[key]
				if value is Array:
					row_copy[key] = (value as Array).duplicate(true)
				else:
					row_copy[key] = value
			copy.append(row_copy)
		return copy

static func calculate(components: Array[Dictionary], armor_current: int, armor_max: int, hp_before: int, hp_max: int, defenses: Dictionary, common_multiplier: ArmorFraction = null) -> Result:
	var result := Result.new()
	result.hp_before = hp_before
	result.hp_after = hp_before
	if armor_current < 0 or armor_max < 0 or hp_before < 0 or hp_max < 0 or hp_before > hp_max:
		result.reason = &"armor/invalid_hit"
		return result
	if not _valid_defenses(defenses):
		result.reason = &"armor/invalid_hit"
		return result
	var multiplier := common_multiplier if common_multiplier != null else ArmorFraction.make(1)
	if not multiplier.valid or multiplier.numerator < 0 or multiplier.denominator <= 0:
		result.reason = &"armor/invalid_hit"
		return result
	var p: Variant = _calculate_p(armor_current, armor_max)
	if p == null:
		result.reason = &"armor/overflow"
		return result
	result.p_num = p.numerator
	result.p_den = p.denominator
	var grouped: Dictionary = {}
	for component: Dictionary in components:
		if not _valid_component(component):
			result.reason = &"armor/invalid_hit"
			return result
		var type: StringName = _read(component, &"type") as StringName
		var policy: StringName = _read(component, &"policy") as StringName
		var key := String(type) + "|" + String(policy)
		if not grouped.has(key):
			grouped[key] = {&"type": type, &"policy": policy, &"amount": ArmorFraction.make(0), &"sources": []}
		var entry: Dictionary = grouped[key]
		var amount: ArmorFraction = _read(component, &"amount") as ArmorFraction
		if amount.numerator < 0:
			amount = ArmorFraction.make(0)
		var summed: ArmorFraction = (entry[&"amount"] as ArmorFraction).add(amount)
		if not summed.valid:
			result.reason = &"armor/overflow"
			return result
		entry[&"amount"] = summed
		(entry[&"sources"] as Array).append(_read(component, &"source") as StringName)
	for type: StringName in [&"physical", &"fire"]:
		for policy: StringName in [&"standard", &"hp_only_natural", &"hp_only_unresisted"]:
			var key := String(type) + "|" + String(policy)
			if grouped.has(key):
				var entry: Dictionary = grouped[key]
				var scaled: ArmorFraction = (entry[&"amount"] as ArmorFraction).multiply(multiplier)
				if not scaled.valid:
					result.reason = &"armor/overflow"
					return result
				var damage := scaled.floor_value()
				var row_result: Variant = _calculate_row(type, policy, damage, p, _read(defenses, type))
				if row_result == null:
					result.reason = &"armor/overflow"
					return result
				var row: Dictionary = row_result
				row[&"type"] = type
				row[&"D"] = damage
				row[&"policy"] = policy
				row[&"sources"] = (entry[&"sources"] as Array).duplicate()
				result.rows.append(row)
				var next_total: Variant = _safe_add(result.armor_spent, int(row[&"armor_spent"]))
				var next_damage: Variant = _safe_add(result.total_damage, int(row[&"hp_damage"]))
				var next_healing: Variant = _safe_add(result.total_healing, int(row[&"healing"]))
				if next_total == null or next_damage == null or next_healing == null:
					result.reason = &"armor/overflow"
					result.rows.clear()
					return result
				result.armor_spent = int(next_total)
				result.total_damage = int(next_damage)
				result.total_healing = int(next_healing)
	var weights: Array[int] = []
	var branch_total := 0
	for row: Dictionary in result.rows:
		var weight: int = int(row[&"B_damage"])
		weights.append(weight)
		var branch_sum: Variant = _safe_add(branch_total, weight)
		if branch_sum == null:
			result.reason = &"armor/overflow"
			result.rows.clear()
			return result
		branch_total = int(branch_sum)
	if branch_total > 0:
		var covered := mini(armor_current, branch_total)
		var shares := distribute(covered, weights)
		if shares.is_empty():
			result.reason = &"armor/overflow"
			result.rows.clear()
			return result
		result.armor_spent = 0
		result.total_damage = 0
		for i in range(result.rows.size()):
			var row: Dictionary = result.rows[i]
			var spent: int = shares[i]
			row[&"armor_spent"] = spent
			row[&"overflow"] = int(row[&"B_damage"]) - spent
			var hp_sum: Variant = _safe_add(int(row[&"H_direct"]), int(row[&"overflow"]))
			if hp_sum == null:
				result.reason = &"armor/overflow"
				result.rows.clear()
				return result
			row[&"hp_damage"] = int(hp_sum)
			var spent_sum: Variant = _safe_add(result.armor_spent, spent)
			var damage_sum: Variant = _safe_add(result.total_damage, int(row[&"hp_damage"]))
			if spent_sum == null or damage_sum == null:
				result.reason = &"armor/overflow"
				result.rows.clear()
				return result
			result.armor_spent = int(spent_sum)
			result.total_damage = int(damage_sum)
	else:
		result.armor_spent = 0
		result.total_damage = 0
		for row: Dictionary in result.rows:
			var damage_sum: Variant = _safe_add(result.total_damage, int(row[&"hp_damage"]))
			if damage_sum == null:
				result.reason = &"armor/overflow"
				result.rows.clear()
				return result
			result.total_damage = int(damage_sum)
	var net: Variant = _safe_add(hp_before, -result.total_damage)
	if net == null:
		result.reason = &"armor/overflow"
		result.rows.clear()
		return result
	net = _safe_add(int(net), result.total_healing)
	if net == null:
		result.reason = &"armor/overflow"
		result.rows.clear()
		return result
	result.hp_after = clampi(int(net), 0, hp_max)
	return result

static func distribute(total: int, weights: Array[int]) -> Array[int]:
	var result: Array[int] = []
	if total < 0 or weights.is_empty():
		return result
	var sum := 0
	for weight: int in weights:
		if weight < 0:
			return []
		var next: Variant = _safe_add(sum, weight)
		if next == null:
			return []
		sum = int(next)
	if sum <= 0:
		return []
	var remainders: Array[int] = []
	var assigned := 0
	for weight: int in weights:
		var product: Variant = _safe_mul(total, weight)
		if product == null:
			return []
		var share := int(product) / sum
		result.append(share)
		assigned += share
		remainders.append(int(product) % sum)
	var left := total - assigned
	while left > 0:
		var best := -1
		for i in range(remainders.size()):
			if remainders[i] >= 0 and (best < 0 or remainders[i] > remainders[best]):
				best = i
		if best < 0:
			return []
		result[best] += 1
		remainders[best] = -1
		left -= 1
	return result

static func _calculate_p(current: int, maximum: int) -> Variant:
	if maximum == 0:
		return ArmorFraction.make(0 if current > 0 else 1)
	if current >= maximum / 2 + maximum % 2: return ArmorFraction.make(0)
	var twice: Variant = _safe_mul(current, 2)
	if twice == null:
		return null
	var numerator: Variant = _safe_add(maximum, -int(twice))
	if numerator == null:
		return null
	return ArmorFraction.make(clampi(int(numerator), 0, maximum), maximum)

static func _calculate_row(type: StringName, policy: StringName, damage: int, p: ArmorFraction, defense: Dictionary) -> Variant:
	var h0 := 0
	var b0 := 0
	if policy == &"standard":
		var hp_fraction := ArmorFraction.make(damage).multiply(p)
		if not hp_fraction.valid:
			return null
		h0 = hp_fraction.floor_value()
		b0 = damage - h0
	elif policy == &"hp_only_natural":
		h0 = damage
	else:
		h0 = damage
	var r_b := 0
	var r_h: int = int(_read(defense, &"natural"))
	if policy == &"standard":
		var sum: Variant = _safe_add(int(_read(defense, &"armor")), int(_read(defense, &"natural")))
		if sum == null:
			return null
		r_b = mini(int(sum), int(_read(defense, &"limit_armor")))
		r_h = mini(r_h, int(_read(defense, &"limit_natural")))
	elif policy == &"hp_only_unresisted":
		r_h = 0
	else:
		r_b = 0
		r_h = mini(r_h, int(_read(defense, &"limit_natural")))
	var direct: Variant = _protected(h0, r_h)
	if direct == null:
		return null
	var branch: Variant = _protected(b0, r_b)
	if branch == null:
		return null
	var armor_damage := 0
	var healing_sum: Variant = _safe_add(int(direct[&"healing"]), int(branch[&"healing"]))
	if healing_sum == null:
		return null
	var healing := int(healing_sum)
	var hp_damage := int(direct[&"damage"])
	if b0 > 0 and int(branch[&"damage"]) > 0:
		armor_damage = int(branch[&"damage"])
	var values := [h0, b0, int(direct[&"damage"]), armor_damage, healing, hp_damage]
	for value: int in values:
		if value < 0 or value > MAX_INT:
			return null
	return {&"H0": h0, &"B0": b0, &"R_H": r_h, &"R_B": r_b, &"H_direct": int(direct[&"damage"]), &"B_damage": armor_damage, &"healing": healing, &"armor_spent": 0, &"overflow": 0, &"hp_damage": hp_damage}

static func _protected(amount: int, resistance: int) -> Variant:
	if resistance == -9223372036854775808: return null
	var factor: Variant = _safe_add(PERCENT_DENOMINATOR, -resistance)
	if factor == null:
		return null
	var magnitude: Variant = _safe_mul(amount, abs(int(factor)))
	if magnitude == null:
		return null
	var value := int(magnitude) / PERCENT_DENOMINATOR
	if factor < 0:
		return {&"damage": 0, &"healing": value}
	return {&"damage": value, &"healing": 0}

static func _valid_component(component: Dictionary) -> bool:
	if component.size() != 4: return false
	for key: StringName in [&"type", &"policy", &"amount", &"source"]:
		if not component.has(key):
			return false
	var type := _read(component, &"type") as StringName
	var policy := _read(component, &"policy") as StringName
	if type not in [&"physical", &"fire"] or policy not in [&"standard", &"hp_only_natural", &"hp_only_unresisted"]:
		return false
	var amount := _read(component, &"amount") as ArmorFraction
	return amount != null and amount.get_script() == ArmorFraction and amount.valid and amount.denominator > 0 and amount.numerator != -9223372036854775808 and (_read(component, &"source") as StringName) != &""

static func _valid_defenses(defenses: Dictionary) -> bool:
	if defenses.size() != 2: return false
	for type: StringName in [&"physical", &"fire"]:
		var entry_value: Variant = _read(defenses, type)
		if entry_value == null or not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if entry.size() != 4: return false
		for key: StringName in [&"armor", &"natural", &"limit_armor", &"limit_natural"]:
			var value: Variant = _read(entry, key)
			if value == null or not value is int:
				return false
			if key in [&"limit_armor", &"limit_natural"] and int(value) < 7500:
				return false
	return true

static func _read(dictionary: Dictionary, key: StringName) -> Variant:
	if dictionary.has(key):
		return dictionary[key]
	var text_key := String(key)
	if dictionary.has(text_key):
		return dictionary[text_key]
	return null

static func _safe_add(a: int, b: int) -> Variant:
	if b > 0 and a > MAX_INT - b:
		return null
	if b < 0 and a < -9223372036854775808 - b:
		return null
	return a + b

static func _safe_mul(a: int, b: int) -> Variant:
	if a == 0 or b == 0:
		return 0
	if abs(a) > MAX_INT / abs(b):
		return null
	return a * b
