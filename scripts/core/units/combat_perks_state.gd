extends RefCounted
class_name CombatPerksState

enum Mode { NONE, OPPORTUNIST, COVER, COUNTERATTACK = 3 }

const MAX_ID: int = 9223372036854775807

var definition: CombatPerksDefinition = CombatPerksDefinition.new()
var mode: int = Mode.NONE
var cover_target_id: int = 0
var reaction_left: int = 0
var movement_stopped: bool = false
## Новые сессии хранят запас бонусных действий в ActionResources.
var uses_bonus_actions: bool = false

func to_dict() -> Dictionary:
	if get_script() != CombatPerksState or definition == null or definition.get_script() != CombatPerksDefinition:
		return {}
	if uses_bonus_actions:
		# Нельзя сериализовать два независимых запаса одной и той же реакции.
		if reaction_left != 0: return {}
		var current_definition := {
			"sneak_attack": definition.sneak_attack,
			"tank_reactions": definition.tank_reactions,
			"stunning_strike": definition.stunning_strike,
			"stun_immune": definition.stun_immune,
			"entangle_immune": definition.entangle_immune,
			"counterattack": definition.counterattack,
			"burning_bypass_hp_gate": definition.burning_bypass_hp_gate,
		}
		if definition.passive_opportunist:
			# Отдельная версия хранит именно включённый флаг и не меняет старую форму схемы 5.
			current_definition["passive_opportunist"] = true
		var current := {"schema_version": 6 if definition.passive_opportunist else 5, "definition": current_definition, "mode": mode,
			"cover_target_id": cover_target_id, "movement_stopped": movement_stopped}
		return current if valid(current) else {}
	var has_v2_perk: bool = definition.stunning_strike or definition.stun_immune or definition.entangle_immune
	var has_v3_perk: bool = definition.counterattack
	var definition_data := {"sneak_attack": definition.sneak_attack, "tank_reactions": definition.tank_reactions}
	var version: int = 1
	if definition.passive_opportunist: return {}
	if has_v2_perk:
		version = 2
		definition_data["stunning_strike"] = definition.stunning_strike
		definition_data["stun_immune"] = definition.stun_immune
		definition_data["entangle_immune"] = definition.entangle_immune
	if has_v3_perk:
		version = 3
		definition_data["stunning_strike"] = definition.stunning_strike
		definition_data["stun_immune"] = definition.stun_immune
		definition_data["entangle_immune"] = definition.entangle_immune
		definition_data["counterattack"] = true
	if definition.burning_bypass_hp_gate:
		version = 4
		definition_data["stunning_strike"] = definition.stunning_strike
		definition_data["stun_immune"] = definition.stun_immune
		definition_data["entangle_immune"] = definition.entangle_immune
		definition_data["counterattack"] = definition.counterattack
		definition_data["burning_bypass_hp_gate"] = true
	var value := {"schema_version": version, "definition": definition_data, "mode": mode, "cover_target_id": cover_target_id, "reaction_left": reaction_left, "movement_stopped": movement_stopped}
	return value if valid(value) else {}

static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var data: Dictionary = value
	if not data.has("schema_version") or typeof(data["schema_version"]) != TYPE_INT: return false
	var version: int = data["schema_version"]
	if version == 6:
		return _valid_passive_schema(data)
	if version == 5:
		return _valid_current_schema(data)
	if not UnitState._has_exact_string_keys(data, ["schema_version", "definition", "mode", "cover_target_id", "reaction_left", "movement_stopped"]): return false
	value = data
	if version not in [1, 2, 3, 4]: return false
	var expected_definition_keys: Array[String] = ["sneak_attack", "tank_reactions"]
	if version == 2:
		expected_definition_keys.append_array(["stunning_strike", "stun_immune", "entangle_immune"])
	if version >= 3:
		expected_definition_keys.append_array(["stunning_strike", "stun_immune", "entangle_immune", "counterattack"])
	if version == 4: expected_definition_keys.append("burning_bypass_hp_gate")
	if typeof(value["definition"]) != TYPE_DICTIONARY or not UnitState._has_exact_string_keys(value["definition"], expected_definition_keys): return false
	var definition_data: Dictionary = value["definition"]
	if typeof(definition_data["sneak_attack"]) != TYPE_BOOL or typeof(definition_data["tank_reactions"]) != TYPE_BOOL: return false
	if version == 2:
		for key: String in ["stunning_strike", "stun_immune", "entangle_immune"]:
			if typeof(definition_data[key]) != TYPE_BOOL: return false
		# Версия 2 нужна только при наличии нового флага, иначе сохраняется единственная форма схемы 1.
		if not (definition_data["stunning_strike"] or definition_data["stun_immune"] or definition_data["entangle_immune"]): return false
	if version >= 3:
		for key: String in ["stunning_strike", "stun_immune", "entangle_immune", "counterattack"]:
			if typeof(definition_data[key]) != TYPE_BOOL: return false
		# Схема 3 принадлежит только реальному новому перку, чтобы старые данные нельзя было выдать за новую форму.
		if version == 3 and not definition_data["counterattack"]: return false
	if version >= 4 and (typeof(definition_data["burning_bypass_hp_gate"]) != TYPE_BOOL or not definition_data["burning_bypass_hp_gate"]): return false
	for key: String in ["mode", "cover_target_id", "reaction_left"]:
		if typeof(value[key]) != TYPE_INT: return false
	if typeof(value["movement_stopped"]) != TYPE_BOOL or value["mode"] not in [Mode.NONE, Mode.OPPORTUNIST, Mode.COVER, Mode.COUNTERATTACK] or value["cover_target_id"] < 0 or value["cover_target_id"] >= MAX_ID or value["reaction_left"] not in [0, 1]: return false
	if version < 3 and value["mode"] == Mode.COUNTERATTACK: return false
	if value["mode"] in [Mode.OPPORTUNIST, Mode.COVER] and not definition_data["tank_reactions"]: return false
	if value["mode"] == Mode.COUNTERATTACK and (version < 3 or not definition_data["counterattack"]): return false
	if not definition_data["tank_reactions"] and not (version >= 3 and definition_data["counterattack"]) and (value["mode"] != Mode.NONE or value["cover_target_id"] != 0 or value["reaction_left"] != 0): return false
	if value["mode"] != Mode.COVER and value["cover_target_id"] != 0: return false
	if value["mode"] == Mode.COVER and value["cover_target_id"] == 0: return false
	return true

static func _valid_current_schema(value: Dictionary) -> bool:
	if not UnitState._has_exact_string_keys(value, ["schema_version", "definition", "mode", "cover_target_id", "movement_stopped"]): return false
	var expected_definition_keys: Array[String] = ["sneak_attack", "tank_reactions", "stunning_strike",
		"stun_immune", "entangle_immune", "counterattack", "burning_bypass_hp_gate"]
	if typeof(value["definition"]) != TYPE_DICTIONARY or not UnitState._has_exact_string_keys(value["definition"], expected_definition_keys): return false
	var definition_data: Dictionary = value["definition"]
	for key: String in expected_definition_keys:
		if typeof(definition_data[key]) != TYPE_BOOL: return false
	if typeof(value["mode"]) != TYPE_INT or typeof(value["cover_target_id"]) != TYPE_INT or typeof(value["movement_stopped"]) != TYPE_BOOL: return false
	return _valid_mode_state(5, definition_data, value["mode"], value["cover_target_id"], 0)

static func _valid_passive_schema(value: Dictionary) -> bool:
	if not UnitState._has_exact_string_keys(value, ["schema_version", "definition", "mode", "cover_target_id", "movement_stopped"]): return false
	var expected: Array[String] = ["sneak_attack", "tank_reactions", "stunning_strike", "stun_immune",
		"entangle_immune", "counterattack", "burning_bypass_hp_gate", "passive_opportunist"]
	if typeof(value["definition"]) != TYPE_DICTIONARY or not UnitState._has_exact_string_keys(value["definition"], expected): return false
	var definition_data: Dictionary = value["definition"]
	for key: String in expected:
		if typeof(definition_data[key]) != TYPE_BOOL: return false
	if not definition_data["passive_opportunist"]: return false
	if typeof(value["mode"]) != TYPE_INT or typeof(value["cover_target_id"]) != TYPE_INT or typeof(value["movement_stopped"]) != TYPE_BOOL: return false
	return _valid_mode_state(6, definition_data, value["mode"], value["cover_target_id"], 0)

static func _valid_mode_state(version: int, definition_data: Dictionary, state_mode: int, target_id: int, legacy_reaction_left: int) -> bool:
	if state_mode not in [Mode.NONE, Mode.OPPORTUNIST, Mode.COVER, Mode.COUNTERATTACK] or target_id < 0 or target_id >= MAX_ID or legacy_reaction_left not in [0, 1]: return false
	if version < 3 and state_mode == Mode.COUNTERATTACK: return false
	if state_mode == Mode.OPPORTUNIST and not definition_data["tank_reactions"] and not (version == 6 and definition_data["passive_opportunist"]): return false
	if state_mode == Mode.COVER and not definition_data["tank_reactions"]: return false
	if state_mode == Mode.COUNTERATTACK and (version < 3 or not definition_data["counterattack"]): return false
	if not definition_data["tank_reactions"] and not (version >= 3 and definition_data["counterattack"]) and not (version == 6 and definition_data["passive_opportunist"]) and (state_mode != Mode.NONE or target_id != 0 or legacy_reaction_left != 0): return false
	if state_mode != Mode.COVER and target_id != 0: return false
	if state_mode == Mode.COVER and target_id == 0: return false
	return true

static func from_dict(value: Dictionary) -> CombatPerksState:
	if not valid(value): return null
	var result := CombatPerksState.new()
	var definition_data: Dictionary = value["definition"]
	result.definition = CombatPerksDefinition.new()
	if value["schema_version"] in [5, 6]:
		result.uses_bonus_actions = true
		result.definition.sneak_attack = definition_data["sneak_attack"]
		result.definition.tank_reactions = definition_data["tank_reactions"]
		result.definition.stunning_strike = definition_data["stunning_strike"]
		result.definition.stun_immune = definition_data["stun_immune"]
		result.definition.entangle_immune = definition_data["entangle_immune"]
		result.definition.counterattack = definition_data["counterattack"]
		result.definition.burning_bypass_hp_gate = definition_data["burning_bypass_hp_gate"]
		if value["schema_version"] == 6: result.definition.passive_opportunist = true
		result.mode = value["mode"]
		result.cover_target_id = value["cover_target_id"]
		result.movement_stopped = value["movement_stopped"]
		return result
	result.definition.sneak_attack = definition_data["sneak_attack"]
	result.definition.tank_reactions = definition_data["tank_reactions"]
	if value["schema_version"] == 2:
		result.definition.stunning_strike = definition_data["stunning_strike"]
		result.definition.stun_immune = definition_data["stun_immune"]
		result.definition.entangle_immune = definition_data["entangle_immune"]
	if value["schema_version"] >= 3:
		result.definition.stunning_strike = definition_data["stunning_strike"]
		result.definition.stun_immune = definition_data["stun_immune"]
		result.definition.entangle_immune = definition_data["entangle_immune"]
		result.definition.counterattack = definition_data["counterattack"]
	if value["schema_version"] >= 4: result.definition.burning_bypass_hp_gate = true
	result.mode = value["mode"]
	result.cover_target_id = value["cover_target_id"]
	result.reaction_left = value["reaction_left"]
	result.movement_stopped = value["movement_stopped"]
	return result

func copy() -> CombatPerksState:
	var value := to_dict()
	if value.is_empty(): return null
	return from_dict(value)
