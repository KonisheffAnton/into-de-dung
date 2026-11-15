extends RefCounted
class_name BalancePoints

const GUARD_REDUCTION: int = 2

## Очки равновесия целые; float сохраняет существующую форму снимка.
## Округление выполняется после всех множителей воздействия, один раз на получателя.
static func whole(value: float) -> float:
	return floorf(value)

static func valid(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value == floorf(value)

static func guard_impact(value: float) -> float:
	return maxf(0.0, value - GUARD_REDUCTION)
