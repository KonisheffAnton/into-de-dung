extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	_check("initial inventory", _initial_inventory())
	_check("catalog fresh definitions", _catalog())
	_check("moves and atomic hub operations", _moves())
	_check("victory loot courier", _victory_flow())
	_check("defeat deterministic and roundtrip", _defeat_roundtrip())
	_check("repair cost", _repair())
	_check("courier save and later defeat", _courier_persistence())
	_check("rng restore and repeated outcome", _rng_restore())
	_check("battle payload atomicity", _battle_atomicity())
	_check("snapshot rejection matrix", _snapshot_rejections())
	_check("full second victory roundtrip", _second_victory_roundtrip())
	_check("odd carried pool", _defeat_pool(3, 2))
	_check("even carried pool", _defeat_pool(4, 2))
	_check("zero carried pool", _defeat_pool(0, 0))
	_check("single carried pool", _defeat_pool(1, 1))
	_check("repair budget and material caps", _repair_caps())
	_check("strict snapshot scalar and hero order", _strict_snapshot_scalars())
	_check("loot duplicate and dead hero rejection", _loot_and_dead_rejection())
	_check("item and counter overflow", _item_overflow())
	_check("failed mutations preserve state", _failed_mutations())
	print("D4 RUN RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(_name: String, result: bool) -> void:
	if result: _passed += 1
	else:
		_failed += 1
		print("D4 FAIL: " + _name)

func _initial_inventory() -> bool:
	var state := D4RunState.new()
	if state.heroes.size() != 3 or state.items.size() != 12 or state.next_item_id != 13: return false
	var equipped: int = 0
	var warehouse: int = 0
	for record: Dictionary in state.items:
		if record["place"] == "equipped": equipped += 1
		if record["place"] == "warehouse": warehouse += 1
	return equipped == 9 and warehouse == 3 and state.to_dict()["schema_version"] == 1

func _catalog() -> bool:
	var first := D4Catalog.definition("sword")
	var second := D4Catalog.definition("sword")
	return first != null and second != null and first != second and first.id == &"d4_sword" and first.effects.size() == 1 and D4Catalog.slot("coat") == 1 and D4Catalog.definition("unknown") == null

func _moves() -> bool:
	var state := D4RunState.new()
	var id: int = state.items[9]["id"]
	if not state.equip(id, 1): return false
	if state.item(id)["place"] != "equipped" or not state.unequip(id): return false
	var snapshot: Dictionary = state.to_dict()
	if state.start_run() and state.equip(id, 1): return false
	return state.to_dict()["phase"] == D4RunState.BATTLE and snapshot["phase"] == "hub"

func _victory_flow() -> bool:
	var state := D4RunState.new()
	if not state.start_run(): return false
	var hp := {1: 32, 2: 20, 3: 0}
	var armor: Dictionary = {}
	for record: Dictionary in state.items:
		if record["place"] == "equipped": armor[record["id"]] = record["armor"]
	if not state.apply_battle_result(true, hp, armor) or state.phase != D4RunState.LOOT or state.loot_ids.size() != 3: return false
	var loot_item_id: int = state.loot_ids[0]
	if not state.collect_loot(1) or state.phase != D4RunState.COURIER: return false
	if not state.send_item(loot_item_id): return false
	return state.continue_run() and state.encounter == 2

func _defeat_roundtrip() -> bool:
	var state := D4RunState.new()
	state.start_run()
	var armor: Dictionary = {}
	for record: Dictionary in state.items:
		if record["place"] == "equipped": armor[record["id"]] = record["armor"]
	if not state.apply_battle_result(false, {1: 0, 2: 0, 3: 0}, armor): return false
	var saved: Dictionary = state.to_dict()
	var restored := D4RunState.from_dict(saved)
	if restored == null or restored.lost_ids.size() == 0 or restored.lost_items.size() != restored.lost_ids.size(): return false
	restored.lost_ids.clear()
	return state.lost_ids.size() > 0 and D4RunState.from_dict({"schema_version": 1}) == null

func _repair() -> bool:
	var state := D4RunState.new()
	var coat_id: int = -1
	for record: Dictionary in state.items:
		if record["place"] == "equipped" and record["kind"] == "coat": coat_id = record["id"]; break
	var before: int = state.materials
	if not state.unequip(coat_id): return false
	if state.repair(coat_id, 10) != 0: return false
	if not state.equip(coat_id, 1): return false
	var equipped: Dictionary = state.item(coat_id)
	state.items[state._find_item_index(coat_id)]["armor"] = 50
	var spent: int = state.repair(coat_id, 20)
	return spent == 10 and state.materials == before - 10 and equipped["armor"] == 60

func _courier_persistence() -> bool:
	var state := D4RunState.new()
	state.start_run()
	var armor := _armor(state)
	state.apply_battle_result(true, {1: 32, 2: 32, 3: 32}, armor)
	var loot_id: int = state.loot_ids[0]
	state.collect_loot(1)
	if not state.send_item(loot_id): return false
	var restored := D4RunState.from_dict(state.to_dict())
	if restored == null or restored.phase != D4RunState.COURIER or restored.item(loot_id)["place"] != "warehouse": return false
	if not restored.continue_run() or not restored.apply_battle_result(false, {1: 0, 2: 0, 3: 0}, _armor(restored)): return false
	return restored.lost_ids.has(loot_id) == false and restored.item(loot_id).get("place", "") == "warehouse"

func _rng_restore() -> bool:
	var first := D4RunState.new(); first.start_run()
	var saved := first.to_dict()
	var second := D4RunState.from_dict(saved)
	if second == null: return false
	var hp := {1: 0, 2: 0, 3: 0}
	first.apply_battle_result(false, hp, _armor(first))
	second.apply_battle_result(false, hp, _armor(second))
	if first.to_dict() != second.to_dict(): return false
	var before := first.to_dict()
	return not first.apply_battle_result(false, hp, {}) and first.to_dict() == before

func _battle_atomicity() -> bool:
	var state := D4RunState.new(); state.start_run()
	var before := state.to_dict()
	var bad_armor := _armor(state); bad_armor[999] = 0
	if state.apply_battle_result(true, {1: 32, 2: 32, 3: 32}, bad_armor): return false
	return state.to_dict() == before

func _snapshot_rejections() -> bool:
	var state := D4RunState.new(); var raw := state.to_dict()
	var extra := raw.duplicate(true); extra["extra"] = 1
	var wrong := raw.duplicate(true); wrong["materials"] = 1.0
	var duplicate := raw.duplicate(true); duplicate["items"] = [raw["items"][0], raw["items"][0]]
	var bad_counter := raw.duplicate(true); bad_counter["next_item_id"] = 1
	var bad_phase := raw.duplicate(true); bad_phase["phase"] = D4RunState.LOOT
	var bad_loot := raw.duplicate(true); bad_loot["loot_ids"] = [1]
	return D4RunState.from_dict(extra) == null and D4RunState.from_dict(wrong) == null and D4RunState.from_dict(duplicate) == null and D4RunState.from_dict(bad_counter) == null and D4RunState.from_dict(bad_phase) == null and D4RunState.from_dict(bad_loot) == null

func _second_victory_roundtrip() -> bool:
	var state := D4RunState.new(); state.start_run()
	if not state.apply_battle_result(true, {1: 32, 2: 32, 3: 32}, _armor(state)): return false
	if not state.collect_loot(1) or not state.continue_run(): return false
	if not state.apply_battle_result(true, {1: 20, 2: 0, 3: 0}, _armor(state)): return false
	if state.phase != D4RunState.LOOT or state.encounter != 2: return false
	var restored := D4RunState.from_dict(state.to_dict())
	if restored == null or restored.phase != D4RunState.LOOT or restored.loot_ids.size() != 3: return false
	if not restored.collect_loot(1) or restored.phase != D4RunState.RESULT or restored.last_result != "victory": return false
	if not restored.return_to_hub() or restored.phase != D4RunState.HUB: return false
	for hero: Dictionary in restored.heroes:
		if hero["hp"] != 32: return false
	return true

func _defeat_pool(pool_size: int, expected_lost: int) -> bool:
	var state := D4RunState.new()
	var kept: int = 0
	for record: Dictionary in state.items.duplicate(true):
		if record["place"] == "equipped":
			if kept < pool_size: kept += 1
			else: state.unequip(record["id"])
	state.start_run()
	if not state.apply_battle_result(false, {1: 0, 2: 0, 3: 0}, _armor(state)): return false
	return state.lost_ids.size() == expected_lost and state.lost_items.size() == expected_lost

func _repair_caps() -> bool:
	var state := D4RunState.new()
	var coat_id: int = -1
	for record: Dictionary in state.items:
		if record["place"] == "equipped" and record["kind"] == "coat": coat_id = record["id"]; break
	var index: int = state._find_item_index(coat_id)
	state.items[index]["armor"] = 0
	var before: int = state.materials
	if state.repair(coat_id, 10000) != 60 or state.materials != before - 60: return false
	if state.repair(coat_id, 1) != 0: return false
	state.items[index]["armor"] = 0
	state.materials = 5
	return state.repair(coat_id, 100) == 5 and state.materials == 0

func _strict_snapshot_scalars() -> bool:
	var raw: Dictionary = D4RunState.new().to_dict()
	var float_schema := raw.duplicate(true); float_schema["schema_version"] = 1.0
	var reordered := raw.duplicate(true); reordered["heroes"] = [raw["heroes"][1], raw["heroes"][0], raw["heroes"][2]]
	return D4RunState.from_dict(float_schema) == null and D4RunState.from_dict(reordered) == null

func _loot_and_dead_rejection() -> bool:
	var state := D4RunState.new(); state.start_run()
	if not state.apply_battle_result(true, {1: 32, 2: 32, 3: 0}, _armor(state)): return false
	var duplicate := state.to_dict(); duplicate["loot_ids"] = [state.loot_ids[0], state.loot_ids[0], state.loot_ids[1]]
	if D4RunState.from_dict(duplicate) != null: return false
	return not state.collect_loot(3)

func _item_overflow() -> bool:
	var state := D4RunState.new(); var raw := state.to_dict()
	var records: Array = raw["items"].duplicate(true)
	var source: Dictionary = records[0].duplicate(true)
	for offset: int in range(12, 1024):
		var copy: Dictionary = source.duplicate(true); copy["id"] = offset + 1; copy["place"] = "warehouse"; copy["hero"] = 0; copy["slot"] = -1; records.append(copy)
	raw["items"] = records; raw["next_item_id"] = 1037
	var loaded := D4RunState.from_dict(raw)
	if loaded == null or loaded.items.size() != 1024: return false
	loaded.start_run()
	return not loaded.apply_battle_result(true, {1: 32, 2: 32, 3: 32}, _armor(loaded))

func _failed_mutations() -> bool:
	var state := D4RunState.new(); var before := state.to_dict()
	if state.equip(999, 1) or state.unequip(999) or state.repair(999, 10): return false
	return state.to_dict() == before

func _armor(state: D4RunState) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in state.items:
		if record["place"] == "equipped": result[record["id"]] = record["armor"]
	return result
