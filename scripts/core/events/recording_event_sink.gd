extends EventSink
class_name RecordingEventSink

## Сток событий, который вместо рассылки ЗАПИСЫВАЕТ их — для unit-тестов
## (G-5) и для отладки цепочек синергий.
##
## Позволяет проверять не только итоговое состояние, но и ПОРЯДОК событий.
## Это важно из-за дефекта S-5: в старом коде реакции на событие исполнялись
## синхронно в середине незавершённой транзакции (урон -> синхронный
## `unit_damaged` -> предмет уже вылечил HP -> и только потом считался
## баланс). Порядок "урон, лечение, баланс" получился случайно, и проверить
## его было нечем.

## Массив записей вида {"event": StringName, "args": Array}.
var records: Array[Dictionary] = []


func _record(event: StringName, args: Array) -> void:
	records.append({"event": event, "args": args})


func clear() -> void:
	records.clear()


func count_of(event: StringName) -> int:
	var n := 0
	for r in records:
		if r["event"] == event:
			n += 1
	return n


func has_event(event: StringName) -> bool:
	return count_of(event) > 0


## Последовательность имён событий в порядке возникновения — для ассертов
## вида `assert_eq(sink.event_sequence(), [&"unit_damaged", &"unit_died"])`.
func event_sequence() -> Array[StringName]:
	var seq: Array[StringName] = []
	for r in records:
		seq.append(r["event"])
	return seq


# --- Переопределения -------------------------------------------------------

func unit_damaged(unit: UnitState, amount: float, source: Variant) -> void:
	_record(&"unit_damaged", [unit, amount, source])


func unit_healed(unit: UnitState, amount: float, source: Variant) -> void:
	_record(&"unit_healed", [unit, amount, source])


func unit_died(unit: UnitState, source: Variant) -> void:
	_record(&"unit_died", [unit, source])


func unit_balance_changed(unit: UnitState, old_value: float, new_value: float) -> void:
	_record(&"unit_balance_changed", [unit, old_value, new_value])


func unit_balance_broken(unit: UnitState) -> void:
	_record(&"unit_balance_broken", [unit])


func unit_pushed(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void:
	_record(&"unit_pushed", [unit, from_cell, to_cell])


func unit_moved(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void:
	_record(&"unit_moved", [unit, from_cell, to_cell])


func turn_started(unit: UnitState) -> void:
	_record(&"turn_started", [unit])


func turn_ended(unit: UnitState) -> void:
	_record(&"turn_ended", [unit])


func round_started(round_number: int) -> void:
	_record(&"round_started", [round_number])


func round_ended(round_number: int) -> void:
	_record(&"round_ended", [round_number])
