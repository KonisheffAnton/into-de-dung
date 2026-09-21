extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL DAMAGE: " + label)

func check_float(actual: float, expected: float, label: String) -> void:
	check(actual == expected, label + " actual=" + str(actual) + " expected=" + str(expected))

func stage_kinds(result: AttackDamageCalculation.Result) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for stage: Dictionary in result.get_stages():
		kinds.append(stage[&"kind"] as StringName)
	return kinds

func _run() -> void:
	_test_fractional_negative()
	_test_height_guard_order_and_stages()
	_test_failures()
	_test_copy_isolation()
	_test_differential_grid()
	print("D1 CALCULATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_fractional_negative() -> void:
	var result := AttackDamageCalculation.calculate(2.5, 1.25, 0.75, false, 99, false)
	check(result.reason == &"", "fractional succeeds")
	check_float(result.raw_attack, 3.75, "fractional raw attack")
	check_float(result.scaled, 3.75, "nonspatial keeps raw attack")
	check_float(result.hit_amount, 3.0, "fractional armor subtraction")
	check(stage_kinds(result) == [&"base_add", &"armor_subtract", &"minimum"], "nonspatial stage kinds")
	var negative := AttackDamageCalculation.calculate(-5.5, -2.25, -1.0, false, 0, false)
	check(negative.reason == &"", "negative finite inputs succeed")
	check_float(negative.raw_attack, -7.75, "negative raw attack")
	check_float(negative.scaled, -7.75, "negative scaled")
	check_float(negative.hit_amount, 1.0, "negative minimum")

func _test_height_guard_order_and_stages() -> void:
	var result := AttackDamageCalculation.calculate(10.0, 2.0, 3.0, true, 2, true)
	check(result.reason == &"", "height guarded succeeds")
	check_float(result.raw_attack, 12.0, "raw attack before height")
	check_float(result.scaled, 12.0 * SpatialRules.height_multiplier(2), "height scaling")
	check_float(result.hit_amount, maxf(1.0, maxf(1.0, 12.0 * SpatialRules.height_multiplier(2) - 3.0) * 0.7), "guard after minimum")
	var stages := result.get_stages()
	check(stage_kinds(result) == [&"base_add", &"height_multiply", &"armor_subtract", &"minimum", &"guard_multiply", &"guard_minimum"], "spatial guarded stage kinds")
	check_float(float(stages[0][&"input"]), 10.0, "base input")
	check_float(float(stages[0][&"operand"]), 2.0, "base operand")
	check_float(float(stages[0][&"output"]), 12.0, "base output")
	check_float(float(stages[1][&"operand"]), SpatialRules.height_multiplier(2), "height operand")
	check_float(float(stages[1][&"output"]), 12.0 * SpatialRules.height_multiplier(2), "height output")
	check_float(float(stages[2][&"output"]), 12.0 * SpatialRules.height_multiplier(2) - 3.0, "armor output")
	check_float(float(stages[3][&"output"]), maxf(1.0, 12.0 * SpatialRules.height_multiplier(2) - 3.0), "minimum output")
	check_float(float(stages[4][&"output"]), maxf(1.0, 12.0 * SpatialRules.height_multiplier(2) - 3.0) * 0.7, "guard multiply output")
	check_float(float(stages[5][&"output"]), maxf(1.0, maxf(1.0, 12.0 * SpatialRules.height_multiplier(2) - 3.0) * 0.7), "guard minimum output")
	var minimum_guard := AttackDamageCalculation.calculate(-10.0, 0.0, 100.0, false, 0, true)
	check_float(minimum_guard.hit_amount, 1.0, "guard minimum after multiplication")
	check(stage_kinds(minimum_guard) == [&"base_add", &"armor_subtract", &"minimum", &"guard_multiply", &"guard_minimum"], "guarded nonspatial stage kinds")

func _test_failures() -> void:
	var nan_input := AttackDamageCalculation.calculate(NAN, 1.0, 1.0, false, 0, false)
	check(nan_input.reason == &"attack/nonfinite_damage" and nan_input.get_stages().is_empty(), "nan input rejected")
	var inf_input := AttackDamageCalculation.calculate(1.0, INF, 1.0, false, 0, false)
	check(inf_input.reason == &"attack/nonfinite_damage" and inf_input.get_stages().is_empty(), "inf input rejected")
	var sum_overflow := AttackDamageCalculation.calculate(1.0e308, 1.0e308, 0.0, false, 0, false)
	check(sum_overflow.reason == &"attack/nonfinite_damage" and sum_overflow.get_stages().is_empty(), "sum overflow rejected")
	var scale_overflow := AttackDamageCalculation.calculate(1.0e308, 0.0, 0.0, true, 2147483647, false)
	check(scale_overflow.reason == &"attack/nonfinite_damage" and scale_overflow.get_stages().is_empty(), "scale overflow rejected reason=" + String(scale_overflow.reason))
	var subtraction_overflow := AttackDamageCalculation.calculate(1.0e308, 0.0, -1.0e308, false, 0, false)
	check(subtraction_overflow.reason == &"attack/nonfinite_damage" and subtraction_overflow.get_stages().is_empty(), "subtraction overflow rejected reason=" + String(subtraction_overflow.reason))
	var nonspatial_height := AttackDamageCalculation.calculate(4.0, 2.0, 1.0, false, 2147483647, false)
	check_float(nonspatial_height.scaled, 6.0, "nonspatial ignores height")
	check(stage_kinds(nonspatial_height) == [&"base_add", &"armor_subtract", &"minimum"], "nonspatial has no height stage")

func _test_copy_isolation() -> void:
	var first := AttackDamageCalculation.calculate(8.0, 2.0, 1.0, true, 1, false)
	var first_stages := first.get_stages()
	first_stages[0][&"input"] = -999.0
	first_stages.append({&"kind": &"fake", &"input": 0.0, &"operand": 0.0, &"output": 0.0})
	check(first.get_stages().size() == 4, "stage array copy isolated")
	check_float(float(first.get_stages()[0][&"input"]), 8.0, "stage dictionary copy isolated")
	var second := AttackDamageCalculation.calculate(8.0, 2.0, 1.0, true, 1, false)
	check(second.get_stages() == first.get_stages(), "independent results equal")

func _test_differential_grid() -> void:
	var strengths: Array[float] = [-3.75, -1.25, -0.5, 0.25, 1.5, 4.75, 9.125]
	var weapons: Array[float] = [-2.5, -0.75, -0.125, 0.375, 1.25, 3.5, 8.625]
	var armors: Array[float] = [-4.25, -1.5, -0.25, 0.625, 2.75, 7.875]
	var height_steps: Array[int] = [-12, -1, 0, 1, 4]
	for strength: float in strengths:
		for weapon: float in weapons:
			for armor: float in armors:
				for spatial: bool in [false, true]:
					for signed_steps: int in height_steps:
						for guarded: bool in [false, true]:
							# Буквальная последовательность сохраняет арифметику старой команды при рефакторинге.
							var expected_raw_attack := strength + weapon
							var expected_scaled := expected_raw_attack * SpatialRules.height_multiplier(signed_steps) if spatial else expected_raw_attack
							var expected_raw := expected_scaled - armor
							var expected_hit := maxf(1.0, expected_raw)
							if guarded:
								expected_hit = maxf(1.0, expected_hit * 0.7)
							var actual := AttackDamageCalculation.calculate(strength, weapon, armor, spatial, signed_steps, guarded)
							var label := "grid s=%s w=%s a=%s spatial=%s steps=%s guard=%s" % [strength, weapon, armor, spatial, signed_steps, guarded]
							check(actual.reason == &"", label + " succeeds")
							check(actual.raw_attack == expected_raw_attack, label + " raw exact")
							check(actual.scaled == expected_scaled, label + " scaled exact")
							check(actual.hit_amount == expected_hit, label + " hit exact")
