extends RefCounted
class_name BleedingState

const DURATION: int = 2
const DAMAGE: int = 4
const MAX_ID: int = 9223372036854775807
const MAX_TICKS: int = 9223372036854775807
const STACK_DURATION: int = 3
const STACK_DAMAGE: int = 1
const MOVE_DAMAGE: int = 2
const MAX_STACKS: int = 9223372036854775807

var immune: bool = false
var ticks_left: int = 0
var source: Dictionary = {}
var hit_id: String = ""
var stacked: bool = false
var stacks: int = 0

signal changed()

func to_dict() -> Dictionary:
	var result: Dictionary = {
		"schema_version": 3 if stacked else schema_for_ticks(ticks_left),
		"immune": immune,
		"ticks_left": ticks_left,
		"source": _copy_source(source),
		"hit_id": hit_id,
	}
	if stacked:
		result["stacks"] = stacks
	elif stacks != 0:
		# Некорректный runtime не должен терять стак при сериализации.
		result["stacks"] = stacks
	return result

static func schema_for_ticks(ticks: int) -> int:
	# Минимальная схема сохраняет точные байты прежних снимков D3/M1.
	return 1 if ticks <= DURATION else 2

static func valid(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var value: Dictionary = data
	if typeof(value.get("schema_version")) == TYPE_INT and value["schema_version"] == 3:
		return _valid_stacked(value)
	if not _has_exact_keys(value, ["schema_version", "immune", "ticks_left", "source", "hit_id"]):
		return false
	if typeof(value["schema_version"]) != TYPE_INT or value["schema_version"] not in [1, 2]:
		return false
	if typeof(value["immune"]) != TYPE_BOOL or typeof(value["ticks_left"]) != TYPE_INT:
		return false
	var ticks: int = value["ticks_left"]
	# Старый формат сохраняет свой предел; накопленный срок хранится только в v2.
	if ticks < 0 or value["schema_version"] != schema_for_ticks(ticks) or typeof(value["source"]) != TYPE_DICTIONARY or typeof(value["hit_id"]) != TYPE_STRING:
		return false
	if value["hit_id"].to_utf8_buffer().size() > 128:
		return false
	if ticks == 0:
		return value["source"].is_empty() and value["hit_id"].is_empty()
	if value["hit_id"].is_empty() or not _valid_source(value["source"]):
		return false
	return true

static func _valid_stacked(value: Dictionary) -> bool:
	if not _has_exact_keys(value, ["schema_version", "immune", "ticks_left", "source", "hit_id", "stacks"]):
		return false
	if typeof(value["immune"]) != TYPE_BOOL or typeof(value["ticks_left"]) != TYPE_INT or typeof(value["stacks"]) != TYPE_INT:
		return false
	if typeof(value["source"]) != TYPE_DICTIONARY or typeof(value["hit_id"]) != TYPE_STRING:
		return false
	var ticks: int = value["ticks_left"]
	var count: int = value["stacks"]
	if ticks < 0 or ticks > STACK_DURATION or count < 0 or count > MAX_STACKS:
		return false
	if value["hit_id"].to_utf8_buffer().size() > 128:
		return false
	if ticks == 0:
		return count == 0 and value["source"].is_empty() and value["hit_id"].is_empty()
	return count >= 1 and not value["hit_id"].is_empty() and ElementalState.valid_effect_source(value["source"])

static func from_dict(data: Dictionary) -> BleedingState:
	if not valid(data):
		return null
	var result := BleedingState.new()
	result.immune = data["immune"]
	result.ticks_left = data["ticks_left"]
	result.source = _copy_source(data["source"])
	result.hit_id = data["hit_id"]
	if data["schema_version"] == 3:
		result.stacked = true
		result.stacks = data["stacks"]
	return result

static func _valid_source(value: Dictionary) -> bool:
	if not _has_exact_keys(value, ["kind", "source_instance_id", "origin_cell", "instigator_unit_id", "credit_unit_id"]):
		return false
	if typeof(value["kind"]) != TYPE_STRING_NAME or value["kind"] != &"attack":
		return false
	if typeof(value["source_instance_id"]) != TYPE_INT or value["source_instance_id"] != 0:
		return false
	if typeof(value["origin_cell"]) != TYPE_VECTOR2I:
		return false
	for key: String in ["instigator_unit_id", "credit_unit_id"]:
		if typeof(value[key]) != TYPE_INT or value[key] <= 0 or value[key] >= MAX_ID:
			return false
	return value["instigator_unit_id"] == value["credit_unit_id"]

static func _copy_source(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in value.keys():
		result[key] = value[key]
	return result

static func _has_exact_keys(value: Dictionary, required: Array) -> bool:
	if value.size() != required.size():
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key):
			return false
	return true
