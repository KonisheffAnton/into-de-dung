extends RefCounted
class_name EventSink

## Абстракция стока игровых событий — фикс дефекта S-4 и реализация правила
## R-3 ("`scripts/core/**` не имеет права ссылаться на автозагрузки").
##
## ПРОБЛЕМА. Раньше `DamageCalculator.apply()` — СТАТИЧЕСКИЙ метод в слое
## чистой логики — эмитил напрямую в автозагрузку:
##     GameEventBus.unit_damaged.emit(...)
## Это скрытая глобальная зависимость, из-за которой:
##  - боевую логику нельзя выполнить в unit-тесте без поднятия автозагрузок;
##  - нельзя иметь ДВЕ изолированные симуляции одновременно, а они нужны для
##    AI-lookahead (просчёт на 2 хода вперёд) и для sandbox-превью (R-6:
##    превью = прогон настоящей команды на копии состояния). При глобальной
##    шине пробный прогон разослал бы события всем предметам/перкам, и они
##    среагировали бы на то, что ещё не произошло.
##
## РЕАЛИЗАЦИИ:
##  - `GameEventBusSink` — прод: пробрасывает в автозагрузку `GameEventBus`;
##  - `NullEventSink` (этот класс по умолчанию) — ничего не делает, для
##    AI-lookahead и превью;
##  - `RecordingEventSink` — записывает вызовы, для тестов.
##
## Базовый класс сам является рабочим "нулевым" стоком, поэтому код может
## безопасно получить `EventSink.new()` вместо null-проверок на каждом вызове.

func unit_damaged(_unit: UnitState, _amount: float, _source: Variant) -> void:
	pass


func unit_healed(_unit: UnitState, _amount: float, _source: Variant) -> void:
	pass


func unit_died(_unit: UnitState, _source: Variant) -> void:
	pass


func unit_balance_changed(_unit: UnitState, _old_value: float, _new_value: float) -> void:
	pass


func unit_balance_broken(_unit: UnitState) -> void:
	pass


func unit_pushed(_unit: UnitState, _from_cell: Vector2i, _to_cell: Vector2i) -> void:
	pass


func unit_moved(_unit: UnitState, _from_cell: Vector2i, _to_cell: Vector2i) -> void:
	pass


func turn_started(_unit: UnitState) -> void:
	pass


func turn_ended(_unit: UnitState) -> void:
	pass


func round_started(_round_number: int) -> void:
	pass


func round_ended(_round_number: int) -> void:
	pass
