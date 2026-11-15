extends RefCounted
class_name CharacterAttributeRules

const BASE_BALANCE_MAX: float = 5.0

static func power_multiplier(value: float) -> float:
	return 1.0 + 0.02 * (maxf(0.0, value) - 10.0)

static func status_multiplier(value: float) -> float:
	return 1.0 + 0.03 * (maxf(0.0, value) - 10.0)

static func position_bonus_multiplier(value: float) -> float:
	return 1.0 + 0.06 * (maxf(0.0, value) - 10.0)

static func critical_multiplier(value: float) -> float:
	return 2.0 + 0.10 * (maxf(0.0, value) - 10.0)

static func max_hp(value: float) -> float:
	return 28.0 + maxf(0.0, value) - 10.0

static func balance_max(value: float) -> float:
	# Пятёрки дают ступенчатый рост; floor сохраняет штраф ниже нейтральных десяти.
	return BASE_BALANCE_MAX + floorf((maxf(0.0, value) - 10.0) / 5.0)

static func move_max(value: float) -> float:
	var delta := maxf(0.0, value) - 10.0
	return 4.0 + signf(delta) * floorf(absf(delta) / 5.0)

static func resistance_contribution(value: float) -> float:
	return maxf(0.0, value) - 10.0
