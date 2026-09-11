extends RefCounted
class_name InitiativeTimeline

## Менеджер очереди ходов. Хранит участников боя и текущую
## TurnOrderStrategy, пересчитывает порядок по запросу (например, когда
## изменение INITIATIVE участника в процессе боя требует переупорядочивания
## — типичная механика для Into the Breach-style тактик).
##
## НЕ управляет фазами боя (PlayerTurn/EnemyTurn/...) — это задача
## Battle Flow State Machine (Модуль 8). Здесь только порядок и очередь.

var _strategy: TurnOrderStrategy
var _participants: Array[StatsComponent] = []
var _current_order: Array[StatsComponent] = []
var _current_index: int = -1


func set_strategy(strategy: TurnOrderStrategy) -> void:
	_strategy = strategy


func register_participant(stats: StatsComponent) -> void:
	if _participants.has(stats):
		return
	_participants.append(stats)
	recompute_order()


func unregister_participant(stats: StatsComponent) -> void:
	_participants.erase(stats)
	recompute_order()


## Форсирует пересчёт порядка ходов текущей стратегией. Вызывать при
## существенных изменениях (смена инициативы, смерть участника, начало
## нового раунда).
func recompute_order() -> void:
	if _strategy == null:
		_current_order = _participants.duplicate()
	else:
		_current_order = _strategy.compute_order(_participants)
	_current_index = -1


func get_current_order() -> Array[StatsComponent]:
	return _current_order.duplicate()


## Возвращает следующего ходящего участника, продвигая внутренний курсор.
## При достижении конца очереди начинается новый раунд (курсор сбрасывается
## в начало текущего порядка; для пересчёта порядка между раундами нужно
## явно вызывать recompute_order() снаружи — это ответственность Battle
## Flow State Machine).
func advance_turn() -> StatsComponent:
	if _current_order.is_empty():
		return null
	_current_index = (_current_index + 1) % _current_order.size()
	return _current_order[_current_index]


func peek_current() -> StatsComponent:
	if _current_index < 0 or _current_index >= _current_order.size():
		return null
	return _current_order[_current_index]
