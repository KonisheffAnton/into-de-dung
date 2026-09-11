extends AIConsideration
class_name HoldPositionConsideration

## Для роли "Блокер": выше, если итоговая клетка кандидата ближе к союзникам
## (`context.ally_cells`) — защита позиции/группировка, а не агрессивное
## преследование игрока. (Сохранено.)
##
## ИЗМЕНЕНО: при отсутствии союзников возвращает `ABSTAIN`, а не `0.5`
## (S-3в). Раньше "нейтральные" 0.5 попадали в знаменатель и СДВИГАЛИ
## итоговую оценку всех кандидатов одинаково, размывая вклад остальных
## факторов. Теперь фактор просто молчит, когда ему нечего сказать.

@export var max_relevant_distance: int = 6


func score(action: AIAction, context: AIDecisionContext) -> float:
	if context.ally_cells.is_empty():
		return ABSTAIN ## нет союзников — фактор нерелевантен

	var closest := max_relevant_distance
	for ally_cell in context.ally_cells.keys():
		var d := AIGridMath.manhattan_distance(action.final_cell, ally_cell)
		if d < closest:
			closest = d

	return clampf(1.0 - (float(closest) / float(max_relevant_distance)), 0.0, 1.0)
