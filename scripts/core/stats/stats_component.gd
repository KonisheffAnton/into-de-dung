extends Node
class_name StatsComponent

## Агрегатор набора характеристик юнита (Dictionary[StatType, Stat]).
## Присоединяется как child-нода к юниту/актёру. Не содержит игровой
## логики (урон, инициатива и т.п.) — только хранение и доступ к статам,
## плюс сигнал изменения для UI/Event Bus (Модуль 5)/эффектов.

signal stat_changed(stat_type: StatTypes.StatType, old_value: float, new_value: float)

var _stats: Dictionary = {} # StatTypes.StatType -> Stat


func _ready() -> void:
	pass


## Инициализирует стат с базовым значением, если он ещё не создан.
## Использовать при спавне юнита с данными из его Resource-конфига.
func set_base_value(type: StatTypes.StatType, value: float) -> void:
	var stat := _get_or_create_stat(type)
	var old_value := stat.get_value()
	stat.set_base_value(value)
	_emit_if_changed(type, old_value)


func get_stat(type: StatTypes.StatType) -> Stat:
	return _get_or_create_stat(type)


func get_value(type: StatTypes.StatType) -> float:
	return _get_or_create_stat(type).get_value()


func add_modifier(type: StatTypes.StatType, modifier: StatModifier) -> void:
	var stat := _get_or_create_stat(type)
	var old_value := stat.get_value()
	stat.add_modifier(modifier)
	_emit_if_changed(type, old_value)


## Снимает модификаторы указанного источника со ВСЕХ характеристик
## (удобно при потере предмета/перка, который мог менять несколько статов).
func remove_modifiers_by_source(source_id: StringName) -> void:
	for type in _stats.keys():
		var stat: Stat = _stats[type]
		var old_value := stat.get_value()
		if stat.remove_modifiers_by_source(source_id):
			_emit_if_changed(type, old_value)


func _get_or_create_stat(type: StatTypes.StatType) -> Stat:
	if not _stats.has(type):
		_stats[type] = Stat.new(0.0)
	return _stats[type]


func _emit_if_changed(type: StatTypes.StatType, old_value: float) -> void:
	var stat: Stat = _stats[type]
	var new_value: float = stat.get_value()
	if not is_equal_approx(old_value, new_value):
		stat_changed.emit(type, old_value, new_value)
