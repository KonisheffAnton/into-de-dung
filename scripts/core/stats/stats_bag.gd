extends RefCounted
class_name StatsBag

## Набор ПРОИЗВОДНЫХ характеристик юнита (Attributes, R-2).
##
## ЗАМЕНЯЕТ `StatsComponent : Node` по двум причинам:
##
## 1. (R-3) `StatsComponent` был `Node` — то есть чистая игровая логика была
##    привязана к дереву сцены. Ни один боевой расчёт нельзя было выполнить без
##    `SceneTree`: ни в unit-тесте, ни в изолированной симуляции для
##    AI-lookahead, ни в sandbox-прогоне превью (R-6). `RefCounted` снимает это
##    ограничение и при этом дешевле по памяти.
##
## 2. (C-1) `StatsComponent` де-факто использовался как ИДЕНТИЧНОСТЬ юнита —
##    ссылка на него лежала в `DamageInfo.attacker/target`, в
##    `InitiativeTimeline._participants`, в сигналах шины. "Мешок
##    характеристик" не должен быть первичным ключом личности: теперь
##    идентичность — это `UnitId`, а `StatsBag` — лишь одно из полей
##    `UnitState`.
##
## ИНКАПСУЛЯЦИЯ (фикс части C-2): наружу НЕ отдаётся мутабельный `Stat`.
## Раньше публичный `get_stat()` позволял писать значение напрямую
## (`get_stat(HP).set_base_value(...)`), что обходило сигнал `stat_changed` —
## поэтому UI не видел изменений HP, хотя сигнал формально существовал.
## Здесь все мутации проходят через методы этого класса, что гарантирует
## и инвариант, и сигнал.

## Характеристика изменилась (базовое значение или набор модификаторов).
signal stat_changed(stat_type: StatTypes.StatType, old_value: float, new_value: float)

var _stats: Dictionary = {} # StatTypes.StatType -> Stat


## Создаёт bag из словаря базовых значений — основной способ инициализации
## юнита из его определения (`UnitDef.tres`).
static func from_base_values(values: Dictionary) -> StatsBag:
	var bag := StatsBag.new()
	for key in values.keys():
		var type: StatTypes.StatType = key
		var value: float = values[key]
		bag.set_base_value(type, value)
	return bag


# --- Чтение ----------------------------------------------------------------

func get_value(type: StatTypes.StatType) -> float:
	if not _stats.has(type):
		return 0.0
	var stat: Stat = _stats[type]
	return stat.get_value()


## Целочисленное чтение для статов, которые по смыслу дискретны
## (MOVE_RANGE в очках, ARMOR). Округление — единое в одном месте,
## чтобы разные системы не округляли по-разному.
func get_value_int(type: StatTypes.StatType) -> int:
	return int(roundf(get_value(type)))


func get_base_value(type: StatTypes.StatType) -> float:
	if not _stats.has(type):
		return 0.0
	var stat: Stat = _stats[type]
	return stat.base_value


func has_stat(type: StatTypes.StatType) -> bool:
	return _stats.has(type)


func get_declared_types() -> Array:
	return _stats.keys()


# --- Мутация ---------------------------------------------------------------

## Устанавливает БАЗОВОЕ значение характеристики (инициализация юнита, рост
## от уровня). НЕ для записи текущих HP/Balance — они в `Vitals` (R-2).
func set_base_value(type: StatTypes.StatType, value: float) -> void:
	var stat := _get_or_create_stat(type)
	var old_value := stat.get_value()
	stat.set_base_value(value)
	_emit_if_changed(type, old_value)


func add_modifier(type: StatTypes.StatType, modifier: StatModifier) -> void:
	if modifier == null:
		return
	var stat := _get_or_create_stat(type)
	var old_value := stat.get_value()
	stat.add_modifier(modifier)
	_emit_if_changed(type, old_value)


## Снимает модификаторы указанного источника со ВСЕХ характеристик — так
## потеря предмета/перка/статуса откатывает все его эффекты одним вызовом,
## без необходимости помнить, что именно он менял.
func remove_modifiers_by_source(source_id: StringName) -> void:
	for key in _stats.keys():
		var type: StatTypes.StatType = key
		var stat: Stat = _stats[type]
		var old_value := stat.get_value()
		if stat.remove_modifiers_by_source(source_id):
			_emit_if_changed(type, old_value)


func has_modifiers_from_source(source_id: StringName) -> bool:
	for key in _stats.keys():
		var stat: Stat = _stats[key]
		if stat.has_modifiers_from_source(source_id):
			return true
	return false


# --- Внутреннее ------------------------------------------------------------

func _get_or_create_stat(type: StatTypes.StatType) -> Stat:
	if not _stats.has(type):
		_stats[type] = Stat.new(0.0)
	var stat: Stat = _stats[type]
	return stat


func _emit_if_changed(type: StatTypes.StatType, old_value: float) -> void:
	var stat: Stat = _stats[type]
	var new_value := stat.get_value()
	if not is_equal_approx(old_value, new_value):
		stat_changed.emit(type, old_value, new_value)


# --- Сериализация (R-4) ----------------------------------------------------
## Сохраняются ТОЛЬКО базовые значения. Модификаторы намеренно НЕ сохраняются
## здесь: они являются производными от источников (предметы, перки, статусы),
## которые сериализуются сами и заново применят свои эффекты при загрузке.
## Иначе модификаторы удвоились бы: один раз из сейва bag'а, второй раз при
## восстановлении предметов.

func to_dict() -> Dictionary:
	var bases: Dictionary = {}
	for key in _stats.keys():
		var type: StatTypes.StatType = key
		var stat: Stat = _stats[type]
		bases[str(int(type))] = stat.base_value
	return {"bases": bases}


static func from_dict(data: Dictionary) -> StatsBag:
	var bag := StatsBag.new()
	var bases: Dictionary = data.get("bases", {})
	for key in bases.keys():
		var type_int := int(String(key))
		var value: float = bases[key]
		bag.set_base_value(type_int as StatTypes.StatType, value)
	return bag
