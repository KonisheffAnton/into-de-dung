extends SceneTree

class UnsupportedSnapshotItemDef:
	extends ItemDef

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
	_test_returned_snapshot_branch_isolation()
	_test_live_mutations_and_rejection()
	_test_capture_precedence()
	print("LIVE SNAPSHOT CAPTURE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_session_roundtrip(session: BattleDemoSession, label: String) -> void:
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, label + " capture succeeds")
	if captured.snapshot != null:
		var raw := captured.snapshot.to_dict()
		var decoded := ItemSimulationSnapshot.from_dict(raw)
		check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_bytes() == captured.snapshot.canonical_bytes() and decoded.snapshot.to_dict() == captured.snapshot.to_dict(), label + " from_dict full canonical parity")
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

func _test_returned_snapshot_branch_isolation() -> void:
	var status_session := BattleCoreReactionsSession.new()
	var status_unit := status_session.units[0]
	status_unit.bleeding.stacks = 0
	status_unit.bleeding.ticks_left = 0
	status_unit.bleeding.source = {}
	status_unit.bleeding.hit_id = ""
	var source := {"kind": &"cell", "source_instance_id": 1, "origin_cell": status_unit.cell, "instigator_unit_id": 0, "credit_unit_id": 0}
	status_unit.elemental.burning_stacks = 1
	status_unit.elemental.burning_ticks = 2
	status_unit.elemental.burning_source = source
	var first := ItemSimulationSnapshot.capture(status_session.state, [])
	check(first.code == ItemSnapshotResult.Code.OK and first.snapshot != null, "nested status/source fixture captures")
	if first.snapshot == null:
		status_session.close()
		return
	var first_bytes := first.snapshot.canonical_bytes()
	var original := first.snapshot.to_dict()
	var revision := status_session.context.get_revision()
	status_unit.elemental.burning_source["origin_cell"] = status_unit.cell + Vector2i(1, 0)
	status_unit.armor.natural["physical"] += 1
	var strength: Stat = status_unit.stats._stats[StatTypes.StatType.STRENGTH]
	strength.add_modifier(StatModifier.new(&"capture_isolation", StatModifier.Operation.ADD_FLAT, 1.0))
	check(status_session.context.get_revision() == revision, "nested status, armor, and modifier changes skip action revision")
	var fresh := ItemSimulationSnapshot.capture(status_session.state, [])
	check(fresh.code == ItemSnapshotResult.Code.OK and fresh.snapshot != null and fresh.snapshot.canonical_bytes() != first_bytes, "fresh capture observes nested board and status mutations")
	check(first.snapshot.to_dict() == original, "first capture owns nested status source, armor, and modifier data")
	status_session.close()

	var owner_session := BattleTacticalSession.new()
	var summon_definitions: Array[SummonDefinition] = []
	for owner: ItemOwnerState in owner_session.state._owners:
		var candidate: ItemDef = owner._definitions.get(&"tactical_summoning_seal")
		if candidate != null and candidate.use_summon and candidate.summon_definition != null:
			summon_definitions.append(candidate.summon_definition)
	check(not summon_definitions.is_empty(), "fixture has nested summon definitions")
	# Одинаковый ID определения обязан иметь одинаковое содержимое у всех владельцев.
	for definition: SummonDefinition in summon_definitions:
		definition.hp_max += 1.0
	var owner_first := ItemSimulationSnapshot.capture(owner_session.state, [])
	check(owner_first.code == ItemSnapshotResult.Code.OK and owner_first.snapshot != null and not summon_definitions.is_empty(), "owner definition fixture captures code=%d reason=%s" % [owner_first.code, owner_first.reason])
	if owner_first.snapshot != null and not summon_definitions.is_empty():
		var owner_original := owner_first.snapshot.to_dict()
		var owner_bytes := owner_first.snapshot.canonical_bytes()
		var owner_revision := owner_session.context.get_revision()
		for definition: SummonDefinition in summon_definitions:
			definition.hp_max += 1.0
		var owner_fresh := ItemSimulationSnapshot.capture(owner_session.state, [])
		check(owner_session.context.get_revision() == owner_revision, "nested definition change skips action revision")
		check(owner_fresh.code == ItemSnapshotResult.Code.OK and owner_fresh.snapshot != null and owner_fresh.snapshot.canonical_bytes() != owner_bytes, "fresh capture observes nested owner definition mutation")
		check(owner_first.snapshot.to_dict() == owner_original, "first capture owns nested owner definition data")
	owner_session.close()

func _test_capture_precedence() -> void:
	var session := BattleTacticalSession.new()
	var unit := session.units[0]
	var owner := session.state.get_owner(unit.id)
	owner._guard = true
	var original_width := session.board.width
	session.board.width = -1
	var busy := ItemSimulationSnapshot.capture(session.state, [])
	check(busy.code == ItemSnapshotResult.Code.SNAPSHOT_BUSY and busy.reason == "owner/%d/guard" % unit.id, "busy owner precedes malformed board")
	owner._guard = false
	session.board.width = original_width
	var definition := UnsupportedSnapshotItemDef.new()
	definition.id = &"unsupported_capture_precedence"
	owner._definitions[definition.id] = definition
	var stat: Stat = unit.stats._stats[StatTypes.StatType.STRENGTH]
	stat.base_value = NAN
	var invalid_board := ItemSimulationSnapshot.capture(session.state, [])
	check(invalid_board.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and invalid_board.reason == "board/unit/stat/base/finite", "invalid finite board precedes unsupported owner definition")
	session.close()

func _check_fresh_capture(state: ItemSimulationState, prior: PackedByteArray, label: String) -> PackedByteArray:
	var fresh := ItemSimulationSnapshot.capture(state, [])
	check(fresh.code == ItemSnapshotResult.Code.OK and fresh.snapshot != null, label + " remains valid")
	if fresh.snapshot == null: return prior
	var bytes := fresh.snapshot.canonical_bytes()
	check(bytes != prior, label + " changes canonical snapshot")
	return bytes
