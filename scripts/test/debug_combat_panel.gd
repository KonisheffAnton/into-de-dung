extends Label

## Демонстрация боевой системы: тестовый "атакующий" и "цель" на сетке.
## ЛКМ — ПРЕВЬЮ (без побочных эффектов), ПКМ — ПРИМЕНИТЬ атаку.
## Не финальная архитектура: реальный UI-триггер атаки появится в Battle Flow.
##
## ОБНОВЛЕНО ПОСЛЕ АУДИТА. Панель теперь ещё и РЕГРЕССИОННАЯ ПРОВЕРКА
## дефекта C-2: цели выдан модификатор HP_MAX (+5 от "амулета"). На старой
## модели (HP как Stat.base_value) каждый удар ВПЕКАЛ бы этот модификатор в
## базу, и HP росло бы от полученного урона. Строка "C-2 check" показывает,
## что теперь HP только убывает, а HP_MAX остаётся производным.

@export var grid_config: IsoGridConfig
@export var attacker_cell: Vector2i = Vector2i(1, 1)
@export var target_cell: Vector2i = Vector2i(2, 1)
@export var base_damage: float = 1.0
@export var max_height_step: int = 1

## Стены/высоты копируются из той же тестовой карты, что и GridVisualizer,
## чтобы push-резолвинг проверялся на одних и тех же данных.
@export var wall_cells: Array[Vector2i] = []
@export var elevated_cells: Array[Vector2i] = []
@export var elevated_height: int = 1

const AMULET_SOURCE: StringName = &"debug_amulet"

var _attacker: UnitState
var _target: UnitState
var _data_provider: GridDataProvider
var _sink: EventSink
var _last_preview: DamageInfo
var _hits_applied: int = 0
var _death_reported: bool = false


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	var attacker_stats := StatsBag.new()
	attacker_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	attacker_stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)
	_attacker = UnitState.create(Faction.Type.ENEMY, attacker_cell, attacker_stats, "Attacker")

	var target_stats := StatsBag.new()
	target_stats.set_base_value(StatTypes.StatType.HP_MAX, 15.0)
	target_stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
	# "Амулет" +5 к максимуму HP — раньше именно такой модификатор ломал
	# расчёт урона (C-2). Добавляем ДО создания юнита, чтобы стартовое HP
	# сразу было полным (20 = 15 базовых + 5 от амулета).
	target_stats.add_modifier(
		StatTypes.StatType.HP_MAX,
		StatModifier.new(AMULET_SOURCE, StatModifier.Operation.ADD_FLAT, 5.0)
	)
	_target = UnitState.create(Faction.Type.PLAYER, target_cell, target_stats, "Target")

	# Реальный бой пробрасывает события в шину через адаптер (R-3).
	_sink = GameEventBusSink.new()

	_data_provider = GridDataProvider.new(_is_cell_walkable, _height_query, Callable())

	GameEventBus.unit_died.connect(_on_unit_died)
	InputManager.primary_action.connect(_on_primary_action)
	InputManager.secondary_action.connect(_on_secondary_action)

	_refresh_preview()


func _is_cell_walkable(cell: Vector2i) -> bool:
	return not wall_cells.has(cell)


func _height_query(cell: Vector2i) -> int:
	if elevated_cells.has(cell):
		return elevated_height
	return 0


func _on_unit_died(unit: UnitState, _source: Variant) -> void:
	if unit == _target:
		_death_reported = true
		_refresh_preview()


func _on_primary_action(_screen_pos: Vector2) -> void:
	_refresh_preview()


func _on_secondary_action(_screen_pos: Vector2) -> void:
	_refresh_preview()
	if _last_preview != null and _target.is_alive():
		DamageCalculator.apply(_last_preview, _sink)
		_hits_applied += 1
	_refresh_preview()


func _refresh_preview() -> void:
	var impact_power := _attacker.get_stat(StatTypes.StatType.IMPACT_POWER)
	_last_preview = ActionPreview.build(
		_attacker, _target,
		attacker_cell, target_cell,
		base_damage, impact_power,
		_data_provider, max_height_step
	)
	_update_text()


func _update_text() -> void:
	var vitals := _target.vitals
	var hp := vitals.get_hp()
	var hp_max := vitals.get_hp_max()
	var balance := vitals.get_balance()
	var balance_max := vitals.get_balance_max()

	var push_line := "Push: none"
	if _last_preview.would_break_balance:
		if _last_preview.push_blocked:
			push_line = "Push: BLOCKED (%s), target stays at %s" % [
				_last_preview.push_blocked_reason, str(_last_preview.push_target_cell)
			]
		else:
			push_line = "Push: %s -> %s (dir %s)" % [
				str(target_cell), str(_last_preview.push_target_cell),
				str(_last_preview.push_direction)
			]

	var status := "ALIVE"
	if not _target.is_alive():
		status = "DEAD (unit_died fired: %s)" % _death_reported

	text = (
		"=== Combat Demo (LMB=preview, RMB=apply) ===\n" +
		"Target HP: %.1f / %.1f   [%s]\n" % [hp, hp_max, status] +
		"Target Balance: %.1f / %.1f\n" % [balance, balance_max] +
		"Preview: %s\n" % _last_preview.to_debug_string() +
		push_line + "\n" +
		"Hits applied: %d\n" % _hits_applied +
		"C-2 check: HP_MAX base=15 +5 amulet = %.1f (must stay 20.0 forever)" % hp_max
	)
