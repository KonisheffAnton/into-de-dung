extends TurnOrderStrategy
class_name SimpleInitiativeStrategy

## Базовая формула порядка ходов: выше INITIATIVE — ходит раньше.
##
## ИЗМЕНЕНО (R-5, дефект G-1). Раньше при равной инициативе порядок
## перемешивался через глобальный `randf()`. Это ломало воспроизводимость:
## после загрузки сейва порядок ходов получался ДРУГИМ, реплеи и шаринг
## сидов роглайка становились невозможны, а баг-репорты — невоспроизводимыми.
##
## Теперь тай-брейк детерминированный и управляемый:
##  - `randomize_ties = false` (по умолчанию) — стабильный порядок по `UnitId`
##    (порядок создания юнитов). Предсказуемо и воспроизводимо.
##  - `randomize_ties = true` — случайность, но из ЯВНОГО seed через
##    `RandomNumberGenerator`, а не из глобального состояния. Seed задаётся
##    снаружи (`set_tiebreak_seed`) и должен сохраняться вместе с боем.
##    Когда появится `RngService` (шаг 0.10), seed будет приходить из него.
##
## Требование геймдизайна "рандом при равенстве" сохранено — но теперь оно
## не конфликтует с воспроизводимостью.

## Перемешивать ли юнитов с одинаковой инициативой.
@export var randomize_ties: bool = false

## Seed для тай-брейка. Меняется снаружи между раундами/боями.
var _tiebreak_seed: int = 0


func set_tiebreak_seed(value: int) -> void:
	_tiebreak_seed = value


func compute_order(participants: Array[UnitState]) -> Array[UnitState]:
	var result := participants.duplicate()

	# Вторичный ключ считается ОДИН раз на вызов: внутри одного пересчёта
	# порядок стабилен (сортировка не "дёргается"), но при новом seed
	# равенства могут разрешиться иначе.
	var tiebreak_keys: Dictionary = {} # unit_id -> int
	if randomize_ties:
		var rng := RandomNumberGenerator.new()
		rng.seed = _tiebreak_seed
		for participant in result:
			tiebreak_keys[participant.id] = rng.randi()
	else:
		for participant in result:
			tiebreak_keys[participant.id] = participant.id

	result.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var initiative_a := a.get_stat(StatTypes.StatType.INITIATIVE)
		var initiative_b := b.get_stat(StatTypes.StatType.INITIATIVE)
		if not is_equal_approx(initiative_a, initiative_b):
			return initiative_a > initiative_b
		var key_a: int = tiebreak_keys[a.id]
		var key_b: int = tiebreak_keys[b.id]
		return key_a < key_b
	)

	return result
