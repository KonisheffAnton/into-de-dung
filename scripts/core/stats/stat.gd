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
##  1. Зафиксирован порядок стадий. Внутри стадии порядок float-операций
##     сохраняется при snapshot через evaluation_order.
##  2. `priority` становится не нужен (удалён из StatModifier).
##  3. Из горячего пути убраны `duplicate()` + `sort_custom()` с лямбдой,
##     которые выполнялись при КАЖДОМ пересчёте (D-4.2). Теперь пересчёт —
##     один линейный проход без аллокаций.

var base_value: float:
	set(value):
		base_value = value
		_cache_dirty = true

var _modifiers: Array[StatModifier] = []
var _modifier_slots: Array[int] = []
var _next_modifier_slot: int = 0
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
	_modifier_slots.append(_next_modifier_slot)
	_next_modifier_slot += 1
	_cache_dirty = true


## Снимает все модификаторы с указанным source_id (например при потере
## предмета/перка/окончании статуса). Возвращает true, если что-то удалено.
func remove_modifiers_by_source(source_id: StringName) -> bool:
	var before := _modifiers.size()
	var kept: Array[StatModifier] = []
	var kept_slots: Array[int] = []
	for i in _modifiers.size():
		var m: StatModifier = _modifiers[i]
		if m.source_id != source_id:
			kept.append(m)
			kept_slots.append(_modifier_slots[i])
	if kept.size() == before:
		return false
	_modifiers = kept
	_modifier_slots = kept_slots
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
	_modifier_slots.clear()
	_cache_dirty = true


func get_modifier_count() -> int:
	return _modifiers.size()


func get_value() -> float:
	if _cache_dirty:
		_recompute_value()
	return _cached_value


func _recompute_value() -> void:
	_cached_value = snapshot_value_unchecked()
	_cache_dirty = false


## Чисто считает формулу, чтобы аудит снимка не прогревал runtime-кэш.
## Вызывать только после проверки графа модификаторов.
func snapshot_value_unchecked() -> float:
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

	return (base_value + flat_sum) * (1.0 + percent_sum) * multiplier


func snapshot_runtime_valid() -> bool:
	if get_script() != Stat or _modifiers.size() != _modifier_slots.size() or _next_modifier_slot < 0 or not is_finite(base_value):
		return false
	for modifier in _modifiers:
		if modifier == null or modifier.get_script() != StatModifier or not is_finite(modifier.value) or int(modifier.operation) < 0 or int(modifier.operation) > 2:
			return false
	var computed := snapshot_value_unchecked()
	if not is_finite(computed) or (not _cache_dirty and (not is_finite(_cached_value) or computed != _cached_value)):
		return false
	var used_slots: Dictionary = {}
	for i in _modifiers.size():
		if _modifier_slots[i] < 0 or _modifier_slots[i] >= _next_modifier_slot or used_slots.has(_modifier_slots[i]):
			return false
		used_slots[_modifier_slots[i]] = true
	return true


func to_snapshot_dict() -> Dictionary:
	if not snapshot_runtime_valid():
		return {}
	return _snapshot_data_unchecked()


## Создаёт DTO только после синхронной проверки того же графа.
func _snapshot_data_unchecked() -> Dictionary:
	var records: Array[Dictionary] = []
	for i in _modifiers.size():
		var m: StatModifier = _modifiers[i]
		records.append({"source_id": String(m.source_id), "instance_id": 0,
			"local_slot": _modifier_slots[i], "evaluation_order": i,
			"operation": int(m.operation), "value": m.value})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["source_id"] != b["source_id"]: return a["source_id"] < b["source_id"]
		return a["local_slot"] < b["local_slot"])
	return {"schema_version": 1, "base_value": base_value,
		"next_modifier_slot": _next_modifier_slot, "modifiers": records}


func snapshot_cache_is_stale() -> bool:
	if _cache_dirty or _modifiers.size() != _modifier_slots.size() or not is_finite(base_value): return false
	for modifier in _modifiers:
		if modifier == null: return false
	var computed := snapshot_value_unchecked()
	return not is_finite(computed) or not is_finite(_cached_value) or computed != _cached_value


static func from_snapshot_dict(data: Dictionary) -> Stat:
	if not validate_snapshot_dict(data): return null
	var stat := Stat.new()
	stat.base_value = data["base_value"]
	stat._next_modifier_slot = data["next_modifier_slot"]
	var records: Array = data["modifiers"]
	var ordered: Array = []
	for i in records.size(): ordered.append(null)
	for record_variant in records:
		var record: Dictionary = record_variant
		var modifier := StatModifier.new(StringName(record["source_id"]),
			record["operation"] as StatModifier.Operation, record["value"])
		ordered[record["evaluation_order"]] = [modifier, record["local_slot"]]
	for item_variant in ordered:
		var item: Array = item_variant
		stat._modifiers.append(item[0] as StatModifier)
		stat._modifier_slots.append(int(item[1]))
	stat._cache_dirty = true
	return stat


static func validate_snapshot_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if not _has_exact_string_keys(d, ["schema_version", "base_value", "next_modifier_slot", "modifiers"]):
		return false
	if typeof(d["schema_version"]) != TYPE_INT or d["schema_version"] != 1 or typeof(d["base_value"]) != TYPE_FLOAT or not is_finite(d["base_value"]) or typeof(d["next_modifier_slot"]) != TYPE_INT or d["next_modifier_slot"] < 0 or typeof(d["modifiers"]) != TYPE_ARRAY:
		return false
	var records: Array = d["modifiers"]
	var slots: Dictionary = {}
	var orders: Dictionary = {}
	var ordered: Array = []
	ordered.resize(records.size())
	for raw in records:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var r: Dictionary = raw
		var required := ["source_id", "instance_id", "local_slot", "evaluation_order", "operation", "value"]
		if not _has_exact_string_keys(r, required):
			return false
		if typeof(r["source_id"]) != TYPE_STRING or typeof(r["instance_id"]) != TYPE_INT or r["instance_id"] != 0 or typeof(r["local_slot"]) != TYPE_INT or typeof(r["evaluation_order"]) != TYPE_INT or typeof(r["operation"]) != TYPE_INT or typeof(r["value"]) != TYPE_FLOAT or not is_finite(r["value"]):
			return false
		if r["local_slot"] < 0 or r["evaluation_order"] < 0 or r["evaluation_order"] >= records.size() or r["operation"] < 0 or r["operation"] > 2 or slots.has(r["local_slot"]) or orders.has(r["evaluation_order"]):
			return false
		slots[r["local_slot"]] = true
		orders[r["evaluation_order"]] = true
		ordered[r["evaluation_order"]] = r
	if not slots.is_empty() and d["next_modifier_slot"] <= 0:
		return false
	for slot in slots:
		if slot >= d["next_modifier_slot"]: return false
	var flat := 0.0
	var percent := 0.0
	var multiply := 1.0
	for ordered_variant in ordered:
		var ordered_record: Dictionary = ordered_variant
		match ordered_record["operation"]:
			StatModifier.Operation.ADD_FLAT: flat += ordered_record["value"]
			StatModifier.Operation.ADD_PERCENT: percent += ordered_record["value"]
			StatModifier.Operation.MULTIPLY: multiply *= ordered_record["value"]
	return is_finite((d["base_value"] + flat) * (1.0 + percent) * multiply)


static func _has_exact_string_keys(value: Dictionary, required: Array) -> bool:
	if value.keys().size() != required.size(): return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key): return false
	return true
