class_name BattleArtifactState
extends RefCounted

var heroes: Array[int] = []
var mages: Array[int] = []
var attacks: Dictionary = {}
var equipped: Array[Dictionary] = []
var formation_serials: Array[int] = [0, 0]

func to_dict() -> Dictionary:
	if not _runtime_shape_valid():
		return {}
	var hero_copy: Array[int] = heroes.duplicate()
	hero_copy.sort()
	var mage_copy: Array[int] = mages.duplicate()
	mage_copy.sort()
	var attack_rows: Array[Dictionary] = []
	for unit_id: int in hero_copy:
		if not attacks.has(unit_id):
			continue
		attack_rows.append({"unit_id": unit_id, "attack_id": String(attacks[unit_id])})
	var equipment_copy: Array[Dictionary] = []
	for row: Dictionary in equipped:
		equipment_copy.append(row.duplicate(true))
	equipment_copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["unit_id"] != b["unit_id"]: return a["unit_id"] < b["unit_id"]
		if a["slot"] != b["slot"]: return a["slot"] < b["slot"]
		return a["id"] < b["id"])
	return {"schema": 1, "heroes": hero_copy, "mages": mage_copy, "attacks": attack_rows, "equipped": equipment_copy, "formation_serials": formation_serials.duplicate()}

static func from_dict(data: Variant) -> BattleArtifactState:
	if not valid(data):
		return null
	var result := BattleArtifactState.new()
	result.heroes.assign(data["heroes"])
	result.mages.assign(data["mages"])
	for attack: Dictionary in data["attacks"]:
		result.attacks[attack["unit_id"]] = StringName(attack["attack_id"])
	for row: Dictionary in data["equipped"]:
		result.equipped.append(row.duplicate(true))
	result.formation_serials.assign(data["formation_serials"])
	return result

static func valid(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not _exact_keys(data, ["schema", "heroes", "mages", "attacks", "equipped", "formation_serials"]):
		return false
	if typeof(data["schema"]) != TYPE_INT or data["schema"] != 1:
		return false
	if typeof(data["heroes"]) != TYPE_ARRAY or typeof(data["mages"]) != TYPE_ARRAY or typeof(data["attacks"]) != TYPE_ARRAY or typeof(data["equipped"]) != TYPE_ARRAY or typeof(data["formation_serials"]) != TYPE_ARRAY:
		return false
	var hero_values: Array = data["heroes"]
	if hero_values.is_empty() or hero_values.size() > 3 or data["attacks"].size() != hero_values.size() or data["equipped"].size() > 9 or data["formation_serials"].size() != 2:
		return false
	var hero_ids: Dictionary = {}
	var previous_hero: int = 0
	for hero_id: Variant in hero_values:
		if typeof(hero_id) != TYPE_INT or hero_id <= 0 or hero_id <= previous_hero:
			return false
		hero_ids[hero_id] = true
		previous_hero = hero_id
	var previous_mage: int = 0
	for mage_id: Variant in data["mages"]:
		if typeof(mage_id) != TYPE_INT or mage_id <= previous_mage or not hero_ids.has(mage_id): return false
		previous_mage = mage_id
	var attack_ids: Dictionary = {}
	for attack: Variant in data["attacks"]:
		if not _exact_keys(attack, ["unit_id", "attack_id"]):
			return false
		if typeof(attack["unit_id"]) != TYPE_INT or typeof(attack["attack_id"]) != TYPE_STRING or attack["unit_id"] <= 0 or attack["attack_id"].is_empty() or not hero_ids.has(attack["unit_id"]) or attack_ids.has(attack["unit_id"]):
			return false
		attack_ids[attack["unit_id"]] = true
	if attack_ids.size() != hero_ids.size():
		return false
	var item_ids: Dictionary = {}
	var slots: Dictionary = {}
	var definitions: Dictionary = {}
	for row: Variant in data["equipped"]:
		if not _exact_keys(row, ["id", "unit_id", "slot", "definition", "version", "stacks"]):
			return false
		for field: String in ["id", "unit_id", "slot", "version", "stacks"]:
			if typeof(row[field]) != TYPE_INT:
				return false
		if typeof(row["definition"]) != TYPE_STRING:
			return false
		var item_id: int = row["id"]
		var unit_id: int = row["unit_id"]
		var slot: int = row["slot"]
		var artifact_id: String = row["definition"]
		if item_id <= 0 or item_ids.has(item_id) or not hero_ids.has(unit_id) or slot < 1 or slot > 3 or row["version"] != 1:
			return false
		var definition := ExpeditionCatalog.artifact(artifact_id)
		if definition == null or row["stacks"] < 1 or row["stacks"] > definition.max_stacks:
			return false
		var slot_key: String = "%d:%d" % [unit_id, slot]
		var definition_key: String = "%d:%s" % [unit_id, artifact_id]
		if slots.has(slot_key) or definitions.has(definition_key):
			return false
		item_ids[item_id] = true
		slots[slot_key] = true
		definitions[definition_key] = true
	for serial: Variant in data["formation_serials"]:
		if typeof(serial) != TYPE_INT or serial < 0:
			return false
	return true

func stacks(unit_id: int, definition: String) -> int:
	for row: Dictionary in equipped:
		if row.get("unit_id") == unit_id and row.get("definition") == definition:
			return int(row.get("stacks", 0))
	return 0

func ordinary(unit_id: int, attack_id: StringName) -> bool:
	return heroes.has(unit_id) and attacks.get(unit_id, &"") == attack_id and not attack_id.is_empty()

func effect_allowed(unit_id: int, definition: String) -> bool:
	# Класс входит в value-снимок: preview не читает изменяемый профиль героя.
	return heroes.has(unit_id) and (definition not in ["spark", "harvest"] or not mages.has(unit_id))

func references_valid(board: BattleBoard) -> bool:
	if board == null or not valid(to_dict()):
		return false
	for unit_id: int in heroes:
		var unit := board.get_unit_by_id(unit_id)
		if unit == null or unit.id != unit_id or unit.faction != Faction.Type.PLAYER:
			return false
	return true

static func _exact_keys(value: Variant, expected: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true

func _runtime_shape_valid() -> bool:
	if typeof(attacks) != TYPE_DICTIONARY:
		return false
	for key: Variant in attacks:
		if typeof(key) != TYPE_INT or typeof(attacks[key]) != TYPE_STRING_NAME or String(attacks[key]).is_empty():
			return false
	if attacks.size() != heroes.size():
		return false
	for row: Variant in equipped:
		if not _exact_keys(row, ["id", "unit_id", "slot", "definition", "version", "stacks"]):
			return false
		for field: String in ["id", "unit_id", "slot", "version", "stacks"]:
			if typeof(row[field]) != TYPE_INT:
				return false
		if typeof(row["definition"]) != TYPE_STRING:
			return false
	return true
