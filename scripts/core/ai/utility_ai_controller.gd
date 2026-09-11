extends RefCounted
class_name UtilityAIController

## Точка входа Модуля 7 (Extensible Utility AI). MVP-контракт (Вариант A из
## обсуждения): decide() вызывается ОДИН раз за ход юнита и возвращает ОДНО
## лучшее намерение (AIAction) — "дойти до клетки X" или "дойти до клетки X
## и атаковать Y" — совместимое с UI-потоком Move+Attack одним подтверждением
## (см. DECISIONS.md).
##
## Расширяемость на "сложное" поведение (Вариант B — несколько итераций
## решения за один ход) заложена намеренно:
## - decide() не хранит внутреннего состояния между вызовами (static-подобный,
##   без mutable полей) — его можно безопасно вызвать несколько раз за один
##   ход в цикле, передав ОБНОВЛЁННЫЙ AIDecisionContext/unit_cell после
##   каждого частичного действия, без каких-либо изменений в этом файле.
## - Генерация кандидатов (_generate_candidates) и выбор лучшего (_pick_best)
##   разделены на отдельные шаги — новый тип кандидата (например, "использовать
##   предмет/способность") добавляется отдельной функцией-генератором без
##   переписывания оценки.
## - Сама оценка (score) полностью делегирована AIBehaviorProfile/
##   AIConsideration — контроллер не знает НИЧЕГО о конкретных тактических
##   мотивах (Balance exploit, hazard push, safety...).

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## unit_stats/unit_cell — атакующий (ИИ) юнит и его текущая позиция.
## profile — AIBehaviorProfile.tres, определяющий "личность" врага.
## pathfinder — уже configure()-нный GridPathfinder для текущей карты.
## context — снимок ситуации (см. AIDecisionContext), включая enemy_cells.
## base_damage/attack_range — параметры атаки этого юнита (attack_range в
## клетках по манхэттену, 1 = ближний бой, как договорено в DECISIONS.md).
static func decide(
	unit_stats: StatsComponent,
	unit_cell: Vector2i,
	profile: AIBehaviorProfile,
	pathfinder: GridPathfinder,
	context: AIDecisionContext,
	base_damage: float,
	attack_range: int = 1
) -> AIAction:
	var move_range := unit_stats.get_value(StatTypes.StatType.MOVE_RANGE)
	var reachable_cells := pathfinder.get_reachable_cells(unit_cell, move_range)

	var candidates := _generate_candidates(
		unit_stats, reachable_cells, context, base_damage, attack_range
	)

	return _pick_best(candidates, profile, context)


## Строит полный список кандидатов: idle/move для каждой достижимой клетки,
## плюс move_and_attack для клеток, из которых достижим враг в attack_range.
static func _generate_candidates(
	unit_stats: StatsComponent,
	reachable_cells: Dictionary,
	context: AIDecisionContext,
	base_damage: float,
	attack_range: int
) -> Array[AIAction]:
	var candidates: Array[AIAction] = []
	var impact_power := unit_stats.get_value(StatTypes.StatType.IMPACT_POWER)

	for final_cell in reachable_cells.keys():
		# Кандидат простого перемещения (или "остаться на месте", если
		# final_cell == текущая клетка юнита — она всегда входит в reachable
		# с стоимостью 0).
		var move_action := AIAction.new()
		move_action.action_type = &"move"
		move_action.final_cell = final_cell
		candidates.append(move_action)

		# Кандидаты атаки: для каждого врага в пределах attack_range от
		# final_cell строим move_and_attack с готовым DamageInfo (через
		# ActionPreview — ЧИСТЫЙ расчёт, безопасный для превью/сравнения).
		for enemy_cell in context.enemy_cells.keys():
			if AIGridMath.manhattan_distance(final_cell, enemy_cell) > attack_range:
				continue

			var enemy_stats: StatsComponent = context.enemy_cells[enemy_cell]
			var attack_action := AIAction.new()
			attack_action.action_type = &"move_and_attack"
			attack_action.final_cell = final_cell
			attack_action.target = enemy_stats
			attack_action.target_cell = enemy_cell
			attack_action.damage_info = ActionPreview.build(
				unit_stats, enemy_stats,
				final_cell, enemy_cell,
				base_damage, impact_power,
				context.data_provider, context.max_height_step
			)
			candidates.append(attack_action)

	return candidates


## Оценивает каждого кандидата через профиль поведения и возвращает
## кандидата с максимальным score. При пустом списке возвращает idle-заглушку
## (юнит остаётся на месте) — контроллер никогда не возвращает null, чтобы
## вызывающему коду (Battle Flow, Модуль 8) не нужно было каждый раз
## обрабатывать этот edge-case отдельно.
static func _pick_best(
	candidates: Array[AIAction],
	profile: AIBehaviorProfile,
	context: AIDecisionContext
) -> AIAction:
	if candidates.is_empty():
		return AIAction.new()

	var best: AIAction = null
	var best_score := -INF

	for candidate in candidates:
		var s := profile.evaluate(candidate, context)
		candidate.score = s
		if s > best_score:
			best_score = s
			best = candidate

	return best
