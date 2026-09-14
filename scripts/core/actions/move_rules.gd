extends RefCounted
class_name MoveRules

const MAX_ID: int = 9223372036854775807
const MAX_ALLOWLIST_SIZE: int = 65536

var _admitted_unit_ids: Array[int] = []
var _max_height_step: int = 0
var _invalid: bool = false
var _profile: StringName = &"legacy_move_v1"

func _init(admitted_unit_ids: Array[int] = [], max_height_step: int = 0, profile: StringName = &"legacy_move_v1") -> void:
	_profile = profile
	if profile != &"legacy_move_v1" and profile != &"spatial_move_v1":
		_invalid = true
	if profile == &"spatial_move_v1" and max_height_step != 1:
		_invalid = true
	# Слишком большой список не копируем: это сохраняет bounded admission при повреждённом payload.
	if admitted_unit_ids.size() > MAX_ALLOWLIST_SIZE:
		_invalid = true
		_max_height_step = max_height_step
		return
	_admitted_unit_ids = admitted_unit_ids.duplicate()
	_max_height_step = max_height_step
	for unit_id in _admitted_unit_ids:
		if unit_id <= 0 or unit_id >= MAX_ID:
			_invalid = true
			break
	var seen: Dictionary = {}
	for unit_id in _admitted_unit_ids:
		if seen.has(unit_id):
			_invalid = true
			break
		seen[unit_id] = true
	if max_height_step < 0 or max_height_step > 2147483647:
		_invalid = true

func copy() -> MoveRules:
	var result := MoveRules.new(_admitted_unit_ids, _max_height_step, _profile)
	result._invalid = _invalid
	return result

func validate() -> StringName:
	if _invalid:
		return &"move/invalid_rules"
	return &""

func allows(unit_id: int) -> bool:
	if validate() != &"" or unit_id <= 0 or unit_id >= MAX_ID:
		return false
	return _admitted_unit_ids.has(unit_id)

func get_max_height_step() -> int:
	return _max_height_step

func get_profile() -> StringName:
	return _profile
