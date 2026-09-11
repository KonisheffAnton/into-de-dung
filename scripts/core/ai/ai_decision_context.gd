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
## ЧТО ИСПРАВЛЕНО (часть C-1). Раньше `enemy_cells`/`ally_cells` нужно было
## заполнять ВРУЧНУЮ снаружи, потому что понятия фракции не существовало и ни
## одна система не могла ответить на вопрос "кто мне враг". В тестовой панели
## это делалось хардкодом. Теперь есть фабрика `build_for()`, которая
## разделяет юнитов по `Faction` автоматически — источник правды один.

var data_provider: GridDataProvider = null
var max_height_step: int = 1

## Клетка -> враждебный юнит (с точки зрения ДУМАЮЩЕГО юнита, не игрока).
var enemy_cells: Dictionary = {} # Vector2i -> UnitState

## Клетка -> союзный юнит.
var ally_cells: Dictionary = {} # Vector2i -> UnitState

## Клетки-опасности (пропасти/вода/лава) — толкание туда считается выгодным.
## Источник данных — карта уровня (будет `BattleBoard.hazard_cells()`, шаг 0.4).
var hazard_cells: Array[Vector2i] = []


func _init(p_data_provider: GridDataProvider = null, p_max_height_step: int = 1) -> void:
	data_provider = p_data_provider
	max_height_step = p_max_height_step


## Строит контекст для `thinking_unit` из плоского списка всех участников боя.
## Разделение на врагов/союзников — по фракциям, а не вручную.
## Мёртвые юниты исключаются: цель, которая уже погибла, не должна влиять на
## оценку (раньше смерти не существовало, поэтому проблема не возникала).
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
