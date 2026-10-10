extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_full_graph()
	var armor := ArmorState.new()
	armor.next_grant_id = 2
	armor.natural = {"physical": 120, "fire": -25}
	armor.perks = [{"id": "perk", "type": "physical", "branch": "both", "bonus": 1500}]
	armor.grants = [{"grant_id": 1, "source": "spell", "remaining": 4, "expires": "battle", "battle_id": 1}]
	var restored := ArmorState.from_dict(armor.to_dict())
	_check(restored != null and restored.natural["fire"] == -25 and restored.grants[0]["remaining"] == 4, "armor state roundtrip")
	_check(not ArmorState.valid({"schema_version": 2}), "unknown armor version")
	_check(UnitState.from_dict({"armor": {}}) == null, "legacy unit rejects armor")
	var legacy := {"schema_version": 1, "id": 1, "faction": 0, "cell_x": 0, "cell_y": 0, "height": 0, "debug_name": "u", "ai_profile_path": "", "move_points_left": 0.0, "has_attacked": false, "stats": {}, "vitals": {}}
	_check(not UnitState.validate_snapshot_dict(legacy.merged({"schema_version": UnitState.SNAPSHOT_SCHEMA_VERSION})), "current schema missing fields")
	var bad_hp := legacy.duplicate(true)
	bad_hp["schema_version"] = UnitState.SNAPSHOT_SCHEMA_VERSION
	bad_hp["action_resources"] = {}
	bad_hp["guard_stance"] = false
	bad_hp["armor"] = armor.to_dict()
	bad_hp["vitals"] = {"hp": 1.5, "balance": 0.0, "is_alive": true}
	_check(not UnitState.validate_snapshot_dict(bad_hp), "current fractional hp rejected")
	print("ARMOR SNAPSHOT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_full_graph() -> void:
	var session := BattleArmorSession.new()
	var unit := session.units[0]
	unit.guard_stance = true
	unit.armor.next_grant_id = 2
	unit.armor.grants = [{"grant_id": 1, "source": "spell", "remaining": 7, "expires": "battle", "battle_id": 1}]
	var depleted_id := 0
	for item: ItemInstance in session.state.get_owner(unit.id)._items.values():
		if item.get_definition().armor_max > 0:
			item.armor_remaining = 0
			depleted_id = item._item_id
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	_check(captured.code == ItemSnapshotResult.Code.OK, "full schema eleven capture: " + captured.reason)
	if captured.snapshot == null:
		session.close()
		return
	var raw := captured.snapshot.to_dict()
	_check(raw["schema_version"] == ItemSimulationSnapshot.SCHEMA_VERSION and raw["scope"] == ItemSimulationSnapshot.SCOPE and raw["board_snapshot"]["board"]["units"][0]["schema_version"] == UnitState.SNAPSHOT_SCHEMA_VERSION, "current envelope and unit schema")
	var saved_item: Dictionary = raw["owners"][0]["items"][0]
	for field: String in ["armor_remaining", "armor_origin_owner", "armor_origin_item", "charges_left"]:
		_check(saved_item.has(field), "current item retains " + field)
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := captured.snapshot.instantiate(definitions)
	_check(restored.code == ItemSnapshotResult.Code.OK, "full instantiate: " + restored.reason)
	if restored.state != null:
		var copy := ItemSimulationSnapshot.capture(restored.state, [])
		_check(copy.code == ItemSnapshotResult.Code.OK and copy.snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), "full canonical roundtrip")
		var restored_unit := restored.state.get_board().get_unit_by_id(unit.id)
		var restored_item: ItemInstance = restored.state.get_owner(unit.id)._items[depleted_id]
		_check(restored_item.armor_remaining == 0, "depleted remains depleted")
		_check(restored_unit.guard_stance and restored_unit.armor.grants[0]["remaining"] == 7, "stance and grants retained")
		restored_item.armor_remaining = 1
		restored_unit.armor.grants[0]["remaining"] = 3
		restored_item.get_definition().armor_resistances["fire"] = 123
		_check((session.state.get_owner(unit.id)._items[depleted_id] as ItemInstance).armor_remaining == 0 and unit.armor.grants[0]["remaining"] == 7, "runtime isolation")
		_check((session.state.get_owner(unit.id)._items[depleted_id] as ItemInstance).get_definition().armor_resistances["fire"] == 0, "definition isolation")
		for inventory: InventoryState in restored.state.get_inventories(): inventory.close()
		for equipment: EquipmentState in restored.state.get_equipment_facades(): equipment.close()
		for owner: ItemOwnerState in restored.state.get_owners(): owner.close()
		restored.state.get_board().resize(0, 0)
	for field: String in ["armor", "action_resources", "guard_stance"]:
		var invalid := raw.duplicate(true)
		invalid["board_snapshot"]["board"]["units"][0].erase(field)
		_check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK, "missing unit " + field)
	for field: String in ["armor_remaining", "armor_origin_owner", "armor_origin_item", "charges_left"]:
		var invalid := raw.duplicate(true)
		invalid["owners"][0]["items"][0].erase(field)
		_check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK, "missing item " + field)
	for version: int in [0, 2, 99]:
		var invalid := raw.duplicate(true)
		invalid["board_snapshot"]["board"]["units"][0]["armor"]["schema_version"] = version
		_check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK, "unknown armor schema%d" % version)
	var duplicate := raw.duplicate(true)
	duplicate["owners"][1]["items"][0]["armor_origin_owner"] = duplicate["owners"][0]["items"][0]["armor_origin_owner"]
	duplicate["owners"][1]["items"][0]["armor_origin_item"] = duplicate["owners"][0]["items"][0]["armor_origin_item"]
	_check(ItemSimulationSnapshot.from_dict(duplicate).code != ItemSnapshotResult.Code.OK, "global duplicate creation identity")
	var bad_amount := raw.duplicate(true)
	bad_amount["owners"][0]["items"][0]["armor_remaining"] = 999
	_check(ItemSimulationSnapshot.from_dict(bad_amount).code != ItemSnapshotResult.Code.OK, "remaining exceeds item max")
	# Изменённый каталог нельзя подключить даже к уже проверенному DTO.
	definitions[&"armor_coat"].armor_max += 1
	_check(captured.snapshot.instantiate(definitions).code != ItemSnapshotResult.Code.OK, "definition content mismatch")
	session.close()
	var hybrid_session := BattleTacticalSession.new()
	var hybrid_capture := ItemSimulationSnapshot.capture(hybrid_session.state, [])
	_check(hybrid_capture.code == ItemSnapshotResult.Code.OK, "current base envelope for armor hybrid")
	if hybrid_capture.snapshot != null:
		var hybrid := hybrid_capture.snapshot.to_dict()
		var hybrid_unit: UnitState = hybrid_session.units[0]
		if hybrid_unit.action_resources == null: hybrid_unit.enable_action_resources()
		hybrid_unit.armor = ArmorState.new()
		hybrid["board_snapshot"]["board"]["units"][0] = hybrid_unit.to_snapshot_dict()
		var hybrid_decoded := ItemSimulationSnapshot.from_dict(hybrid)
		_check(hybrid_decoded.code == ItemSnapshotResult.Code.OK, "current envelope accepts valid armor unit hybrid")
		var hybrid_catalogue: Dictionary = {}
		for owner: ItemOwnerState in hybrid_session.state.get_owners():
			for id: StringName in owner._definitions: hybrid_catalogue[id] = (owner._definitions[id] as ItemDef).duplicate(true)
		if hybrid_decoded.snapshot != null and not hybrid_catalogue.is_empty():
			for id: StringName in hybrid_catalogue:
				hybrid_catalogue[id].armor_resistances["fire"] = 1
				break
			_check(hybrid_decoded.snapshot.instantiate(hybrid_catalogue).code != ItemSnapshotResult.Code.OK, "current hybrid rejects changed catalogue")
	hybrid_session.close()

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ARMOR SNAPSHOT: " + label)
