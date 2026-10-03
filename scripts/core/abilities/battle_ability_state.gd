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

static func create(definitions: Array[AbilityDefinition]) -> BattleAbilityState:
	var result := BattleAbilityState.new()
	for definition: AbilityDefinition in definitions: result.catalog.append(definition.copy())
	result.catalog.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return String(a.ability_id) < String(b.ability_id))
	return result

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
	return {"schema_version": 1, "catalog": definitions, "mana": mana, "maximum": maximum, "ledger": ledger.duplicate(true), "serials": Array(serials).duplicate(), "ended": Array(ended).duplicate(), "team": team, "stage": stage, "mage_allowed": mage_allowed}

static func valid(value: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(value, {"schema_version": TYPE_INT, "catalog": TYPE_ARRAY, "mana": TYPE_INT, "maximum": TYPE_INT, "ledger": TYPE_ARRAY, "serials": TYPE_ARRAY, "ended": TYPE_ARRAY, "team": TYPE_INT, "stage": TYPE_STRING, "mage_allowed": TYPE_BOOL}): return false
	if value.schema_version != 1 or value.maximum != 6 or value.mana < 0 or value.mana > value.maximum or value.team not in [0, 1] or value.stage not in ["setup", "active", "closing", "ended", "ready", "terminal"]: return false
	if value.mage_allowed != (value.stage == "active" and value.team == 0): return false
	if value.serials.size() != 2 or value.ended.size() != 2: return false
	for i: int in 2:
		if typeof(value.serials[i]) != TYPE_INT or typeof(value.ended[i]) != TYPE_INT or value.serials[i] < 0 or value.ended[i] < 0 or value.ended[i] > value.serials[i] or value.serials[i] - value.ended[i] > 1: return false
	if value.serials[1] < value.serials[0] or value.serials[1] - value.serials[0] > 1: return false
	if value.stage == "setup" and (value.team != 1 or value.serials != [0, 0] or value.ended != [0, 0] or not value.ledger.is_empty() or value.mana != value.maximum): return false
	if value.stage in ["active", "closing", "ready", "ended"]:
		if value.serials[1 - value.team] != value.ended[1 - value.team]: return false
		if value.serials[1] - value.serials[0] != value.team: return false
	if value.stage in ["active", "closing", "ready"] and value.serials[value.team] - value.ended[value.team] != 1: return false
	if value.stage == "ended" and value.serials[value.team] != value.ended[value.team]: return false
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
		fixed[id] = true
		if not ids.has(id): return false
		if not id.begins_with("mage.") and ids[id].to_dict() != descriptor.to_dict(): return false
	for id: String in ids:
		if fixed.has(id): continue
		if AbilityDefinition.TEST_EFFECTS.has(StringName(id)) or AbilityDefinition.TEST_SUPPORT_EFFECTS.has(StringName(id)): continue
		# Ссылки предметов сверяет envelope; ссылки атак — контекст с AttackRules.
		if id.begins_with("attack:") and id.length() > 7: continue
		if id.begins_with("item_use:") or id.begins_with("item_effect:"): continue
		return false
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

func paid(id: StringName) -> Dictionary:
	var after := to_dict()
	var spell := definition(id)
	if not valid(after) or spell == null or not mage_allowed or remaining(id) > 0 or mana < spell.mana_cost: return {}
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
			if team == 0:
				for record: Dictionary in after.ledger:
					if record.skip_current_end: record.skip_current_end = false
					elif record.remaining > 0: record.remaining -= 1
			after.ended[team] = serial; after.stage = "ended"
		&"begin":
			if stage != "ended" or serials[1 - team] == MAX: return {}
			after.team = 1 - team; after.serials[1 - team] += 1; after.stage = "ready"
			if after.team == 0: after.mana = mini(maximum, mana + 2)
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
