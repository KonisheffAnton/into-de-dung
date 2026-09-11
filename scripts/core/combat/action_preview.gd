extends RefCounted
class_name ActionPreview

## Тонкий фасад над DamageCalculator для UI (Модуль 10 будет рисовать
## стрелки/числа на основе этого результата). Не добавляет новую логику
## расчёта — просто вызывает calculate() и НЕ вызывает apply(), гарантируя
## что превью не имеет побочных эффектов на реальное состояние игры.
static func build(
	attacker: StatsComponent,
	target: StatsComponent,
	attacker_cell: Vector2i,
	target_cell: Vector2i,
	base_damage: float,
	impact_power: float,
	data_provider: GridDataProvider,
	max_height_step: int = 1
) -> DamageInfo:
	return DamageCalculator.calculate(
		attacker, target, attacker_cell, target_cell, base_damage, impact_power, data_provider, max_height_step
	)
