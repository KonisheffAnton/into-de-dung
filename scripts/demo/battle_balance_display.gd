extends RefCounted
class_name BattleBalanceDisplay

# UI получает запас, потому что runtime balance хранит уже потраченную устойчивость.
static func remaining(disruption: float, maximum: float) -> float:
	var whole_maximum := BalancePoints.whole(maximum)
	if whole_maximum <= 0.0:
		return 0.0
	return clampf(whole_maximum - BalancePoints.whole(disruption), 0.0, whole_maximum)

static func ratio(disruption: float, maximum: float) -> float:
	var whole_maximum := BalancePoints.whole(maximum)
	if whole_maximum <= 0.0:
		return 1.0
	return remaining(disruption, whole_maximum) / whole_maximum

static func value_text(disruption: float, maximum: float) -> String:
	var whole_maximum := BalancePoints.whole(maximum)
	if whole_maximum <= 0.0:
		return "невосприимчив"
	return "%s/%s" % [_number(remaining(disruption, whole_maximum)), _number(whole_maximum)]

static func _number(value: float) -> String:
	return String.num(BalancePoints.whole(value), 0)
