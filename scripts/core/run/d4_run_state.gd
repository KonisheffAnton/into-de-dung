extends RefCounted
class_name D4RunState

const HUB: String = "hub"
const BATTLE: String = "battle"
const LOOT: String = "loot"
const COURIER: String = "courier"
const RESULT: String = "result"
const MAX_ITEMS: int = 1024
const MAX_COUNTER: int = 2147483647
const MAX_RNG: int = 2147483647

var phase: String = HUB
var encounter: int = 0
var run_number: int = 0
var next_item_id: int = 1
var materials: int = 180
var loss_rng_state: int = 123456789
var items: Array[Dictionary] = []
var heroes: Array[Dictionary] = []
var lost_ids: Array[int] = []
var lost_items: Array[Dictionary] = []
var last_result: String = ""
var loot_ids: Array[int] = []

func _init() -> void:
	heroes = [
		{"id": 1, "name": "Астра", "hp": 32},
		{"id": 2, "name": "Бор", "hp": 32},
		{"id": 3, "name": "Рей", "hp": 32},
	]
	for hero_id: int in range(1, 4):
		_add_item("sword", "equipped", hero_id, 0, 0)
		_add_item("coat", "equipped", hero_id, 1, 60)
		_add_item("bracer", "equipped", hero_id, 2, 40)
	for kind: String in ["sword", "coat", "bracer", "piercing_sword"]:
		_add_item(kind, "warehouse", 0, -1, D4Catalog.definition(kind).armor_max)

func _add_item(kind: String, place: String, hero: int, item_slot: int, armor: int) -> void:
	items.append({"id": next_item_id, "kind": kind, "armor": armor, "place": place, "hero": hero, "slot": item_slot})
	next_item_id += 1

func item(item_id: int) -> Dictionary:
	for record: Dictionary in items:
		if record["id"] == item_id:
			return record.duplicate(true)
	return {}

func equip(item_id: int, hero_id: int) -> bool:
	if phase != HUB or not _valid_hero_id(hero_id): return false
	var chosen_index: int = _find_item_index(item_id)
	if chosen_index < 0: return false
	var chosen: Dictionary = items[chosen_index]
	if chosen["place"] != "warehouse" and chosen["place"] != "backpack": return false
	var target_slot: int = D4Catalog.slot(chosen["kind"])
	if target_slot < 0: return false
	var old_index: int = _equipped_index(hero_id, target_slot)
	if old_index >= 0:
		items[old_index]["place"] = "warehouse"
		items[old_index]["hero"] = 0
		items[old_index]["slot"] = -1
	items[chosen_index]["place"] = "equipped"
	items[chosen_index]["hero"] = hero_id
	items[chosen_index]["slot"] = target_slot
	return true

func unequip(item_id: int) -> bool:
	if phase != HUB: return false
	var index: int = _find_item_index(item_id)
	if index < 0 or items[index]["place"] != "equipped": return false
	items[index]["place"] = "warehouse"
	items[index]["hero"] = 0
	items[index]["slot"] = -1
	return true

func start_run() -> bool:
	if phase != HUB or run_number >= MAX_COUNTER: return false
	phase = BATTLE
	encounter = 1
	run_number += 1
	last_result = ""
	lost_ids.clear()
	lost_items.clear()
	loot_ids.clear()
	for hero: Dictionary in heroes:
		hero["hp"] = 32
	return true

func apply_battle_result(victory: bool, hero_hp: Dictionary, armor_by_id: Dictionary) -> bool:
	if phase != BATTLE or not _validate_battle_result(victory, hero_hp, armor_by_id): return false
	if victory and (items.size() > MAX_ITEMS - 3 or next_item_id > MAX_COUNTER - 3): return false
	for hero: Dictionary in heroes:
		hero["hp"] = hero_hp[hero["id"]]
	for record: Dictionary in items:
		if record["place"] == "equipped":
			record["armor"] = armor_by_id[record["id"]]
	if victory:
		_add_item("keen_sword", "loot", 0, -1, 0)
		_add_item("charm", "loot", 0, -1, 0)
		_add_item("coat", "loot", 0, -1, 60)
		loot_ids = [next_item_id - 3, next_item_id - 2, next_item_id - 1]
		phase = LOOT
		return true
	var candidates: Array[int] = []
	for record: Dictionary in items:
		if record["place"] != "warehouse": candidates.append(record["id"])
	candidates.sort()
	var to_lose: int = (candidates.size() + 1) / 2
	var selected: Array[int] = []
	for _draw: int in range(to_lose):
		var pick: int = _next_rng() % candidates.size()
		selected.append(candidates[pick])
		candidates.remove_at(pick)
	selected.sort()
	lost_ids = selected.duplicate()
	lost_items.clear()
	for lost_id: int in lost_ids:
		var lost_index: int = _find_item_index(lost_id)
		if lost_index >= 0: lost_items.append(items[lost_index].duplicate(true))
	for index: int in range(items.size() - 1, -1, -1):
		if lost_ids.has(items[index]["id"]): items.remove_at(index)
	for record: Dictionary in items:
		if record["place"] != "warehouse":
			record["place"] = "warehouse"
			record["hero"] = 0
			record["slot"] = -1
	phase = RESULT
	last_result = "defeat"
	return true

func collect_loot(hero_id: int) -> bool:
	if phase != LOOT or not _valid_hero_id(hero_id) or _hero_hp(hero_id) <= 0: return false
	if encounter == 2 and materials > MAX_COUNTER - 60: return false
	for record: Dictionary in items:
		if record["place"] == "loot":
			record["place"] = "backpack"
			record["hero"] = hero_id
			record["slot"] = -1
	loot_ids.clear()
	if encounter == 1:
		phase = COURIER
	else:
		_finish_victory()
	return true

func send_item(item_id: int) -> bool:
	if phase != COURIER: return false
	var index: int = _find_item_index(item_id)
	if index < 0 or (items[index]["place"] != "equipped" and items[index]["place"] != "backpack"): return false
	items[index]["place"] = "warehouse"
	items[index]["hero"] = 0
	items[index]["slot"] = -1
	return true

func continue_run() -> bool:
	if phase != COURIER or encounter != 1: return false
	phase = BATTLE
	encounter = 2
	return true

func return_to_hub() -> bool:
	if phase != RESULT: return false
	phase = HUB
	encounter = 0
	for hero: Dictionary in heroes: hero["hp"] = 32
	return true

func repair(item_id: int, budget: int) -> int:
	if phase != HUB or budget <= 0: return 0
	var index: int = _find_item_index(item_id)
	if index < 0 or items[index]["place"] != "equipped": return 0
	var maximum: int = D4Catalog.definition(items[index]["kind"]).armor_max
	var missing: int = maximum - items[index]["armor"]
	var spent: int = mini(mini(missing, budget), materials)
	if spent <= 0: return 0
	items[index]["armor"] += spent
	materials -= spent
	return spent

func to_dict() -> Dictionary:
	return {"schema_version": 1, "phase": phase, "encounter": encounter, "run_number": run_number, "next_item_id": next_item_id, "materials": materials, "loss_rng_state": loss_rng_state, "items": items.duplicate(true), "heroes": heroes.duplicate(true), "lost_ids": lost_ids.duplicate(), "lost_items": lost_items.duplicate(true), "last_result": last_result, "loot_ids": loot_ids.duplicate()}

static func from_dict(raw: Variant) -> D4RunState:
	if typeof(raw) != TYPE_DICTIONARY or not _keys_exact(raw, ["schema_version", "phase", "encounter", "run_number", "next_item_id", "materials", "loss_rng_state", "items", "heroes", "lost_ids", "lost_items", "last_result", "loot_ids"]): return null
	if typeof(raw["schema_version"]) != TYPE_INT or raw["schema_version"] != 1 or typeof(raw["phase"]) != TYPE_STRING or typeof(raw["encounter"]) != TYPE_INT or typeof(raw["run_number"]) != TYPE_INT or typeof(raw["next_item_id"]) != TYPE_INT or typeof(raw["materials"]) != TYPE_INT or typeof(raw["loss_rng_state"]) != TYPE_INT or typeof(raw["items"]) != TYPE_ARRAY or typeof(raw["heroes"]) != TYPE_ARRAY or typeof(raw["lost_ids"]) != TYPE_ARRAY or typeof(raw["lost_items"]) != TYPE_ARRAY or typeof(raw["last_result"]) != TYPE_STRING or typeof(raw["loot_ids"]) != TYPE_ARRAY: return null
	var result := D4RunState.new()
	result.phase = raw["phase"]
	result.encounter = raw["encounter"]
	result.run_number = raw["run_number"]
	result.next_item_id = raw["next_item_id"]
	result.materials = raw["materials"]
	result.loss_rng_state = raw["loss_rng_state"]
	result.items.clear(); result.heroes.clear(); result.lost_ids.clear(); result.lost_items.clear(); result.loot_ids.clear()
	if not result._validate_snapshot(raw["items"], raw["heroes"], raw["lost_ids"], raw["lost_items"], raw["loot_ids"], raw["last_result"]): return null
	for value: Variant in raw["items"]: result.items.append(value.duplicate(true))
	for value: Variant in raw["heroes"]: result.heroes.append(value.duplicate(true))
	for value: Variant in raw["lost_ids"]: result.lost_ids.append(value)
	for value: Variant in raw["lost_items"]: result.lost_items.append(value.duplicate(true))
	for value: Variant in raw["loot_ids"]: result.loot_ids.append(value)
	result.last_result = raw["last_result"]
	return result

func _finish_victory() -> void:
	for record: Dictionary in items:
		if record["place"] != "warehouse":
			record["place"] = "warehouse"; record["hero"] = 0; record["slot"] = -1
	phase = RESULT
	last_result = "victory"
	materials += 60

func _validate_battle_result(victory: bool, hero_hp: Dictionary, armor_by_id: Dictionary) -> bool:
	if typeof(victory) != TYPE_BOOL or typeof(hero_hp) != TYPE_DICTIONARY or typeof(armor_by_id) != TYPE_DICTIONARY: return false
	if hero_hp.size() != 3 or armor_by_id.size() != _equipped_count(): return false
	var living: int = 0
	for key: Variant in hero_hp:
		if typeof(key) != TYPE_INT: return false
	for hero: Dictionary in heroes:
		var id: int = hero["id"]
		if not hero_hp.has(id) or typeof(hero_hp[id]) != TYPE_INT or hero_hp[id] < 0 or hero_hp[id] > 32: return false
		if hero.hp == 0 and hero_hp[id] > 0: return false
		if hero_hp[id] > 0: living += 1
	for record: Dictionary in items:
		if record["place"] != "equipped": continue
		var id: int = record["id"]
		if not armor_by_id.has(id) or typeof(armor_by_id[id]) != TYPE_INT: return false
		var maximum: int = D4Catalog.definition(record["kind"]).armor_max
		if armor_by_id[id] < 0 or armor_by_id[id] > maximum: return false
	for key: Variant in armor_by_id.keys():
		if typeof(key) != TYPE_INT or _find_item_index(key) < 0 or items[_find_item_index(key)]["place"] != "equipped": return false
	return (victory and living > 0) or (not victory and living == 0)

func _validate_snapshot(raw_items: Array, raw_heroes: Array, raw_lost: Array, raw_lost_items: Array, raw_loot: Array, result_name: String) -> bool:
	if phase not in [HUB, BATTLE, LOOT, COURIER, RESULT] or encounter not in [0, 1, 2] or run_number < 0 or run_number > MAX_COUNTER or next_item_id < 1 or next_item_id > MAX_COUNTER or materials < 0 or materials > MAX_COUNTER or loss_rng_state < 1 or loss_rng_state > MAX_RNG or raw_items.size() > MAX_ITEMS or raw_lost.size() > MAX_ITEMS: return false
	if (phase == HUB and encounter != 0) or (phase != HUB and encounter == 0) or (phase == COURIER and encounter != 1): return false
	if result_name not in ["", "victory", "defeat"] or (phase == RESULT and result_name == "") or (phase != RESULT and phase != HUB and result_name != ""): return false
	if encounter > 0 and run_number < 1: return false
	if result_name == "victory" and phase == RESULT and encounter != 2: return false
	if result_name != "defeat" and not raw_lost.is_empty(): return false
	if raw_heroes.size() != 3: return false
	var hero_ids: Array[int] = []
	var living: int = 0
	for hero: Variant in raw_heroes:
		if typeof(hero) != TYPE_DICTIONARY or not _keys_exact(hero, ["id", "name", "hp"]) or typeof(hero["id"]) != TYPE_INT or typeof(hero["name"]) != TYPE_STRING or typeof(hero["hp"]) != TYPE_INT or not _valid_hero_id(hero["id"]) or hero["hp"] < 0 or hero["hp"] > 32 or hero_ids.has(hero["id"]): return false
		if hero["name"] != ["", "Астра", "Бор", "Рей"][hero["id"]]: return false
		if hero["id"] != hero_ids.size() + 1: return false
		if phase == HUB and hero.hp != 32: return false
		if hero.hp > 0: living += 1
		hero_ids.append(hero["id"])
	if phase in [BATTLE, LOOT, COURIER] and living == 0: return false
	if phase == RESULT and ((result_name == "victory" and living == 0) or (result_name == "defeat" and living != 0)): return false
	var ids: Array[int] = []; var slots: Array[String] = []; var loot_check: Array[int] = []
	for record: Variant in raw_items:
		if typeof(record) != TYPE_DICTIONARY or not _keys_exact(record, ["id", "kind", "armor", "place", "hero", "slot"]): return false
		if typeof(record["id"]) != TYPE_INT or typeof(record["kind"]) != TYPE_STRING or typeof(record["armor"]) != TYPE_INT or typeof(record["place"]) != TYPE_STRING or typeof(record["hero"]) != TYPE_INT or typeof(record["slot"]) != TYPE_INT: return false
		var definition: ItemDef = D4Catalog.definition(record["kind"])
		if definition == null or record["id"] < 1 or record["id"] >= next_item_id or ids.has(record["id"]) or record["armor"] < 0 or record["armor"] > definition.armor_max: return false
		if record["place"] not in ["warehouse", "equipped", "backpack", "loot"]: return false
		if phase == RESULT and record.place != "warehouse": return false
		if phase == HUB and record.place not in ["warehouse", "equipped"]: return false
		if record["place"] in ["warehouse", "loot"] and (record["hero"] != 0 or record["slot"] != -1): return false
		if record["place"] == "backpack" and (not _valid_hero_id(record["hero"]) or record["slot"] != -1): return false
		if record["place"] == "equipped" and (not _valid_hero_id(record["hero"]) or record["slot"] != D4Catalog.slot(record["kind"])): return false
		if record["place"] == "equipped":
			var slot_key: String = str(record["hero"]) + ":" + str(record["slot"])
			if slots.has(slot_key): return false
			slots.append(slot_key)
		if record["place"] == "loot": loot_check.append(record["id"])
		ids.append(record["id"])
	var lost_check: Array[int] = []
	for value: Variant in raw_lost:
		if typeof(value) != TYPE_INT or value < 1 or value >= next_item_id or lost_check.has(value) or ids.has(value): return false
		lost_check.append(value)
	if raw_lost.size() != raw_lost_items.size(): return false
	for lost_index: int in range(raw_lost_items.size()):
		var lost_record: Variant = raw_lost_items[lost_index]
		if typeof(lost_record) != TYPE_DICTIONARY or not _keys_exact(lost_record, ["id", "kind", "armor", "place", "hero", "slot"]): return false
		if typeof(lost_record["id"]) != TYPE_INT or typeof(lost_record["kind"]) != TYPE_STRING or typeof(lost_record["armor"]) != TYPE_INT or typeof(lost_record["place"]) != TYPE_STRING or typeof(lost_record["hero"]) != TYPE_INT or typeof(lost_record["slot"]) != TYPE_INT: return false
		var lost_definition: ItemDef = D4Catalog.definition(lost_record["kind"])
		if lost_definition == null or lost_record["id"] != raw_lost[lost_index] or lost_record["id"] < 1 or lost_record["id"] >= next_item_id or ids.has(lost_record["id"]) or lost_record["armor"] < 0 or lost_record["armor"] > lost_definition.armor_max: return false
		if lost_record["place"] not in ["equipped", "backpack"] or not _valid_hero_id(lost_record.hero): return false
		if lost_record.place == "equipped" and lost_record.slot != D4Catalog.slot(lost_record.kind): return false
		if lost_record.place == "backpack" and lost_record.slot != -1: return false
	var seen_loot: Array[int] = []
	for value: Variant in raw_loot:
		if typeof(value) != TYPE_INT or not loot_check.has(value) or seen_loot.has(value): return false
		seen_loot.append(value)
	if raw_loot.size() != loot_check.size() or phase != LOOT and raw_loot.size() != 0: return false
	if phase == LOOT and raw_loot.size() != 3: return false
	return true

func _next_rng() -> int:
	loss_rng_state = int((loss_rng_state * 1103515245 + 12345) % 2147483648)
	if loss_rng_state == 0: loss_rng_state = 1
	return loss_rng_state

func _find_item_index(item_id: int) -> int:
	for index: int in range(items.size()):
		if items[index]["id"] == item_id: return index
	return -1

func _equipped_index(hero_id: int, item_slot: int) -> int:
	for index: int in range(items.size()):
		if items[index]["place"] == "equipped" and items[index]["hero"] == hero_id and items[index]["slot"] == item_slot: return index
	return -1

func _equipped_count() -> int:
	var count: int = 0
	for record: Dictionary in items:
		if record["place"] == "equipped": count += 1
	return count

func _hero_hp(hero_id: int) -> int:
	for hero: Dictionary in heroes:
		if hero["id"] == hero_id: return hero["hp"]
	return 0

func _valid_hero_id(hero_id: int) -> bool:
	return hero_id >= 1 and hero_id <= 3

static func _keys_exact(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size(): return false
	for key: String in expected:
		if not value.has(key): return false
	return true
