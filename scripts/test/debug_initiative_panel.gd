extends Label

## Тестовая панель: создаёт N юнитов со случайными статами (INITIATIVE,
## STRENGTH, BALANCE_MAX, IMPACT_POWER), строит очередь ходов через
## InitiativeTimeline + SimpleInitiativeStrategy и выводит текст очереди.
## Клик по панели пересчитывает порядок заново (демонстрация Strategy
## pattern и случайного tiebreak). Не является частью финальной архитектуры.

@export var unit_count: int = 4
@export var strategy_resource: TurnOrderStrategy

var _timeline := InitiativeTimeline.new()
var _unit_names: Dictionary = {} # StatsComponent -> String
var _stats_nodes: Array[StatsComponent] = []


func _ready() -> void:
	if strategy_resource == null:
		strategy_resource = load("res://resources/initiative/default_initiative_strategy.tres")
	_timeline.set_strategy(strategy_resource)

	for i in range(unit_count):
		var stats := StatsComponent.new()
		add_child(stats)

		var initiative := randi_range(1, 10)
		var strength := randi_range(2, 8)
		var balance_max := randi_range(80, 120)
		var impact_power := randi_range(1, 6)

		stats.set_base_value(StatTypes.StatType.INITIATIVE, float(initiative))
		stats.set_base_value(StatTypes.StatType.STRENGTH, float(strength))
		stats.set_base_value(StatTypes.StatType.BALANCE_MAX, float(balance_max))
		stats.set_base_value(StatTypes.StatType.IMPACT_POWER, float(impact_power))

		var unit_name := "Unit_%d" % (i + 1)
		_unit_names[stats] = unit_name
		_stats_nodes.append(stats)
		_timeline.register_participant(stats)

	_refresh_text()
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_timeline.recompute_order()
		_refresh_text()


func _refresh_text() -> void:
	var lines: Array[String] = ["=== Initiative Timeline (click to reroll tiebreak) ==="]
	var order := _timeline.get_current_order()
	for i in range(order.size()):
		var stats: StatsComponent = order[i]
		var name: String = _unit_names[stats]
		var initiative := stats.get_value(StatTypes.StatType.INITIATIVE)
		var strength := stats.get_value(StatTypes.StatType.STRENGTH)
		lines.append("%d. %s  (INIT=%.0f, STR=%.0f)" % [i + 1, name, initiative, strength])
	text = "\n".join(lines)
