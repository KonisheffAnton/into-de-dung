extends EventSink
class_name GameEventBusSink

## Продакшен-реализация `EventSink`: пробрасывает события в автозагрузку
## `GameEventBus`.
##
## ПОЧЕМУ ЭТОТ ФАЙЛ ЛЕЖИТ В `gameplay/`, А НЕ В `core/`: по правилу R-3 слой
## `core/**` не имеет права ссылаться на автозагрузки по имени. Адаптер — это
## единственное место, которое ЗНАЕТ про `GameEventBus`, и поэтому он
## намеренно вынесен за пределы ядра. Ядро видит только абстракцию `EventSink`.
##
## Такое разделение даёт возможность иметь одновременно несколько симуляций:
## реальный бой получает этот сток, а AI-lookahead и sandbox-превью (R-6) —
## `EventSink.new()` (нулевой), чтобы пробный прогон не рассылал события
## предметам и перкам.

func unit_damaged(unit: UnitState, amount: float, source: Variant) -> void:
	GameEventBus.unit_damaged.emit(unit, amount, source)


func unit_healed(unit: UnitState, amount: float, source: Variant) -> void:
	GameEventBus.unit_healed.emit(unit, amount, source)


func unit_died(unit: UnitState, source: Variant) -> void:
	GameEventBus.unit_died.emit(unit, source)


func unit_balance_changed(unit: UnitState, old_value: float, new_value: float) -> void:
	GameEventBus.unit_balance_changed.emit(unit, old_value, new_value)


func unit_balance_broken(unit: UnitState) -> void:
	GameEventBus.unit_balance_broken.emit(unit)


func unit_pushed(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void:
	GameEventBus.unit_pushed.emit(unit, from_cell, to_cell)


func unit_moved(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void:
	GameEventBus.unit_moved.emit(unit, from_cell, to_cell)


func turn_started(unit: UnitState) -> void:
	GameEventBus.turn_started.emit(unit)


func turn_ended(unit: UnitState) -> void:
	GameEventBus.turn_ended.emit(unit)


func round_started(round_number: int) -> void:
	GameEventBus.round_started.emit(round_number)


func round_ended(round_number: int) -> void:
	GameEventBus.round_ended.emit(round_number)
