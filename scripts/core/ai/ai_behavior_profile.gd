extends Resource
class_name AIBehaviorProfile

## Набор взвешенных AIConsideration для одного "типа поведения" врага
## (Aggressor, Blocker, ...). Подмена поведения = замена .tres-ресурса,
## как со SimpleInitiativeStrategy (Модуль 4) — без изменения кода.

@export var display_name: String = ""
@export var considerations: Array[AIConsideration] = []


## Взвешенное среднее score всех considerations для данного кандидата.
## Простое и предсказуемое агрегирование для MVP; при необходимости
## (например, "veto"-считерации, которые должны обнулять весь результат)
## легко заменить на мультипликативную схему здесь, без изменения
## UtilityAIController или самих considerations.
func evaluate(action: AIAction, context: AIDecisionContext) -> float:
	if considerations.is_empty():
		return 0.0

	var weighted_sum := 0.0
	var weight_total := 0.0
	for consideration in considerations:
		var w := consideration.weight
		if w <= 0.0:
			continue
		weighted_sum += consideration.score(action, context) * w
		weight_total += w

	if weight_total <= 0.0:
		return 0.0
	return weighted_sum / weight_total
