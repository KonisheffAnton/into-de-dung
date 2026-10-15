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
		printerr("FAIL HERO PROGRESSION: " + label)

func _hero(perk: StringName = &"hardy") -> HeroProgression:
	var hero := HeroProgression.new()
	hero.id = 1
	hero.class_id = &"warrior"
	hero.name = "Воин 1"
	hero.base_attributes = [10, 10, 10, 10, 10]
	hero.allocated = [0, 0, 0, 0, 0]
	hero.perk = perk
	hero.hp_current = hero.max_hp()
	return hero

func _run() -> void:
	_test_experience_and_allocation()
	_test_reset_and_snapshot()
	_test_catalog()
	_test_attribute_rules()
	print("HERO PROGRESSION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_experience_and_allocation() -> void:
	var hero := _hero()
	for index: int in 10:
		_check(hero.award_experience_tenths(7), "award fractional xp step")
	_check(hero.xp_tenths == 70 and hero.level() == 1, "ten tenths awards sum to seven xp")
	_check(hero.award_experience_tenths(930) and hero.level() == 2 and hero.available_points() == 1, "first level threshold grants one point")
	_check(hero.award_experience_tenths(44000) and hero.level() == 10 and hero.available_points() == 9, "cumulative thresholds grant nine points")
	var hp_before := hero.hp_current
	_check(hero.apply_allocation([0, 0, 2, 0, 0]), "endurance allocation accepted")
	_check(is_equal_approx(hero.max_hp(), 34.0) and is_equal_approx(hero.hp_current, hp_before + 2.0), "endurance raises max and current hp by one per point")
	var before := hero.to_dict()
	_check(not hero.apply_allocation([0, 0, 0, 0, 0]) and hero.to_dict() == before, "empty allocation rejected without mutation")
	_check(not hero.award_experience_tenths(HeroProgression.MAX_XP_TENTHS) and hero.xp_tenths == before["xp_tenths"], "experience overflow rejected atomically")
	var veteran := _hero()
	veteran.award_experience_tenths(530000)
	_check(veteran.level() > 20, "progression exceeds level twenty")
	_check(veteran.apply_allocation([31, 0, 0, 0, 0]) and veteran.attributes()[0] > 40, "allocation can raise attributes above forty")

func _test_reset_and_snapshot() -> void:
	var hero := _hero()
	hero.award_experience_tenths(1000)
	_check(hero.apply_allocation([0, 0, 1, 0, 0]), "one level point allocated")
	hero.hp_current = hero.max_hp()
	_check(hero.reset_allocations() and hero.allocated == [0, 0, 0, 0, 0] and is_equal_approx(hero.hp_current, 32.0), "reset restores baseline and clamps current hp")
	hero.hp_current = 0.0
	_check(not hero.reset_allocations(), "dead hero cannot reset")
	hero.hp_current = hero.max_hp()
	hero.award_experience_tenths(1000)
	_check(hero.apply_allocation([1, 0, 0, 0, 0]), "second level point allocated")
	var packed := hero.to_dict()
	var clone := HeroProgression.from_dict(packed)
	_check(clone != null and clone.to_dict() == packed, "hero snapshot roundtrip")
	clone.base_attributes[0] += 1
	clone.allocated[0] += 1
	_check(hero.base_attributes[0] != clone.base_attributes[0] and hero.allocated[0] != clone.allocated[0], "snapshot arrays are independent")
	var bad := packed.duplicate(true)
	bad["id"] = true
	_check(HeroProgression.from_dict(bad) == null, "boolean rejected for integer id")
	bad = packed.duplicate(true)
	bad["extra"] = "forbidden"
	_check(HeroProgression.from_dict(bad) == null, "unknown snapshot key rejected")
	bad = packed.duplicate(true)
	bad["allocated"] = [9, 0, 0, 0, 0]
	_check(HeroProgression.from_dict(bad) == null, "overspending rejected")
	bad = packed.duplicate(true)
	bad["base_attributes"] = [10, 10, 10, 10]
	_check(HeroProgression.from_dict(bad) == null, "legacy four attribute snapshot rejected")
	bad = packed.duplicate(true)
	bad["hp_current"] = INF
	_check(HeroProgression.from_dict(bad) == null, "non-finite hp rejected")

func _test_catalog() -> void:
	for seed: int in 100:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hero := HeroCatalog.make_hero(seed + 1, &"archer", rng)
		_check(hero != null and hero.base_attributes.size() == 5 and hero.allocated.size() == 5, "generated candidate uses five attributes")
		_check(hero.base_attributes.min() >= 3 and _sum(hero.base_attributes) == 50, "candidate respects minimum and total")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var hero := HeroCatalog.make_hero(3, &"archer", rng)
	var repeat_rng := RandomNumberGenerator.new()
	repeat_rng.seed = 42
	var repeat_hero := HeroCatalog.make_hero(3, &"archer", repeat_rng)
	_check(hero.level() == 1 and hero.xp_tenths == 0 and hero.allocated == [0, 0, 0, 0, 0], "catalog creates a fresh level one hero")
	_check(hero.hp_current == hero.max_hp() and hero.name == "Стрелок 3", "generated hero has full hp and class name")
	_check(repeat_hero.base_attributes == hero.base_attributes and repeat_hero.perk == hero.perk, "candidate generation is deterministic")
	var definition := HeroCatalog.class_definition(&"mage")
	_check(definition != null and definition.display_name == "Маг" and definition.base_attributes == [10, 10, 10, 10, 10], "class attributes are neutral definitions")
	_check(HeroCatalog.class_definition(&"missing") == null, "catalog rejects unknown class")

func _test_attribute_rules() -> void:
	_check(is_equal_approx(CharacterAttributeRules.power_multiplier(10.0), 1.0), "power neutral")
	_check(is_equal_approx(CharacterAttributeRules.power_multiplier(3.0), 0.86), "power at three")
	_check(is_equal_approx(CharacterAttributeRules.status_multiplier(9.0), 0.97), "status at nine")
	_check(is_equal_approx(CharacterAttributeRules.status_multiplier(11.0), 1.03), "status at eleven")
	_check(is_equal_approx(CharacterAttributeRules.position_bonus_multiplier(19.0), 1.54), "position bonus at nineteen")
	_check(is_equal_approx(CharacterAttributeRules.critical_multiplier(30.0), 4.0), "critical at thirty")
	_check(is_equal_approx(CharacterAttributeRules.max_hp(3.0), 21.0), "hp at three")
	_check(is_equal_approx(CharacterAttributeRules.balance_max(9.0), 13.0), "balance at nine")
	_check(is_equal_approx(CharacterAttributeRules.move_max(0.0), 2.0), "movement at zero")
	_check(is_equal_approx(CharacterAttributeRules.move_max(30.0), 8.0), "movement at thirty")
	_check(is_equal_approx(CharacterAttributeRules.resistance_contribution(3.0), -7.0), "resistance permits negative contribution")
	var data := _hero().to_dict()
	data["base_attributes"] = [38, 3, 3, 3, 3]
	data["hp_current"] = 25.0
	var high_base := HeroProgression.from_dict(data)
	_check(high_base != null and high_base.attributes()[0] == 38, "codec accepts valid high base attributes")
	data["base_attributes"] = [39, 3, 3, 3, 2]
	_check(HeroProgression.from_dict(data) == null, "codec rejects base below minimum")

func _sum(values: Array[int]) -> int:
	var total := 0
	for value: int in values:
		total += value
	return total
