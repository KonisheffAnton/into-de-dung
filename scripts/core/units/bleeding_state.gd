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
	return {"schema_version": 4, "immune": immune, "ticks_left": ticks_left,
		"source": _copy_source(source), "hit_id": hit_id, "stacked": stacked, "stacks": stacks}

static func valid(data: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(data, {"schema_version": TYPE_INT, "immune": TYPE_BOOL,
		"ticks_left": TYPE_INT, "source": TYPE_DICTIONARY, "hit_id": TYPE_STRING,
		"stacked": TYPE_BOOL, "stacks": TYPE_INT}): return false
	if data.schema_version != 4 or data.ticks_left < 0 or data.stacks < 0: return false
	if data.hit_id.to_utf8_buffer().size() > 128: return false
	if data.stacked:
		if data.ticks_left > STACK_DURATION: return false
	elif data.stacks != 0: return false
	if data.ticks_left == 0:
		return data.stacks == 0 and data.source.is_empty() and data.hit_id.is_empty()
	if data.hit_id.is_empty(): return false
	if data.stacked: return data.stacks >= 1 and ElementalState.valid_effect_source(data.source)
	return _valid_source(data.source)

static func from_dict(data: Dictionary) -> BleedingState:
	if not valid(data): return null
	var result := BleedingState.new()
	result.immune = data.immune
	result.ticks_left = data.ticks_left
	result.source = _copy_source(data.source)
	result.hit_id = data.hit_id
	result.stacked = data.stacked
	result.stacks = data.stacks
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
