extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_current_roundtrip()
	_test_schema_nine_restore()
	_test_rejections()
	print("ELEMENTAL SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_current_roundtrip() -> void:
	var session := BattleTacticalSession.new()
	var source_unit: UnitState = session.units[0]
	var stats := StatsBag.from_snapshot_dict(source_unit.stats.to_snapshot_dict())
	var current := UnitState.create(Faction.Type.PLAYER, Vector2i(1, 1), stats, "current")
	var dto := current.to_snapshot_dict()
	_check(dto["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION and dto["guard_stance"] == false and not dto.has("elemental") and UnitState.validate_snapshot_dict(dto), "current unit preserves absent elemental capability")
	var decoded := UnitState.from_snapshot_dict(dto)
	_check(decoded != null and decoded.to_snapshot_dict() == dto, "current unit roundtrip")
	for old_version: int in range(1, UnitState.SNAPSHOT_SCHEMA_VERSION):
		var old_snapshot := dto.duplicate(true)
		old_snapshot["schema_version"] = old_version
		_check(not UnitState.validate_snapshot_dict(old_snapshot), "old unit schema rejected " + str(old_version))
	session.close()

func _test_schema_nine_restore() -> void:
	for state_kind: String in ["empty", "burning", "burning_cell", "wet", "frozen", "bleeding"]:
		var session := _new_session()
		if session == null:
			_check(false, state_kind + " fixture initialized")
			continue
		var target: UnitState = session.units[1]
		var elemental := ElementalState.new()
		match state_kind:
			"burning", "burning_cell":
				elemental.burning_stacks = 2
				elemental.burning_ticks = 4
				elemental.burning_source = _attack_source(session.units[0].id) if state_kind == "burning" else _cell_source(987654321)
			"wet": elemental.wet_turns = 3
			"frozen":
				elemental.frozen_turns = 2
				elemental.freeze_immune = true
		target.elemental = elemental
		var bleed := BleedingState.new()
		bleed.stacked = true
		if state_kind == "bleeding":
			bleed.stacks = 3
			bleed.ticks_left = BleedingState.STACK_DURATION
			bleed.source = _attack_source(session.units[0].id)
			bleed.hit_id = "snapshot-hit"
		target.bleeding = bleed
		var target_dto: Dictionary = target.to_snapshot_dict()
		_check(target_dto.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and target_dto.has("guard_stance") and target_dto.has("elemental") and target_dto["elemental"]["acid_ticks"] == 0 and target_dto["bleeding"]["schema_version"] == 4, state_kind + " creates schema nine with current status codecs")
		var item_snapshot := ItemSimulationSnapshot.capture(session.state, [])
		_check(item_snapshot.code == ItemSnapshotResult.Code.OK, state_kind + " item capture")
		if item_snapshot.code == ItemSnapshotResult.Code.OK:
			var dto: Dictionary = item_snapshot.snapshot.to_dict()
			var restored := item_snapshot.snapshot.instantiate(_definitions(session))
			_check(restored.code == ItemSnapshotResult.Code.OK, state_kind + " item restore")
			if restored.state != null:
				var restored_unit: UnitState = restored.state.get_board().get_unit_by_id(target.id)
				_check(restored_unit != target and restored_unit.elemental != target.elemental and restored_unit.bleeding != target.bleeding, state_kind + " runtime instances detached")
				_check(restored_unit.elemental.to_dict() == target.elemental.to_dict() and restored_unit.bleeding.to_dict() == target.bleeding.to_dict(), state_kind + " status data preserved")
				restored_unit.elemental.burning_source["origin_cell"] = Vector2i(88, 88)
				restored_unit.bleeding.source["origin_cell"] = Vector2i(77, 77)
				_check(target.elemental.burning_source.get("origin_cell", Vector2i.ZERO) != Vector2i(88, 88) and target.bleeding.source.get("origin_cell", Vector2i.ZERO) != Vector2i(77, 77), state_kind + " restored DTO dictionaries detached")
				_check(dto["board_snapshot"]["board"]["units"][1]["elemental"] == target.elemental.to_dict(), state_kind + " snapshot DTO detached from restored runtime")
			var standalone := SimulationSnapshot.from_dict(dto["board_snapshot"])
			_check(standalone.code == BoardSnapshotResult.Code.OK, state_kind + " board snapshot accepts schema nine")
		session.close()

func _test_rejections() -> void:
	var session := _new_session()
	if session == null: return
	var target: UnitState = session.units[1]
	target.elemental = ElementalState.new()
	target.bleeding = BleedingState.new()
	target.bleeding.stacked = true
	var dto: Dictionary = target.to_snapshot_dict()
	_check(UnitState.validate_snapshot_dict(dto), "empty stacked bleeding and elemental are valid schema nine")
	var bad: Dictionary = dto.duplicate(true)
	bad["elemental"]["unknown"] = 1
	_check(not UnitState.validate_snapshot_dict(bad), "schema nine rejects elemental extra key")
	bad = dto.duplicate(true)
	bad["elemental"].erase("acid_ticks")
	_check(not UnitState.validate_snapshot_dict(bad), "current elemental schema requires zero acid field")
	bad = dto.duplicate(true)
	bad["elemental"]["schema_version"] = 2
	bad["elemental"]["acid_ticks"] = 1
	_check(not UnitState.validate_snapshot_dict(bad), "old elemental codec is refused")
	bad = dto.duplicate(true)
	bad["schema_version"] = 7
	_check(not UnitState.validate_snapshot_dict(bad), "schema nine rejects old version")
	bad = dto.duplicate(true)
	bad.erase("elemental")
	bad["schema_version"] = 8
	_check(not UnitState.validate_snapshot_dict(bad), "old Unit version rejects current stacked bleeding")
	bad = dto.duplicate(true)
	bad["schema_version"] = UnitState.SNAPSHOT_SCHEMA_VERSION + 1
	_check(not UnitState.validate_snapshot_dict(bad), "future Unit version rejected")
	bad = dto.duplicate(true)
	bad["bleeding"]["schema_version"] = 3
	_check(not UnitState.validate_snapshot_dict(bad), "schema nine requires bleeding schema four")
	var active := dto.duplicate(true)
	active["elemental"]["burning_stacks"] = 1
	active["elemental"]["burning_ticks"] = 1
	active["elemental"]["burning_source"] = {"kind": &"unknown"}
	_check(not UnitState.validate_snapshot_dict(active), "malformed new status source rejected by unit codec")
	var missing_source := _new_session()
	if missing_source != null:
		var missing_target: UnitState = missing_source.units[1]
		missing_target.elemental = ElementalState.new()
		missing_target.elemental.burning_stacks = 1
		missing_target.elemental.burning_ticks = 1
		missing_target.elemental.burning_source = _attack_source(999999)
		missing_target.bleeding = BleedingState.new()
		missing_target.bleeding.stacked = true
		var capture := ItemSimulationSnapshot.capture(missing_source.state, [])
		_check(capture.code != ItemSnapshotResult.Code.OK, "capture rejects attack source absent from unit map")
		missing_source.close()
	# Источники валидны по отдельности, но schema9 запрещает одновременное
	# горение и активное кровотечение: горение всегда снимает кровотечение.
	target.elemental.burning_stacks = 1
	target.elemental.burning_ticks = 1
	target.elemental.burning_source = _attack_source(session.units[0].id)
	target.bleeding.stacks = 1
	target.bleeding.ticks_left = BleedingState.STACK_DURATION
	target.bleeding.source = _attack_source(session.units[0].id)
	target.bleeding.hit_id = "cross-status-hit"
	_check(ElementalState.valid(target.elemental.to_dict()) and BleedingState.valid(target.bleeding.to_dict()), "cross-state fixture has valid individual sources and DTOs")
	var live_dto: Dictionary = target.to_snapshot_dict()
	_check(live_dto.is_empty(), "live schema nine refuses active burning plus bleeding")
	var cross_dto: Dictionary = dto.duplicate(true)
	cross_dto["elemental"] = target.elemental.to_dict()
	cross_dto["bleeding"] = target.bleeding.to_dict()
	_check(cross_dto.get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION and not UnitState.validate_snapshot_dict(cross_dto), "schema nine validation rejects active burning plus bleeding")
	_check(UnitState.from_snapshot_dict(cross_dto) == null, "schema nine restore rejects active burning plus bleeding")
	var cross_capture := ItemSimulationSnapshot.capture(session.state, [])
	_check(cross_capture.code != ItemSnapshotResult.Code.OK, "live snapshot capture rejects active burning plus bleeding")
	session.close()

func _new_session() -> BattleArmorSession:
	var session := BattleArmorSession.new()
	for unit: UnitState in session.units:
		if unit.action_resources == null and unit.enable_action_resources() != &"":
			session.close()
			return null
		var bleeding := BleedingState.new()
		bleeding.stacked = true
		unit.bleeding = bleeding
		unit.elemental = ElementalState.new()
	return session

func _definitions(session: BattleArmorSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _attack_source(unit_id: int) -> Dictionary:
	return {"kind": &"attack", "source_instance_id": 0, "origin_cell": Vector2i(1, 2), "instigator_unit_id": unit_id, "credit_unit_id": unit_id}

func _cell_source(cell_id: int) -> Dictionary:
	return {"kind": &"cell", "source_instance_id": cell_id, "origin_cell": Vector2i(91, 92), "instigator_unit_id": 0, "credit_unit_id": 0}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)
