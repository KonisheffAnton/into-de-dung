extends AIConsideration
class_name PreferAttackConsideration

## Простой "тайбрейк"-фактор: атака в целом предпочтительнее простого
## перемещения/ожидания, даже без других бонусов. Без него Utility AI мог бы
## выбрать move с тем же итоговым score, что и безобидную атаку, что
## выглядит нерешительно.
##
## ИЗМЕНЕНО: проверка через `has_attack()`/enum вместо строк (S-3б). Этот
## фактор — единственный, который ПО СМЫСЛУ оценивает сам тип действия,
## поэтому здесь сравнение с типом уместно (в отличие от остальных, где оно
## блокировало добавление новых типов действий).

## Оценка для действий с атакой.
@export var attack_score: float = 1.0

## Оценка для простого перемещения.
@export var move_score: float = 0.3

## Оценка для "остаться на месте, ничего не делать".
@export var idle_score: float = 0.0


func score(action: AIAction, _context: AIDecisionContext) -> float:
	if action.has_attack():
		return clampf(attack_score, 0.0, 1.0)
	if action.action_type == AIAction.Type.MOVE:
		return clampf(move_score, 0.0, 1.0)
	return clampf(idle_score, 0.0, 1.0)
