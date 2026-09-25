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
	_test_all_schemas_and_input_purity()
	_test_armor_hp_cases()
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
