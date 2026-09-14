extends RefCounted
class_name DamageCalculator

## Расчёт и применение результата атаки.
##
## `calculate()` НЕ мутирует состояние (безопасно для Preview UI — можно
## вызывать многократно), `apply()` мутирует и сообщает о событиях. Оба
## используют один и тот же `DamageInfo` — гарантия, что превью и реальное
## исполнение совпадают. (Сохранённое решение модуля 6.)
##
## ЧТО ИСПРАВЛЕНО:
##
## 1. ДЕФЕКТ C-2 (порча данных). Раньше `apply()` делал:
##        hp_stat.set_base_value(hp_stat.get_value() - info.final_damage)
##    `get_value()` = база + модификаторы, поэтому запись результата в базу
##    ВПЕКАЛА модификаторы. HP base=10 + амулет +5 -> урон 3 -> HP становилось
##    17 вместо 12. Теперь урон идёт через `Vitals.apply_damage()`, который
##    работает с отдельным полем-состоянием, клампит по нулю и сообщает о
##    смерти. Записать модификаторы в базу стало невозможно (R-2).
##
## 2. ДЕФЕКТ S-4 (скрытая зависимость от автозагрузки). Раньше статический
##    `apply()` эмитил прямо в `GameEventBus`, из-за чего боевую логику нельзя
##    было выполнить в тесте и нельзя было прогнать изолированную симуляцию
##    (нужна для AI-lookahead и sandbox-превью, R-6). Теперь сток событий
##    ИНЖЕКТИРУЕТСЯ (`EventSink`), по умолчанию нулевой (R-3).
##
## 3. Появилось предсказание смерти (`would_kill`) — раньше смерти не
##    существовало как понятия, и превью не могло её показать.
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (S-1, отложено до работающего среза по R-7):
## формула `final_damage = base_damage + STRENGTH - ARMOR` захардкожена. Для
## роглайка с синергиями нужен конвейер `DamageModifier : Resource` (стадии
## FLAT/PERCENT/MULT), иначе каждый предмет вида "+50% урона по цели со
## сломанным балансом" требует правки этого файла. Отложено сознательно:
## пока нет игрового цикла, конвейер невозможно проверить на практике.
##
## ЧИСТАЯ функция: ничего не мутирует, безопасна для превью и для оценки
## кандидатов ИИ (вызывается десятки раз за ход).
##
## `attacker_cell`/`target_cell` передаются ЯВНО (не читаются из "текущей"
## позиции юнита) — необходимо для комбо-потока Move+Attack, где превью
## строится ДО фактического перемещения (см. DECISIONS.md).
## `board` — авторитетное состояние доски (шаг 0.4). Через него резолвер
## толкания видит ЮНИТОВ, а не только геометрию, и поэтому может сообщить о
## столкновении и падении в пропасть (было невозможно из-за дефекта C-4).
static func calculate(
	attacker: UnitState,
	target: UnitState,
	attacker_cell: Vector2i,
	target_cell: Vector2i,
	base_damage: float,
	impact_power: float,
	board: BattleBoard,
	max_height_step: int = 1
) -> DamageInfo:
	var info := DamageInfo.new()
	info.attacker = attacker
	info.target = target
	info.attacker_cell = attacker_cell
	info.target_cell = target_cell
	info.base_damage = base_damage
	info.impact_power = impact_power

	if attacker == null or target == null:
		return info

	# STRENGTH прямо увеличивает урон, ARMOR — плоско снижает.
	# IMPACT_POWER на урон НЕ влияет: это отдельная ось геймдизайна (можно
	# бить сильно, но не толкать, и наоборот) — см. DECISIONS.md.
	var attacker_strength := attacker.get_stat(StatTypes.StatType.STRENGTH)
	var target_armor := target.get_stat(StatTypes.StatType.ARMOR)
	info.final_damage = maxf(0.0, base_damage + attacker_strength - target_armor)
	info.balance_added = impact_power

	# Предсказание смерти и слома баланса — читаем текущее состояние,
	# но НЕ меняем его.
	if target.vitals != null:
		info.would_kill = target.vitals.get_hp() - info.final_damage <= 0.0
		info.would_break_balance = target.vitals.would_break(impact_power)

	if info.would_break_balance:
		info.push_direction = PushResolver.compute_push_direction(attacker_cell, target_cell)
		# Полный резолв с учётом юнитов/террейна/высот: результат различает
		# перемещение, упор в стену, СТОЛКНОВЕНИЕ с юнитом и падение в
		# пропасть. Превью обязано показать всю цепочку (R-6).
		info.push_result = PushResolver.resolve_push(
			board, target, target_cell, info.push_direction, max_height_step
		)
		info.push_target_cell = info.push_result.final_cell
		info.push_blocked = not info.push_result.moved()
		info.push_blocked_reason = info.push_result.blocked_reason

		# Толчок сам может убить цель (пропасть) — превью показывает это до
		# подтверждения. Раньше предсказать было нечем: не было ни occupancy,
		# ни понятия смерти.
		if info.push_result.is_lethal():
			info.would_kill = true
	else:
		info.push_direction = Vector2i.ZERO
		info.push_target_cell = target_cell
		info.push_blocked = false
		info.push_blocked_reason = &""
		info.push_result = null

	return info


## Применяет уже посчитанный `DamageInfo`: снимает HP через `Vitals`,
## накапливает Баланс, сообщает о событиях в переданный сток.
##
## НЕ перемещает юнита по сетке физически — `push_target_cell` возвращается в
## `info`, а фактическое перемещение выполняет `PushCommand` (шаг 0.5), т.к.
## это требует анимации и обновления occupancy на доске, а не мгновенной
## мутации данных. (Сохранённое решение модуля 6.)
##
## `sink` по умолчанию нулевой — вызывающий код обязан передать
## `GameEventBusSink` для реального боя (R-3).
static func apply(info: DamageInfo, sink: EventSink = null) -> void:
	if info == null or info.target == null or info.target.vitals == null:
		return

	var event_sink := sink if sink != null else EventSink.new()
	var vitals := info.target.vitals

	# 1. Урон. Vitals клампит по нулю и возвращает ФАКТИЧЕСКИ снятое
	#    количество — важно для эффектов вида "вампиризм по нанесённому
	#    урону", чтобы они не лечили за оверкилл.
	var was_alive := vitals.is_alive()
	var dealt := vitals.apply_damage(info.final_damage)
	# Фиксируем переход сразу: сток может синхронно запустить вложенный apply().
	var died_in_this_apply := was_alive and not vitals.is_alive()
	if dealt > 0.0:
		event_sink.unit_damaged(info.target, dealt, info.attacker)

	# 2. Баланс — только для живых: мёртвого толкать бессмысленно.
	#    ПРИМЕЧАНИЕ (D-6.3): порядок "смерть vs толкание" зафиксирован явно —
	#    смерть приоритетнее. Полноценное разрешение (цепные толчки, урон при
	#    столкновении) — работа PushCommand на шаге 0.5.
	if vitals.is_alive():
		var old_balance := vitals.get_balance()
		var broke := vitals.add_impact(info.balance_added)
		var new_balance := vitals.get_balance()
		if not is_equal_approx(old_balance, new_balance):
			event_sink.unit_balance_changed(info.target, old_balance, new_balance)
		if broke:
			event_sink.unit_balance_broken(info.target)

	# 3. Смерть — последней, чтобы подписчики видели финальное состояние.
	if died_in_this_apply:
		event_sink.unit_died(info.target, info.attacker)
