extends RefCounted
class_name Stat

## Одна ПРОИЗВОДНАЯ характеристика (Attribute, R-2): base_value плюс список
## активных StatModifier. Итоговое значение кэшируется и пересчитывается
## только при изменении модификаторов или базы — важно для мобилок.
##
## КОНВЕЙЕР СТАДИЙ (фикс D-4.1). Формула ЖЁСТКО фиксирована:
##
##     (base + Σ flat) * (1 + Σ percent) * Π multiply
##
## Раньше модификаторы применялись в цикле, отсортированном по `priority`,
## причём ADD_PERCENT считался от `base_value`, а MULTIPLY — от накопленного
## результата. Это семантически неопределённо: итог зависел от расстановки
## приоритетов, а комментарий в StatModifier описывал соглашение ("flat,
## потом percent, потом multiply"), которое код НЕ обеспечивал.
##
## Фиксированный конвейер даёт три выигрыша:
##  1. Результат НЕ зависит от порядка добавления модификаторов — критично
##     для сохранений (R-4): загрузка в другом порядке даёт то же значение.
##  2. `priority` становится не нужен (удалён из StatModifier).
##  3. Из горячего пути убраны `duplicate()` + `sort_custom()` с лямбдой,
##     которые выполнялись при КАЖДОМ пересчёте (D-4.2). Теперь пересчёт —
##     один линейный проход без аллокаций.

var base_value: float:
	set(value):
		base_value = value
		_cache_dirty = true

var _modifiers: Array[StatModifier] = []
var _cached_value: float = 0.0
var _cache_dirty: bool = true


func _init(p_base_value: float = 0.0) -> void:
	base_value = p_base_value


## ВНИМАНИЕ (R-2): использовать ТОЛЬКО для настройки характеристики
## (инициализация юнита, рост от уровня). НИКОГДА не записывать сюда текущее
## значение ресурса вида `get_value() - damage` — это дефект C-2.
## Текущие HP/Balance живут в `Vitals`, а не здесь.
func set_base_value(value: float) -> void:
	base_value = value


func add_modifier(modifier: StatModifier) -> void:
	if modifier == null:
		return
	_modifiers.append(modifier)
	_cache_dirty = true


## Снимает все модификаторы с указанным source_id (например при потере
## предмета/перка/окончании статуса). Возвращает true, если что-то удалено.
func remove_modifiers_by_source(source_id: StringName) -> bool:
	var before := _modifiers.size()
	var kept: Array[StatModifier] = []
	for m in _modifiers:
		if m.source_id != source_id:
			kept.append(m)
	if kept.size() == before:
		return false
	_modifiers = kept
	_cache_dirty = true
	return true


func has_modifiers_from_source(source_id: StringName) -> bool:
	for m in _modifiers:
		if m.source_id == source_id:
			return true
	return false


func clear_modifiers() -> void:
	if _modifiers.is_empty():
		return
	_modifiers.clear()
	_cache_dirty = true


func get_modifier_count() -> int:
	return _modifiers.size()


func get_value() -> float:
	if _cache_dirty:
		_recompute_value()
	return _cached_value


func _recompute_value() -> void:
	var flat_sum := 0.0
	var percent_sum := 0.0
	var multiplier := 1.0

	# Один линейный проход, без сортировки и без копий массива.
	for modifier in _modifiers:
		match modifier.operation:
			StatModifier.Operation.ADD_FLAT:
				flat_sum += modifier.value
			StatModifier.Operation.ADD_PERCENT:
				percent_sum += modifier.value
			StatModifier.Operation.MULTIPLY:
				multiplier *= modifier.value

	_cached_value = (base_value + flat_sum) * (1.0 + percent_sum) * multiplier
	_cache_dirty = false
