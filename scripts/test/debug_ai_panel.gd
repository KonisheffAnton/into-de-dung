extends Label

## Демонстрация Utility AI. Тестовый враг с подключаемым `AIBehaviorProfile`
## (Aggressor/Blocker — `.tres`, подмена без изменения кода), тестовый игрок и
## союзник ИИ. ЛКМ — рандомизировать ситуацию и пересчитать решение.
## Не финальная архитектура; реальный вызов ИИ появится в Battle Flow.
##
## ОБНОВЛЕНО ПОСЛЕ АУДИТА:
##  - враги/союзники больше НЕ заполняются вручную: контекст строится
##    фабрикой `AIDecisionContext.build_for()` по фракциям (часть C-1);
##  - рандомизация идёт из явного seed (R-5), а не из глобального RNG,
##    поэтому расклад воспроизводим — раньше один и тот же клик давал
##    разные результаты, и сравнить поведение профилей было нельзя;
##  - HP/Balance игрока задаются через `Vitals`, а не через статы (R-2).

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

var _enemy: UnitState
var _player: UnitState
var _ally: UnitState
var _data_provider: GridDataProvider
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

	_rng.seed = 20260911

	_enemy = _make_unit(Faction.Type.ENEMY, enemy_cell, "Enemy", 4.0)
	_player = _make_unit(Faction.Type.PLAYER, player_cell, "Player", 3.0)
	_ally = _make_unit(Faction.Type.ENEMY, ally_cell, "Ally", 3.0)

	_data_provider = GridDataProvider.new(_is_cell_walkable, _height_query, Callable())
	_pathfinder.configure(Rect2i(0, 0, grid_width, grid_height), _data_provider, max_height_step)

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


## Переключает профиль и рандомизирует позиции/состояние игрока, чтобы один
## клик наглядно показывал разные решения ИИ без правки сцены в инспекторе.
func _randomize_scenario() -> void:
	behavior_profile = _blocker_profile if behavior_profile == _aggressor_profile else _aggressor_profile

	player_cell = _random_free_cell([enemy_cell])
	ally_cell = _random_free_cell([enemy_cell, player_cell])
	_player.cell = player_cell
	_ally.cell = ally_cell

	# HP/Balance — это ресурсы (R-2), задаются через Vitals, а не через статы.
	_player.vitals.set_hp(_rng.randf_range(1.0, _player.vitals.get_hp_max()))
	_player.vitals.set_balance(_rng.randf_range(0.0, _player.vitals.get_balance_max() * 0.9))

	_enemy.begin_turn()


func _random_free_cell(exclude_cells: Array[Vector2i]) -> Vector2i:
	for _attempt in range(50):
		var candidate := Vector2i(
			_rng.randi_range(0, grid_width - 1),
			_rng.randi_range(0, grid_height - 1)
		)
		if wall_cells.has(candidate):
			continue
		if exclude_cells.has(candidate):
			continue
		return candidate
	return Vector2i.ZERO


func _recompute() -> void:
	# Контекст строится по фракциям автоматически — раньше enemy_cells и
	# ally_cells приходилось собирать руками (часть дефекта C-1).
	var all_units: Array[UnitState] = [_enemy, _player, _ally]
	var context := AIDecisionContext.build_for(
		_enemy, all_units, _data_provider, hazard_cells, max_height_step
	)

	_last_action = UtilityAIController.decide(
		_enemy, behavior_profile, _pathfinder, context, base_damage, attack_range
	)
	_update_text()


func _update_text() -> void:
	var lines: Array[String] = [
		"=== Utility AI Demo (%s, click = randomize) ===" % behavior_profile.display_name,
		"Enemy at %s, Player at %s, Ally at %s" % [
			str(_enemy.cell), str(_player.cell), str(_ally.cell)
		],
		"Player HP: %.1f/%.1f   Balance: %.1f/%.1f" % [
			_player.vitals.get_hp(), _player.vitals.get_hp_max(),
			_player.vitals.get_balance(), _player.vitals.get_balance_max(),
		],
		"Hazards: %s" % str(hazard_cells),
	]

	if _last_action == null:
		lines.append("No decision (null action)")
	else:
		lines.append("Chosen: %s" % _last_action.to_debug_string())

	text = "\n".join(lines)
