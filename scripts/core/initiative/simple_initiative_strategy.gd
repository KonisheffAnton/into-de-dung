extends TurnOrderStrategy
class_name SimpleInitiativeStrategy

## Базовая формула порядка ходов: выше INITIATIVE — ходит раньше.
## При равенстве значений порядок между "уравненными" участниками
## перемешивается случайно (по требованию геймдизайна), но результат
## остаётся стабильным до следующего явного пересчёта (не дёргается
## каждый кадр — компонент вызывается только при необходимости).

func compute_order(participants: Array[StatsComponent]) -> Array[StatsComponent]:
	var result := participants.duplicate()

	# Случайный тай-брейк реализован через рандомизированный вторичный ключ,
	# сгенерированный один раз на вызов — стабильный порядок внутри одного
	# пересчёта, но каждый новый compute_order() может иначе разрешить равенство.
	var tiebreak_keys: Dictionary = {}
	for participant in result:
		tiebreak_keys[participant] = randf()

	result.sort_custom(func(a: StatsComponent, b: StatsComponent) -> bool:
		var initiative_a := a.get_value(StatTypes.StatType.INITIATIVE)
		var initiative_b := b.get_value(StatTypes.StatType.INITIATIVE)
		if not is_equal_approx(initiative_a, initiative_b):
			return initiative_a > initiative_b
		return tiebreak_keys[a] < tiebreak_keys[b]
	)

	return result
