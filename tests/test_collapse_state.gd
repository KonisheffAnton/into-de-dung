extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL COLLAPSE STATE: " + label)

func _run() -> void:
	_test_legacy()
	_test_v2_roundtrip()
	_test_invalid_shapes()
	_test_snapshot_geometry()
	print("COLLAPSE STATE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_legacy() -> void:
	var session := BattleEnvironmentSession.new()
	var raw: Dictionary = session.state.environment.to_dict()
	check(raw.keys().size() == 6 and raw["schema_version"] == 1 and not raw.has("collapse"), "empty state emits exact legacy v1 fields")
	var decoded := CombatEnvironmentState.from_dict(raw)
	check(decoded != null and decoded.collapse.is_empty() and decoded.to_dict() == raw, "legacy v1 roundtrip stays exact")
	session.close()

func _test_v2_roundtrip() -> void:
	var state := CombatEnvironmentState.new()
	state.collapse = {"turn": 19, "marked": [Vector2i(2, 3)]}
	var raw := state.to_dict()
	check(raw["schema_version"] == 2 and raw["collapse"] == state.collapse, "enabled state emits v2 collapse")
	var decoded := CombatEnvironmentState.from_dict(raw)
	check(decoded != null and decoded.to_dict() == raw, "v2 roundtrip is canonical")
	if decoded != null:
		raw["collapse"]["marked"][0] = Vector2i(9, 9)
		raw["collapse"]["turn"] = 20
		check(decoded.collapse == {"turn": 19, "marked": [Vector2i(2, 3)]}, "from_dict deep-copies nested values")
	var exported := state.to_dict()
	exported["collapse"]["marked"][0] = Vector2i(8, 8)
	check(state.collapse["marked"] == [Vector2i(2, 3)], "to_dict deep-copies nested values")
	var canonical := CombatEnvironmentState.from_dict({"schema_version": 2, "next_fire_id": 1, "next_corpse_id": 1, "fires": [], "corpses": [], "processed_deaths": [], "collapse": {"turn": 7, "marked": []}})
	check(canonical != null and canonical.to_dict()["collapse"] == {"turn": 7, "marked": []}, "v2 accepts empty marker list at positive turn")

func _test_invalid_shapes() -> void:
	var base: Dictionary = CombatEnvironmentState.new().to_dict()
	var cases: Array[Dictionary] = []
	var item := base.duplicate(true); item["schema_version"] = true; cases.append(item)
	item = base.duplicate(true); item["extra"] = 1; cases.append(item)
	item = base.duplicate(true); item["schema_version"] = 2; cases.append(item)
	item = _v2({"turn": true, "marked": []}); cases.append(item)
	item = _v2({"turn": -1, "marked": []}); cases.append(item)
	item = _v2({"turn": CombatEnvironmentState.MAX_ID - 1, "marked": []}); cases.append(item)
	item = _v2({"turn": 0, "marked": [Vector2i.ZERO]}); cases.append(item)
	item = _v2({"turn": 1, "marked": [Vector2i.ZERO, Vector2i.ONE]}); cases.append(item)
	item = _v2({"turn": 1, "marked": [Vector2i.ZERO, Vector2i.ZERO]}); cases.append(item)
	item = _v2({"turn": 1, "marked": [Vector2.ZERO]}); cases.append(item)
	item = _v2({"turn": 1, "marked": []}); item["collapse"]["unexpected"] = 1; cases.append(item)
	item = _v2({"turn": 1, "marked": []}); item["collapse"]["turn"] = 1.0; cases.append(item)
	item = _v2({"turn": 1, "marked": []}); item["collapse"]["marked"] = PackedVector2Array(); cases.append(item)
	for index: int in cases.size():
		check(not CombatEnvironmentState.valid(cases[index]) and CombatEnvironmentState.from_dict(cases[index]) == null, "reject malformed codec case %d" % index)
	var corrupted := CombatEnvironmentState.new()
	corrupted.collapse = {"turn": true, "marked": []}
	check(not CombatEnvironmentState.valid(corrupted.to_dict()), "to_dict does not normalize invalid runtime fields")

func _v2(collapse: Dictionary) -> Dictionary:
	var raw: Dictionary = CombatEnvironmentState.new().to_dict()
	raw["schema_version"] = 2
	raw["collapse"] = collapse
	return raw

func _test_snapshot_geometry() -> void:
	var session := BattleCoreReactionsSession.new()
	if session.state.environment == null: session.state.environment = CombatEnvironmentState.new()
	session.state.environment.collapse = {"turn": 1, "marked": [Vector2i(999, 999)]}
	var result := ItemSimulationSnapshot.capture(session.state, [])
	check(result.code != ItemSnapshotResult.Code.OK and result.reason == "environment/collapse_cell", "production capture rejects non-floor/out-of-bounds marker")
	session.close()
