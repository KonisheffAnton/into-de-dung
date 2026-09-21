extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_fraction()
	_test_standard_and_p()
	_test_healing_and_vulnerability()
	_test_grouping_and_copies()
	_test_distribute_and_failures()
	_test_d0_acceptance()
	print("ARMOR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ARMOR: " + label)

func _defense(armor: int = 0, natural: int = 0, limit_armor: int = 7500, limit_natural: int = 7500) -> Dictionary:
	return {"physical": {"armor": armor, "natural": natural, "limit_armor": limit_armor, "limit_natural": limit_natural}, "fire": {"armor": armor, "natural": natural, "limit_armor": limit_armor, "limit_natural": limit_natural}}

func _component(type: StringName, policy: StringName, amount: ArmorFraction, source: StringName) -> Dictionary:
	return {"type": type, "policy": policy, "amount": amount, "source": source}

func _test_fraction() -> void:
	var a := ArmorFraction.make(1, 3).add(ArmorFraction.make(1, 6))
	check(a.valid and a.numerator == 1 and a.denominator == 2, "fraction add reduction")
	var b := ArmorFraction.make(2, 3).multiply(ArmorFraction.make(3, 4))
	check(b.valid and b.numerator == 1 and b.denominator == 2, "fraction multiply reduction")
	check(ArmorFraction.from_decimal(0.125).floor_value() == 0, "decimal exact")
	check(not ArmorFraction.make(1, 0).valid, "zero denominator invalid")

func _test_standard_and_p() -> void:
	var components: Array[Dictionary] = [_component(&"physical", &"standard", ArmorFraction.make(200), &"hit")]
	var result := ArmorHitCalculation.calculate(components, 50, 100, 100, 100, _defense(2000, 3000))
	check(result.reason == &"" and result.p_num == 0, "p at half armor")
	check(result.armor_spent == 50 and result.hp_after == 50, "standard armor branch")
	var no_armor := ArmorHitCalculation.calculate(components, 0, 100, 100, 100, _defense(2000, 3000))
	check(no_armor.p_num == 1 and no_armor.hp_after == 0, "p at empty armor")

func _test_healing_and_vulnerability() -> void:
	var fire: Array[Dictionary] = [_component(&"fire", &"standard", ArmorFraction.make(10), &"spell")]
	var result := ArmorHitCalculation.calculate(fire, 0, 0, 5, 10, _defense(0, 11000, 11000, 11000))
	check(result.total_healing == 1 and result.hp_after == 6, "110 percent heals one")
	var vulnerable := ArmorHitCalculation.calculate(fire, 0, 0, 10, 20, _defense(0, -2500))
	check(vulnerable.total_damage == 12, "negative resistance vulnerability")

func _test_grouping_and_copies() -> void:
	var components: Array[Dictionary] = [_component(&"physical", &"standard", ArmorFraction.make(3, 5), &"a"), _component(&"physical", &"standard", ArmorFraction.make(3, 5), &"b")]
	var result := ArmorHitCalculation.calculate(components, 0, 0, 10, 20, _defense())
	var rows := result.get_rows()
	check(rows.size() == 1 and rows[0][&"hp_damage"] == 1, "fractional grouping floors once")
	(rows[0][&"sources"] as Array).append(&"mutated")
	check(result.get_rows()[0][&"sources"].size() == 2, "rows deep copy")

func _test_distribute_and_failures() -> void:
	var shares := ArmorHitCalculation.distribute(3, [2, 1])
	check(shares == [2, 1], "largest remainder")
	check(ArmorHitCalculation.distribute(3, [0, 0]).is_empty(), "zero weights invalid")
	var bad: Array[Dictionary] = [_component(&"bad", &"standard", ArmorFraction.make(1), &"x")]
	var result := ArmorHitCalculation.calculate(bad, 0, 0, 0, 10, _defense())
	check(result.reason == &"armor/invalid_hit", "invalid component rejected")
	var overflow := ArmorFraction.make(9223372036854775807).multiply(ArmorFraction.make(2))
	check(not overflow.valid, "fraction overflow rejected")

func _test_d0_acceptance() -> void:
	# D0 §3: D, current, max, rA, rH, limitA, limitH, lossA, lossHP.
	var cases: Array = [
		[20,0,0,0,0,7500,7500,0,20], [20,0,100,10000,0,7500,7500,0,20],
		[20,100,100,0,0,7500,7500,20,0], [20,50,100,0,0,7500,7500,20,0],
		[20,49,100,0,0,7500,7500,20,0], [20,25,100,0,0,7500,7500,10,10],
		[3,25,100,0,0,7500,7500,2,1], [80,60,100,0,0,7500,7500,60,20],
		[200,60,100,5000,2500,7500,7500,50,0], [200,50,100,2000,3000,7500,7500,50,50],
		[20,25,100,5000,2000,7500,7500,3,8], [20,25,100,6000,2000,7500,7500,2,8],
		[200,25,100,2000,3000,7500,7500,25,95], [3,25,100,2000,3000,7500,7500,1,0],
		[20,100,100,0,5000,7500,7500,10,0], [80,25,100,0,10000,10000,10000,0,0],
		[20,25,100,10000,0,10000,7500,0,10], [20,50,100,8000,4000,7500,7500,5,0],
		[20,25,100,8000,4000,7500,7500,2,6], [20,0,100,8000,4000,7500,7500,0,12],
		[20,0,100,0,11000,7500,7500,0,5], [0,25,100,0,0,7500,7500,0,0]]
	for c: Array in cases:
		var hit: Array[Dictionary] = [_component(&"physical", &"standard", ArmorFraction.make(c[0]), &"test")]
		var r := ArmorHitCalculation.calculate(hit, c[1], c[2], 1000, 1000, _defense(c[3], c[4], c[5], c[6]))
		check(r.reason == &"" and r.armor_spent == c[7] and 1000 - r.hp_after == c[8], "D0 table " + str(c))
		check(r.get_rows()[0]["D"] == c[0], "explanation keeps quantized input")
	var mixed: Array[Dictionary] = [_component(&"physical", &"standard", ArmorFraction.make(40), &"steel"), _component(&"fire", &"standard", ArmorFraction.make(40), &"rune")]
	var defenses := _defense()
	defenses["fire"]["armor"] = 2500; defenses["fire"]["natural"] = 2500
	var r := ArmorHitCalculation.calculate(mixed, 25, 100, 100, 100, defenses)
	check(r.reason == &"" and r.armor_spent == 25 and r.total_damage == 40, "D0 mixed overflow25/40")
	check(r.rows[0]["armor_spent"] == 17 and r.rows[1]["armor_spent"] == 8 and r.rows[0]["hp_damage"] == 23 and r.rows[1]["hp_damage"] == 17, "largest remainder17/8 then HP23/17")
	mixed.reverse()
	check(ArmorHitCalculation.calculate(mixed,25,100,100,100,defenses).get_rows() == r.get_rows(), "permutation does not change type distribution")
	defenses = _defense(0,0,11000,11000)
	defenses["fire"]["natural"] = 11000
	mixed = [_component(&"physical", &"standard", ArmorFraction.make(20), &"steel"), _component(&"fire", &"standard", ArmorFraction.make(200), &"rune")]
	r = ArmorHitCalculation.calculate(mixed,0,0,7,10,defenses)
	check(r.hp_after == 7 and r.total_damage == 20 and r.total_healing == 20, "no intermediate overkill clamp or death")
	mixed[1]["amount"] = ArmorFraction.make(1000)
	r = ArmorHitCalculation.calculate(mixed,0,0,7,10,defenses)
	check(r.hp_after == 10 and r.total_damage == 20 and r.total_healing == 100, "one final HPmax clamp")
	var bypass: Array[Dictionary] = [_component(&"physical", &"hp_only_natural",ArmorFraction.make(20),&"spell")]
	r = ArmorHitCalculation.calculate(bypass,100,100,100,100,_defense(5000,2500))
	check(r.armor_spent == 0 and r.total_damage == 15, "hp only natural bypasses armor only")
	bypass[0]["policy"] = &"hp_only_unresisted"
	r = ArmorHitCalculation.calculate(bypass,100,100,100,100,_defense(5000,2500))
	check(r.armor_spent == 0 and r.total_damage == 20, "explicit unresisted")
	check(not ArmorFraction.from_decimal(0.123456789).valid and not ArmorFraction.from_decimal(1.0e20).valid, "decimal adapter rejects precision loss and overflow")
	check(ArmorHitCalculation.calculate(bypass,0,0,100,100,_defense(),ArmorFraction.make(-1)).reason != &"", "negative multiplier refused")
