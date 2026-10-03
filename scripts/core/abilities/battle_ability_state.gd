extends RefCounted
class_name BattleAbilityState

const MAX: int = 9223372036854775807
var catalog: Array[AbilityDefinition] = []
var mana: int = 6
var maximum: int = 6
var ledger: Array[Dictionary] = []
var serials: Array[int] = [0, 0]
var ended: Array[int] = [0, 0]
var team: int = 1
var stage: String = "setup"
var mage_allowed: bool = false
var schema_version: int = 1
var ruleset_id: String = ""
var first_team: int = 1

static func create(definitions: Array[AbilityDefinition]) -> BattleAbilityState:
	var result := BattleAbilityState.new()
	for definition: AbilityDefinition in definitions: result.catalog.append(definition.copy())
	result.catalog.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return String(a.ability_id) < String(b.ability_id))
	return result

static func create_deck(definitions: Array[AbilityDefinition], first_team_value: int) -> BattleAbilityState:
	if first_team_value not in [0, 1]: return null
	var result := BattleAbilityState.new()
	result.schema_version = 2; result.ruleset_id = "u14-deck-v1"; result.first_team = first_team_value
	result.team = first_team_value; result.mana = 2; result.maximum = 2; result.mage_allowed = false
	for definition: AbilityDefinition in definitions:
		if definition == null or definition.validate() != &"": return null
		if String(definition.ability_id).begins_with("mage."): continue
		var copy := definition.copy()
		if copy == null: return null
		result.catalog.append(copy)
	result.catalog.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return String(a.ability_id) < String(b.ability_id))
	return result if valid(result.to_dict()) else null

func definition(id: StringName) -> AbilityDefinition:
	for value: AbilityDefinition in catalog:
		if value != null and value.ability_id == id: return value
	return null

func remaining(id: StringName) -> int:
	for record: Dictionary in ledger:
		if record["ability_id"] == String(id): return record["remaining"]
	return 0

func to_dict() -> Dictionary:
	var definitions: Array = []
	for value: AbilityDefinition in catalog:
		if value == null: return {}
		definitions.append(value.to_dict())
	var result: Dictionary = {"schema_version": schema_version, "catalog": definitions, "mana": mana, "maximum": maximum, "ledger": ledger.duplicate(true), "serials": Array(serials).duplicate(), "ended": Array(ended).duplicate(), "team": team, "stage": stage, "mage_allowed": mage_allowed}
	if schema_version == 2:
		result["ruleset_id"] = ruleset_id; result["first_team"] = first_team
	return result

static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var common: Dictionary = {"schema_version": TYPE_INT, "catalog": TYPE_ARRAY, "mana": TYPE_INT, "maximum": TYPE_INT, "ledger": TYPE_ARRAY, "serials": TYPE_ARRAY, "ended": TYPE_ARRAY, "team": TYPE_INT, "stage": TYPE_STRING, "mage_allowed": TYPE_BOOL}
	if typeof(value.get("schema_version")) != TYPE_INT: return false
	var schema: int = value.schema_version
	if schema == 2:
		common["ruleset_id"] = TYPE_STRING; common["first_team"] = TYPE_INT
	if not ItemSimulationSnapshot._shape(value, common) or schema not in [1, 2]: return false
	if value.maximum < 1 or value.mana < 0 or value.mana > value.maximum or value.team not in [0, 1] or value.stage not in ["setup", "active", "closing", "ended", "ready", "terminal"]: return false
	if schema == 1:
		if value.maximum != 6 or value.mage_allowed != (value.stage == "active" and value.team == 0): return false
	else:
		if value.ruleset_id != "u14-deck-v1" or value.first_team not in [0, 1] or value.maximum < 2 or value.maximum > 9: return false
		if value.mage_allowed != (value.stage == "active" and value.team == 0) or not value.ledger.is_empty(): return false
	if value.serials.size() != 2 or value.ended.size() != 2: return false
	for i: int in 2:
		if typeof(value.serials[i]) != TYPE_INT or typeof(value.ended[i]) != TYPE_INT or value.serials[i] < 0 or value.ended[i] < 0 or value.ended[i] > value.serials[i] or value.serials[i] - value.ended[i] > 1: return false
	if schema == 1:
		if value.serials[1] < value.serials[0] or value.serials[1] - value.serials[0] > 1: return false
	else:
		var first_delta: int = value.serials[value.first_team] - value.serials[1 - value.first_team]
		if first_delta < 0 or first_delta > 1: return false
		var expected_maximum: int = 2 if value.serials[0] <= 1 else (9 if value.serials[0] >= 8 else value.serials[0] + 1)
		if value.maximum != expected_maximum: return false
	if value.stage == "setup":
		if schema == 1 and (value.team != 1 or not value.ledger.is_empty() or value.mana != value.maximum): return false
		if schema == 2 and (value.team != value.first_team or value.mana != 2 or value.maximum != 2 or not value.ledger.is_empty()): return false
		if value.serials != [0, 0] or value.ended != [0, 0]: return false
	if value.stage in ["active", "closing", "ready", "ended"]:
		if value.serials[1 - value.team] != value.ended[1 - value.team]: return false
		if schema == 1 and value.serials[1] - value.serials[0] != value.team: return false
		if schema == 2 and (value.serials[value.team] < value.serials[1 - value.team] or value.serials[value.team] - value.serials[1 - value.team] > 1): return false
	if value.stage in ["active", "closing", "ready"] and value.serials[value.team] - value.ended[value.team] != 1: return false
	if value.stage == "ended":
		if value.serials[value.team] != value.ended[value.team]: return false
		if schema == 2 and value.serials != value.ended: return false
	if value.catalog.size() < 2 or value.catalog.size() > 4096 or value.ledger.size() > 2: return false
	var ids: Dictionary = {}
	var previous := ""
	for raw: Variant in value.catalog:
		var parsed := AbilityDefinition.from_dict(raw)
		if parsed == null or parsed.validate() != &"" or String(parsed.ability_id) <= previous: return false
		previous = String(parsed.ability_id)
		ids[previous] = parsed
	var fixed: Dictionary = {}
	for descriptor: AbilityDefinition in AbilityCatalog.defaults():
		var id := String(descriptor.ability_id)
		if schema == 2 and id.begins_with("mage."): continue
		fixed[id] = true
		if not ids.has(id): return false
		if (schema == 2 or not id.begins_with("mage.")) and ids[id].to_dict() != descriptor.to_dict(): return false
	for id: String in ids:
		if schema == 2 and id.begins_with("mage."): return false
		if fixed.has(id): continue
		if schema == 1 and (AbilityDefinition.TEST_EFFECTS.has(StringName(id)) or AbilityDefinition.TEST_SUPPORT_EFFECTS.has(StringName(id))): continue
		# Ссылки предметов сверяет envelope; ссылки атак — контекст с AttackRules.
		if id.begins_with("attack:") and id.length() > 7: continue
		if id.begins_with("item_use:") or id.begins_with("item_effect:"): continue
		return false
	if schema == 2: return value.ledger.is_empty()
	previous = ""
	for record: Variant in value.ledger:
		if not ItemSimulationSnapshot._shape(record, {"owner_kind": TYPE_STRING, "owner_id": TYPE_INT, "ability_id": TYPE_STRING, "source_instance_id": TYPE_INT, "remaining": TYPE_INT, "skip_current_end": TYPE_BOOL}): return false
		if record.owner_kind != "mage" or record.owner_id != 0 or record.ability_id not in ["mage.fire", "mage.heal"] or record.ability_id <= previous: return false
		previous = record.ability_id
		if record.source_instance_id != (1 if record.ability_id == "mage.fire" else 2): return false
		if record.remaining < 0 or record.remaining > ids[record.ability_id].cooldown_turns or (record.remaining == 0 and record.skip_current_end): return false
	return true

static func from_dict(value: Variant) -> BattleAbilityState:
	if not valid(value): return null
	var result := BattleAbilityState.new()
	for raw: Dictionary in value.catalog: result.catalog.append(AbilityDefinition.from_dict(raw))
	result.apply_values(value)
	return result

func apply_values(value: Dictionary) -> void:
	mana = value.mana; maximum = value.maximum
	ledger.assign(value.ledger.duplicate(true))
	serials.assign(value.serials); ended.assign(value.ended)
	team = value.team; stage = value.stage; mage_allowed = value.mage_allowed
	schema_version = value.schema_version
	ruleset_id = String(value.get("ruleset_id", "")); first_team = int(value.get("first_team", 1))

func paid(id: StringName) -> Dictionary:
	var after := to_dict()
	var spell := definition(id)
	if schema_version != 1 or not valid(after) or spell == null or not mage_allowed or remaining(id) > 0 or mana < spell.mana_cost: return {}
	after.mana -= spell.mana_cost
	if spell.cooldown_turns > 0:
		var found := false
		for record: Dictionary in after.ledger:
			if record.ability_id == String(id):
				record.remaining = spell.cooldown_turns; record.skip_current_end = true; found = true
		if not found: after.ledger.append({"owner_kind": "mage", "owner_id": 0, "ability_id": String(id), "source_instance_id": 1 if id == &"mage.fire" else 2, "remaining": spell.cooldown_turns, "skip_current_end": true})
		after.ledger.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.ability_id) < String(b.ability_id))
	return after

func boundary(operation: StringName, expected_team: int, serial: int) -> Dictionary:
	var after := to_dict()
	if not valid(after) or expected_team != team or serial != serials[team]: return {}
	match operation:
		&"start":
			if stage != "setup": return {}
			after.serials[team] = 1; after.stage = "active"
		&"close":
			if stage != "active": return {}
			after.stage = "closing"
		&"end":
			if stage != "closing" or ended[team] == serial: return {}
			if schema_version == 1 and team == 0:
				for record: Dictionary in after.ledger:
					if record.skip_current_end: record.skip_current_end = false
					elif record.remaining > 0: record.remaining -= 1
			after.ended[team] = serial; after.stage = "ended"
		&"begin":
			if stage != "ended" or serials[1 - team] == MAX: return {}
			after.team = 1 - team; after.serials[1 - team] += 1; after.stage = "ready"
			if after.team == 0:
				if schema_version == 1: after.mana = mini(maximum, mana + 2)
				else:
					if serials[0] >= 1: after.maximum = mini(9, maximum + 1)
					after.mana = after.maximum
		&"open":
			if stage != "ready": return {}
			after.stage = "active"
		_: return {}
	after.mage_allowed = after.stage == "active" and after.team == 0
	return after if valid(after) else {}

static func runtime_key(owner_kind: StringName, owner_id: int, ability_id: StringName, source_instance_id: int = 0) -> Array:
	# Позиция слота не входит в идентичность предмета; mage:0 не является UnitId.
	return [owner_kind, owner_id, ability_id, source_instance_id]

static func battle_over(state: ItemSimulationState) -> bool:
	var living: Array[bool] = [false, false]
	for unit: UnitState in state.get_board().get_all_units():
		if unit.is_alive() and unit.faction in [0, 1]: living[unit.faction] = true
	return not living[0] or not living[1]
