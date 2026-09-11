extends Resource
class_name AIBehaviorProfile

## Набор взвешенных `AIConsideration` для одного "типа поведения" врага
## (Aggressor, Blocker, ...). Подмена поведения = замена `.tres`-ресурса,
## как с `SimpleInitiativeStrategy` — без изменения кода. (Сохранено.)

@export var display_name: String = ""
@export var considerations: Array[AIConsideration] = []

## Агрегация: геометрическое среднее (по умолчанию) или арифметическое.
##
## ПОЧЕМУ ГЕОМЕТРИЧЕСКОЕ ПО УМОЛЧАНИЮ (часть фикса S-3в). Арифметическое
## среднее РАЗМЫВАЕТ плохие факторы: кандидат с оценками [1.0, 1.0, 0.0]
## получает 0.67 — то есть один фактор, категорически против, не может
## повлиять на решение. Для тактического ИИ это неверно: "встать под удар
## трёх врагов" должно резко снижать привлекательность, а не слегка.
## Геометрическое среднее даёт для тех же оценок 0.0 — каждый фактор имеет
## право "утопить" кандидата.
##
## Компенсация (make-up factor) по Dave Mark ("Behavioral Mathematics"):
## без неё геометрическое среднее систематически занижает оценку при росте
## числа факторов (перемножение чисел < 1), и профиль с 6 факторами всегда
## проигрывал бы профилю с 2. Компенсация это выравнивает.
@export var use_geometric_mean: bool = true


## Взвешенная оценка кандидата. Возвращает [0..1]; 0.0 при вето или при
## отсутствии высказавшихся факторов.
func evaluate(action: AIAction, context: AIDecisionContext) -> float:
	if considerations.is_empty():
		return 0.0

	var scores: Array[float] = []
	var weights: Array[float] = []
	var weight_total := 0.0

	for consideration in considerations:
		if consideration == null:
			continue
		var w := consideration.weight
		if w <= 0.0:
			continue

		var s := consideration.score(action, context)

		# ВЕТО: кандидат недопустим — немедленный выход, без усреднения.
		if AIConsideration.is_veto(s):
			return 0.0

		# ABSTAIN: фактор не имеет мнения — НЕ попадает ни в числитель, ни в
		# знаменатель. Раньше вместо этого возвращался 0.0, что было голосом
		# против (дефект S-3в).
		if AIConsideration.is_abstain(s):
			continue

		scores.append(clampf(s, 0.0, 1.0))
		weights.append(w)
		weight_total += w

	# Ни один фактор не высказался — кандидат нейтрален.
	if weight_total <= 0.0:
		return 0.0

	if not use_geometric_mean:
		var weighted_sum := 0.0
		for i in scores.size():
			weighted_sum += scores[i] * weights[i]
		return weighted_sum / weight_total

	return _weighted_geometric_mean(scores, weights, weight_total)


## Взвешенное геометрическое среднее с компенсацией:
##     result = Π ( s_i ^ (w_i / Σw) ) с make-up factor
## Считается через логарифмы: прямое перемножение степеней быстро теряет
## точность при большом числе факторов.
func _weighted_geometric_mean(
	scores: Array[float],
	weights: Array[float],
	weight_total: float
) -> float:
	var count := scores.size()
	if count == 0:
		return 0.0

	# Make-up factor: компенсирует систематическое занижение при росте числа
	# факторов. Чем больше факторов, тем сильнее каждая отдельная оценка
	# "подтягивается" к 1.0 перед перемножением.
	var modification_factor := 1.0 - (1.0 / float(count))

	var log_sum := 0.0
	for i in count:
		var s := scores[i]
		var w := weights[i]

		# Ноль обнуляет произведение целиком — это намеренно (см. выше:
		# каждый фактор имеет право утопить кандидата).
		if s <= 0.0:
			return 0.0

		var make_up := (1.0 - s) * modification_factor
		var adjusted := clampf(s + make_up * s, 0.0, 1.0)
		log_sum += (w / weight_total) * log(adjusted)

	return clampf(exp(log_sum), 0.0, 1.0)
