extends RefCounted
class_name BattleBalanceDisplay

# UI получает запас, потому что runtime balance хранит уже потраченную устойчивость.
static func remaining(disruption: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(maximum - disruption, 0.0, maximum)

static func ratio(disruption: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 1.0
	return remaining(disruption, maximum) / maximum

static func value_text(disruption: float, maximum: float) -> String:
	if maximum <= 0.0:
		return "невосприимчив"
	return "%s/%s" % [_number(remaining(disruption, maximum)), _number(maximum)]

static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, round(value)) else String.num(value, 1)
