extends AIConsideration
class_name PushToHazardConsideration

## Выше, если атака сломает Баланс цели И итоговая клетка толкания попадает
## в опасную клетку (пропасть/вода/лава — `context.hazard_cells`).
## Источник hazard_cells придёт из `BattleBoard` (шаг 0.4); пока — список,
## переданный извне.
##
## ИЗМЕНЕНО: `has_attack()` вместо сравнения со строкой (S-3б), `ABSTAIN`
## для кандидатов, к которым фактор неприменим (S-3в).

func score(action: AIAction, context: AIDecisionContext) -> float:
	if not action.has_attack():
		return ABSTAIN

	var info := action.damage_info

	# Толчка не будет вовсе — фактор не имеет мнения об этом кандидате.
	# (Раньше здесь возвращался 0.0, то есть фактор активно голосовал ПРОТИВ
	# любой атаки, которая не ломает баланс — а таких большинство.)
	if not info.would_break_balance or info.push_blocked:
		return ABSTAIN

	if context.is_hazard(info.push_target_cell):
		return 1.0

	# Толчок есть, но не в опасность — фактор высказался: ценности нет.
	return 0.0
