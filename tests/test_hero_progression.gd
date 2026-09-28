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
	hero.base_attributes = [3, 2, 3, 1]
	hero.allocated = [0, 0, 0, 0]
	hero.perk = perk
	hero.hp_current = float(hero.max_hp())
	return hero

func _run() -> void:
	_test_experience_and_allocation()
	_test_reset_and_snapshot()
	_test_catalog()
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
	_check(hero.apply_allocation([0, 0, 2, 0]), "endurance allocation accepted")
	_check(hero.max_hp() == 34 and hero.hp_current == hp_before + 4.0, "endurance raises max and current hp by delta")
	var before := hero.to_dict()
	_check(not hero.apply_allocation([0, 0, 0, 0]) and hero.to_dict() == before, "empty allocation rejected without mutation")
	_check(not hero.award_experience_tenths(HeroProgression.MAX_XP_TENTHS) and hero.xp_tenths == before["xp_tenths"], "experience overflow rejected atomically")

func _test_reset_and_snapshot() -> void:
	var hero := _hero(&"hardy")
	hero.award_experience_tenths(1000)
	hero.hp_current = float(hero.max_hp())
	_check(hero.apply_allocation([0, 0, 1, 0]), "one level point allocated")
	hero.hp_current = float(hero.max_hp())
	_check(hero.reset_allocations() and hero.allocated == [0, 0, 0, 0] and hero.hp_current == 30.0, "reset restores baseline and clamps current hp")
	hero.hp_current = 0.0
	_check(not hero.reset_allocations(), "dead hero cannot reset")
	hero.hp_current = float(hero.max_hp())
	hero.award_experience_tenths(1000)
	hero.apply_allocation([1, 0, 0, 0])
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
	bad["allocated"] = [9, 0, 0, 0]
	_check(HeroProgression.from_dict(bad) == null, "overspending rejected")

func _test_catalog() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var hero := HeroCatalog.make_hero(3, &"archer", rng)
	_check(hero != null and hero.level() == 1 and hero.xp_tenths == 0 and hero.allocated == [0, 0, 0, 0], "catalog creates fresh level one hero")
	_check(hero != null and hero.hp_current == float(hero.max_hp()) and hero.name == "Стрелок 3", "generated hero has full hp and class name")
	var bonus_points := hero.base_attributes[0] + hero.base_attributes[1] + hero.base_attributes[2] + hero.base_attributes[3] - 9
	_check(bonus_points >= 0 and bonus_points <= 2, "generated candidate has zero to two random start points")
	var definition := HeroCatalog.class_definition(&"mage")
	_check(definition != null and definition.display_name == "Маг" and HeroCatalog.class_definition(&"missing") == null, "catalog returns class definitions")
