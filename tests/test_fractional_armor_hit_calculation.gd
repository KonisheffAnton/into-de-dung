extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL FRACTIONAL ARMOR HIT: " + label)

func _component(type: StringName, policy: StringName, numerator: int, denominator: int, source: StringName) -> Dictionary:
	return {&"type": type, &"policy": policy, &"amount": ArmorFraction.make(numerator, denominator), &"source": source}

func _defenses(physical_armor: int = 0, physical_natural: int = 0, fire_armor: int = 0, fire_natural: int = 0, limit_armor: int = 7500, limit_natural: int = 7500) -> Dictionary:
	return {
		&"physical": {&"armor": physical_armor, &"natural": physical_natural, &"limit_armor": limit_armor, &"limit_natural": limit_natural},
		&"fire": {&"armor": fire_armor, &"natural": fire_natural, &"limit_armor": limit_armor, &"limit_natural": limit_natural},
	}

func _run() -> void:
	_test_fractional_damage()
	_test_long_running_fractional_damage()
	_test_armor_split()
	_test_runtime_exhaustion_determinism()
	_test_fractional_shield()
	_test_resistance_and_healing()
	_test_order_and_input_isolation()
	_test_invalid_inputs()
	print("FRACTIONAL ARMOR HIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_fractional_damage() -> void:
	var rows: Array[Dictionary] = []
	for index: int in 3:
		rows.append(_component(&"fire", &"hp_only_natural", 103, 100, StringName("tick_%d" % index)))
	var defenses := _defenses(0, 0, 0, 1000)
	var result := FractionalArmorHitCalculation.calculate(rows, 0.0, 0.0, 10.0, 10.0, defenses)
	_check(result[&"reason"] == &"", "fractional status calculation succeeds")
	_check(absf(float(result[&"total_damage"]) - 2.781) <= 1e-12, "three resisted 1.03 ticks retain 2.781 damage")
	var single := FractionalArmorHitCalculation.calculate([_component(&"fire", &"hp_only_natural", 103, 100, &"single")], 0.0, 0.0, 10.0, 10.0, defenses)
	_check(absf(float(single[&"total_damage"]) - 0.927) <= 1e-12, "one resisted 1.03 tick retains 0.927 damage")

func _test_long_running_fractional_damage() -> void:
	var hp := 2000.0
	var total := 0.0
	var maximum_cumulative_error := 0.0
	var component: Array[Dictionary] = [_component(&"fire", &"hp_only_natural", 103, 100, &"long-tick")]
	var defenses := _defenses(0, 0, 0, 1000)
	for index: int in 1000:
		var result := FractionalArmorHitCalculation.calculate(component, 0.0, 0.0, hp, 2000.0, defenses)
		if result[&"reason"] != &"":
			_check(false, "all one thousand fractional ticks resolve")
			return
		var damage := float(result[&"total_damage"])
		hp = float(result[&"hp_after"])
		total += damage
		maximum_cumulative_error = maxf(maximum_cumulative_error, absf(total - 0.927 * float(index + 1)))
	_check(absf(total - 927.0) <= 1e-9 and maximum_cumulative_error <= 1e-9 and absf(hp - 1073.0) <= 1e-9, "one thousand 1.03 fire ticks retain 927 total damage without cumulative float drift")

func _test_armor_split() -> void:
	var components: Array[Dictionary] = [
		_component(&"physical", &"standard", 2, 1, &"physical"),
		_component(&"fire", &"standard", 2, 1, &"fire"),
	]
	var result := FractionalArmorHitCalculation.calculate(components, 0.25, 1.0, 10.0, 10.0, _defenses())
	_check(result[&"reason"] == &"", "fractional armor split succeeds")
	_check(absf(float(result[&"armor_spent"]) - 0.25) <= 1e-12, "fractional armor is spent exactly")
	var rows: Array = result[&"rows"]
	_check(rows.size() == 2 and absf(float(rows[0][&"armor_spent"]) - 0.125) <= 1e-12 and absf(float(rows[1][&"armor_spent"]) - 0.125) <= 1e-12, "armor is distributed proportionally across branches")
	_check(absf(float(result[&"total_damage"]) - 3.75) <= 1e-12, "unabsorbed armor branch damage overflows into hp")
	var depleted := FractionalArmorHitCalculation.calculate(components, 0.0, 1.0, 10.0, 10.0, _defenses())
	_check(depleted[&"reason"] == &"" and depleted[&"armor_spent"] == 0.0 and depleted[&"total_damage"] == 4.0, "depleted armor resolves all damage directly to hp")

func _runtime_component(type: String, policy: String, numerator: int, denominator: int, source: String) -> Dictionary:
	return {"type": type, "policy": policy, "numerator": numerator, "denominator": denominator, "source": source}

func _test_runtime_exhaustion_determinism() -> void:
	var session := BattleArmorSession.new()
	var unit: UnitState = session.units[0]
	var owner: ItemOwnerState = session.state.get_owner(unit.id)
	var armor_items: Array[ItemInstance] = []
	for item: ItemInstance in owner._items.values():
		if item.get_definition().armor_max > 0: armor_items.append(item)
	_check(armor_items.size() == 2, "runtime fixture has two armor items")
	if armor_items.size() != 2:
		session.close()
		return
	unit.armor.fractional = true
	unit.armor.grants = [{"grant_id": 1, "source": "fractional-stress", "remaining": 0.25, "expires": "battle", "battle_id": unit.armor.battle_id}]
	unit.armor.next_grant_id = 2
	armor_items[0].armor_remaining = 20.25
	armor_items[1].armor_remaining = 29.75
	var view := ArmorRuntime.capture(owner)
	var saved_view := view.duplicate(true)
	var components: Array[Dictionary] = [
		_runtime_component("physical", "standard", 30, 1, "physical-stress"),
		_runtime_component("fire", "standard", 30, 1, "fire-stress"),
	]
	var rng := CombatRng.new(7401)
	var rng_before := rng.to_dict().duplicate(true)
	var first := ArmorRuntime.plan(view, components, 100.0, 100.0, rng)
	var second := ArmorRuntime.plan(view, components, 100.0, 100.0, rng)
	_check(first.get("reason", &"bad") == &"" and second.get("reason", &"bad") == &"", "mixed physical/fire plan exhausts fractional armor")
	if first.get("reason", &"bad") != &"" or second.get("reason", &"bad") != &"":
		session.close()
		return
	_check(first == second and first["after"] == second["after"] and first["rng_after"] == second["rng_after"], "fixed RNG produces identical full plan DTOs on repeat")
	_check(first["armor_spent"] == 50.25 and first["total_damage"] == 9.75 and first["after"]["state"]["grants"][0]["remaining"] == 0.0, "grant and both fractional items are exhausted before overflow reaches HP")
	_check(first["item_changes"].size() == 2 and first["after"]["items"] != view["items"], "both item layers record their fractional exhaustion")
	_check(view == saved_view and rng.to_dict() == rng_before and armor_items[0].armor_remaining == 20.25 and armor_items[1].armor_remaining == 29.75, "planning leaves captured source, live armor and live RNG unchanged")
	for index: int in 40:
		unit.armor.grants[0].remaining = 0.1 + float(index) / 100.0
		armor_items[0].armor_remaining = 20.1 + float(index) / 100.0
		armor_items[1].armor_remaining = 29.1 - float(index) / 100.0
		var fractional_view := ArmorRuntime.capture(owner)
		var plan := ArmorRuntime.plan(fractional_view, components, 100.0, 100.0, CombatRng.new(index + 1))
		_check(plan.reason == &"" and ArmorRuntime.totals(plan.after).current == 0.0 and absf(plan.total_damage + plan.armor_spent - 60.0) < 1e-12, "decimal layers exhaust without floating subtraction residue %d" % index)
	session.close()

func _test_fractional_shield() -> void:
	var session := BattleArmorSession.new()
	var unit: UnitState = session.units[0]
	var owner: ItemOwnerState = session.state.get_owner(unit.id)
	unit.armor.fractional = true
	unit.armor.shield = {"spell_id": "fractional-test", "hp": 0.25, "hits_left": 1}
	unit.vitals.set_hp(10.25)
	for item: ItemInstance in owner._items.values():
		if item.get_definition().armor_max > 0: item.armor_remaining = 0.0
	var view := ArmorRuntime.capture(owner)
	var saved_view := view.duplicate(true)
	var rng := CombatRng.new(7402)
	var rng_before := rng.to_dict().duplicate(true)
	var raw: Array[Dictionary] = [_runtime_component("physical", "hp_only_unresisted", 1177, 1000, "shield-residual")]
	var plan := ArmorRuntime.plan(view, raw, unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX), rng)
	_check(plan.get("reason", &"bad") == &"" and absf(float(plan.get("shield", {}).get("absorbed", -1.0)) - 0.25) <= 1e-12, "fractional spell shield absorbs a quarter point")
	if plan.get("reason", &"bad") != &"":
		session.close()
		return
	_check(absf(float(plan["total_damage"]) - 0.927) <= 1e-12 and absf(float(plan["hp_after"]) - 9.323) <= 1e-12, "unabsorbed 0.927 spell-shield residual reaches HP without quantization")
	_check(view == saved_view and rng.to_dict() == rng_before and unit.vitals.get_hp() == 10.25 and ArmorRuntime.totals(ArmorRuntime.capture(owner)).current == 0.0, "shield forecast preserves live HP, armor and RNG")
	session.close()

func _test_resistance_and_healing() -> void:
	var vulnerable := FractionalArmorHitCalculation.calculate([_component(&"physical", &"hp_only_natural", 1, 1, &"weakness")], 0.0, 0.0, 10.0, 10.0, _defenses(0, -10000))
	_check(vulnerable[&"reason"] == &"" and vulnerable[&"total_damage"] == 2.0, "negative resistance increases damage")
	var capped := FractionalArmorHitCalculation.calculate([_component(&"physical", &"hp_only_natural", 1, 1, &"cap")], 0.0, 0.0, 10.0, 10.0, _defenses(0, 9000))
	_check(capped[&"reason"] == &"" and capped[&"total_damage"] == 0.25, "natural resistance obeys its branch cap")
	var healing := FractionalArmorHitCalculation.calculate([_component(&"physical", &"hp_only_natural", 3, 2, &"over-100")], 0.0, 0.0, 2.0, 10.0, _defenses(0, 20000, 0, 0, 7500, 20000))
	_check(healing[&"reason"] == &"" and healing[&"total_healing"] == 1.5 and healing[&"hp_after"] == 3.5, "resistance above one hundred percent heals")
	var armor_caps := FractionalArmorHitCalculation.calculate([_component(&"physical", &"standard", 2, 1, &"armor-cap")], 1.0, 2.0, 10.0, 10.0, _defenses(6000, 6000))
	_check(armor_caps[&"reason"] == &"" and armor_caps[&"rows"][0][&"R_B"] == 7500, "combined standard resistance obeys armor cap")

func _test_order_and_input_isolation() -> void:
	var original: Array[Dictionary] = [
		_component(&"fire", &"standard", 3, 2, &"fire-first"),
		_component(&"physical", &"hp_only_unresisted", 2, 1, &"direct"),
		_component(&"physical", &"standard", 1, 1, &"physical-standard"),
	]
	var first_amount: ArmorFraction = original[0][&"amount"]
	var first_numerator := first_amount.numerator
	var first_source: StringName = original[0][&"source"]
	var defenses := _defenses(1200, -500, 0, 250)
	var saved_defenses := defenses.duplicate(true)
	var first := FractionalArmorHitCalculation.calculate(original, 0.75, 2.0, 20.0, 20.0, defenses, 0.5)
	var reversed := original.duplicate()
	reversed.reverse()
	var second := FractionalArmorHitCalculation.calculate(reversed, 0.75, 2.0, 20.0, 20.0, defenses, 0.5)
	_check(first[&"reason"] == &"" and second[&"reason"] == "", "mixed input orders calculate successfully")
	_check(first[&"rows"].size() == 3 and first[&"rows"][0][&"type"] == &"physical" and first[&"rows"][1][&"policy"] == &"hp_only_unresisted" and first[&"rows"][2][&"type"] == &"fire", "output groups retain canonical branch ordering")
	_check(is_equal_approx(first[&"total_damage"], second[&"total_damage"]) and is_equal_approx(first[&"total_healing"], second[&"total_healing"]), "input order does not change totals")
	_check(first_amount.numerator == first_numerator and original[0][&"source"] == first_source and defenses == saved_defenses, "components and defenses remain unchanged")
	var scaled := FractionalArmorHitCalculation.calculate([_component(&"physical", &"hp_only_unresisted", 4, 1, &"shield")], 0.0, 0.0, 10.0, 10.0, _defenses(), 0.25)
	_check(scaled[&"reason"] == &"" and scaled[&"total_damage"] == 1.0, "finite common multiplier scales damage")

func _test_invalid_inputs() -> void:
	var valid: Array[Dictionary] = [_component(&"physical", &"standard", 1, 1, &"valid")]
	var start_hp := 7.0
	for bad_multiplier: float in [NAN, INF, -1.0]:
		var invalid_multiplier := FractionalArmorHitCalculation.calculate(valid, 0.0, 0.0, start_hp, 10.0, _defenses(), bad_multiplier)
		_check(invalid_multiplier[&"reason"] == &"armor/invalid_hit" and invalid_multiplier[&"hp_before"] == start_hp and invalid_multiplier[&"hp_after"] == start_hp and invalid_multiplier[&"rows"].is_empty(), "invalid multiplier refuses without partial result")
	var negative := FractionalArmorHitCalculation.calculate([_component(&"physical", &"standard", -1, 1, &"negative")], 0.0, 0.0, start_hp, 10.0, _defenses())
	_check(negative[&"reason"] == &"armor/invalid_hit" and negative[&"total_damage"] == 0.0, "negative component refuses")
	var nonfinite_hp := FractionalArmorHitCalculation.calculate(valid, 0.0, 0.0, NAN, 10.0, _defenses())
	_check(nonfinite_hp[&"reason"] == &"armor/invalid_hit" and nonfinite_hp[&"rows"].is_empty(), "non-finite hp refuses")
	var invalid_numeric_input := true
	for bad_amount: float in [NAN, INF, -INF, -0.25]:
		var armor_result := FractionalArmorHitCalculation.calculate(valid, bad_amount, 1.0, start_hp, 10.0, _defenses())
		var hp_result := FractionalArmorHitCalculation.calculate(valid, 0.0, 0.0, bad_amount, 10.0, _defenses())
		invalid_numeric_input = invalid_numeric_input and not CombatAmount.valid(bad_amount) and armor_result.reason != &"" and hp_result.reason != &""
	_check(invalid_numeric_input, "CombatAmount and solver refuse non-finite and negative HP/armor amounts")
	var negative_maximum := FractionalArmorHitCalculation.calculate(valid, 0.0, -1.0, start_hp, 10.0, _defenses())
	_check(negative_maximum[&"reason"] == &"armor/invalid_hit", "negative armor maximum refuses")
	var overflow := FractionalArmorHitCalculation.calculate([_component(&"physical", &"hp_only_unresisted", ArmorRuntime.MAX_EXACT_HP, 1, &"large")], 0.0, 0.0, start_hp, 10.0, _defenses(), 2.0)
	_check(overflow[&"reason"] == &"armor/overflow" and overflow[&"total_damage"] == 0.0 and overflow[&"rows"].is_empty(), "out-of-range intermediate refuses atomically")
