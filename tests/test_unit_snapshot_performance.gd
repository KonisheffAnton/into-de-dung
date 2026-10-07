extends SceneTree

const SnapshotReference = preload("res://tests/fixtures/unit_snapshot_reference.gd")

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
	_test_all_schemas_and_input_purity()
	_test_armor_hp_cases()
	_test_reference_equivalence()
	print("UNIT SNAPSHOT PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _unit_snapshot(schema: int, hp_max: float = 10.0, hp: float = 18.0, include_hp: bool = true) -> Dictionary:
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
	if schema >= 3: unit.guard_stance = true
	if schema >= 4: unit.armor = ArmorState.new()
	if schema >= 5: unit.bleeding = BleedingState.new()
	if schema >= 6: unit.control = ControlState.new()
	var data := unit.to_snapshot_dict()
	check(data.get("schema_version") == schema, "fixture schema " + str(schema))
	return data

func _reference_validate_snapshot_dict(data: Variant) -> bool:
	# Эталонная реализация до оптимизации; вложенный duplicate намеренно сохранён.
	if typeof(data) != TYPE_DICTIONARY: return false
	var d: Dictionary = data
	if typeof(d.get("schema_version")) == TYPE_INT and d["schema_version"] == 6:
		if not d.has("control") or not ControlState.valid(d["control"]): return false
		var prior := d.duplicate(true)
		prior.erase("control")
		prior["schema_version"] = 5 if prior.has("bleeding") else (4 if prior.has("armor") else (3 if prior.has("guard_stance") else 2))
		return _reference_validate_snapshot_dict(prior)
	var base_required := ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals"]
	if typeof(data.get("schema_version")) != TYPE_INT or data["schema_version"] not in [1, 2, 3, 4, 5]: return false
	var required := base_required if data["schema_version"] == 1 else base_required + ["action_resources"]
	if data["schema_version"] == 4: required.append("armor")
	if data["schema_version"] == 5:
		required.append("armor")
		required.append("bleeding")
	if data["schema_version"] in [3, 4, 5]:
		required.append("guard_stance")
		if typeof(data.get("guard_stance")) != TYPE_BOOL: return false
	if not _keys_exact(d, required): return false
	for key in ["schema_version", "id", "faction", "cell_x", "cell_y", "height"]:
		if typeof(d[key]) != TYPE_INT: return false
	if d["id"] < UnitId.FIRST or d["faction"] < 0 or d["faction"] > 2 or d["cell_x"] < -2147483648 or d["cell_x"] > 2147483647 or d["cell_y"] < -2147483648 or d["cell_y"] > 2147483647: return false
	if typeof(d["debug_name"]) != TYPE_STRING or typeof(d["ai_profile_path"]) != TYPE_STRING or not d["ai_profile_path"].is_empty() or typeof(d["move_points_left"]) != TYPE_FLOAT or not is_finite(d["move_points_left"]) or d["move_points_left"] < 0.0 or typeof(d["has_attacked"]) != TYPE_BOOL: return false
	if not StatsBag.validate_snapshot_dict(d["stats"]): return false
	if d["schema_version"] in [2, 3, 4, 5] and not ActionResources.validate_snapshot_dict(d["action_resources"], d["id"]): return false
	if d["schema_version"] in [4, 5] and not ArmorState.valid(d["armor"]): return false
	if d["schema_version"] == 5 and not BleedingState.valid(d["bleeding"]): return false
	if typeof(d["vitals"]) != TYPE_DICTIONARY: return false
	var v: Dictionary = d["vitals"]
	if not _keys_exact(v, ["hp", "balance", "is_alive"]): return false
	if typeof(v["hp"]) != TYPE_FLOAT or not is_finite(v["hp"]) or v["hp"] < 0.0: return false
	if typeof(v["balance"]) != TYPE_FLOAT or not is_finite(v["balance"]) or v["balance"] < 0.0: return false
	if d["schema_version"] in [4, 5]:
		if v["hp"] != floorf(v["hp"]) or v["hp"] > ArmorRuntime.MAX_EXACT_HP: return false
		var stats_copy := StatsBag.from_snapshot_dict(d["stats"])
		if stats_copy == null: return false
		var maximum := stats_copy.get_value(StatTypes.StatType.HP_MAX)
		if not is_finite(maximum) or maximum < 0.0 or maximum > ArmorRuntime.MAX_EXACT_HP or maximum != floorf(maximum) or v["hp"] > maximum: return false
	return typeof(v["is_alive"]) == TYPE_BOOL

func _keys_exact(value: Dictionary, required: Array) -> bool:
	if value.keys().size() != required.size(): return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key): return false
	return true

func _compare(data: Dictionary, label: String) -> void:
	var before := data.duplicate(true)
	var expected := _reference_validate_snapshot_dict(data)
	var actual := UnitState.validate_snapshot_dict(data)
	check(actual == expected, label + " reference parity")
	check(data == before, label + " input DTO unchanged")

func _test_all_schemas_and_input_purity() -> void:
	for schema in range(1, 7):
		_compare(_unit_snapshot(schema), "schema " + str(schema))
	var schema6 := _unit_snapshot(6)
	var prior := schema6.duplicate(true)
	prior["control"]["stunned_turns"] = 2
	_compare(prior, "malformed control")
	var malformed_stats := schema6.duplicate(true)
	malformed_stats["stats"]["stats"][0]["stat"]["modifiers"][0]["value"] = INF
	_compare(malformed_stats, "malformed stats")

func _test_armor_hp_cases() -> void:
	var absent := _unit_snapshot(4, 0.0, 0.0, false)
	absent["stats"]["stats"].clear()
	_compare(absent, "HP_MAX absent defaults to zero")
	var fractional_max := _unit_snapshot(4, 10.0, 10.0)
	for entry: Dictionary in fractional_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = 10.5
	_compare(fractional_max, "fractional effective HP_MAX")
	var infinite_max := _unit_snapshot(4, 10.0, 0.0)
	for entry: Dictionary in infinite_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = INF
	_compare(infinite_max, "nonfinite HP_MAX")
	var out_of_range_max := _unit_snapshot(4, 10.0, 0.0)
	for entry: Dictionary in out_of_range_max["stats"]["stats"]:
		if entry["stat_type"] == StatTypes.StatType.HP_MAX: entry["stat"]["base_value"] = 9007199254740992.0
	_compare(out_of_range_max, "out-of-range HP_MAX")
	var fractional_hp := _unit_snapshot(4, 10.0, 10.0)
	fractional_hp["vitals"]["hp"] = 10.5
	_compare(fractional_hp, "fractional current HP")
	var nonfinite_hp := _unit_snapshot(4, 10.0, 10.0)
	nonfinite_hp["vitals"]["hp"] = INF
	_compare(nonfinite_hp, "nonfinite current HP")
	var out_of_range_hp := _unit_snapshot(4, 10.0, 10.0)
	out_of_range_hp["vitals"]["hp"] = 9007199254740992.0
	_compare(out_of_range_hp, "out-of-range current HP")
	var hp_above_max := _unit_snapshot(4, 10.0, 10.0)
	hp_above_max["vitals"]["hp"] = 20.0
	_compare(hp_above_max, "current HP above effective maximum")

func _reference_unit() -> UnitState:
	var unit := UnitState.from_snapshot_dict(_unit_snapshot(1))
	return unit

func _check_reference_matches_legacy(unit: UnitState, label: String) -> void:
	var expected := SnapshotReference.capture(unit)
	var expected_reference := {} if expected.is_empty() else {"id": expected["id"],
		"faction": expected["faction"], "vitals": {"is_alive": expected["vitals"]["is_alive"]}}
	check(unit.to_snapshot_dict() == expected, label + " frozen snapshot")
	var reference := unit.to_reference_dict()
	check(reference == expected_reference, label + " reference parity")
	check(SnapshotReference.capture(unit) == expected, label + " reference leaves runtime unchanged")

func _test_reference_equivalence() -> void:
	# Каждый штатный optional-state путь сверяется с замороженной сериализацией.
	for schema: int in range(1, 9):
		var unit := _reference_unit()
		if schema >= 2: check(unit.enable_action_resources() == &"", "reference resources schema " + str(schema))
		if schema >= 3: unit.guard_stance = true
		if schema >= 4: unit.armor = ArmorState.new()
		if schema >= 5: unit.bleeding = BleedingState.new()
		if schema >= 6: unit.control = ControlState.new()
		if schema >= 7: unit.combat_perks = CombatPerksState.new()
		if schema >= 8:
			unit.bleeding.stacked = true
			unit.bleeding.stacks = 1
			unit.bleeding.ticks_left = 1
			unit.bleeding.hit_id = "snapshot-reference"
			unit.bleeding.source = {"kind": &"attack", "source_instance_id": 0,
				"origin_cell": Vector2i.ZERO, "instigator_unit_id": unit.id,
				"credit_unit_id": unit.id}
			unit.elemental = ElementalState.new()
		var expected := SnapshotReference.capture(unit)
		var actual := unit.to_snapshot_dict()
		check(actual == expected, "frozen full snapshot unchanged schema " + str(schema))
		var runtime_before := SnapshotReference.capture(unit)
		var reference := unit.to_reference_dict()
		check(SnapshotReference.capture(unit) == runtime_before, "reference conversion does not mutate runtime schema " + str(schema))
		var expected_reference := {} if expected.is_empty() else {"id": expected["id"],
			"faction": expected["faction"], "vitals": {"is_alive": expected["vitals"]["is_alive"]}}
		check(reference == expected_reference, "reference DTO parity schema " + str(schema))
		unit.faction = Faction.Type.ENEMY
		unit.vitals.apply_damage(unit.vitals.get_hp())
		check(reference == expected_reference, "reference DTO detached schema " + str(schema))
		var changed := unit.to_reference_dict()
		check(changed.get("faction") == int(Faction.Type.ENEMY), "reference refreshed faction schema " + str(schema))
		check(changed.get("vitals", {}).get("is_alive") == false, "reference refreshed alive schema " + str(schema))
		check(SnapshotReference.capture(unit) != runtime_before, "runtime mutation observed schema " + str(schema))
		unit.faction = Faction.Type.PLAYER
		unit.vitals.revive(5.0 / unit.vitals.get_hp_max())
	# Семь опциональных компонентов проверяются во всех 128 сочетаниях.
	for mask: int in range(128):
		var unit := _reference_unit()
		if (mask & 1) != 0: check(unit.enable_action_resources() == &"", "combo resources " + str(mask))
		if (mask & 2) != 0: unit.guard_stance = true
		if (mask & 4) != 0: unit.armor = ArmorState.new()
		if (mask & 8) != 0: unit.bleeding = BleedingState.new()
		if (mask & 16) != 0: unit.control = ControlState.new()
		if (mask & 32) != 0: unit.combat_perks = CombatPerksState.new()
		if (mask & 64) != 0: unit.elemental = ElementalState.new()
		_check_reference_matches_legacy(unit, "optional combination " + str(mask))
	var invalid_id := _reference_unit()
	invalid_id.id = UnitId.NONE
	_check_reference_matches_legacy(invalid_id, "invalid id")
	var invalid_move := _reference_unit()
	invalid_move.move_points_left = INF
	_check_reference_matches_legacy(invalid_move, "nonfinite move")
	var invalid_faction := _reference_unit()
	invalid_faction.set("faction", 99)
	_check_reference_matches_legacy(invalid_faction, "invalid faction")
	var missing_stats := _reference_unit()
	missing_stats.stats = null
	_check_reference_matches_legacy(missing_stats, "null stats")
	var missing_vitals := _reference_unit()
	missing_vitals.vitals = null
	_check_reference_matches_legacy(missing_vitals, "null vitals")
	var wrong_vitals_stats := _reference_unit()
	wrong_vitals_stats.vitals._stats = StatsBag.new()
	_check_reference_matches_legacy(wrong_vitals_stats, "vitals references different stats")
	var malformed_resources := _reference_unit()
	check(malformed_resources.enable_action_resources() == &"", "malformed-resource fixture setup")
	malformed_resources.action_resources._main_left = ActionResources.MAX_COUNTER + 1
	_check_reference_matches_legacy(malformed_resources, "malformed resources")
	var wrong_resource_owner := _reference_unit()
	check(wrong_resource_owner.enable_action_resources() == &"", "wrong-owner fixture setup")
	wrong_resource_owner.action_resources._owner_unit_id += 1
	_check_reference_matches_legacy(wrong_resource_owner, "resource owner mismatch")
	var malformed_armor := _reference_unit()
	check(malformed_armor.enable_action_resources() == &"", "malformed-armor fixture setup")
	malformed_armor.armor = ArmorState.new()
	malformed_armor.armor.natural["physical"] = -1
	_check_reference_matches_legacy(malformed_armor, "malformed armor")
	var malformed_perks := _reference_unit()
	check(malformed_perks.enable_action_resources() == &"", "malformed-perks fixture setup")
	malformed_perks.combat_perks = CombatPerksState.new()
	malformed_perks.combat_perks.mode = CombatPerksState.Mode.COVER
	malformed_perks.combat_perks.cover_target_id = malformed_perks.id
	_check_reference_matches_legacy(malformed_perks, "self cover rejected")
	var malformed_status := _reference_unit()
	check(malformed_status.enable_action_resources() == &"", "malformed-status fixture setup")
	malformed_status.armor = ArmorState.new()
	malformed_status.bleeding = BleedingState.new()
	malformed_status.bleeding.stacked = true
	malformed_status.bleeding.stacks = 1
	malformed_status.bleeding.ticks_left = 1
	malformed_status.bleeding.hit_id = "without-valid-source"
	_check_reference_matches_legacy(malformed_status, "stacked bleeding without source")
	var malformed_control := _reference_unit()
	check(malformed_control.enable_action_resources() == &"", "malformed-control fixture setup")
	malformed_control.control = ControlState.new()
	malformed_control.control.stunned_turns = 2
	_check_reference_matches_legacy(malformed_control, "invalid control state")
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
	_check_reference_matches_legacy(malformed_elemental, "burning without ticks rejected")
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
	_check_reference_matches_legacy(burning_and_bleeding, "burning with bleeding rejected")
	var invalid_modifier := _reference_unit()
	var hp_stat: Stat = invalid_modifier.stats._stats[StatTypes.StatType.HP_MAX]
	hp_stat._modifiers[0].value = INF
	_check_reference_matches_legacy(invalid_modifier, "nonfinite stat modifier")
	var invalid_slot := _reference_unit()
	var slot_stat: Stat = invalid_slot.stats._stats[StatTypes.StatType.HP_MAX]
	slot_stat._modifier_slots[0] = -1
	_check_reference_matches_legacy(invalid_slot, "invalid modifier slot")
	var stale_cache := _reference_unit()
	var cache_stat: Stat = stale_cache.stats._stats[StatTypes.StatType.HP_MAX]
	cache_stat.get_value()
	cache_stat._cached_value += 1.0
	_check_reference_matches_legacy(stale_cache, "stale stat cache")
	var fractional_hp := _reference_unit()
	check(fractional_hp.enable_action_resources() == &"", "fractional-HP fixture resources")
	fractional_hp.armor = ArmorState.new()
	fractional_hp.vitals._hp = 1.5
	_check_reference_matches_legacy(fractional_hp, "fractional current HP")
	var overmax_hp := _reference_unit()
	check(overmax_hp.enable_action_resources() == &"", "overmax-HP fixture resources")
	overmax_hp.armor = ArmorState.new()
	overmax_hp.vitals._hp = 19.0
	_check_reference_matches_legacy(overmax_hp, "current HP above maximum")
	var fractional_max_hp := _reference_unit()
	check(fractional_max_hp.enable_action_resources() == &"", "fractional-max fixture resources")
	fractional_max_hp.armor = ArmorState.new()
	fractional_max_hp.stats._stats[StatTypes.StatType.HP_MAX].base_value = 10.5
	_check_reference_matches_legacy(fractional_max_hp, "fractional effective maximum HP")
	var overmax_effective_hp := _reference_unit()
	check(overmax_effective_hp.enable_action_resources() == &"", "overmax-effective fixture resources")
	overmax_effective_hp.armor = ArmorState.new()
	overmax_effective_hp.stats._stats[StatTypes.StatType.HP_MAX].base_value = 9007199254740992.0
	overmax_effective_hp.vitals._hp = 0.0
	_check_reference_matches_legacy(overmax_effective_hp, "effective maximum HP exceeds exact range")
	var absent_max_hp := _reference_unit()
	check(absent_max_hp.enable_action_resources() == &"", "absent-max fixture resources")
	absent_max_hp.armor = ArmorState.new()
	absent_max_hp.stats._stats.erase(StatTypes.StatType.HP_MAX)
	absent_max_hp.vitals._hp = 0.0
	_check_reference_matches_legacy(absent_max_hp, "absent HP_MAX")
