extends Resource
class_name TurnOrderStrategy

## Абстрактная база Strategy для расчёта порядка ходов. Конкретные
## реализации подключаются как Resource (.tres) в InitiativeTimeline/
## BattleConfig — подмена формулы порядка ходов "на лету" без изменения
## кода вызывающей стороны.

## participants: Array[StatsComponent]. Возвращает НОВЫЙ отсортированный
## массив (не мутирует входной). Переопределяется в наследниках.
func compute_order(participants: Array[StatsComponent]) -> Array[StatsComponent]:
	push_error("TurnOrderStrategy.compute_order() is abstract, override in a subclass")
	return participants.duplicate()
