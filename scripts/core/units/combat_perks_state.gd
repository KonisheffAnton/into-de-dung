extends RefCounted
class_name CombatPerksState

enum Mode { NONE, OPPORTUNIST, COVER }

const MAX_ID: int = 9223372036854775807

var definition: CombatPerksDefinition = CombatPerksDefinition.new()
var mode: int = Mode.NONE
var cover_target_id: int = 0
var reaction_left: int = 0
var movement_stopped: bool = false

func to_dict() -> Dictionary:
	if get_script() != CombatPerksState or definition == null or definition.get_script() != CombatPerksDefinition:
		return {}
	var has_v2_perk: bool = definition.stunning_strike or definition.stun_immune or definition.entangle_immune
	var definition_data := {"sneak_attack": definition.sneak_attack, "tank_reactions": definition.tank_reactions}
	var version: int = 1
	if has_v2_perk:
		version = 2
		definition_data["stunning_strike"] = definition.stunning_strike
		definition_data["stun_immune"] = definition.stun_immune
		definition_data["entangle_immune"] = definition.entangle_immune
	var value := {"schema_version": version, "definition": definition_data, "mode": mode, "cover_target_id": cover_target_id, "reaction_left": reaction_left, "movement_stopped": movement_stopped}
	return value if valid(value) else {}

static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not UnitState._has_exact_string_keys(value, ["schema_version", "definition", "mode", "cover_target_id", "reaction_left", "movement_stopped"]): return false
	if typeof(value["schema_version"]) != TYPE_INT or value["schema_version"] not in [1, 2]: return false
	var version: int = value["schema_version"]
	var expected_definition_keys: Array[String] = ["sneak_attack", "tank_reactions"]
	if version == 2:
		expected_definition_keys.append_array(["stunning_strike", "stun_immune", "entangle_immune"])
	if typeof(value["definition"]) != TYPE_DICTIONARY or not UnitState._has_exact_string_keys(value["definition"], expected_definition_keys): return false
	var definition_data: Dictionary = value["definition"]
	if typeof(definition_data["sneak_attack"]) != TYPE_BOOL or typeof(definition_data["tank_reactions"]) != TYPE_BOOL: return false
	if version == 2:
		for key: String in ["stunning_strike", "stun_immune", "entangle_immune"]:
			if typeof(definition_data[key]) != TYPE_BOOL: return false
		# Версия 2 нужна только при наличии нового флага, иначе сохраняется единственная форма схемы 1.
		if not (definition_data["stunning_strike"] or definition_data["stun_immune"] or definition_data["entangle_immune"]): return false
	for key: String in ["mode", "cover_target_id", "reaction_left"]:
		if typeof(value[key]) != TYPE_INT: return false
	if typeof(value["movement_stopped"]) != TYPE_BOOL or value["mode"] not in [Mode.NONE, Mode.OPPORTUNIST, Mode.COVER] or value["cover_target_id"] < 0 or value["cover_target_id"] >= MAX_ID or value["reaction_left"] not in [0, 1]: return false
	if not definition_data["tank_reactions"] and (value["mode"] != Mode.NONE or value["cover_target_id"] != 0 or value["reaction_left"] != 0): return false
	if value["mode"] != Mode.COVER and value["cover_target_id"] != 0: return false
	if value["mode"] == Mode.COVER and value["cover_target_id"] == 0: return false
	return true

static func from_dict(value: Dictionary) -> CombatPerksState:
	if not valid(value): return null
	var result := CombatPerksState.new()
	var definition_data: Dictionary = value["definition"]
	result.definition = CombatPerksDefinition.new()
	result.definition.sneak_attack = definition_data["sneak_attack"]
	result.definition.tank_reactions = definition_data["tank_reactions"]
	if value["schema_version"] == 2:
		result.definition.stunning_strike = definition_data["stunning_strike"]
		result.definition.stun_immune = definition_data["stun_immune"]
		result.definition.entangle_immune = definition_data["entangle_immune"]
	result.mode = value["mode"]
	result.cover_target_id = value["cover_target_id"]
	result.reaction_left = value["reaction_left"]
	result.movement_stopped = value["movement_stopped"]
	return result

func copy() -> CombatPerksState:
	var value := to_dict()
	if value.is_empty(): return null
	return from_dict(value)
