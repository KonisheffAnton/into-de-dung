extends AIConsideration
class_name PushToHazardConsideration

## Выше, если атака сломает Баланс цели И итоговая клетка толкания попадает
## в опасную клетку (пропасть/вода/лава — context.hazard_cells). Источник
## hazard_cells придёт из карты уровня (Модуль 9/11); пока — переданный
## извне список для тестов.

func score(action: AIAction, context: AIDecisionContext) -> float:
	if action.action_type != &"move_and_attack" or action.damage_info == null:
		return 0.0

	var info := action.damage_info
	if not info.would_break_balance or info.push_blocked:
		return 0.0

	if context.hazard_cells.has(info.push_target_cell):
		return 1.0
	return 0.0
