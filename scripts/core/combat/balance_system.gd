extends RefCounted
class_name BalanceSystem

## Логика накопления/разрядки шкалы Баланса. Не знает ничего о толкании
## или уроне — только считает BALANCE стат. PushResolver/DamageCalculator
## используют эту логику, но толкание фактическое (перемещение юнита по
## сетке) остаётся ответственностью вызывающего кода/Модуля 10.

## Добавляет impact_power к BALANCE. Возвращает true, если после добавления
## BALANCE >= BALANCE_MAX (юнит "сломан" — должен быть толкнут).
## НЕ мутирует стат — вызывающий код должен явно вызвать apply_impact()
## (мутирующая версия) при реальном выполнении, либо просто прочитать
## результат этой функции для превью без изменения состояния.
static func would_break(stats: StatsComponent, added_impact: float) -> bool:
	var current := stats.get_value(StatTypes.StatType.BALANCE)
	var max_balance := stats.get_value(StatTypes.StatType.BALANCE_MAX)
	if max_balance <= 0.0:
		return false
	return current + added_impact >= max_balance


## Мутирующая версия: реально добавляет impact_power к BALANCE. Если после
## этого BALANCE >= BALANCE_MAX — сбрасывает BALANCE в 0 (готов копиться
## заново) и возвращает true. Не эмитит события — это делает DamageCalculator/
## вызывающий код, чтобы BalanceSystem оставалась чистой логикой стата.
static func apply_impact(stats: StatsComponent, added_impact: float) -> bool:
	var balance_stat := stats.get_stat(StatTypes.StatType.BALANCE)
	var new_value := balance_stat.get_value() + added_impact
	var max_balance := stats.get_value(StatTypes.StatType.BALANCE_MAX)

	var broke := max_balance > 0.0 and new_value >= max_balance
	if broke:
		balance_stat.set_base_value(0.0)
	else:
		balance_stat.set_base_value(new_value)
	return broke


static func reset(stats: StatsComponent) -> void:
	stats.get_stat(StatTypes.StatType.BALANCE).set_base_value(0.0)
