extends RefCounted
class_name FractionalArmorHitCalculation

const PERCENT_DENOMINATOR: float = 10000.0

static func calculate(components: Array[Dictionary], armor_current: float, armor_max: float, hp_before: float, hp_max: float, defenses: Dictionary, common_multiplier: float = 1.0) -> Dictionary:
	var result := _empty_result(&"armor/invalid_hit", hp_before)
	if not _valid_nonnegative(armor_current) or not _valid_nonnegative(armor_max) or not _valid_nonnegative(hp_before) or not _valid_nonnegative(hp_max):
		return result
	if armor_current > float(ArmorRuntime.MAX_EXACT_HP) or armor_max > float(ArmorRuntime.MAX_EXACT_HP) or hp_before > float(ArmorRuntime.MAX_EXACT_HP) or hp_max > float(ArmorRuntime.MAX_EXACT_HP) or hp_before > hp_max:
		return result
	if components.is_empty() or components.size() > 128 or not is_finite(common_multiplier) or common_multiplier < 0.0 or not ArmorHitCalculation._valid_defenses(defenses):
		return result
	var p := 1.0
	if armor_max == 0.0:
		p = 0.0 if armor_current > 0.0 else 1.0
	elif armor_current >= armor_max * 0.5:
		p = 0.0
	else:
		p = clampf(1.0 - (2.0 * armor_current) / armor_max, 0.0, 1.0)
	if not _valid_magnitude(p):
		return _overflow_result(hp_before)
	var grouped: Dictionary = {}
	for component: Dictionary in components:
		if not _valid_component(component):
			return result
		var type: StringName = component[&"type"]
		var policy: StringName = component[&"policy"]
		var key := String(type) + "|" + String(policy)
		if not grouped.has(key):
			grouped[key] = {&"type": type, &"policy": policy, &"amount": 0.0, &"sources": []}
		var entry: Dictionary = grouped[key]
		var amount_resource: ArmorFraction = component[&"amount"]
		var amount := float(amount_resource.numerator) / float(amount_resource.denominator)
		var summed := float(entry[&"amount"]) + amount
		if not _valid_magnitude(amount) or not _valid_magnitude(summed):
			return _overflow_result(hp_before)
		entry[&"amount"] = summed
		(entry[&"sources"] as Array).append(component[&"source"])
	var rows: Array[Dictionary] = []
	for type: StringName in [&"physical", &"fire"]:
		for policy: StringName in [&"standard", &"hp_only_natural", &"hp_only_unresisted"]:
			var key := String(type) + "|" + String(policy)
			if not grouped.has(key):
				continue
			var entry: Dictionary = grouped[key]
			var damage := float(entry[&"amount"]) * common_multiplier
			if not _valid_magnitude(damage):
				return _overflow_result(hp_before)
			var row := _make_row(policy, damage, p, _read(defenses, type))
			if row.is_empty():
				return _overflow_result(hp_before)
			row[&"type"] = type
			row[&"D"] = damage
			row[&"policy"] = policy
			row[&"sources"] = (entry[&"sources"] as Array).duplicate()
			rows.append(row)
	var branch_total := 0.0
	for row: Dictionary in rows:
		branch_total += float(row[&"B_damage"])
		if not _valid_magnitude(branch_total):
			return _overflow_result(hp_before)
	var armor_spent := 0.0
	var total_damage := 0.0
	var total_healing := 0.0
	if branch_total > 0.0:
		var covered := minf(armor_current, branch_total)
		var last_nonzero := -1
		for index: int in rows.size():
			if float(rows[index][&"B_damage"]) > 0.0:
				last_nonzero = index
		var assigned := 0.0
		for index: int in rows.size():
			var row: Dictionary = rows[index]
			var branch_damage: float = row[&"B_damage"]
			var spent := 0.0
			if branch_damage > 0.0:
				if index == last_nonzero:
					# Остаток назначается последней ветви, чтобы сумма расходов точно совпала с покрытием.
					spent = clampf(covered - assigned, 0.0, branch_damage)
				else:
					spent = clampf(covered * branch_damage / branch_total, 0.0, branch_damage)
					assigned += spent
			var overflow := branch_damage - spent
			var hp_damage := float(row[&"H_direct"]) + overflow
			if not _valid_magnitude(spent) or not _valid_magnitude(overflow) or not _valid_magnitude(hp_damage):
				return _overflow_result(hp_before)
			row[&"armor_spent"] = spent
			row[&"overflow"] = overflow
			row[&"hp_damage"] = hp_damage
			armor_spent += spent
			total_damage += hp_damage
			total_healing += float(row[&"healing"])
		# Полное покрытие берём из исходного запаса, без ошибки повторного суммирования ветвей.
		armor_spent = covered
	else:
		for row: Dictionary in rows:
			total_damage += float(row[&"hp_damage"])
			total_healing += float(row[&"healing"])
	if not _valid_magnitude(armor_spent) or not _valid_magnitude(total_damage) or not _valid_magnitude(total_healing):
		return _overflow_result(hp_before)
	var hp_net := hp_before - total_damage
	var hp_with_healing := hp_net + total_healing
	if not _valid_magnitude(hp_net) or not _valid_magnitude(hp_with_healing):
		return _overflow_result(hp_before)
	var hp_after := clampf(hp_with_healing, 0.0, hp_max)
	return {
		&"reason": &"",
		&"p_num": p,
		&"p_den": 1.0,
		&"armor_spent": armor_spent,
		&"hp_before": hp_before,
		&"hp_after": hp_after,
		&"total_damage": total_damage,
		&"total_healing": total_healing,
		&"rows": rows,
	}

static func _make_row(policy: StringName, damage: float, p: float, defense: Dictionary) -> Dictionary:
	var h0 := 0.0
	var b0 := 0.0
	if policy == &"standard":
		h0 = damage * p
		b0 = damage - h0
	else:
		h0 = damage
	var natural := int(_read(defense, &"natural"))
	var natural_limit := int(_read(defense, &"limit_natural"))
	var armor_limit := int(_read(defense, &"limit_armor"))
	var r_h := 0
	var r_b := 0
	if policy == &"standard":
		r_h = mini(natural, natural_limit)
		var armor_resistance: int = _read(defense, &"armor")
		if (natural > 0 and armor_resistance > 9223372036854775807 - natural) or (natural < 0 and armor_resistance < -9223372036854775808 - natural):
			return {}
		r_b = mini(armor_resistance + natural, armor_limit)
	elif policy == &"hp_only_natural":
		r_h = mini(natural, natural_limit)
	var direct := _protected(h0, r_h)
	var branch := _protected(b0, r_b)
	if direct.is_empty() or branch.is_empty():
		return {}
	var branch_damage := float(branch[&"damage"])
	var armor_damage := branch_damage if b0 > 0.0 else 0.0
	var healing := float(direct[&"healing"]) + float(branch[&"healing"])
	var hp_damage := float(direct[&"damage"])
	if not _valid_magnitude(h0) or not _valid_magnitude(b0) or not _valid_magnitude(armor_damage) or not _valid_magnitude(healing) or not _valid_magnitude(hp_damage):
		return {}
	return {
		&"H0": h0,
		&"B0": b0,
		&"R_H": r_h,
		&"R_B": r_b,
		&"H_direct": hp_damage,
		&"B_damage": armor_damage,
		&"healing": healing,
		&"armor_spent": 0.0,
		&"overflow": 0.0,
		&"hp_damage": hp_damage,
	}

static func _protected(amount: float, resistance: int) -> Dictionary:
	var factor := 1.0 - float(resistance) / PERCENT_DENOMINATOR
	var protected := amount * factor
	if not _valid_magnitude(protected):
		return {}
	return {&"damage": maxf(0.0, protected), &"healing": maxf(0.0, -protected)}

static func _valid_component(component: Dictionary) -> bool:
	if component.size() != 4:
		return false
	for key: StringName in [&"type", &"policy", &"amount", &"source"]:
		if not component.has(key):
			return false
	var type_value: Variant = component[&"type"]
	var policy_value: Variant = component[&"policy"]
	var amount_value: Variant = component[&"amount"]
	var source_value: Variant = component[&"source"]
	if not type_value is StringName or not policy_value is StringName or not source_value is StringName:
		return false
	if type_value not in [&"physical", &"fire"] or policy_value not in [&"standard", &"hp_only_natural", &"hp_only_unresisted"] or source_value == &"":
		return false
	if not amount_value is ArmorFraction:
		return false
	var amount: ArmorFraction = amount_value
	return amount.get_script() == ArmorFraction and amount.valid and amount.denominator > 0 and amount.numerator >= 0

static func _valid_nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0

static func _valid_magnitude(value: float) -> bool:
	return is_finite(value) and absf(value) <= float(ArmorRuntime.MAX_EXACT_HP)

static func _empty_result(reason: StringName, hp_before: float) -> Dictionary:
	return {&"reason": reason, &"p_num": 0.0, &"p_den": 1.0, &"armor_spent": 0.0, &"hp_before": hp_before, &"hp_after": hp_before, &"total_damage": 0.0, &"total_healing": 0.0, &"rows": []}

static func _overflow_result(hp_before: float) -> Dictionary:
	return _empty_result(&"armor/overflow", hp_before)

static func _read(dictionary: Dictionary, key: StringName) -> Variant:
	if dictionary.has(key):
		return dictionary[key]
	var text_key := String(key)
	if dictionary.has(text_key):
		return dictionary[text_key]
	return null
