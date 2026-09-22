extends RefCounted
class_name ItemInstance

## Экземпляр отделён от Resource: одинаковое определение может быть выдано
## нескольким владельцам без совместного runtime-состояния.
var _definition: ItemDef
var _definition_id: StringName
var _item_id: int
var _owner_id: int
var _effects: Array[ItemEffectRuntime] = []
var _active := false
var _placement := 0
var _charges_left: int
var armor_remaining: int = 0
var armor_origin_owner: int = 0
var armor_origin_item: int = 0

func _init(definition: ItemDef, owner_id: int, item_id: int, effects: Array[ItemEffectRuntime], charges_left: int = -1) -> void:
	_definition = definition
	_definition_id = definition.id
	_owner_id = owner_id
	_item_id = item_id
	_effects = effects.duplicate()
	_charges_left = definition.max_charges if charges_left < 0 else charges_left
	armor_remaining = definition.armor_max
	armor_origin_owner = owner_id
	armor_origin_item = item_id

func get_definition() -> ItemDef:
	# Печать возвращает копию, чтобы внешний код не мог изменить зафиксированный runtime.
	return _definition.duplicate(true) as ItemDef if _definition.use_summon else _definition
func get_definition_id() -> StringName: return _definition_id
func get_item_instance_id() -> int: return _item_id
func get_owner_unit_id() -> int: return _owner_id
func get_effects() -> Array[ItemEffectRuntime]: return _effects.duplicate()
func get_charges_left() -> int: return _charges_left
func is_active() -> bool: return _active
func _set_active(value: bool) -> void: _active = value
func _set_placement(value: int) -> void: _placement = value
func _get_placement() -> int: return _placement
