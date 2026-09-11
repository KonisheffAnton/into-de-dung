extends Resource
class_name TurnOrderStrategy

## Абстрактная стратегия расчёта порядка ходов (Strategy pattern на Resource).
## Подмена формулы = замена `.tres`-ресурса, без изменения кода. Сохранённое
## решение модуля 4.
##
## ИЗМЕНЕНО (C-1): работает с `Array[UnitState]`, а не `Array[StatsComponent]`.
## Стратегии теперь доступны фракция, позиция и факт смерти юнита — раньше
## "мешок характеристик" этого не давал, и любая формула сложнее "сравнить
## одно число" была невыразима.
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (D-4.8): контракт `compute_order(Array) -> Array` —
## это модель "отсортированный список", которая НЕ выражает time-based
## timeline (ATB/CTB, где юнит может получить два хода за раунд, а способности
## сдвигают его позицию в очереди), хотя требование называется "Initiative
## Timeline Queue". Если ATB понадобится — контракт меняется на
## `next_actor(state) -> UnitState` + `advance_time()`. Решение отложено до
## работающего среза (R-7), пока хватает sorted-list.
func compute_order(participants: Array[UnitState]) -> Array[UnitState]:
	return participants.duplicate()
