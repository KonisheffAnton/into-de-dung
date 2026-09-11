extends AIConsideration
class_name HoldPositionConsideration

## Для роли "Блокер": выше, если итоговая клетка кандидата ближе к
## союзникам (context.ally_cells) — защита позиции/группировка, а не
## агрессивное преследование игрока. Для idle-действия (остаться на месте)
## тоже участвует в оценке через final_cell (равен текущей клетке юнита).

@export var max_relevant_distance: int = 6

func score(action: AIAction, context: AIDecisionContext) -> float:
	if context.ally_cells.is_empty():
		return 0.5 ## нет союзников — нейтральная оценка, не влияет на выбор

	var closest := max_relevant_distance
	for ally_cell in context.ally_cells:
		var d := AIGridMath.manhattan_distance(action.final_cell, ally_cell)
		if d < closest:
			closest = d

	return clampf(1.0 - (float(closest) / float(max_relevant_distance)), 0.0, 1.0)
