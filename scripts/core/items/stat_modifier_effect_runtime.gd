extends ItemEffectRuntime
class_name StatModifierEffectRuntime

var _stat_type: StatTypes.StatType
var _operation: StatModifier.Operation
var _value: float

func _init(owner_id: int, item_id: int, effect_id: int, effect_index: int, stat_type: StatTypes.StatType, operation: StatModifier.Operation, value: float) -> void:
	super(owner_id, item_id, effect_id, effect_index)
	_stat_type = stat_type
	_operation = operation
	_value = value

func get_stat_type() -> StatTypes.StatType: return _stat_type
func get_operation() -> StatModifier.Operation: return _operation
func get_value() -> float: return _value
func get_source_key() -> StringName:
	return StringName("p03a/o%d/i%d/e%d" % [_owner_unit_id, _item_instance_id, _effect_instance_id])
