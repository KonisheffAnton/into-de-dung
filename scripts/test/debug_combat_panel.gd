extends Label

## Демонстрация Модуля 6: тестовый "атакующий" и "цель" на клетках сетки.
## Левый клик по цели (primary_action) считает ПРЕВЬЮ (ActionPreview.build,
## без побочных эффектов) и показывает урон/баланс/пуш. Правый клик
## (secondary_action) ПРИМЕНЯЕТ атаку (DamageCalculator.apply) — реально
## вычитает HP и копит Balance. Не является частью финальной архитектуры;
## реальный UI-триггер атаки появится в Модуле 8 (Battle Flow).

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

var _attacker_stats: StatsComponent
var _target_stats: StatsComponent
var _data_provider: GridDataProvider
var _last_preview: DamageInfo
var _hits_applied: int = 0


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	_attacker_stats = StatsComponent.new()
	add_child(_attacker_stats)
	_attacker_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	_attacker_stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)

	_target_stats = StatsComponent.new()
	add_child(_target_stats)
	_target_stats.set_base_value(StatTypes.StatType.HP, 20.0)
	_target_stats.set_base_value(StatTypes.StatType.BALANCE, 0.0)
	_target_stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)

	_data_provider = GridDataProvider.new(_is_cell_walkable, _height_query, Callable())

	InputManager.primary_action.connect(_on_primary_action)
	InputManager.secondary_action.connect(_on_secondary_action)

	_refresh_preview()


func _is_cell_walkable(cell: Vector2i) -> bool:
	return not wall_cells.has(cell)


func _height_query(cell: Vector2i) -> int:
	if elevated_cells.has(cell):
		return elevated_height
	return 0


func _on_primary_action(_screen_pos: Vector2) -> void:
	_refresh_preview()


func _on_secondary_action(_screen_pos: Vector2) -> void:
	_refresh_preview()
	DamageCalculator.apply(_last_preview)
	_hits_applied += 1
	_refresh_preview()


func _refresh_preview() -> void:
	var impact_power := _attacker_stats.get_value(StatTypes.StatType.IMPACT_POWER)
	_last_preview = ActionPreview.build(
		_attacker_stats, _target_stats,
		attacker_cell, target_cell,
		base_damage, impact_power,
		_data_provider, max_height_step
	)
	_update_text()


func _update_text() -> void:
	var hp := _target_stats.get_value(StatTypes.StatType.HP)
	var balance := _target_stats.get_value(StatTypes.StatType.BALANCE)
	var balance_max := _target_stats.get_value(StatTypes.StatType.BALANCE_MAX)

	var push_line := "Push: none"
	if _last_preview.would_break_balance:
		if _last_preview.push_blocked:
			push_line = "Push: BLOCKED (%s), target stays at %s" % [_last_preview.push_blocked_reason, str(_last_preview.push_target_cell)]
		else:
			push_line = "Push: %s -> %s (dir %s)" % [str(target_cell), str(_last_preview.push_target_cell), str(_last_preview.push_direction)]

	text = (
		"=== Combat Preview Demo (LMB=preview, RMB=apply) ===\n" +
		"Target HP: %.1f\n" % hp +
		"Target Balance: %.1f / %.1f\n" % [balance, balance_max] +
		"Preview dmg: %.1f   balance+%.1f   would_break=%s\n" %
			[_last_preview.final_damage, _last_preview.balance_added, _last_preview.would_break_balance] +
		push_line + "\n" +
		"Hits applied: %d" % _hits_applied
	)
