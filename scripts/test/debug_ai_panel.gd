extends Label

## Демонстрация Модуля 7 (Extensible Utility AI). Один тестовый враг
## (enemy_cell) с подключаемым AIBehaviorProfile (Aggressor/Blocker — .tres,
## подмена без изменения кода), тестовый "игрок" (player_cell) и тестовый
## союзник ИИ (ally_cell, релевантен для Blocker/HoldPositionConsideration).
## ЛКМ по панели — РАНДОМИЗИРУЕТ ситуацию (позиции player/ally на сетке,
## HP и накопленный Balance игрока, а также переключает behavior_profile
## между Aggressor/Blocker) и пересчитывает UtilityAIController.decide(),
## чтобы наглядно показать, что разные роли и разная ситуация дают разные
## решения без единого детерминированного результата. Не является частью
## финальной архитектуры; реальный вызов ИИ в бою появится в Модуле 8
## (Battle Flow State Machine).

@export var grid_config: IsoGridConfig
@export var behavior_profile: AIBehaviorProfile
@export var grid_width: int = 8
@export var grid_height: int = 8
@export var enemy_cell: Vector2i = Vector2i(5, 1)
@export var player_cell: Vector2i = Vector2i(2, 1)
@export var ally_cell: Vector2i = Vector2i(6, 1)
@export var hazard_cells: Array[Vector2i] = []
@export var wall_cells: Array[Vector2i] = []
@export var elevated_cells: Array[Vector2i] = []
@export var elevated_height: int = 1
@export var base_damage: float = 1.0
@export var attack_range: int = 1
@export var max_height_step: int = 1

var _enemy_stats: StatsComponent
var _player_stats: StatsComponent
var _data_provider: GridDataProvider
var _pathfinder := GridPathfinder.new()
var _last_action: AIAction

var _aggressor_profile: AIBehaviorProfile
var _blocker_profile: AIBehaviorProfile


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	_aggressor_profile = load("res://resources/ai/aggressor_profile.tres")
	_blocker_profile = load("res://resources/ai/blocker_profile.tres")
	if behavior_profile == null:
		behavior_profile = _aggressor_profile

	_enemy_stats = StatsComponent.new()
	add_child(_enemy_stats)
	_enemy_stats.set_base_value(StatTypes.StatType.MOVE_RANGE, 4.0)
	_enemy_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	_enemy_stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)

	_player_stats = StatsComponent.new()
	add_child(_player_stats)
	_player_stats.set_base_value(StatTypes.StatType.HP, 20.0)
	_player_stats.set_base_value(StatTypes.StatType.HP_MAX, 20.0)
	_player_stats.set_base_value(StatTypes.StatType.BALANCE, 0.0)
	_player_stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)

	_data_provider = GridDataProvider.new(_is_cell_walkable, _height_query, Callable())
	_pathfinder.configure(Rect2i(0, 0, grid_width, grid_height), _data_provider, max_height_step)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	_recompute()


func _is_cell_walkable(cell: Vector2i) -> bool:
	return not wall_cells.has(cell)


func _height_query(cell: Vector2i) -> int:
	if elevated_cells.has(cell):
		return elevated_height
	return 0


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_randomize_scenario()
		_recompute()


## Рандомизирует позиции player/ally (на непроходимых/занятых клетках не
## оказываются), HP и накопленный Balance игрока, и переключает профиль
## поведения Aggressor<->Blocker — чтобы один клик наглядно демонстрировал
## разные решения ИИ без ручного редактирования сцены в инспекторе.
func _randomize_scenario() -> void:
	behavior_profile = _blocker_profile if behavior_profile == _aggressor_profile else _aggressor_profile

	player_cell = _random_free_cell([enemy_cell])
	ally_cell = _random_free_cell([enemy_cell, player_cell])

	var hp_max := 20.0
	var random_hp := randf_range(1.0, hp_max)
	_player_stats.set_base_value(StatTypes.StatType.HP, random_hp)
	_player_stats.set_base_value(StatTypes.StatType.HP_MAX, hp_max)

	var balance_max := 100.0
	var random_balance := randf_range(0.0, balance_max * 0.9)
	_player_stats.set_base_value(StatTypes.StatType.BALANCE, random_balance)
	_player_stats.set_base_value(StatTypes.StatType.BALANCE_MAX, balance_max)


## Возвращает случайную проходимую клетку сетки, отличную от занятых
## клеток из exclude_cells (простой retry-loop — сетка тестовая, маленькая).
func _random_free_cell(exclude_cells: Array[Vector2i]) -> Vector2i:
	for _attempt in range(50):
		var candidate := Vector2i(randi_range(0, grid_width - 1), randi_range(0, grid_height - 1))
		if wall_cells.has(candidate):
			continue
		if exclude_cells.has(candidate):
			continue
		return candidate
	return Vector2i.ZERO


func _recompute() -> void:
	var context := AIDecisionContext.new(_data_provider, max_height_step)
	context.enemy_cells = {player_cell: _player_stats}
	context.ally_cells = [ally_cell]
	context.hazard_cells = hazard_cells

	_last_action = UtilityAIController.decide(
		_enemy_stats, enemy_cell, behavior_profile, _pathfinder, context, base_damage, attack_range
	)
	_update_text()


func _update_text() -> void:
	var lines: Array[String] = [
		"=== Utility AI Demo (%s, click = randomize) ===" % behavior_profile.display_name,
		"Enemy at %s, Player at %s, Ally at %s" % [str(enemy_cell), str(player_cell), str(ally_cell)],
		"Player HP: %.1f/%.1f   Balance: %.1f/%.1f" % [
			_player_stats.get_value(StatTypes.StatType.HP), _player_stats.get_value(StatTypes.StatType.HP_MAX),
			_player_stats.get_value(StatTypes.StatType.BALANCE), _player_stats.get_value(StatTypes.StatType.BALANCE_MAX)
		],
	]

	if _last_action == null:
		lines.append("No decision (null action)")
		text = "\n".join(lines)
		return

	lines.append("Chosen action: %s -> %s (score=%.3f)" % [_last_action.action_type, str(_last_action.final_cell), _last_action.score])

	if _last_action.action_type == &"move_and_attack" and _last_action.damage_info != null:
		var info := _last_action.damage_info
		lines.append("  Attacks target at %s: dmg=%.1f balance+%.1f would_break=%s" %
			[str(_last_action.target_cell), info.final_damage, info.balance_added, info.would_break_balance])
		if info.would_break_balance:
			if info.push_blocked:
				lines.append("  Push BLOCKED (%s)" % info.push_blocked_reason)
			else:
				lines.append("  Push target -> %s" % str(info.push_target_cell))

	text = "\n".join(lines)
