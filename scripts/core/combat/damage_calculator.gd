extends RefCounted
class_name DamageCalculator

## Чистая логика расчёта результата атаки. calculate() НЕ мутирует статы
## (безопасно для Preview UI — можно вызывать многократно без побочных
## эффектов), apply() мутирует реальное состояние и эмитит события через
## GameEventBus. Оба используют один и тот же DamageInfo — гарантия, что
## превью и реальное исполнение совпадают.

## attacker_cell/target_cell передаются ЯВНО (не читаются из "текущей"
## позиции юнита) — см. DECISIONS.md про Move+Attack комбо-поток.
static func calculate(
	attacker: StatsComponent,
	target: StatsComponent,
	attacker_cell: Vector2i,
	target_cell: Vector2i,
	base_damage: float,
	impact_power: float,
	data_provider: GridDataProvider,
	max_height_step: int = 1
) -> DamageInfo:
	var info := DamageInfo.new()
	info.attacker = attacker
	info.target = target
	info.attacker_cell = attacker_cell
	info.target_cell = target_cell
	info.base_damage = base_damage
	info.impact_power = impact_power

	# STRENGTH атакующего прямо увеличивает урон (см. DECISIONS.md: STRENGTH
	# и IMPACT_POWER - разные оси, STRENGTH только на final_damage).
	var attacker_strength := attacker.get_value(StatTypes.StatType.STRENGTH)
	info.final_damage = base_damage + attacker_strength

	info.balance_added = impact_power
	info.would_break_balance = BalanceSystem.would_break(target, impact_power)

	if info.would_break_balance:
		info.push_direction = PushResolver.compute_push_direction(attacker_cell, target_cell)
		var raw_push_target := PushResolver.compute_push_target(target_cell, info.push_direction)
		var push_result := PushResolver.validate_push(target_cell, raw_push_target, data_provider, max_height_step)
		info.push_target_cell = push_result["final_cell"]
		info.push_blocked = not push_result["success"]
		info.push_blocked_reason = push_result["blocked_reason"]
	else:
		info.push_direction = Vector2i.ZERO
		info.push_target_cell = target_cell
		info.push_blocked = false
		info.push_blocked_reason = &""

	return info


## Применяет уже посчитанный DamageInfo: вычитает HP, добавляет Balance
## (через мутирующий BalanceSystem.apply_impact), эмитит события. НЕ
## перемещает юнита по сетке физически — возвращает push_target_cell в
## info, а фактическое перемещение на сетке выполняет вызывающий код/
## будущий Модуль 10 (Action & Visual Execution Queue), т.к. это требует
## анимации/визуализации, а не мгновенной мутации данных.
static func apply(info: DamageInfo) -> void:
	var hp_stat := info.target.get_stat(StatTypes.StatType.HP)
	hp_stat.set_base_value(hp_stat.get_value() - info.final_damage)
	GameEventBus.unit_damaged.emit(info.target, info.final_damage, info.attacker)

	var broke := BalanceSystem.apply_impact(info.target, info.balance_added)
	if broke:
		GameEventBus.unit_balance_broken.emit(info.target)
