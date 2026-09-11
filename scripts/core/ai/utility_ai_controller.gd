extends RefCounted
class_name UtilityAIController

## Точка входа Utility AI. `decide()` вызывается ОДИН раз за ход юнита и
## возвращает ОДНО лучшее намерение (`AIAction`) — "дойти до клетки X" или
## "дойти до X и атаковать Y" — совместимое с UI-потоком Move+Attack одним
## подтверждением (см. DECISIONS.md). (Сохранённое решение модуля 7.)
##
## Расширяемость на несколько итераций решения за ход сохранена: `decide()`
## не хранит состояния между вызовами, поэтому его можно безопасно вызвать в
## цикле с ОБНОВЛЁННЫМ контекстом после каждого частичного действия.
##
## ЧТО ИСПРАВЛЕНО:
##
## 1. C-1: работает с `UnitState` — теперь контроллеру доступны фракция,
##    позиция и факт смерти. Контекст строится фабрикой
##    `AIDecisionContext.build_for()`, а не заполняется вручную снаружи.
##
## 2. S-3г: ДЕТЕРМИНИРОВАННЫЙ тай-брейк. Раньше `_pick_best` использовал
##    строгий `>`, поэтому при равных оценках побеждал первый ВСТРЕЧЕННЫЙ
##    кандидат, а порядок обхода задавался порядком вставки в Dictionary
##    (то есть порядком обхода Dijkstra). Это делало решения ИИ
##    невоспроизводимыми: реплеи и сиды роглайка ломались, а баг-репорты
##    нельзя было повторить. Теперь при равенстве сравниваются
##    `(cell.y, cell.x, target_id)` — строгий детерминированный порядок (R-5).
##
## 3. S-3б: тип действия — enum вместо строк.
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (S-3а, отложено до работающего среза по R-7):
## генерация кандидатов всё ещё захардкожена в `_generate_candidates()`.
## Документация модуля 7 обещала "новый тип кандидата добавляется отдельным
## генератором без изменения контроллера", но фактически это требует правки
## этого файла. Нужны подключаемые `AIActionGenerator : Resource` в профиле.
## Отложено: пока в игре одно действие (атака в упор), генераторы нечем
## наполнить.


## `unit` — думающий (ИИ) юнит. Его позиция берётся из `unit.cell`.
## `profile` — `AIBehaviorProfile.tres`, определяющий "личность" врага.
## `pathfinder` — уже `configure()`-нный `GridPathfinder` для текущей карты.
## `context` — снимок ситуации (см. `AIDecisionContext.build_for()`).
## `attack_range` — в клетках по манхэттену (1 = ближний бой, см. DECISIONS.md).
static func decide(
	unit: UnitState,
	profile: AIBehaviorProfile,
	pathfinder: GridPathfinder,
	context: AIDecisionContext,
	base_damage: float,
	attack_range: int = 1
) -> AIAction:
	if unit == null or not unit.is_alive():
		return AIAction.make_idle(unit.cell if unit != null else Vector2i.ZERO)

	if profile == null or pathfinder == null or context == null:
		return AIAction.make_idle(unit.cell)

	# Используем ОСТАТОК очков хода, а не максимум MOVE_RANGE: если юнит уже
	# частично сдвинулся в этом ходу, он не должен планировать полный ход.
	var move_budget := unit.move_points_left
	var reachable_cells := pathfinder.get_reachable_cells(unit.cell, move_budget)

	var candidates := _generate_candidates(
		unit, reachable_cells, context, base_damage, attack_range
	)

	return _pick_best(candidates, profile, context, unit.cell)


## Строит полный список кандидатов: move для каждой достижимой клетки плюс
## move_and_attack для клеток, из которых достижим враг в `attack_range`.
static func _generate_candidates(
	unit: UnitState,
	reachable_cells: Dictionary,
	context: AIDecisionContext,
	base_damage: float,
	attack_range: int
) -> Array[AIAction]:
	var candidates: Array[AIAction] = []
	var impact_power := unit.get_stat(StatTypes.StatType.IMPACT_POWER)
	var can_attack := unit.can_attack()

	for key in reachable_cells.keys():
		var final_cell: Vector2i = key

		# Клетка занята другим юнитом — встать туда нельзя.
		# ПРИМЕЧАНИЕ (C-4): пока это проверяется по контексту ИИ, потому что
		# occupancy-слоя нет. На шаге 0.4 фильтрация переедет в
		# `GridDataProvider`, который построит `BattleBoard`, и тогда
		# `get_reachable_cells` перестанет возвращать занятые клетки вовсе.
		if final_cell != unit.cell:
			if context.enemy_cells.has(final_cell) or context.ally_cells.has(final_cell):
				continue

		# Кандидат перемещения (или "остаться на месте", если это текущая
		# клетка — она всегда входит в reachable со стоимостью 0).
		if final_cell == unit.cell:
			candidates.append(AIAction.make_idle(final_cell))
		else:
			candidates.append(AIAction.make_move(final_cell))

		if not can_attack:
			continue

		# Кандидаты атаки: для каждого врага в пределах attack_range от
		# final_cell строим move_and_attack с готовым DamageInfo через
		# ActionPreview — ЧИСТЫЙ расчёт, безопасный для сравнения.
		for enemy_key in context.enemy_cells.keys():
			var enemy_cell: Vector2i = enemy_key
			if AIGridMath.manhattan_distance(final_cell, enemy_cell) > attack_range:
				continue

			var enemy: UnitState = context.enemy_cells[enemy_cell]
			if enemy == null or not enemy.is_alive():
				continue

			var info := ActionPreview.build(
				unit, enemy,
				final_cell, enemy_cell,
				base_damage, impact_power,
				context.data_provider, context.max_height_step
			)
			candidates.append(
				AIAction.make_move_and_attack(final_cell, enemy, enemy_cell, info)
			)

	return candidates


## Оценивает кандидатов профилем поведения и возвращает лучшего.
## Никогда не возвращает null — при пустом списке отдаёт idle-заглушку,
## чтобы вызывающему коду (Battle Flow) не приходилось обрабатывать
## этот edge-case отдельно. (Сохранено.)
static func _pick_best(
	candidates: Array[AIAction],
	profile: AIBehaviorProfile,
	context: AIDecisionContext,
	fallback_cell: Vector2i
) -> AIAction:
	if candidates.is_empty():
		return AIAction.make_idle(fallback_cell)

	var best: AIAction = null
	var best_score := -INF

	for candidate in candidates:
		var s := profile.evaluate(candidate, context)
		candidate.score = s

		if best == null or s > best_score:
			best_score = s
			best = candidate
		elif is_equal_approx(s, best_score) and _is_preferred_tiebreak(candidate, best):
			best = candidate

	return best if best != null else AIAction.make_idle(fallback_cell)


## Детерминированный тай-брейк при равных оценках (S-3г): сравниваем по
## стабильным признакам в фиксированном порядке. Без этого решение зависело
## от порядка обхода Dictionary и было невоспроизводимым.
static func _is_preferred_tiebreak(candidate: AIAction, current_best: AIAction) -> bool:
	# 1. Атака предпочтительнее пассивного действия при равном score.
	var candidate_attacks := candidate.has_attack()
	var best_attacks := current_best.has_attack()
	if candidate_attacks != best_attacks:
		return candidate_attacks

	# 2. Клетка с меньшим (y, x) — стабильный порядок обхода сетки.
	if candidate.final_cell.y != current_best.final_cell.y:
		return candidate.final_cell.y < current_best.final_cell.y
	if candidate.final_cell.x != current_best.final_cell.x:
		return candidate.final_cell.x < current_best.final_cell.x

	# 3. Цель с меньшим id — стабильна между запусками (в отличие от ссылки).
	var candidate_target_id := candidate.target.id if candidate.target != null else UnitId.NONE
	var best_target_id := current_best.target.id if current_best.target != null else UnitId.NONE
	return candidate_target_id < best_target_id
