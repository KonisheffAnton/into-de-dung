extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL UNIT SNAPSHOT PERFORMANCE: " + label)

func _run() -> void:
	_test_current_compositions_and_input_purity()
	_test_armor_hp_cases()
	_test_current_reference_and_combinations()
	print("UNIT SNAPSHOT PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _unit_snapshot(schema: int, hp_max: float = 10.0, hp: float = 10.0, include_hp: bool = true) -> Dictionary:
	var stats := StatsBag.new()
	if include_hp:
		stats.set_base_value(StatTypes.StatType.HP_MAX, hp_max)
		# Порядок операций сериализуется отдельно от фиксированных стадий формулы.
		stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"pct", StatModifier.Operation.ADD_PERCENT, 0.5))
		stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"flat", StatModifier.Operation.ADD_FLAT, 2.0))
		stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"mult", StatModifier.Operation.MULTIPLY, 1.0))
	stats.set_base_value(StatTypes.StatType.MOVE_RANGE, 4.0)
	stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 1.0)
	stats.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 1.0)
	stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 2.0)
	stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
	var unit := UnitState.new()
	unit.id = 800 + schema
	unit.faction = Faction.Type.PLAYER
	unit.debug_name = "Snapshot"
	unit.stats = stats
	unit.vitals = Vitals.new(stats, false)
	unit.vitals.set_hp(hp)
	unit.vitals.set_balance(4.0)
	if schema >= 2:
		check(unit.enable_action_resources() == &"", "fixture enables action resources schema " + str(schema))
	if schema == 3: unit.guard_stance = true
	if schema in [4, 5]: unit.armor = ArmorState.new()
	if schema == 5: unit.bleeding = BleedingState.new()
	if schema >= 6: unit.control = ControlState.new()
	var data := unit.to_snapshot_dict()
	check(data.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and data.get("guard_stance") == unit.guard_stance, "fixture current schema " + str(schema))
	return data

func _compare(data: Dictionary, label: String, expected_valid: bool) -> void:
	var before := data.duplicate(true)
	var actual := UnitState.validate_snapshot_dict(data)
	check(actual == expected_valid, label + " validation expectation")
	check(data == before, label + " input DTO unchanged")

func _test_current_compositions_and_input_purity() -> void:
	for schema: int in range(1, 7):
		_compare(_unit_snapshot(schema), "current component fixture " + str(schema), true)
	for old_version: int in range(1, UnitState.SNAPSHOT_SCHEMA_VERSION):
		var old_data := _unit_snapshot(1)
		old_data["schema_version"] = old_version
		_compare(old_data, "old schema " + str(old_version), false)
	var schema6 := _unit_snapshot(6)
	var prior := schema6.duplicate(true)
	prior["control"]["stunned_turns"] = 2
	_compare(prior, "malformed control", false)
	var malformed_stats := schema6.duplicate(true)
	malformed_stats["stats"]["stats"][0]["stat"]["modifiers"][0]["value"] = INF
	_compare(malformed_stats, "malformed stats", false)

func _test_armor_hp_cases() -> void:
	var absent := _unit_snapshot(4, 0.0, 0.0, false)
	absent["stats"]["stats"].clear()
	_compare(absent, "HP_MAX absent defaults to zero", true)
	var fractional_max := _unit_snapshot(4, 10.0, 10.0)
	for entry: Dictionary in fractional_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = 10.5
	_compare(fractional_max, "fractional effective HP_MAX", false)
	var infinite_max := _unit_snapshot(4, 10.0, 0.0)
	for entry: Dictionary in infinite_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = INF
	_compare(infinite_max, "nonfinite HP_MAX", false)
	var out_of_range_max := _unit_snapshot(4, 10.0, 0.0)
	for entry: Dictionary in out_of_range_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = 9007199254740992.0
	_compare(out_of_range_max, "out-of-range HP_MAX", false)
	var fractional_hp := _unit_snapshot(4, 10.0, 10.0)
	fractional_hp["vitals"]["hp"] = 10.5
	_compare(fractional_hp, "fractional current HP", false)
	var nonfinite_hp := _unit_snapshot(4, 10.0, 10.0)
	nonfinite_hp["vitals"]["hp"] = INF
	_compare(nonfinite_hp, "nonfinite current HP", false)
	var out_of_range_hp := _unit_snapshot(4, 10.0, 10.0)
	out_of_range_hp["vitals"]["hp"] = 9007199254740992.0
	_compare(out_of_range_hp, "out-of-range current HP", false)
	var hp_above_max := _unit_snapshot(4, 10.0, 10.0)
	hp_above_max["vitals"]["hp"] = 20.0
	_compare(hp_above_max, "current HP above effective maximum", false)

func _reference_unit() -> UnitState:
	var unit := UnitState.from_snapshot_dict(_unit_snapshot(1))
	return unit

func _expected_reference(unit: UnitState) -> Dictionary:
	return {"id": unit.id, "faction": int(unit.faction),
		"vitals": {"is_alive": unit.vitals.is_alive()}}

func _check_invalid_reference(unit: UnitState, label: String) -> void:
	check(unit.to_snapshot_dict().is_empty(), label + " producer rejects malformed runtime")
	check(unit.to_reference_dict().is_empty(), label + " invalid reference is empty")

func _check_valid_reference(unit: UnitState, label: String) -> void:
	var snapshot := unit.to_snapshot_dict()
	check(not snapshot.is_empty() and UnitState.validate_snapshot_dict(snapshot), label + " producer and validator accept runtime")
	check(unit.to_reference_dict() == _expected_reference(unit), label + " valid reference DTO")

func _test_current_reference_and_combinations() -> void:
	# Проверяются все 128 комбинаций: взаимосвязи задают допустимость снимка.
	for mask: int in range(128):
		var unit := _reference_unit()
		if (mask & 1) != 0: check(unit.enable_action_resources() == &"", "combo resources " + str(mask))
		if (mask & 2) != 0: unit.guard_stance = true
		if (mask & 4) != 0: unit.armor = ArmorState.new()
		if (mask & 8) != 0:
			unit.bleeding = BleedingState.new()
			if (mask & 64) != 0:
				unit.bleeding.stacked = true
				unit.bleeding.stacks = 1
				unit.bleeding.ticks_left = 1
				unit.bleeding.hit_id = "snapshot-combination"
				unit.bleeding.source = {"kind": &"attack", "source_instance_id": 0,
					"origin_cell": Vector2i.ZERO, "instigator_unit_id": unit.id,
					"credit_unit_id": unit.id}
		if (mask & 16) != 0: unit.control = ControlState.new()
		if (mask & 32) != 0: unit.combat_perks = CombatPerksState.new()
		if (mask & 64) != 0: unit.elemental = ElementalState.new()
		var requires_actions: bool = (mask & 126) != 0
		var expected_valid: bool = (not requires_actions or (mask & 1) != 0)
		if (mask & 8) != 0:
			expected_valid = expected_valid and (mask & 4) != 0
		if (mask & 64) != 0:
			expected_valid = expected_valid and (mask & 4) != 0 and (mask & 8) != 0
		var actual := unit.to_snapshot_dict()
		check((not actual.is_empty()) == expected_valid, "optional combination producer admission " + str(mask))
		check(UnitState.validate_snapshot_dict(actual) == expected_valid, "optional combination validation " + str(mask))
		if expected_valid:
			var expected_fields: Array[String] = ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals", "guard_stance"]
			for pair: Array in [[1, "action_resources"], [4, "armor"], [8, "bleeding"], [16, "control"], [32, "combat_perks"], [64, "elemental"]]:
				var present: bool = (mask & int(pair[0])) != 0
				check(actual.has(String(pair[1])) == present, "optional field presence " + String(pair[1]) + " mask " + str(mask))
				if present: expected_fields.append(String(pair[1]))
			var actual_fields: Array[String] = []
			for key: Variant in actual.keys(): actual_fields.append(String(key))
			expected_fields.sort()
			actual_fields.sort()
			check(actual_fields == expected_fields, "exact current snapshot keys mask " + str(mask))
			var restored := UnitState.from_snapshot_dict(actual)
			check(restored != null and restored.to_snapshot_dict() == actual, "optional combination isolated roundtrip " + str(mask))
			check(unit.to_reference_dict() == _expected_reference(unit), "valid reference DTO mask " + str(mask))
		else:
			check(unit.to_reference_dict().is_empty(), "invalid combination reference DTO mask " + str(mask))
	var fresh_reference_unit := _reference_unit()
	var detached_reference := fresh_reference_unit.to_reference_dict()
	fresh_reference_unit.faction = Faction.Type.ENEMY
	fresh_reference_unit.vitals.apply_damage(fresh_reference_unit.vitals.get_hp())
	check(detached_reference["faction"] == int(Faction.Type.PLAYER) and detached_reference["vitals"]["is_alive"], "reference DTO remains detached after runtime changes")
	var refreshed_reference := fresh_reference_unit.to_reference_dict()
	check(refreshed_reference == _expected_reference(fresh_reference_unit) and refreshed_reference["faction"] == int(Faction.Type.ENEMY) and not refreshed_reference["vitals"]["is_alive"], "reference DTO reflects fresh runtime state")
	var invalid_id := _reference_unit()
	invalid_id.id = UnitId.NONE
	_check_invalid_reference(invalid_id, "invalid id")
	var invalid_move := _reference_unit()
	invalid_move.move_points_left = INF
	_check_invalid_reference(invalid_move, "nonfinite move")
	var invalid_faction := _reference_unit()
	invalid_faction.set("faction", 99)
	_check_invalid_reference(invalid_faction, "invalid faction")
	var missing_stats := _reference_unit()
	missing_stats.stats = null
	_check_invalid_reference(missing_stats, "null stats")
	var missing_vitals := _reference_unit()
	missing_vitals.vitals = null
	_check_invalid_reference(missing_vitals, "null vitals")
	var wrong_vitals_stats := _reference_unit()
	wrong_vitals_stats.vitals._stats = StatsBag.new()
	_check_invalid_reference(wrong_vitals_stats, "vitals references different stats")
	var malformed_resources := _reference_unit()
	check(malformed_resources.enable_action_resources() == &"", "malformed-resource fixture setup")
	malformed_resources.action_resources._main_left = ActionResources.MAX_COUNTER + 1
	_check_invalid_reference(malformed_resources, "malformed resources")
	var wrong_resource_owner := _reference_unit()
	check(wrong_resource_owner.enable_action_resources() == &"", "wrong-owner fixture setup")
	wrong_resource_owner.action_resources._owner_unit_id += 1
	_check_invalid_reference(wrong_resource_owner, "resource owner mismatch")
	var signed_resistance_armor := _reference_unit()
	check(signed_resistance_armor.enable_action_resources() == &"", "signed-resistance fixture setup")
	signed_resistance_armor.armor = ArmorState.new()
	signed_resistance_armor.armor.natural["physical"] = -1
	_check_valid_reference(signed_resistance_armor, "signed natural resistance")
	var malformed_perks := _reference_unit()
	check(malformed_perks.enable_action_resources() == &"", "malformed-perks fixture setup")
	malformed_perks.combat_perks = CombatPerksState.new()
	malformed_perks.combat_perks.mode = CombatPerksState.Mode.COVER
	malformed_perks.combat_perks.cover_target_id = malformed_perks.id
	_check_invalid_reference(malformed_perks, "self cover rejected")
	var malformed_status := _reference_unit()
	check(malformed_status.enable_action_resources() == &"", "malformed-status fixture setup")
	malformed_status.armor = ArmorState.new()
	malformed_status.bleeding = BleedingState.new()
	malformed_status.bleeding.stacked = true
	malformed_status.bleeding.stacks = 1
	malformed_status.bleeding.ticks_left = 1
	malformed_status.bleeding.hit_id = "without-valid-source"
	_check_invalid_reference(malformed_status, "stacked bleeding without source")
	var malformed_control := _reference_unit()
	check(malformed_control.enable_action_resources() == &"", "malformed-control fixture setup")
	malformed_control.control = ControlState.new()
	malformed_control.control.stunned_turns = 2
	_check_invalid_reference(malformed_control, "invalid control state")
	var malformed_elemental := _reference_unit()
	check(malformed_elemental.enable_action_resources() == &"", "malformed-elemental fixture setup")
	malformed_elemental.armor = ArmorState.new()
	malformed_elemental.bleeding = BleedingState.new()
	malformed_elemental.bleeding.stacked = true
	malformed_elemental.bleeding.stacks = 1
	malformed_elemental.bleeding.ticks_left = 1
	malformed_elemental.bleeding.hit_id = "valid-source"
	malformed_elemental.bleeding.source = {"kind": &"attack", "source_instance_id": 0,
		"origin_cell": Vector2i.ZERO, "instigator_unit_id": malformed_elemental.id,
		"credit_unit_id": malformed_elemental.id}
	malformed_elemental.elemental = ElementalState.new()
	malformed_elemental.elemental.burning_stacks = 1
	_check_invalid_reference(malformed_elemental, "burning without ticks rejected")
	var burning_and_bleeding := _reference_unit()
	check(burning_and_bleeding.enable_action_resources() == &"", "burning-bleeding fixture resources")
	burning_and_bleeding.armor = ArmorState.new()
	burning_and_bleeding.bleeding = BleedingState.new()
	burning_and_bleeding.bleeding.stacked = true
	burning_and_bleeding.bleeding.stacks = 1
	burning_and_bleeding.bleeding.ticks_left = 1
	burning_and_bleeding.bleeding.hit_id = "bleed-stack"
	burning_and_bleeding.bleeding.source = {"kind": &"attack", "source_instance_id": 0,
		"origin_cell": Vector2i.ZERO, "instigator_unit_id": burning_and_bleeding.id,
		"credit_unit_id": burning_and_bleeding.id}
	burning_and_bleeding.elemental = ElementalState.new()
	burning_and_bleeding.elemental.burning_stacks = 1
	burning_and_bleeding.elemental.burning_ticks = 1
	burning_and_bleeding.elemental.burning_source = {"kind": &"attack", "source_instance_id": 0,
		"origin_cell": Vector2i.ZERO, "instigator_unit_id": burning_and_bleeding.id,
		"credit_unit_id": burning_and_bleeding.id}
	_check_invalid_reference(burning_and_bleeding, "burning with bleeding rejected")
	var invalid_modifier := _reference_unit()
	var hp_stat: Stat = invalid_modifier.stats._stats[StatTypes.StatType.HP_MAX]
	hp_stat._modifiers[0].value = INF
	_check_invalid_reference(invalid_modifier, "nonfinite stat modifier")
	var invalid_slot := _reference_unit()
	var slot_stat: Stat = invalid_slot.stats._stats[StatTypes.StatType.HP_MAX]
	slot_stat._modifier_slots[0] = -1
	_check_invalid_reference(invalid_slot, "invalid modifier slot")
	var stale_cache := _reference_unit()
	var cache_stat: Stat = stale_cache.stats._stats[StatTypes.StatType.HP_MAX]
	cache_stat.get_value()
	cache_stat._cached_value += 1.0
	_check_invalid_reference(stale_cache, "stale stat cache")
	var fractional_hp := _reference_unit()
	check(fractional_hp.enable_action_resources() == &"", "fractional-HP fixture resources")
	fractional_hp.armor = ArmorState.new()
	fractional_hp.vitals._hp = 1.5
	_check_invalid_reference(fractional_hp, "fractional current HP")
	var overmax_hp := _reference_unit()
	check(overmax_hp.enable_action_resources() == &"", "overmax-HP fixture resources")
	overmax_hp.armor = ArmorState.new()
	overmax_hp.vitals._hp = 19.0
	_check_invalid_reference(overmax_hp, "current HP above maximum")
	var fractional_max_hp := _reference_unit()
	check(fractional_max_hp.enable_action_resources() == &"", "fractional-max fixture resources")
	fractional_max_hp.armor = ArmorState.new()
	fractional_max_hp.stats._stats[StatTypes.StatType.HP_MAX].base_value = 10.5
	_check_invalid_reference(fractional_max_hp, "fractional effective maximum HP")
	var overmax_effective_hp := _reference_unit()
	check(overmax_effective_hp.enable_action_resources() == &"", "overmax-effective fixture resources")
	overmax_effective_hp.armor = ArmorState.new()
	overmax_effective_hp.stats._stats[StatTypes.StatType.HP_MAX].base_value = 9007199254740992.0
	overmax_effective_hp.vitals._hp = 0.0
	_check_invalid_reference(overmax_effective_hp, "effective maximum HP exceeds exact range")
	var absent_max_hp := _reference_unit()
	check(absent_max_hp.enable_action_resources() == &"", "absent-max fixture resources")
	absent_max_hp.armor = ArmorState.new()
	absent_max_hp.stats._stats.erase(StatTypes.StatType.HP_MAX)
	absent_max_hp.vitals._hp = 0.0
	_check_valid_reference(absent_max_hp, "absent HP_MAX defaults to zero")
