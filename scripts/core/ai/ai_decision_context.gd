extends RefCounted
class_name AIDecisionContext

## Снимок тактической ситуации на момент принятия решения ИИ. Считается ОДИН
## раз в `UtilityAIController.decide()` и передаётся во все
## `AIConsideration.score()` — дешевле, чем пересчитывать в каждом факторе, и
## гарантирует, что все факторы видят ОДИНАКОВУЮ картину мира. (Сохранено.)
##
## RefCounted, не Resource — контекст живёт только на время расчёта хода, это
## не персистентный ассет (R-1).
##
## ЧТО ИСПРАВЛЕНО (C-1 + C-4). Раньше `enemy_cells`/`ally_cells`/`hazard_cells`
## нужно было заполнять ВРУЧНУЮ снаружи: понятия фракции не существовало, и ни
## одна система не могла ответить на вопрос "кто мне враг" (в тестовой панели
## это был хардкод). Теперь контекст строится из `BattleBoard` — единственного
## источника правды: фракции разделяются автоматически, опасные клетки берутся
## из террейна, а `data_provider` создаёт сама доска (поэтому правила
## проходимости для ИИ и для pathfinding гарантированно совпадают).

## Доска — авторитетное состояние. Доступна факторам напрямую: некоторым
## нужен террейн и occupancy, а не только списки юнитов.
var board: BattleBoard = null

var data_provider: GridDataProvider = null
var max_height_step: int = 1

## Клетка -> враждебный юнит (с точки зрения ДУМАЮЩЕГО юнита, не игрока).
var enemy_cells: Dictionary = {} # Vector2i -> UnitState

## Клетка -> союзный юнит.
var ally_cells: Dictionary = {} # Vector2i -> UnitState

## Клетки-опасности (пропасти/вода/лава): толкание туда выгодно, а вставать
## самому — запрещено (VETO в `SelfSafetyConsideration`).
var hazard_cells: Array[Vector2i] = []


func _init(p_data_provider: GridDataProvider = null, p_max_height_step: int = 1) -> void:
	data_provider = p_data_provider
	max_height_step = p_max_height_step


## ОСНОВНАЯ фабрика: строит контекст для `thinking_unit` из состояния доски.
## Мёртвые юниты исключаются — цель, которая уже погибла, не должна влиять на
## оценку кандидатов.
static func build_from_board(
	thinking_unit: UnitState,
	p_board: BattleBoard,
	p_max_height_step: int = 1
) -> AIDecisionContext:
	# Провайдер создаётся доской и учитывает occupancy, при этом САМ
	# думающий юнит себя не блокирует (D-3.6).
	var context := AIDecisionContext.new(
		p_board.make_data_provider(thinking_unit), p_max_height_step
	)
	context.board = p_board
	context.hazard_cells = p_board.get_hazard_cells()

	for unit in p_board.get_alive_units():
		if unit == null or unit.id == thinking_unit.id:
			continue
		if thinking_unit.is_hostile_to(unit):
			context.enemy_cells[unit.cell] = unit
		elif thinking_unit.is_friendly_to(unit):
			context.ally_cells[unit.cell] = unit

	return context


## Вариант для случаев, когда доски нет (unit-тесты агрегации оценок).
## В реальном бою использовать `build_from_board`.
static func build_for(
	thinking_unit: UnitState,
	all_units: Array[UnitState],
	p_data_provider: GridDataProvider,
	p_hazard_cells: Array[Vector2i] = [],
	p_max_height_step: int = 1
) -> AIDecisionContext:
	var context := AIDecisionContext.new(p_data_provider, p_max_height_step)
	context.hazard_cells = p_hazard_cells.duplicate()

	for unit in all_units:
		if unit == null or unit == thinking_unit or not unit.is_alive():
			continue
		if thinking_unit.is_hostile_to(unit):
			context.enemy_cells[unit.cell] = unit
		elif thinking_unit.is_friendly_to(unit):
			context.ally_cells[unit.cell] = unit

	return context


func is_hazard(cell: Vector2i) -> bool:
	return hazard_cells.has(cell)
