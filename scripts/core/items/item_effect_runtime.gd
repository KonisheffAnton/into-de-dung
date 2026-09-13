extends RefCounted
class_name ItemEffectRuntime

var _owner_unit_id: int
var _item_instance_id: int
var _effect_instance_id: int
var _effect_index: int
var _active := false

func _init(owner_id: int, item_id: int, effect_id: int, effect_index: int) -> void:
	_owner_unit_id = owner_id
	_item_instance_id = item_id
	_effect_instance_id = effect_id
	_effect_index = effect_index

func get_owner_unit_id() -> int: return _owner_unit_id
func get_item_instance_id() -> int: return _item_instance_id
func get_effect_instance_id() -> int: return _effect_instance_id
func get_effect_index() -> int: return _effect_index
func is_active() -> bool: return _active
func _set_active(value: bool) -> void: _active = value
