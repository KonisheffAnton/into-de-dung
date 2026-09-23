extends RefCounted
class_name ControlState

var stunned_turns: int = 0
var entangled_turns: int = 0

func to_dict() -> Dictionary:
	return {"schema_version": 1, "stunned_turns": stunned_turns, "entangled_turns": entangled_turns}

static func from_dict(value: Variant) -> ControlState:
	if not valid(value): return null
	var result := ControlState.new()
	result.stunned_turns = value["stunned_turns"]
	result.entangled_turns = value["entangled_turns"]
	return result

static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	if not UnitState._has_exact_string_keys(value, ["schema_version", "stunned_turns", "entangled_turns"]): return false
	for key: String in ["schema_version", "stunned_turns", "entangled_turns"]:
		if typeof(value[key]) != TYPE_INT: return false
	return value["schema_version"] == 1 and value["stunned_turns"] in [0, 1] and value["entangled_turns"] in [0, 1]
