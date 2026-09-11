extends AIConsideration
class_name SelfSafetyConsideration

## Штрафует кандидатов, чья итоговая клетка находится слишком близко к
## нескольким врагам одновременно (риск ответного размена). Дешёвая
## эвристика на манхэттенском расстоянии, НЕ полный пересчёт путей — этого
## достаточно для оценки "нахожусь под угрозой". (Сохранено.)
##
## ДОБАВЛЕНО: ВЕТО на клетки-опасности (S-3в). Раньше механизма запрета не
## существовало, и ИИ мог добровольно встать в лаву/пропасть, если сумма
## других факторов перевешивала — при арифметическом среднем это вполне
## возможный исход. Теперь такой кандидат отбрасывается целиком.

## Дистанция, на которой враг считается угрозой (1 = впритык, ближний бой).
@export var danger_radius: int = 1

## Запрещать ли вставать в опасные клетки (пропасть/лава).
@export var veto_hazard_cells: bool = true


func score(action: AIAction, context: AIDecisionContext) -> float:
	# Самосохранение важнее любой тактической выгоды: шаг в пропасть — это
	# не "плохой ход", а недопустимый.
	if veto_hazard_cells and context.is_hazard(action.final_cell):
		return VETO

	var threats := 0
	for enemy_cell in context.enemy_cells.keys():
		if AIGridMath.manhattan_distance(action.final_cell, enemy_cell) <= danger_radius:
			threats += 1

	if threats <= 0:
		return 1.0 ## безопасно — не штрафуем

	# Больше угроз рядом -> ниже score, но не обнуляем совсем, чтобы не
	# блокировать единственно возможные ходы.
	return clampf(1.0 / float(threats + 1), 0.0, 1.0)
