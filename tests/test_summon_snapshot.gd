extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SUMMON SNAPSHOT: " + label)

func _unit(id: int, cell: Vector2i) -> UnitState:
	var stats := StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 16.0, StatTypes.StatType.BALANCE_MAX: 5.0, StatTypes.StatType.MOVE_RANGE: 4.0, StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0, StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0, StatTypes.StatType.WEAPON_DAMAGE: 2.0, StatTypes.StatType.ATTACK_RANGE: 1.0})
	var unit := UnitState.new()
	unit.id = id
	unit.faction = Faction.Type.PLAYER
	unit.cell = cell
	unit.stats = stats
	unit.vitals = Vitals.new(stats, true)
	unit.enable_action_resources()
	unit.action_resources._set_for_refill(0, 0)
	return unit

func _fixture() -> Dictionary:
	var board := BattleBoard.new(4, 1)
	var owner_unit := _unit(1, Vector2i(0, 0))
	var helper := _unit(2, Vector2i(1, 0))
	check(board.add_unit(owner_unit), "add owner")
	var owner := ItemOwnerState.new(owner_unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var definition := ItemDef.new()
	definition.id = &"tactical_summoning_seal"
	definition.use_summon = true
	definition.max_charges = 2
	var item := owner.create_item(definition)
	check(item != null and inventory.add_item(item), "register summon item")
	var state := ItemSimulationState.new(board, [owner], [inventory], [equipment])
	state.register_summon_owner(helper, owner_unit.id)
	check(board.add_unit(helper), "add helper")
	return {"board": board, "state": state, "definition": definition}

func _catalogue(definition: ItemDef) -> Dictionary:
	return {definition.id: definition.duplicate(true)}

func _run() -> void:
	_test_legacy_bytes()
	_test_roundtrip_and_isolation()
	_test_malformed_and_catalogue()
	_test_dead_helper_limit()
	print("SUMMON SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_roundtrip_and_isolation() -> void:
	var fixture := _fixture()
	var state: ItemSimulationState = fixture["state"]
	var definition: ItemDef = fixture["definition"]
	var captured := ItemSimulationSnapshot.capture(state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "v3 capture")
	check(captured.snapshot.to_dict()["scope"] == ItemSimulationSnapshot.SCOPE_V3, "v3 scope")
	check(captured.snapshot.to_dict()["summons"] == [{"unit_id": 2, "owner_unit_id": 1, "pending": true}], "metadata")
	var restored := captured.snapshot.instantiate(_catalogue(definition))
	check(restored.code == ItemSnapshotResult.Code.OK, "v3 restore")
	check(restored.state.get_summons() == state.get_summons(), "metadata roundtrip")
	check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), "v3 canonical roundtrip charges")
	var clone_definition: ItemDef = restored.state.get_owner(1)._definitions[definition.id]
	clone_definition.max_charges = 7
	check(definition.max_charges == 2, "catalogue definition isolation")
	var copied_metadata := state.get_summons()
	copied_metadata[0]["pending"] = false
	check(state.is_summon_pending(2), "metadata deep copy")
	AttackForecast._close(restored.state)
	AttackForecast._close(state)

func _test_malformed_and_catalogue() -> void:
	var fixture := _fixture()
	var state: ItemSimulationState = fixture["state"]
	var definition: ItemDef = fixture["definition"]
	var data := ItemSimulationSnapshot.capture(state, []).snapshot.to_dict()
	for value: Variant in [true, 0, -1, "2"]:
		var bad := data.duplicate(true)
		bad["summons"][0]["unit_id"] = value
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "bad summon id " + str(value))
	for field: String in ["pending", "owner_unit_id"]:
		var bad := data.duplicate(true)
		bad["summons"][0].erase(field)
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "missing summon field " + field)
	var duplicate := data.duplicate(true)
	duplicate["summons"].append(duplicate["summons"][0].duplicate(true))
	check(ItemSimulationSnapshot.from_dict(duplicate).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "duplicate summon")
	var wrong_faction := data.duplicate(true)
	wrong_faction["board_snapshot"]["board"]["units"][1]["faction"] = int(Faction.Type.ENEMY)
	check(ItemSimulationSnapshot.from_dict(wrong_faction).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "faction mismatch")
	var pending_resources := data.duplicate(true)
	pending_resources["board_snapshot"]["board"]["units"][1]["action_resources"]["main_left"] = 1
	check(ItemSimulationSnapshot.from_dict(pending_resources).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "pending resources")
	for field in ["unit_id", "owner_unit_id", "pending"]:
		for value: Variant in [1.5, "x", null]:
			var bad := data.duplicate(true)
			bad["summons"][0][field] = value
			check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "metadata strict type " + field)
	for owner_id in [2, 999]:
		var bad := data.duplicate(true)
		bad["summons"][0]["owner_unit_id"] = owner_id
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "self/missing owner rejected")
	var nested := data.duplicate(true)
	nested["summons"].append({"unit_id": 1, "owner_unit_id": 2, "pending": true})
	check(ItemSimulationSnapshot.from_dict(nested).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "summoned owner cycle rejected")
	var no_resources := data.duplicate(true)
	no_resources["board_snapshot"]["board"]["units"][1]["schema_version"] = 1
	no_resources["board_snapshot"]["board"]["units"][1].erase("action_resources")
	check(ItemSimulationSnapshot.from_dict(no_resources).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "pending needs enabled ledger")
	state._summons[0]["extra"] = 1
	check(ItemSimulationSnapshot.capture(state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "live extra metadata not erased")
	state._summons[0].erase("extra")
	var substituted := _catalogue(definition)
	(substituted[definition.id] as ItemDef).use_summon = false
	check(ItemSimulationSnapshot.from_dict(data).snapshot.instantiate(substituted).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "catalogue summon mismatch")
	var legacy_v2 := data.duplicate(true)
	legacy_v2["schema_version"] = 2
	legacy_v2["scope"] = ItemSimulationSnapshot.SCOPE_V2
	legacy_v2.erase("summons")
	legacy_v2["owners"][0]["definitions"][0].erase("use_summon")
	legacy_v2["owners"][0]["definitions"][0]["use_heal_amount"] = 1.0
	var v2_catalogue := _catalogue(definition)
	(v2_catalogue[definition.id] as ItemDef).use_summon = false
	(v2_catalogue[definition.id] as ItemDef).use_heal_amount = 1.0
	check(ItemSimulationSnapshot.from_dict(legacy_v2).code == ItemSnapshotResult.Code.OK, "legacy v2 shape")
	var legacy_v1 := legacy_v2.duplicate(true)
	legacy_v1["schema_version"] = 1
	legacy_v1["scope"] = ItemSimulationSnapshot.SCOPE
	legacy_v1["owners"][0]["definitions"][0].erase("use_heal_amount")
	legacy_v1["owners"][0]["definitions"][0].erase("max_charges")
	legacy_v1["owners"][0]["items"][0].erase("charges_left")
	check(ItemSimulationSnapshot.from_dict(legacy_v1).code == ItemSnapshotResult.Code.OK, "legacy v1 shape")
	var legacy_bad := legacy_v1.duplicate(true)
	legacy_bad["owners"][0]["definitions"][0]["use_summon"] = true
	check(ItemSimulationSnapshot.from_dict(legacy_bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "legacy rejects summon field")
	var extra_metadata := data.duplicate(true)
	extra_metadata["summons"][0]["extra"] = 1
	check(ItemSimulationSnapshot.from_dict(extra_metadata).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "metadata extra field")
	AttackForecast._close(state)

func _test_dead_helper_limit() -> void:
	var fixture := _fixture()
	var state: ItemSimulationState = fixture["state"]
	var helper := state.get_board().get_unit_by_id(2)
	helper.vitals.apply_damage(100.0)
	var extra := _unit(3, Vector2i(1, 0))
	state.register_summon_owner(extra, 1)
	check(state.summon_owner_id(3) == 1, "dead helper frees owner limit")
	check(state.active_summon(1) == null, "dead helper inactive")
	AttackForecast._close(state)

static func legacy_fixture(version: int) -> ItemSimulationState:
	var board := BattleBoard.new(2, 1)
	var unit := UnitState.new()
	unit.id = 1
	unit.faction = Faction.Type.PLAYER
	unit.cell = Vector2i.ZERO
	unit.stats = StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 16.0, StatTypes.StatType.BALANCE_MAX: 5.0, StatTypes.StatType.MOVE_RANGE: 4.0, StatTypes.StatType.MAIN_ACTIONS_MAX: 1.0, StatTypes.StatType.BONUS_ACTIONS_MAX: 1.0, StatTypes.StatType.WEAPON_DAMAGE: 2.0, StatTypes.StatType.ATTACK_RANGE: 1.0})
	unit.vitals = Vitals.new(unit.stats, true)
	unit.enable_action_resources()
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var definition := ItemDef.new()
	definition.id = &"legacy_compat"
	if version == 2:
		definition.use_heal_amount = 12.0
		definition.max_charges = 2
	var item := owner.create_item(definition)
	inventory.add_item(item)
	return ItemSimulationState.new(board, [owner], [inventory], [equipment])

func _test_legacy_bytes() -> void:
	# Отпечатки получены тем же fixture из чистого git archive исходного 458365a0.
	var hashes := ["2c5ba9cc86049b95f688add0d691bbfebe54d7b8ac39bb908f14cb5a4fb45d03", "21da179bb41140f76d14ee0b3b72972d74cfa222786560aef541c6873b281739"]
	for version in [1, 2]:
		var state := legacy_fixture(version)
		var snapshot := ItemSimulationSnapshot.capture(state, []).snapshot
		check(snapshot.to_dict()["schema_version"] == version and snapshot.fingerprint() == hashes[version - 1], "baseline v%d canonical bytes unchanged" % version)
		var definition: ItemDef = state.get_owner(1)._definitions[&"legacy_compat"]
		var restored := snapshot.instantiate({definition.id: definition.duplicate(true)})
		check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snapshot.canonical_bytes(), "legacy canonical roundtrip")
		AttackForecast._close(restored.state)
		var bad := snapshot.to_dict()
		bad["owners"][0]["definitions"][0]["use_summon"] = false
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "legacy forbids even false summon flag")
		var unknown := snapshot.to_dict()
		unknown["schema_version"] = 99
		check(ItemSimulationSnapshot.from_dict(unknown).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unknown legacy-shaped version stays unsupported")
		AttackForecast._close(state)
