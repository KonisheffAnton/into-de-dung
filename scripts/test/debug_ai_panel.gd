extends Label

## Демонстрация Utility AI на реальной `BattleBoard`.
## ЛКМ — рандомизировать ситуацию, переключить профиль и пересчитать решение.
## Не финальная архитектура; реальный вызов ИИ появится в Battle Flow.
##
## ОБНОВЛЕНО НА ШАГЕ 0.4 (C-4). Контекст решения строится ОДНИМ вызовом
## `AIDecisionContext.build_from_board()`: доска сама разделяет юнитов по
## фракциям, отдаёт опасные клетки из террейна и создаёт `GridDataProvider` с
## учётом occupancy. Раньше панель собирала всё это вручную (позиции врагов,
## список hazard'ов, замыкания проходимости), и правила у ИИ и pathfinding
## расходились. Теперь ИИ также видит новый фактор — толчок в столкновение,
## который до появления доски был невыразим.

@export var grid_config: IsoGridConfig
@export var behavior_profile: AIBehaviorProfile
@export var board_size: Vector2i = Vector2i(8, 8)
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

var _board: BattleBoard
var _enemy: UnitState
var _player: UnitState
var _ally: UnitState
var _pathfinder := GridPathfinder.new()
var _last_action: AIAction
var _rng := RandomNumberGenerator.new()

var _aggressor_profile: AIBehaviorProfile
var _blocker_profile: AIBehaviorProfile


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	_aggressor_profile = load("res://resources/ai/aggressor_profile.tres")
	_blocker_profile = load("res://resources/ai/blocker_profile.tres")
	if behavior_profile == null:
		behavior_profile = _aggressor_profile

	# Детерминированный RNG (R-5): один и тот же клик даёт один и тот же
	# расклад, иначе сравнить поведение профилей невозможно.
	_rng.seed = 20260911

	_board = BattleBoard.new(board_size.x, board_size.y)
	for cell in wall_cells:
		_board.set_terrain(cell, TerrainType.Type.WALL)
	for cell in hazard_cells:
		_board.set_terrain(cell, TerrainType.Type.HAZARD)
	for cell in elevated_cells:
		_board.set_height(cell, elevated_height)

	_enemy = _make_unit(Faction.Type.ENEMY, enemy_cell, "Enemy", 4.0)
	_player = _make_unit(Faction.Type.PLAYER, player_cell, "Player", 3.0)
	_ally = _make_unit(Faction.Type.ENEMY, ally_cell, "Ally", 3.0)
	_board.add_unit(_enemy)
	_board.add_unit(_player)
	_board.add_unit(_ally)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	_recompute()


func _make_unit(
	faction: Faction.Type,
	cell: Vector2i,
	unit_name: String,
	move_range: float
) -> UnitState:
	var stats := StatsBag.new()
	stats.set_base_value(StatTypes.StatType.HP_MAX, 20.0)
	stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
	stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)
	stats.set_base_value(StatTypes.StatType.MOVE_RANGE, move_range)
	return UnitState.create(faction, cell, stats, unit_name)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_randomize_scenario()
		_recompute()


## Переключает профиль и рандомизирует позиции/состояние игрока, чтобы один
## клик наглядно показывал разные решения ИИ без правки сцены в инспекторе.
func _randomize_scenario() -> void:
	behavior_profile = _blocker_profile if behavior_profile == _aggressor_profile else _aggressor_profile

	# Перемещение ТОЛЬКО через доску: она обновляет и occupancy, и unit.cell,
	# поэтому они не могут разойтись.
	_board.move_unit(_player, _random_free_cell([_enemy.cell, _ally.cell]))
	_board.move_unit(_ally, _random_free_cell([_enemy.cell, _player.cell]))

	# HP/Balance — это ресурсы (R-2), задаются через Vitals, а не статы.
	_player.vitals.set_hp(_rng.randf_range(1.0, _player.vitals.get_hp_max()))
	_player.vitals.set_balance(_rng.randf_range(0.0, _player.vitals.get_balance_max() * 0.9))

	_enemy.begin_turn()


func _random_free_cell(exclude_cells: Array[Vector2i]) -> Vector2i:
	for _attempt in range(50):
		var candidate := Vector2i(
			_rng.randi_range(0, _board.width - 1),
			_rng.randi_range(0, _board.height - 1)
		)
		if not _board.is_terrain_walkable(candidate):
			continue
		if exclude_cells.has(candidate):
			continue
		if _board.is_occupied(candidate):
			continue
		return candidate
	return Vector2i.ZERO


func _recompute() -> void:
	# ОДИН вызов вместо ручной сборки врагов/союзников/hazard'ов/провайдера.
	var context := AIDecisionContext.build_from_board(_enemy, _board, max_height_step)

	# Pathfinder получает провайдер ОТ ДОСКИ, поэтому его правила
	# проходимости идентичны тем, что видит ИИ (закрыт источник расхождений).
	_pathfinder.configure(_board.get_bounds(), context.data_provider, max_height_step)

	_last_action = UtilityAIController.decide(
		_enemy, behavior_profile, _pathfinder, context, base_damage, attack_range
	)
	_update_text()


func _update_text() -> void:
	var lines: Array[String] = [
		"=== Utility AI on BattleBoard (%s, click = randomize) ===" % behavior_profile.display_name,
		"Enemy %s   Player %s   Ally %s" % [
			str(_enemy.cell), str(_player.cell), str(_ally.cell)
		],
		"Player HP: %.1f/%.1f   Balance: %.1f/%.1f" % [
			_player.vitals.get_hp(), _player.vitals.get_hp_max(),
			_player.vitals.get_balance(), _player.vitals.get_balance_max(),
		],
		"Hazards on board: %d   walls: %d   board_version: %d" % [
			_board.get_hazard_cells().size(), wall_cells.size(), _board.board_version
		],
	]

	if _last_action == null:
		lines.append("No decision (null action)")
	else:
		lines.append("Chosen: %s" % _last_action.to_debug_string())

	text = "\n".join(lines)
