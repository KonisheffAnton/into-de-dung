extends Label

## Демонстрация боевой системы на реальной `BattleBoard`.
## ЛКМ — ПРЕВЬЮ (без побочных эффектов), ПКМ — ПРИМЕНИТЬ атаку.
## Не финальная архитектура: реальный UI-триггер атаки появится в Battle Flow.
##
## ПАНЕЛЬ СЛУЖИТ ДВУМЯ РЕГРЕССИОННЫМИ ПРОВЕРКАМИ:
##
## 1. ДЕФЕКТ C-2. Цели выдан модификатор HP_MAX (+5 от "амулета"). На старой
##    модели (HP как `Stat.base_value`) каждый удар ВПЕКАЛ бы этот модификатор
##    в базу, и HP росло бы от полученного урона. Строка "C-2 check" должна
##    всегда показывать 20.0.
##
## 2. ДЕФЕКТ C-4 (шаг 0.4). За целью поставлен третий юнит-"блокер", поэтому
##    при срыве Баланса цель ВРЕЗАЕТСЯ в него, а не пролетает сквозь.
##    Раньше это было невыразимо: резолвер толкания не знал о юнитах и
##    сообщал об успешном перемещении в занятую клетку.

@export var grid_config: IsoGridConfig
@export var board_size: Vector2i = Vector2i(8, 8)
@export var attacker_cell: Vector2i = Vector2i(1, 1)
@export var target_cell: Vector2i = Vector2i(2, 1)
## Юнит за целью — чтобы продемонстрировать столкновение при толчке.
@export var blocker_cell: Vector2i = Vector2i(3, 1)
@export var base_damage: float = 1.0
@export var max_height_step: int = 1

## Стены/высоты/пропасти копируются из той же тестовой карты, что и
## GridVisualizer, чтобы push-резолвинг проверялся на одних данных.
@export var wall_cells: Array[Vector2i] = []
@export var hazard_cells: Array[Vector2i] = []
@export var elevated_cells: Array[Vector2i] = []
@export var elevated_height: int = 1

const AMULET_SOURCE: StringName = &"debug_amulet"

var _board: BattleBoard
var _attacker: UnitState
var _target: UnitState
var _blocker: UnitState
var _sink: EventSink
var _last_preview: DamageInfo
var _hits_applied: int = 0
var _death_reported: bool = false


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	_build_board()
	_spawn_units()

	# Реальный бой пробрасывает события в шину через адаптер (R-3).
	_sink = GameEventBusSink.new()

	GameEventBus.unit_died.connect(_on_unit_died)
	InputManager.primary_action.connect(_on_primary_action)
	InputManager.secondary_action.connect(_on_secondary_action)

	_refresh_preview()


## Доска — единственный источник правды о террейне и occupancy (C-4).
## Раньше эти же данные жили в @export-массивах каждой панели отдельно,
## и правила проходимости у разных систем расходились.
func _build_board() -> void:
	_board = BattleBoard.new(board_size.x, board_size.y)

	for cell in wall_cells:
		_board.set_terrain(cell, TerrainType.Type.WALL)
	for cell in hazard_cells:
		_board.set_terrain(cell, TerrainType.Type.HAZARD)
	for cell in elevated_cells:
		_board.set_height(cell, elevated_height)


func _spawn_units() -> void:
	var attacker_stats := StatsBag.new()
	attacker_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	attacker_stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)
	attacker_stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
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

	var blocker_stats := StatsBag.new()
	blocker_stats.set_base_value(StatTypes.StatType.HP_MAX, 12.0)
	blocker_stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
	_blocker = UnitState.create(Faction.Type.PLAYER, blocker_cell, blocker_stats, "Blocker")

	_board.add_unit(_attacker)
	_board.add_unit(_target)
	_board.add_unit(_blocker)


func _on_unit_died(unit: UnitState, _source: Variant) -> void:
	if unit == _target:
		_death_reported = true
	# Мёртвый освобождает клетку — иначе труп продолжал бы блокировать
	# движение и толкание.
	_board.clear_occupancy(unit)
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
		_attacker.cell, _target.cell,
		base_damage, impact_power,
		_board, max_height_step
	)
	_update_text()


func _update_text() -> void:
	var vitals := _target.vitals
	var hp := vitals.get_hp()
	var hp_max := vitals.get_hp_max()
	var balance := vitals.get_balance()
	var balance_max := vitals.get_balance_max()

	var status := "ALIVE"
	if not _target.is_alive():
		status = "DEAD (unit_died fired: %s)" % _death_reported

	var push_line := "Push: (balance not broken yet)"
	if _last_preview.push_result != null:
		push_line = "Push: %s" % _last_preview.push_result.to_debug_string()
		var victim := _last_preview.get_collision_victim()
		if victim != null:
			push_line += "  -> BOTH take collision damage (%s)" % victim.debug_name

	text = (
		"=== Combat Demo on BattleBoard (LMB=preview, RMB=apply) ===\n" +
		"Target HP: %.1f / %.1f   [%s]\n" % [hp, hp_max, status] +
		"Target Balance: %.1f / %.1f\n" % [balance, balance_max] +
		"Preview dmg: %.1f%s\n" % [
			_last_preview.final_damage, "  (KILL)" if _last_preview.would_kill else ""
		] +
		push_line + "\n" +
		"Hits applied: %d   board_version: %d\n" % [_hits_applied, _board.board_version] +
		"C-2 check: HP_MAX base=15 +5 amulet = %.1f (must stay 20.0)\n" % hp_max +
		"C-4 check: %s stands at %s behind target" % [_blocker.debug_name, str(_blocker.cell)]
	)
