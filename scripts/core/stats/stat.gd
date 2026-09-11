extends RefCounted
class_name Stat

## Одна характеристика: неизменяемое base_value + список активных
## StatModifier. Итоговое значение кэшируется и пересчитывается только
## при изменении списка модификаторов или base_value — важно для
## производительности на мобильных устройствах (не пересчитывать на
## каждый доступ/кадр).

var base_value: float
var _modifiers: Array[StatModifier] = []
var _cached_value: float
var _cache_dirty: bool = true


func _init(p_base_value: float = 0.0) -> void:
	base_value = p_base_value
	_cached_value = p_base_value


func set_base_value(value: float) -> void:
	base_value = value
	_cache_dirty = true


func add_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	_cache_dirty = true


## Снимает все модификаторы с указанным source_id (например при потере
## предмета/перка/окончании статуса). Возвращает true, если что-то удалено.
func remove_modifiers_by_source(source_id: StringName) -> bool:
	var before := _modifiers.size()
	_modifiers = _modifiers.filter(func(m: StatModifier) -> bool: return m.source_id != source_id)
	if _modifiers.size() != before:
		_cache_dirty = true
		return true
	return false


func clear_modifiers() -> void:
	_modifiers.clear()
	_cache_dirty = true


func get_value() -> float:
	if _cache_dirty:
		_recompute_value()
	return _cached_value


func _recompute_value() -> void:
	var sorted_modifiers := _modifiers.duplicate()
	sorted_modifiers.sort_custom(func(a: StatModifier, b: StatModifier) -> bool: return a.priority < b.priority)

	var result := base_value
	for modifier in sorted_modifiers:
		match modifier.operation:
			StatModifier.Operation.ADD_FLAT:
				result += modifier.value
			StatModifier.Operation.ADD_PERCENT:
				result += base_value * modifier.value
			StatModifier.Operation.MULTIPLY:
				result *= modifier.value

	_cached_value = result
	_cache_dirty = false
