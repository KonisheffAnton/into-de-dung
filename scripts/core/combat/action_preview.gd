extends RefCounted
class_name ActionPreview

## Фасад над `DamageCalculator.calculate()` для превью: вызывает расчёт и
## НИКОГДА не вызывает `apply()`, гарантируя отсутствие побочных эффектов.
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (D-6.5 / R-6). Сейчас это тонкое делегирование,
## которое не добавляет ничего. Правильное превью в стиле Into the Breach —
## это СУХОЙ ПРОГОН той же самой команды на КОПИИ состояния доски, чтобы
## показать полную цепочку: толчок -> столкновение с другим юнитом -> урон
## обоим -> смерть -> падение в пропасть -> срабатывание предметов.
## Отдельная функция расчёта даёт parity превью и результата "по
## договорённости" (её легко нарушить, добавив эффект только в apply-путь),
## а прогон команды — "по построению".
##
## Поэтому после шага 0.5 (`Command` + `ActionQueue`) этот класс будет
## заменён на `Command.preview(board_copy)` и, скорее всего, удалён. Пока он
## сохраняется, чтобы не ломать ИИ и дебаг-панели.
static func build(
	attacker: UnitState,
	target: UnitState,
	attacker_cell: Vector2i,
	target_cell: Vector2i,
	base_damage: float,
	impact_power: float,
	data_provider: GridDataProvider,
	max_height_step: int = 1
) -> DamageInfo:
	return DamageCalculator.calculate(
		attacker, target, attacker_cell, target_cell,
		base_damage, impact_power, data_provider, max_height_step
	)
