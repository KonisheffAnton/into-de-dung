extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := {"kind": &"attack", "source_instance_id": 0, "origin_cell": Vector2i(1, 2), "instigator_unit_id": 1, "credit_unit_id": 1}
	var state := BleedingState.new()
	state.immune = true
	state.ticks_left = 2
	state.source = source
	state.hit_id = "hit-1"
	var raw := state.to_dict()
	_check(BleedingState.valid(raw), "bleeding roundtrip shape")
	var copy := BleedingState.from_dict(raw)
	_check(copy != null and copy.immune and copy.ticks_left == 2 and copy.hit_id == "hit-1", "bleeding values")
	copy.source["origin_cell"] = Vector2i(9, 9)
	_check(state.source["origin_cell"] == Vector2i(1, 2), "source deep isolation")
	var expired := raw.duplicate(true)
	expired["ticks_left"] = 0
	expired["source"] = {}
	expired["hit_id"] = ""
	_check(BleedingState.valid(expired), "expired shape")
	var invalid := raw.duplicate(true)
	invalid["source"]["kind"] = &"fire"
	_check(not BleedingState.valid(invalid), "invalid source rejected")
	_check(not BleedingState.valid(raw.merged({"extra": true})), "extra field rejected")
	var bad_ticks := raw.duplicate(true)
	bad_ticks["ticks_left"] = 3
	_check(not BleedingState.valid(bad_ticks), "ticks limit rejected")
	var bad_hit := raw.duplicate(true)
	bad_hit["hit_id"] = ""
	_check(not BleedingState.valid(bad_hit), "empty active hit rejected")
	var bad_credit := raw.duplicate(true)
	bad_credit["source"]["credit_unit_id"] = 2
	_check(not BleedingState.valid(bad_credit), "cross source ids rejected")
	for field: String in raw:
		var missing_field := raw.duplicate(true)
		missing_field.erase(field)
		_check(not BleedingState.valid(missing_field), "required state field " + field)
	for version: int in [0,2]:
		var unknown := raw.duplicate(true)
		unknown["schema_version"] = version
		_check(not BleedingState.valid(unknown), "unknown bleeding version")

	var session := BattleArmorSession.new()
	var unit: UnitState = session.units[0]
	var attacker: UnitState = session.units[1]
	if unit.action_resources == null:
		unit.enable_action_resources()
	if attacker.action_resources == null:
		attacker.enable_action_resources()
	unit.bleeding = state
	state.source["instigator_unit_id"] = attacker.id
	state.source["credit_unit_id"] = attacker.id
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	if captured.code != ItemSnapshotResult.Code.OK:
		print("capture reason: ", captured.reason)
		print("unit snapshot valid: ", UnitState.validate_snapshot_dict(unit.to_snapshot_dict()), " schema=", unit.to_snapshot_dict().get("schema_version", -1))
		print("caps resources=", unit.action_resources != null, " guard=", unit.guard_stance, " armor=", unit.armor != null, " bleed=", unit.bleeding != null)
		print("armor valid=", ArmorState.valid(unit.armor.to_dict()), "bleed valid=", BleedingState.valid(unit.bleeding.to_dict()))
		print("resources valid=", unit.action_resources.validate(unit.id), "stats=", unit.stats.get_script() == StatsBag, "vitals=", unit.vitals.get_script() == Vitals, "same=", unit.vitals._stats == unit.stats)
		print("stats snapshot=", not unit.stats.to_snapshot_dict().is_empty(), "vitals=", unit.vitals.to_dict())
	_check(captured.code == ItemSnapshotResult.Code.OK, "item snapshot capture")
	if captured.snapshot != null:
		var dto := captured.snapshot.to_dict()
		_check(dto["schema_version"] == 4, "item envelope remains v4")
		var unit_dto: Dictionary = dto["board_snapshot"]["board"]["units"][0]
		_check(unit_dto["schema_version"] == 5 and unit_dto["bleeding"]["hit_id"] == "hit-1", "unit v5 retained")
		var legacy_unit: Dictionary = unit_dto.duplicate(true)
		legacy_unit["schema_version"] = 4
		legacy_unit.erase("bleeding")
		_check(UnitState.validate_snapshot_dict(legacy_unit), "unit v4 remains valid")
		var missing := unit_dto.duplicate(true)
		missing.erase("bleeding")
		_check(not UnitState.validate_snapshot_dict(missing), "unit v5 missing bleeding rejected")
		_check(not unit.guard_stance and UnitState.validate_snapshot_dict(unit_dto), "inactive stance supported")
		for field: String in ["armor","action_resources","guard_stance"]:
			var missing_field := unit_dto.duplicate(true)
			missing_field.erase(field)
			_check(not UnitState.validate_snapshot_dict(missing_field), "required Unit5 field " + field)
		var unknown_unit := unit_dto.duplicate(true)
		unknown_unit["schema_version"] = 6
		_check(not UnitState.validate_snapshot_dict(unknown_unit), "unknown unit version")
		_check(not UnitState.validate_snapshot_dict(unit_dto.merged({"extra":1})), "unit extra rejected")
		var lost_source := dto.duplicate(true)
		lost_source["board_snapshot"]["board"]["units"][0]["bleeding"]["source"]["instigator_unit_id"] = 987654
		lost_source["board_snapshot"]["board"]["units"][0]["bleeding"]["source"]["credit_unit_id"] = 987654
		_check(ItemSimulationSnapshot.from_dict(lost_source).code != ItemSnapshotResult.Code.OK, "missing source unit rejected")
		var old_envelope := dto.duplicate(true)
		old_envelope["schema_version"] = 3
		old_envelope["scope"] = ItemSimulationSnapshot.SCOPE_V3
		_check(ItemSimulationSnapshot.from_dict(old_envelope).code != ItemSnapshotResult.Code.OK, "old envelope cannot hide status")
		var altered := dto.duplicate(true)
		altered["board_snapshot"]["board"]["units"][0]["bleeding"]["source"]["origin_cell"] = Vector2i(-2,9)
		var altered_capture := ItemSimulationSnapshot.from_dict(altered)
		_check(altered_capture.code == ItemSnapshotResult.Code.OK and altered_capture.snapshot.canonical_bytes() != captured.snapshot.canonical_bytes(), "source coordinates affect canonical bytes")
		var restored := captured.snapshot.instantiate(_definitions(session))
		_check(restored.code == ItemSnapshotResult.Code.OK, "item snapshot restore")
		if restored.state != null:
			var restored_unit: UnitState = restored.state.get_board().get_unit_by_id(unit.id)
			_check(restored_unit.bleeding != null and restored_unit.bleeding.source["instigator_unit_id"] == attacker.id, "restored source")
			_check(restored_unit.bleeding != unit.bleeding, "runtime isolation")
			_check(restored_unit.bleeding.to_dict() == unit.bleeding.to_dict(), "restore preserves duration immunity and source exactly")
			restored_unit.bleeding.source["origin_cell"] = Vector2i(7,7)
			_check(unit.bleeding.source["origin_cell"] != Vector2i(7,7), "restored source detached")
			AttackForecast._close(restored.state)
		attacker.vitals.set_hp(0.0)
		_check(ItemSimulationSnapshot.capture(session.state,[]).code == ItemSnapshotResult.Code.OK, "dead source remains valid")
	session.close()
	print("BLEEDING SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _definitions(session: BattleArmorSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(label)
