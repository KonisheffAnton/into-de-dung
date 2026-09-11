extends RefCounted
class_name AIDecisionContext

## Снимок тактической ситуации на момент принятия решения ИИ. Передаётся
## во все AIConsideration.score() вызовы для одного и того же юнита в
## одном и том же ходу — считается ОДИН раз в UtilityAIController.decide(),
## а не пересчитывается в каждой consideration отдельно (дешевле и
## гарантирует, что все considerations видят одинаковую картину мира).
##
## RefCounted, не Resource — контекст живёт только на время расчёта хода,
## это не персистентный ассет.

var data_provider: GridDataProvider = null
var max_height_step: int = 1

## Vector2i -> StatsComponent. Все вражеские (для ИИ — игровые) юниты,
## видимые/релевантные для расчёта.
var enemy_cells: Dictionary = {}

## Клетки союзников ИИ (для considerations типа "защищать союзника").
var ally_cells: Array[Vector2i] = []

## Клетки-опасности (пропасти/вода/лава и т.п.) — куда толкание считается
## выгодным. Источник данных — карта уровня (появится в Модуле 9/11).
var hazard_cells: Array[Vector2i] = []


func _init(p_data_provider: GridDataProvider = null, p_max_height_step: int = 1) -> void:
	data_provider = p_data_provider
	max_height_step = p_max_height_step
