extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_legacy_and_percentages()
	_test_floor_and_modifiers()
	_test_extras_and_defenses()
	_test_invalid_and_overflow()
	print("ARMOR PIERCING CALCULATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ARMOR PIERCING: " + label)

func _defense(armor: int = 0, natural: int = 0) -> Dictionary:
	return {"physical": {"armor": armor, "natural": natural, "limit_armor": 7500, "limit_natural": 7500}, "fire": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}}

func _physical_components(raw: Array[Dictionary]) -> Array[Dictionary]:
	return ArmorRuntime.components(raw)

func _test_legacy_and_percentages() -> void:
	var legacy := ArmorAttack.components(8.0, 3.0, 1, true, [], 25, 2)
	var explicit_zero := ArmorAttack.components(8.0, 3.0, 1, true, [], 25, 2, 0)
	check(legacy == explicit_zero, "zero piercing preserves legacy component dictionaries")
	var fifty := ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 50)
	check(fifty.size() == 2 and fifty[0]["policy"] == "standard" and fifty[1]["policy"] == "hp_only_natural", "50 percent emits standard then natural-only rows")
	check(fifty[0]["numerator"] == 11 and fifty[0]["denominator"] == 2 and fifty[1]["numerator"] == 11 and fifty[1]["denominator"] == 2, "11 physical splits into exact halves")
	var hundred := ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 100)
	check(hundred.size() == 1 and hundred[0]["policy"] == "hp_only_natural" and hundred[0]["numerator"] == 11, "100 percent emits only natural-only row")

func _test_floor_and_modifiers() -> void:
	var halves := ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 50)
	var calculated := ArmorHitCalculation.calculate(_physical_components(halves), 0, 0, 100, 100, _defense())
	check(calculated.reason == &"" and calculated.rows.size() == 2 and calculated.rows[0]["D"] == 5 and calculated.rows[1]["D"] == 5, "D0 floors 5.5 branches separately")
	var subpoint := ArmorAttack.components(1.0, 0.0, 0, false, [], 0, 1, 50)
	calculated = ArmorHitCalculation.calculate(_physical_components(subpoint), 0, 0, 100, 100, _defense())
	check(calculated.reason == &"" and calculated.total_damage == 0 and calculated.rows[0]["D"] == 0 and calculated.rows[1]["D"] == 0, "odd fractional halves floor to zero before defenses")
	var combined := ArmorAttack.components(8.0, 2.0, 2, true, [], 50, 2, 25)
	check(combined.size() == 2 and combined[0]["numerator"] == 357 and combined[0]["denominator"] == 20 and combined[1]["numerator"] == 119 and combined[1]["denominator"] == 20, "height backstab guard critical then exact 25 percent split")

func _test_extras_and_defenses() -> void:
	var extras: Array[Dictionary] = [{"type": "physical", "policy": "hp_only_unresisted", "numerator": 3, "denominator": 2, "source": "extra", "factor_num": 1, "factor_den": 1}]
	var before := extras.duplicate(true)
	var raw := ArmorAttack.components(8.0, 3.0, 0, false, extras, 0, 1, 50)
	check(raw.size() == 3 and raw[2]["policy"] == "hp_only_unresisted" and raw[2]["numerator"] == 3 and raw[2]["denominator"] == 2, "extra retains its policy and ignores piercing")
	check(extras == before, "extras input remains unchanged")
	var runtime_rows := _physical_components(ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 50))
	var empty_armor := ArmorHitCalculation.calculate(runtime_rows, 0, 0, 100, 100, _defense(0, 2000))
	check(empty_armor.reason == &"" and empty_armor.armor_spent == 0 and empty_armor.total_damage == 8 and empty_armor.rows[0]["D"] == 5 and empty_armor.rows[1]["D"] == 5, "empty armor keeps both branches under natural resistance")
	var full_armor := ArmorHitCalculation.calculate(runtime_rows, 100, 100, 100, 100, _defense(5000, 5000))
	check(full_armor.reason == &"" and full_armor.armor_spent == 1 and full_armor.total_damage == 2 and full_armor.rows[0]["H0"] == 0 and full_armor.rows[0]["B0"] == 5 and full_armor.rows[1]["H0"] == 5, "full armor protects standard branch while pierced branch sees natural defense")

func _test_invalid_and_overflow() -> void:
	check(ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, -1).is_empty(), "negative piercing rejected")
	check(ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 101).is_empty(), "piercing above 100 rejected")
	check(ArmorAttack.components(8.0, 3.0, 0, false, [], 0, 1, 2147483647).is_empty(), "large out of range piercing rejected")
	check(ArmorAttack.components(9000000000000000.0, 0.0, 2147483647, false, [], 0, 1, 50).is_empty(), "fraction overflow fails closed")
