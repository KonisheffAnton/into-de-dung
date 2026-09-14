extends RefCounted
class_name AttackRules

const MAX_ID: int = 9223372036854775807
const MAX_ACTORS: int = 65536
const MAX_PAIRS: int = 65536
const MAX_DEFINITIONS: int = 256
const MAX_DEFINITION_ID_BYTES: int = 128
const PROFILE: StringName = &"flat_melee_v1"
const BALANCE_PROFILE: StringName = &"flat_melee_balance_v1"

var _actors: Array[int] = []
var _pairs: Array[Dictionary] = []
var _definitions: Array[AttackDefinition] = []
var _invalid: bool = false

func _init(admitted_actor_ids: Array[int] = [], allowed_pairs: Array[Dictionary] = [], definitions: Array[AttackDefinition] = []) -> void:
	if admitted_actor_ids.size() > MAX_ACTORS or allowed_pairs.size() > MAX_PAIRS or definitions.size() > MAX_DEFINITIONS:
		_mark_invalid()
		return
	_actors = admitted_actor_ids.duplicate()
	var actors: Dictionary = {}
	for candidate_id in _actors:
		if candidate_id <= 0 or candidate_id >= MAX_ID or actors.has(candidate_id):
			_mark_invalid()
			return
		actors[candidate_id] = true
	var pair_keys: Dictionary = {}
	for raw_pair in allowed_pairs:
		# Чужой Dictionary не копируем до проверки формы: он может содержать цикл или большой graph.
		if not _exact_pair(raw_pair):
			_mark_invalid()
			return
		var actor_id: int = raw_pair["actor_unit_id"]
		var target_id: int = raw_pair["target_unit_id"]
		var pair_key := "%d:%d" % [actor_id, target_id]
		if actor_id <= 0 or actor_id >= MAX_ID or target_id <= 0 or target_id >= MAX_ID or actor_id == target_id or not actors.has(actor_id) or pair_keys.has(pair_key):
			_mark_invalid()
			return
		pair_keys[pair_key] = true
		_pairs.append({"actor_unit_id": actor_id, "target_unit_id": target_id})
	var definition_ids: Dictionary = {}
	for definition in definitions:
		if definition == null or definition.get_script() != AttackDefinition or definition.id == &"" or String(definition.id).to_utf8_buffer().size() > MAX_DEFINITION_ID_BYTES or (definition.profile != PROFILE and definition.profile != BALANCE_PROFILE) or definition_ids.has(definition.id):
			_mark_invalid()
			return
		definition_ids[definition.id] = true
		_definitions.append(_copy_definition(definition))

func _mark_invalid() -> void:
	_invalid = true
	_actors.clear()
	_pairs.clear()
	_definitions.clear()

func copy() -> AttackRules:
	var result := AttackRules.new(_actors, _pairs, _definitions)
	result._invalid = result._invalid or _invalid
	return result

func validate() -> StringName:
	return &"attack/invalid_rules" if _invalid else &""

func allows(actor_id: int, target_id: int) -> bool:
	if validate() != &"" or actor_id <= 0 or actor_id >= MAX_ID or target_id <= 0 or target_id >= MAX_ID:
		return false
	for pair in _pairs:
		if pair.get("actor_unit_id", 0) == actor_id and pair.get("target_unit_id", 0) == target_id:
			return true
	return false

func get_definition(id: StringName) -> AttackDefinition:
	if validate() != &"": return null
	for definition in _definitions:
		if definition != null and definition.id == id:
			return _copy_definition(definition)
	return null

func _validate_structure() -> void:
	var actors: Dictionary = {}
	for id in _actors:
		if id <= 0 or id >= MAX_ID or actors.has(id):
			_invalid = true
			return
		actors[id] = true
	var pairs: Dictionary = {}
	for pair in _pairs:
		if not _exact_pair(pair):
			_invalid = true
			return
		var actor: int = pair["actor_unit_id"]
		var target: int = pair["target_unit_id"]
		var pair_key := "%d:%d" % [actor, target]
		if actor <= 0 or actor >= MAX_ID or target <= 0 or target >= MAX_ID or actor == target or not actors.has(actor) or pairs.has(pair_key):
			_invalid = true
			return
		pairs[pair_key] = true
	var ids: Dictionary = {}
	for definition in _definitions:
		if definition == null or definition.get_script() != AttackDefinition or definition.id == &"" or String(definition.id).to_utf8_buffer().size() > MAX_DEFINITION_ID_BYTES or (definition.profile != PROFILE and definition.profile != BALANCE_PROFILE) or ids.has(definition.id):
			_invalid = true
			return
		ids[definition.id] = true

static func _copy_definition(source: AttackDefinition) -> AttackDefinition:
	var copy := AttackDefinition.new()
	copy.id = source.id
	copy.profile = source.profile
	return copy

static func _exact_pair(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var pair: Dictionary = value
	if pair.size() != 2: return false
	for key in pair:
		if typeof(key) != TYPE_STRING or key not in ["actor_unit_id", "target_unit_id"] or typeof(pair[key]) != TYPE_INT:
			return false
	return true
