extends RefCounted
class_name ElementalState

const MAX_VALUE: int = 9223372036854775807
const MAX_ID: int = 9223372036854775807

var burning_stacks: int = 0
var burning_ticks: int = 0
var burning_source: Dictionary = {}
var wet_turns: int = 0
var frozen_turns: int = 0
var freeze_immune: bool = false

signal changed()

func to_dict() -> Dictionary:
	return {
		"schema_version": 1,
		"burning_stacks": burning_stacks,
		"burning_ticks": burning_ticks,
		"burning_source": _copy_source(burning_source),
		"wet_turns": wet_turns,
		"frozen_turns": frozen_turns,
		"freeze_immune": freeze_immune,
	}

static func valid(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var value: Dictionary = data
	if not _has_exact_keys(value, ["schema_version", "burning_stacks", "burning_ticks", "burning_source", "wet_turns", "frozen_turns", "freeze_immune"]):
		return false
	for key: String in ["schema_version", "burning_stacks", "burning_ticks", "wet_turns", "frozen_turns"]:
		if typeof(value[key]) != TYPE_INT:
			return false
	if value["schema_version"] != 1 or typeof(value["freeze_immune"]) != TYPE_BOOL or typeof(value["burning_source"]) != TYPE_DICTIONARY:
		return false
	var stacks: int = value["burning_stacks"]
	var ticks: int = value["burning_ticks"]
	var wet: int = value["wet_turns"]
	var frozen: int = value["frozen_turns"]
	if stacks < 0 or ticks < 0 or wet < 0 or wet > 3 or frozen < 0:
		return false
	if (stacks == 0) != (ticks == 0):
		return false
	if stacks == 0:
		if not value["burning_source"].is_empty():
			return false
	else:
		if not valid_effect_source(value["burning_source"]):
			return false
		if wet > 0 or frozen > 0:
			return false
	return true

static func from_dict(data: Dictionary) -> ElementalState:
	if not valid(data):
		return null
	var result := ElementalState.new()
	result.burning_stacks = data["burning_stacks"]
	result.burning_ticks = data["burning_ticks"]
	result.burning_source = _copy_source(data["burning_source"])
	result.wet_turns = data["wet_turns"]
	result.frozen_turns = data["frozen_turns"]
	result.freeze_immune = data["freeze_immune"]
	return result

static func valid_effect_source(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = value
	if not _has_exact_keys(source, ["kind", "source_instance_id", "origin_cell", "instigator_unit_id", "credit_unit_id"]):
		return false
	if typeof(source["kind"]) != TYPE_STRING_NAME or typeof(source["source_instance_id"]) != TYPE_INT or typeof(source["origin_cell"]) != TYPE_VECTOR2I:
		return false
	if typeof(source["instigator_unit_id"]) != TYPE_INT or typeof(source["credit_unit_id"]) != TYPE_INT:
		return false
	var source_id: int = source["source_instance_id"]
	var instigator: int = source["instigator_unit_id"]
	var credit: int = source["credit_unit_id"]
	if source["kind"] == &"attack":
		return source_id == 0 and instigator == credit and credit > 0 and credit < MAX_ID
	if source["kind"] == &"cell":
		return source_id > 0 and source_id < MAX_ID and instigator == 0 and credit == 0
	return false

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
