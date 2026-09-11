extends AIConsideration
class_name PreferAttackConsideration

## Простой "тайбрейк"-фактор: атака в целом предпочтительнее простого
## перемещения/ожидания, даже без других бонусов. Без этой considerration
## Utility AI мог бы выбрать move-действие с тем же итоговым score, что и
## безобидную атаку, что выглядит нерешительно.

func score(action: AIAction, _context: AIDecisionContext) -> float:
	match action.action_type:
		&"move_and_attack":
			return 1.0
		&"move":
			return 0.3
		_:
			return 0.0
