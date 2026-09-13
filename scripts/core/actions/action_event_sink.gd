extends RefCounted
class_name ActionEventSink

## Значения копируются на границе, чтобы внешний presentation слой не менял журнал боя.
func publish(_event: Dictionary) -> void:
	# Базовый sink намеренно ничего не делает: core не должен знать о глобальной шине.
	pass

static func copy_value(value: Variant) -> Variant:
	return _copy_value(value)

static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys(): result[key] = _copy_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_copy_value(item))
		return result
	return value
