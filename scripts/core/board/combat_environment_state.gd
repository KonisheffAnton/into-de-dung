extends RefCounted
class_name CombatEnvironmentState

const FIRE_DAMAGE: int = 8
const MAX_RECORDS: int = 1024
const MAX_PROCESSED_DEATHS: int = 65536
const MAX_ID: int = 9223372036854775807

var next_fire_id: int = 1
var next_corpse_id: int = 1
var fires: Array[Dictionary] = []
var corpses: Array[Dictionary] = []
var processed_deaths: Array[int] = []
var collapse: Dictionary = {}

func to_dict() -> Dictionary:
	# Пустая фаза сохраняет точную старую форму, чтобы legacy-снимки не меняли канон.
	var raw := {"schema_version": 1 if collapse.is_empty() else 2, "next_fire_id": next_fire_id, "next_corpse_id": next_corpse_id, "fires": fires.duplicate(true), "corpses": corpses.duplicate(true), "processed_deaths": processed_deaths.duplicate()}
	if not collapse.is_empty(): raw["collapse"] = collapse.duplicate(true)
	# Повреждённый runtime должен дойти до отказа capture, а не до сортировки
	# по отсутствующему полю; нельзя скрывать лишние поля при построении DTO.
	if not valid(raw): return raw
	# Сортировка нужна, чтобы одинаковое состояние имело один канонический снимок.
	var sorted_fires: Array[Dictionary] = _sorted_records(fires)
	var sorted_corpses: Array[Dictionary] = _sorted_records(corpses)
	var sorted_deaths: Array[int] = processed_deaths.duplicate()
	sorted_deaths.sort()
	return {
		"schema_version": raw["schema_version"],
		"next_fire_id": next_fire_id,
		"next_corpse_id": next_corpse_id,
		"fires": _copy_records(sorted_fires),
		"corpses": _copy_records(sorted_corpses),
		"processed_deaths": sorted_deaths,
	}.merged({"collapse": collapse.duplicate(true)} if not collapse.is_empty() else {})

static func valid(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var value: Dictionary = data
	if typeof(value.get("schema_version")) != TYPE_INT or value["schema_version"] not in [1, 2]:
		return false
	var schema: int = value["schema_version"]
	var expected_keys: Array[String] = ["schema_version", "next_fire_id", "next_corpse_id", "fires", "corpses", "processed_deaths"]
	if schema == 2: expected_keys.append("collapse")
	if not _has_exact_keys(value, expected_keys):
		return false
	if schema == 2 and not _valid_collapse(value["collapse"]): return false
	if typeof(value["next_fire_id"]) != TYPE_INT or typeof(value["next_corpse_id"]) != TYPE_INT:
		return false
	var next_fire: int = value["next_fire_id"]
	var next_corpse: int = value["next_corpse_id"]
	if not _valid_id(next_fire) or not _valid_id(next_corpse):
		return false
	if typeof(value["fires"]) != TYPE_ARRAY or typeof(value["corpses"]) != TYPE_ARRAY or typeof(value["processed_deaths"]) != TYPE_ARRAY:
		return false
	var raw_fires: Array = value["fires"]
	var raw_corpses: Array = value["corpses"]
	var raw_deaths: Array = value["processed_deaths"]
	if raw_fires.size() > MAX_RECORDS or raw_corpses.size() > MAX_RECORDS or raw_deaths.size() > MAX_PROCESSED_DEATHS:
		return false
	var fire_ids: Dictionary = {}
	var fire_cells: Dictionary = {}
	var max_fire: int = 0
	for raw: Variant in raw_fires:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var fire: Dictionary = raw
		if not _has_exact_keys(fire, ["id", "cell", "damage"]):
			return false
		if typeof(fire["id"]) != TYPE_INT or not _valid_id(fire["id"]) or fire_ids.has(fire["id"]):
			return false
		if typeof(fire["cell"]) != TYPE_VECTOR2I or typeof(fire["damage"]) != TYPE_INT or fire["damage"] != FIRE_DAMAGE:
			return false
		var cell: Vector2i = fire["cell"]
		var cell_key: String = "%d:%d" % [cell.x, cell.y]
		if fire_cells.has(cell_key):
			return false
		fire_ids[fire["id"]] = true
		fire_cells[cell_key] = true
		max_fire = maxi(max_fire, fire["id"])
	if next_fire <= max_fire:
		return false
	var corpse_ids: Dictionary = {}
	var corpse_sources: Dictionary = {}
	var max_corpse: int = 0
	for raw: Variant in raw_corpses:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var corpse: Dictionary = raw
		if not _has_exact_keys(corpse, ["id", "cell", "source_unit_id", "faction", "creature_kind"]):
			return false
		if typeof(corpse["id"]) != TYPE_INT or not _valid_id(corpse["id"]) or corpse_ids.has(corpse["id"]):
			return false
		if typeof(corpse["cell"]) != TYPE_VECTOR2I or typeof(corpse["source_unit_id"]) != TYPE_INT or not _valid_id(corpse["source_unit_id"]):
			return false
		if typeof(corpse["faction"]) != TYPE_INT or not _valid_faction(corpse["faction"]):
			return false
		if typeof(corpse["creature_kind"]) != TYPE_STRING or not _valid_kind(corpse["creature_kind"]):
			return false
		if corpse_sources.has(corpse["source_unit_id"]):
			return false
		corpse_ids[corpse["id"]] = true
		corpse_sources[corpse["source_unit_id"]] = true
		max_corpse = maxi(max_corpse, corpse["id"])
	if next_corpse <= max_corpse:
		return false
	var deaths: Dictionary = {}
	for raw_death: Variant in raw_deaths:
		if typeof(raw_death) != TYPE_INT or not _valid_id(raw_death) or deaths.has(raw_death):
			return false
		deaths[raw_death] = true
	for source: Variant in corpse_sources.keys():
		if not deaths.has(source):
			return false
	return true

static func from_dict(data: Dictionary) -> CombatEnvironmentState:
	if not valid(data):
		return null
	var result := CombatEnvironmentState.new()
	if data["schema_version"] == 2: result.collapse = data["collapse"].duplicate(true)
	result.next_fire_id = data["next_fire_id"]
	result.next_corpse_id = data["next_corpse_id"]
	result.fires.assign(_sorted_records(data["fires"]))
	result.corpses.assign(_sorted_records(data["corpses"]))
	result.processed_deaths.assign(data["processed_deaths"].duplicate())
	result.processed_deaths.sort()
	return result

static func _valid_collapse(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var record: Dictionary = value
	if not _has_exact_keys(record, ["turn", "marked"]): return false
	if typeof(record["turn"]) != TYPE_INT or typeof(record["marked"]) != TYPE_ARRAY: return false
	var turn: int = record["turn"]
	var marked: Array = record["marked"]
	# Один маркер исключает неоднозначное разрешение, а нулевой ход не имеет предыдущего хода.
	if turn < 0 or turn > MAX_ID - 2 or marked.size() > 1: return false
	if turn == 0 and not marked.is_empty(): return false
	for cell: Variant in marked:
		if typeof(cell) != TYPE_VECTOR2I: return false
	return true

func fire_at(cell: Vector2i) -> Dictionary:
	for fire: Dictionary in fires:
		if fire["cell"] == cell:
			return fire.duplicate(true)
	return {}

func corpses_at(cell: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for corpse: Dictionary in corpses:
		if corpse["cell"] == cell:
			result.append(corpse.duplicate(true))
	result.sort_custom(_sort_by_id)
	return result

func ignite(cell: Vector2i) -> Dictionary:
	# Проверяем пределы до записи, чтобы отказ не менял ни запись, ни счётчик.
	if fires.size() >= MAX_RECORDS or not _valid_id(next_fire_id) or next_fire_id >= MAX_ID - 1 or not fire_at(cell).is_empty():
		return {}
	var result := {"id": next_fire_id, "cell": cell, "damage": FIRE_DAMAGE}
	fires.append(result.duplicate(true))
	next_fire_id += 1
	return result.duplicate(true)

func record_death(unit_id: int, cell: Vector2i, faction: int, creature_kind: String, leaves_body: bool = true) -> Dictionary:
	if not _valid_id(unit_id) or not _valid_faction(faction) or not _valid_kind(creature_kind):
		return {}
	if processed_deaths.has(unit_id):
		return {}
	if processed_deaths.size() >= MAX_PROCESSED_DEATHS:
		return {}
	if leaves_body and (corpses.size() >= MAX_RECORDS or not _valid_id(next_corpse_id) or next_corpse_id >= MAX_ID - 1 or _has_corpse_source(unit_id)):
		return {}
	processed_deaths.append(unit_id)
	processed_deaths.sort()
	if not leaves_body:
		return {}
	var result := {"id": next_corpse_id, "cell": cell, "source_unit_id": unit_id, "faction": faction, "creature_kind": creature_kind}
	corpses.append(result.duplicate(true))
	next_corpse_id += 1
	return result.duplicate(true)

func consume_corpse(corpse_id: int) -> Dictionary:
	# Потребление убирает только тело; факт смерти остаётся для идемпотентности.
	if not _valid_id(corpse_id):
		return {}
	for index: int in corpses.size():
		if corpses[index]["id"] == corpse_id:
			var result: Dictionary = corpses[index].duplicate(true)
			corpses.remove_at(index)
			return result
	return {}

static func _valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value > 0 and value < MAX_ID

static func _valid_faction(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value in [Faction.Type.PLAYER, Faction.Type.ENEMY, Faction.Type.NEUTRAL]

static func _valid_kind(value: String) -> bool:
	return not value.is_empty() and value.to_utf8_buffer().size() <= 64

func _has_corpse_source(source_id: int) -> bool:
	for corpse: Dictionary in corpses:
		if corpse["source_unit_id"] == source_id:
			return true
	return false

static func _sort_by_id(left: Dictionary, right: Dictionary) -> bool:
	return left["id"] < right["id"]

static func _sorted_records(records: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in records:
		result.append((raw as Dictionary).duplicate(true))
	result.sort_custom(_sort_by_id)
	return result

static func _copy_records(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		result.append(record.duplicate(true))
	return result

static func _has_exact_keys(value: Dictionary, required: Array[String]) -> bool:
	if value.size() != required.size():
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key):
			return false
	return true
