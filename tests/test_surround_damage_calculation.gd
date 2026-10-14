extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_damage_types_and_counts()
	_test_policies_and_combined_modifiers()
	_test_floor_and_invalid_counts()
	print("SURROUND DAMAGE CALCULATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL SURROUND DAMAGE: " + label)

func _amount(row: Dictionary) -> float:
	return float(row["numerator"]) / float(row["denominator"])

func _test_damage_types_and_counts() -> void:
	var fire: Array[Dictionary] = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "fire", "factor_num": 1, "factor_den": 1}]
	var expected_physical: Array[float] = [10.0, 11.0, 12.0, 13.0]
	var expected_fire: Array[float] = [10.0, 11.0, 12.0, 13.0]
	for count: int in range(4):
		var physical := ArmorAttack.components(8.0, 2.0, 0, false, [], 0, 1, 0, 0, count)
		var flame := ArmorAttack.components(0.0, 0.0, 0, false, fire, 0, 1, 0, 0, count)
		check(physical.size() == 1 and is_equal_approx(_amount(physical[0]), expected_physical[count]), "physical scale at count %d" % count)
		check(flame.size() == 2 and is_equal_approx(_amount(flame[1]), expected_fire[count]), "fire scale at count %d" % count)
	var zero_old := ArmorAttack.components(8.0, 2.0, 1, true, fire, 25, 2, 50, 30)
	var zero_new := ArmorAttack.components(8.0, 2.0, 1, true, fire, 25, 2, 50, 30, 0)
	check(zero_old == zero_new, "default matches explicit zero for every raw component")

func _test_policies_and_combined_modifiers() -> void:
	var extras: Array[Dictionary] = [{"type": "fire", "policy": "hp_only_unresisted", "numerator": 10, "denominator": 1, "source": "fire", "factor_num": 1, "factor_den": 1}]
	var split := ArmorAttack.components(8.0, 2.0, 2, true, extras, 50, 2, 25, 30, 2)
	check(split.size() == 3, "surround retains all three armor policies")
	if split.size() == 3:
		check(split[0]["type"] == "physical" and split[0]["policy"] == "standard", "piercing standard policy stays first")
		check(split[1]["type"] == "physical" and split[1]["policy"] == "hp_only_natural", "piercing branch retains natural-only policy")
		check(split[2]["type"] == "fire" and split[2]["policy"] == "hp_only_unresisted", "fire extra keeps unresisted policy")
		check(is_equal_approx(_amount(split[0]), 14.994), "height, backstab, guard, critical, cover and surround on standard branch")
		check(is_equal_approx(_amount(split[1]), 4.998), "all modifiers apply jointly to pierced branch")
		check(is_equal_approx(_amount(split[2]), 14.112), "fire component gets surround and cover, without physical modifiers")

func _test_floor_and_invalid_counts() -> void:
	var extras: Array[Dictionary] = [{"type": "physical", "policy": "standard", "numerator": 1, "denominator": 1, "source": "fraction", "factor_num": 1, "factor_den": 1}]
	var fractional := ArmorAttack.components(0.0, 0.0, 0, false, extras, 0, 1, 0, 0, 1)
	check(fractional.size() == 2 and _amount(fractional[1]) == 1.1, "fractional surround stays exact in raw extra component")
	var runtime := ArmorRuntime.components(fractional)
	var defenses := {"physical": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}, "fire": {"armor": 0, "natural": 0, "limit_armor": 7500, "limit_natural": 7500}}
	var hit := ArmorHitCalculation.calculate(runtime, 0, 0, 10, 10, defenses)
	check(hit.reason == &"" and hit.total_damage == 1, "fractional raw damage receives D0 floor in hit calculation")
	check(ArmorAttack.components(1.0, 0.0, 0, false, [], 0, 1, 0, 0, -1).is_empty(), "negative surround count rejected")
	check(ArmorAttack.components(1.0, 0.0, 0, false, [], 0, 1, 0, 0, 4).is_empty(), "count above three rejected")
