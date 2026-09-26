extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL LIVE SNAPSHOT CAPTURE: " + label)

func _run() -> void:
	_check_session_roundtrip(BattleTacticalSession.new(), "tactical")
	_check_session_roundtrip(BattleEnvironmentSession.new(), "environment")
	_check_session_roundtrip(BattleCoreReactionsSession.new(), "core reactions")
	_test_live_mutations_and_rejection()
	print("LIVE SNAPSHOT CAPTURE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_session_roundtrip(session: BattleDemoSession, label: String) -> void:
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, label + " capture succeeds")
	if captured.snapshot != null:
		var raw := captured.snapshot.to_dict()
		var decoded := ItemSimulationSnapshot.from_dict(raw)
		check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), label + " from_dict canonical parity")
		var unchanged := captured.snapshot.to_dict()
		var escaped := captured.snapshot.to_dict()
		escaped["owners"][0]["next_item_id"] += 1
		check(captured.snapshot.to_dict() == unchanged, label + " to_dict does not alias snapshot")
	session.close()

func _test_live_mutations_and_rejection() -> void:
	var session := BattleTacticalSession.new()
	var first := ItemSimulationSnapshot.capture(session.state, [])
	check(first.code == ItemSnapshotResult.Code.OK and first.snapshot != null, "mutation fixture captures")
	if first.snapshot == null:
		session.close()
		return
	var original := first.snapshot.to_dict()
	var last_bytes := first.snapshot.canonical_bytes()
	var unit := session.units[0]
	var revision := session.context.get_revision()
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, unit.stats.get_base_value(StatTypes.StatType.STRENGTH) + 1.0)
	check(session.context.get_revision() == revision, "direct stat change skips action revision")
	last_bytes = _check_fresh_capture(session.state, last_bytes, "stat change is captured")
	unit.vitals.set_hp(unit.vitals.get_hp() - 1.0)
	check(session.context.get_revision() == revision, "direct HP change skips action revision")
	last_bytes = _check_fresh_capture(session.state, last_bytes, "HP change is captured")
	var destination := Vector2i(0, 3)
	check(session.board.move_unit(unit, destination), "fixture moves unit through board API")
	check(session.context.get_revision() == revision, "direct occupancy change skips action revision")
	last_bytes = _check_fresh_capture(session.state, last_bytes, "occupancy change is captured")
	var owner := session.state.get_owner(unit.id)
	owner._next_item_id += 1
	check(session.context.get_revision() == revision, "direct owner change skips action revision")
	last_bytes = _check_fresh_capture(session.state, last_bytes, "owner counter change is captured")
	var item: ItemInstance
	for candidate: ItemInstance in owner._items.values():
		if candidate._charges_left > 0:
			item = candidate
			break
	check(item != null, "fixture has a charge-bearing owner item")
	if item != null:
		item._charges_left -= 1
		check(session.context.get_revision() == revision, "direct item change skips action revision")
		last_bytes = _check_fresh_capture(session.state, last_bytes, "item charge change is captured")
	check(first.snapshot.to_dict() == original, "capture is isolated from later live mutations")
	var malformed := original.duplicate(true)
	malformed["board_snapshot"]["board"]["width"] = -1
	check(ItemSimulationSnapshot.from_dict(malformed).code != ItemSnapshotResult.Code.OK, "from_dict rejects malformed board")
	var corrupt := ItemSimulationSnapshot.new()
	corrupt._data = original.duplicate(true)
	corrupt._data["board_snapshot"]["board"]["width"] = -1
	check(corrupt.instantiate({}).code != ItemSnapshotResult.Code.OK, "instantiate rejects corrupted snapshot data")
	session.close()

func _check_fresh_capture(state: ItemSimulationState, prior: PackedByteArray, label: String) -> PackedByteArray:
	var fresh := ItemSimulationSnapshot.capture(state, [])
	check(fresh.code == ItemSnapshotResult.Code.OK and fresh.snapshot != null, label + " remains valid")
	if fresh.snapshot == null: return prior
	var bytes := fresh.snapshot.canonical_bytes()
	check(bytes != prior, label + " changes canonical snapshot")
	return bytes
