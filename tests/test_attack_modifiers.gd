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
		printerr("FAIL BACKSTAB: " + label)

func _run() -> void:
	_test_directions()
	_test_damage()
	_test_armor()
	_test_definition_validation_and_copy()
	_test_zero_legacy()
	print("ATTACK MODIFIERS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_directions() -> void:
	check(AttackModifiers.rear_offset(Faction.Type.PLAYER) == Vector2i(-1, 0), "player rear direction")
	check(AttackModifiers.rear_offset(Faction.Type.ENEMY) == Vector2i(1, 0), "enemy rear direction")
	check(AttackModifiers.rear_offset(Faction.Type.NEUTRAL) == Vector2i.ZERO, "neutral has no rear")
	check(AttackModifiers.is_backstab(Vector2i(2, 3), Vector2i(3, 3), Faction.Type.PLAYER), "player rear cell")
	check(AttackModifiers.is_backstab(Vector2i(4, 3), Vector2i(3, 3), Faction.Type.ENEMY), "enemy rear cell")
	check(not AttackModifiers.is_backstab(Vector2i(2, 3), Vector2i(3, 3), Faction.Type.ENEMY), "front cell")
	check(not AttackModifiers.is_backstab(Vector2i(3, 2), Vector2i(3, 3), Faction.Type.PLAYER), "side cell")
	check(not AttackModifiers.is_backstab(Vector2i(1, 3), Vector2i(3, 3), Faction.Type.PLAYER), "nonadjacent cell")
	check(not AttackModifiers.is_backstab(Vector2i(2, 3), Vector2i(3, 3), Faction.Type.NEUTRAL), "neutral target")

func _test_damage() -> void:
	var result := AttackDamageCalculation.calculate(8.0, 2.0, 0.0, true, 2, false, 50)
	check(result.reason == &"", "backstab damage succeeds")
	check(result.raw_attack == 10.0, "raw attack remains unmodified")
	check(result.scaled == 17.0, "height and backstab add after height")
	var guarded := AttackDamageCalculation.calculate(8.0, 2.0, 0.0, true, 2, true, 50)
	check(absf(guarded.hit_amount - 11.9) < 0.000001, "backstab applies before guard")
	var invalid := AttackDamageCalculation.calculate(8.0, 2.0, 0.0, true, 0, false, 1001)
	check(invalid.reason != &"" and invalid.get_stages().is_empty(), "out of range bonus rejected without stages")

func _test_armor() -> void:
	var base := ArmorAttack.components(8.0, 2.0, 0, false, [], 50)
	check(base.size() == 1 and float(base[0]["numerator"]) / float(base[0]["denominator"]) == 15.0, "armor physical gets additive backstab")
	var guarded := ArmorAttack.components(8.0, 2.0, 0, true, [], 50)
	check(guarded.size() == 1 and float(guarded[0]["numerator"]) / float(guarded[0]["denominator"]) == 10.5, "guard reduces bonus physical")
	var extras: Array[Dictionary] = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "test", "factor_num": 1, "factor_den": 1}]
	var with_extra := ArmorAttack.components(8.0, 2.0, 0, false, extras, 50)
	check(with_extra.size() == 2, "armor extra retained")
	check(float(with_extra[0]["numerator"]) / float(with_extra[0]["denominator"]) == 15.0, "physical receives backstab")
	check(float(with_extra[1]["numerator"]) / float(with_extra[1]["denominator"]) == 10.0, "extra does not receive backstab")
	check(ArmorAttack.components(8.0, 2.0, 0, false, [], 1001).is_empty(), "armor rejects unsupported bonus")

func _test_definition_validation_and_copy() -> void:
	var definition := AttackDefinition.new()
	definition.id = &"backstab"
	definition.profile = &"spatial_melee_balance_v1"
	definition.backstab_bonus_percent = 50
	var rules := AttackRules.new([1, 2], [{"actor_unit_id": 1, "target_unit_id": 2}], [definition])
	check(rules.validate() == &"", "spatial profile accepts bonus")
	definition.backstab_bonus_percent = 0
	var copied := rules.get_definition(&"backstab")
	check(copied != null and copied.backstab_bonus_percent == 50, "rules snapshot copies bonus")
	if copied != null: copied.backstab_bonus_percent = 75
	var copied_again := rules.get_definition(&"backstab")
	check(copied_again != null and copied_again.backstab_bonus_percent == 50, "definition copies isolated")
	var invalid_range := AttackDefinition.new()
	invalid_range.id = &"invalid_range"
	invalid_range.profile = &"armor_spatial_v1"
	invalid_range.backstab_bonus_percent = 1001
	check(AttackRules.new([1, 2], [], [invalid_range]).validate() != &"", "definition range rejected")
	var invalid_profile := AttackDefinition.new()
	invalid_profile.id = &"invalid_profile"
	invalid_profile.profile = &"flat_melee_v1"
	invalid_profile.backstab_bonus_percent = 1
	check(AttackRules.new([1, 2], [], [invalid_profile]).validate() != &"", "unsupported profile rejected")

func _test_zero_legacy() -> void:
	var legacy := AttackDamageCalculation.calculate(10.0, 2.0, 3.0, true, 2, true)
	var explicit_zero := AttackDamageCalculation.calculate(10.0, 2.0, 3.0, true, 2, true, 0)
	check(legacy.raw_attack == explicit_zero.raw_attack and legacy.scaled == explicit_zero.scaled and legacy.hit_amount == explicit_zero.hit_amount, "zero bonus retains old values")
	check(legacy.get_stages() == explicit_zero.get_stages(), "zero bonus retains old stages")
	var armor_legacy := ArmorAttack.components(10.0, 2.0, 2, true, [])
	var armor_zero := ArmorAttack.components(10.0, 2.0, 2, true, [], 0)
	check(armor_legacy == armor_zero, "zero armor bonus retains old components")
