extends Label

## Тестовая панель очереди ходов. ЛКМ — продвинуть ход (`advance_turn`),
## ПКМ по панели — "убить" текущего юнита, чтобы проверить фикс D-4.6.
## Не является частью финальной архитектуры.
##
## ОБНОВЛЕНО ПОСЛЕ АУДИТА: панель теперь проверяет именно тот баг, который
## раньше был невидим. Прежняя версия только пересчитывала порядок по клику,
## поэтому дефект D-4.6 (смерть участника посреди раунда СБРАСЫВАЛА курсор и
## все уже ходившие получали ход снова) проявиться не мог — смерти как
## понятия не существовало, и `unregister_participant()` никто не вызывал.
## Теперь видно: после убийства номер раунда и позиция в очереди сохраняются.

@export var unit_count: int = 4
@export var strategy_resource: TurnOrderStrategy

var _timeline := InitiativeTimeline.new()
var _units: Array[UnitState] = []
var _turn_log: Array[String] = []


func _ready() -> void:
	if strategy_resource == null:
		strategy_resource = load("res://resources/initiative/default_initiative_strategy.tres")
	_timeline.set_strategy(strategy_resource)

	# Детерминированный генератор (R-5): панель должна давать один и тот же
	# расклад при каждом запуске, иначе визуальная проверка невоспроизводима.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911

	for i in range(unit_count):
		var stats := StatsBag.new()
		stats.set_base_value(StatTypes.StatType.INITIATIVE, float(rng.randi_range(1, 10)))
		stats.set_base_value(StatTypes.StatType.STRENGTH, float(rng.randi_range(2, 8)))
		stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
		stats.set_base_value(StatTypes.StatType.BALANCE_MAX, float(rng.randi_range(80, 120)))
		stats.set_base_value(StatTypes.StatType.IMPACT_POWER, float(rng.randi_range(1, 6)))
		stats.set_base_value(StatTypes.StatType.MOVE_RANGE, 4.0)

		var faction := Faction.Type.PLAYER if i % 2 == 0 else Faction.Type.ENEMY
		var unit := UnitState.create(faction, Vector2i(i, 0), stats, "Unit_%d" % (i + 1))
		_units.append(unit)
		_timeline.register_participant(unit)

	_timeline.round_started.connect(_on_round_started)
	_timeline.round_ended.connect(_on_round_ended)

	_timeline.start_battle()

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_refresh_text()


func _on_round_started(round_number: int) -> void:
	_log("--- ROUND %d START ---" % round_number)


func _on_round_ended(round_number: int) -> void:
	_log("--- ROUND %d END ---" % round_number)


func _log(line: String) -> void:
	_turn_log.append(line)
	if _turn_log.size() > 8:
		_turn_log.remove_at(0)


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		var unit := _timeline.advance_turn()
		if unit != null:
			_log("turn: %s (INIT=%.0f)" % [unit.debug_name, unit.get_stat(StatTypes.StatType.INITIATIVE)])
		else:
			_log("no living participants")
		_refresh_text()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_kill_current()
		_refresh_text()


## Убивает текущего юнита — проверка фикса D-4.6: раунд НЕ должен
## перезапуститься, курсор не должен сброситься.
func _kill_current() -> void:
	var current := _timeline.peek_current()
	if current == null or not current.is_alive():
		_log("nothing to kill")
		return
	current.vitals.apply_damage(current.vitals.get_hp_max() * 2.0)
	_timeline.unregister_participant(current)
	_log("KILLED %s (round must stay %d)" % [current.debug_name, _timeline.get_round_number()])


func _refresh_text() -> void:
	var lines: Array[String] = [
		"=== Initiative Timeline (LMB=next turn, RMB=kill current) ===",
		"Round: %d   Alive: player=%d enemy=%d" % [
			_timeline.get_round_number(),
			_timeline.count_alive_of_faction(Faction.Type.PLAYER),
			_timeline.count_alive_of_faction(Faction.Type.ENEMY),
		],
	]

	var order := _timeline.get_current_order()
	var current := _timeline.peek_current()
	for i in range(order.size()):
		var unit := order[i]
		var marker := ">" if unit == current else " "
		lines.append("%s %d. %s (%s, INIT=%.0f)" % [
			marker, i + 1, unit.debug_name,
			Faction.to_string_name(unit.faction),
			unit.get_stat(StatTypes.StatType.INITIATIVE),
		])

	lines.append("")
	lines.append_array(_turn_log)
	text = "\n".join(lines)
