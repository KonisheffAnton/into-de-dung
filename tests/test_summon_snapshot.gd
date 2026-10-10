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
	_test_current_codec()
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
	check(captured.code == ItemSnapshotResult.Code.OK, "current schema capture")
	check(captured.snapshot.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and captured.snapshot.to_dict()["scope"] == ItemSimulationSnapshot.SCOPE, "current schema and scope")
	check(captured.snapshot.to_dict()["summons"] == [{"unit_id": 2, "owner_unit_id": 1, "pending": true}], "metadata")
	var descriptor: Dictionary = captured.snapshot.to_dict()["owners"][0]["definitions"][0]
	for field: String in ["use_heal_amount", "max_charges", "use_summon", "armor_resistances", "summon_definition"]:
		check(descriptor.has(field), "current descriptor always includes " + field)
	check(descriptor["use_heal_amount"] == 0.0 and descriptor["max_charges"] == 2 and descriptor["use_summon"] == true and not descriptor["summon_definition"].is_empty(), "summon descriptor preserves active use values")
	var restored := captured.snapshot.instantiate(_catalogue(definition))
	check(restored.code == ItemSnapshotResult.Code.OK, "current schema restore")
	check(restored.state.get_summons() == state.get_summons(), "metadata roundtrip")
	check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), "current canonical roundtrip charges")
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
	no_resources["board_snapshot"]["board"]["units"][1].erase("action_resources")
	check(ItemSimulationSnapshot.from_dict(no_resources).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "pending needs enabled ledger")
	state._summons[0]["extra"] = 1
	check(ItemSimulationSnapshot.capture(state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "live extra metadata not erased")
	state._summons[0].erase("extra")
	var substituted := _catalogue(definition)
	(substituted[definition.id] as ItemDef).use_summon = false
	check(ItemSimulationSnapshot.from_dict(data).snapshot.instantiate(substituted).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "catalogue summon mismatch")
	var old_scopes: Array[String] = ["board_items_two_effects_v1", "board_items_usable_v2", "board_items_summons_v3", "board_items_armor_v4", "board_items_environment_v5", "board_items_summon_definitions_v6", "board_items_abilities_v7", "board_items_artifacts_v8", "board_items_team_summons_v9", "board_items_mage_deck_v10"]
	for old_version: int in range(1, ItemSimulationSnapshot.SCHEMA_VERSION):
		var old_import := data.duplicate(true)
		old_import["schema_version"] = old_version
		old_import["scope"] = old_scopes[old_version - 1]
		check(ItemSimulationSnapshot.from_dict(old_import).code != ItemSnapshotResult.Code.OK, "old schema import rejected " + str(old_version))
	var missing_capability := data.duplicate(true)
	missing_capability["owners"][0]["definitions"][0].erase("use_summon")
	check(ItemSimulationSnapshot.from_dict(missing_capability).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "current descriptor requires summon flag")
	var malformed_capability := data.duplicate(true)
	malformed_capability["owners"][0]["definitions"][0]["use_summon"] = "false"
	check(ItemSimulationSnapshot.from_dict(malformed_capability).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "current descriptor rejects wrong summon flag type")
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

static func current_fixture(with_healing: bool) -> ItemSimulationState:
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
	definition.id = &"current_codec"
	if with_healing:
		definition.use_heal_amount = 12.0
		definition.max_charges = 2
	var item := owner.create_item(definition)
	inventory.add_item(item)
	return ItemSimulationState.new(board, [owner], [inventory], [equipment])

func _test_current_codec() -> void:
	for with_healing: bool in [false, true]:
		var state := current_fixture(with_healing)
		var snapshot := ItemSimulationSnapshot.capture(state, []).snapshot
		check(snapshot.to_dict()["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and snapshot.to_dict()["scope"] == ItemSimulationSnapshot.SCOPE, "current fixture uses schema eleven")
		var descriptor: Dictionary = snapshot.to_dict()["owners"][0]["definitions"][0]
		for field: String in ["use_heal_amount", "max_charges", "use_summon", "armor_resistances", "summon_definition"]:
			check(descriptor.has(field), "current fixture includes " + field)
		var definition: ItemDef = state.get_owner(1)._definitions[&"current_codec"]
		var restored := snapshot.instantiate({definition.id: definition.duplicate(true)})
		check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.canonical_bytes() == snapshot.canonical_bytes(), "current canonical roundtrip")
		AttackForecast._close(restored.state)
		var bad := snapshot.to_dict()
		bad["owners"][0]["definitions"][0].erase("use_summon")
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "current descriptor requires summon flag")
		var unknown := snapshot.to_dict()
		unknown["schema_version"] = 99
		check(ItemSimulationSnapshot.from_dict(unknown).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unknown version stays unsupported")
		AttackForecast._close(state)
