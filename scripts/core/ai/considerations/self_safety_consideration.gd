extends AIConsideration
class_name SelfSafetyConsideration

## Штрафует кандидатов, чья итоговая клетка (final_cell) находится слишком
## близко к нескольким врагам одновременно (риск ответного размена).
## Дешёвая эвристика на манхэттенском расстоянии (AIGridMath), НЕ полный
## пересчёт путей — этого достаточно для оценки "нахожусь под угрозой".
##
## danger_radius — дистанция, на которой враг считается угрозой для этой
## клетки (по умолчанию 1 = впритык, ближний бой).

@export var danger_radius: int = 1

func score(action: AIAction, context: AIDecisionContext) -> float:
	var threats := 0
	for enemy_cell in context.enemy_cells.keys():
		if AIGridMath.manhattan_distance(action.final_cell, enemy_cell) <= danger_radius:
			threats += 1

	if threats <= 0:
		return 1.0 ## безопасно — не штрафуем
	# Больше угроз рядом -> ниже score (безопасность), но не обнуляем совсем,
	# чтобы не блокировать единственно возможные ходы.
	return clampf(1.0 / float(threats + 1), 0.0, 1.0)
