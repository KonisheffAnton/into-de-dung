extends RefCounted
class_name ActionResources

const MAX_ID: int = 9223372036854775807
const MAX_COUNTER: int = 4096

var _owner_unit_id: int
var _main_left: int
var _bonus_left: int

func _init(owner_unit_id: int, main_left: int = 0, bonus_left: int = 0) -> void:
	_owner_unit_id = owner_unit_id
	_main_left = main_left
	_bonus_left = bonus_left

func validate(expected_owner_unit_id: int) -> StringName:
	if _owner_unit_id != expected_owner_unit_id or _owner_unit_id < 1 or _owner_unit_id >= MAX_ID:
		return &"resources/owner_id"
	if _main_left < 0 or _main_left > MAX_COUNTER or _bonus_left < 0 or _bonus_left > MAX_COUNTER:
		return &"resources/value"
	return &""

func get_owner_unit_id() -> int:
	return _owner_unit_id

func get_main_left() -> int:
	return _main_left

func get_bonus_left() -> int:
	return _bonus_left

func try_spend_main(amount: int) -> bool:
	if validate(_owner_unit_id) != &"" or amount <= 0 or amount > _main_left:
		return false
	_main_left -= amount
	return true

func _set_for_refill(main_left: int, bonus_left: int) -> void:
	# Назначение доступно только UnitState после полной атомарной проверки.
	_main_left = main_left
	_bonus_left = bonus_left

func to_snapshot_dict() -> Dictionary:
	if validate(_owner_unit_id) != &"":
		return {}
	return {"schema_version": 1, "owner_unit_id": _owner_unit_id,
		"main_left": _main_left, "bonus_left": _bonus_left}

static func from_snapshot_dict(data: Dictionary, expected_owner_unit_id: int) -> ActionResources:
	if typeof(data) != TYPE_DICTIONARY or not _has_exact_keys(data, ["schema_version", "owner_unit_id", "main_left", "bonus_left"]):
		return null
	for key in ["schema_version", "owner_unit_id", "main_left", "bonus_left"]:
		if typeof(data[key]) != TYPE_INT:
			return null
	if data["schema_version"] != 1 or data["owner_unit_id"] != expected_owner_unit_id:
		return null
	var result := ActionResources.new(data["owner_unit_id"], data["main_left"], data["bonus_left"])
	return result if result.validate(expected_owner_unit_id) == &"" else null

static func validate_snapshot_dict(data: Variant, expected_owner_unit_id: int) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if not _has_exact_keys(d, ["schema_version", "owner_unit_id", "main_left", "bonus_left"]):
		return false
	if typeof(d["schema_version"]) != TYPE_INT or d["schema_version"] != 1:
		return false
	if typeof(d["owner_unit_id"]) != TYPE_INT or typeof(d["main_left"]) != TYPE_INT or typeof(d["bonus_left"]) != TYPE_INT:
		return false
	var result := ActionResources.new(d["owner_unit_id"], d["main_left"], d["bonus_left"])
	return result.validate(expected_owner_unit_id) == &""

static func _has_exact_keys(value: Dictionary, required: Array) -> bool:
	if value.size() != required.size():
		return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key):
			return false
	return true
