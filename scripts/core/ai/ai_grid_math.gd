extends RefCounted
class_name AIGridMath

## Общие геометрические хелперы для AI-модуля. Вынесены отдельно, чтобы
## considerations не дублировали друг у друга подсчёт манхэттенского
## расстояния (используется как дешёвая эвристика "угрозы"/"близости",
## НЕ заменяет GridPathfinder там, где важна реальная проходимость).

static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
