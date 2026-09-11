extends AIConsideration
class_name LowHpTargetConsideration

## Выше, если атака способна добить/сильно ранить цель с малым остатком HP
## (приоритет "убить раненого" вместо размена по здоровым целям).

func score(action: AIAction, _context: AIDecisionContext) -> float:
	if action.action_type != &"move_and_attack" or action.target == null or action.damage_info == null:
		return 0.0

	var hp := action.target.get_value(StatTypes.StatType.HP)
	var hp_max := action.target.get_value(StatTypes.StatType.HP_MAX)
	if hp_max <= 0.0:
		return 0.0

	var projected_hp := hp - action.damage_info.final_damage
	if projected_hp <= 0.0:
		return 1.0 ## лечальный удар — максимальный приоритет

	# Чем меньше остаётся HP относительно максимума, тем выше score.
	return clampf(1.0 - (projected_hp / hp_max), 0.0, 1.0)
