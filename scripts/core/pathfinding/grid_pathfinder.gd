extends RefCounted
class_name GridPathfinder

## Поиск пути и расчёт зоны хода по логической сетке.
##
## ВАЖНО: правило высоты (переход между соседними клетками запрещён, если
## |height(a) - height(b)| > max_height_step) — это запрет конкретного
## РЕБРА графа, зависящий от пары клеток, а не свойство одной точки.
## AStarGrid2D умеет запрещать/взвешивать только ТОЧКИ (set_point_solid /
## set_point_weight_scale), а не пары точек — поэтому для гарантированно
## корректного и единообразного поведения find_path и get_reachable_cells
## реализованы одним и тем же собственным Dijkstra-алгоритмом с общей
## функцией проверки перехода (_can_move_between). Это чуть больше кода,
## чем "из коробки" AStarGrid2D, но исключает несогласованность правил
## между поиском пути и расчётом зоны хода.
##
## Движение только по 4 направлениям (без диагоналей) — соответствует
## правилам Into the Breach.

var _bounds: Rect2i
var _data: GridDataProvider
var _max_height_step: int = 1
var _profile: StringName = &"legacy_move_v1"

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


func configure(bounds: Rect2i, data_provider: GridDataProvider, max_height_step: int = 1, profile: StringName = &"legacy_move_v1") -> void:
	_bounds = bounds
	_data = data_provider
	_max_height_step = max_height_step
	_profile = profile


## Ищет путь между клетками с учётом проходимости, высоты и стоимости.
## Возвращает пустой массив, если пути не существует.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _data == null:
		return []
	if _profile != &"legacy_move_v1" and _profile != &"spatial_move_v1": return []
	if _profile == &"spatial_move_v1" and (not _data.has_spatial_heights() or _max_height_step != 1): return []
	if not _bounds.has_point(from) or not _bounds.has_point(to):
		return []
	if not _data.cell_is_walkable(from) or not _data.cell_is_walkable(to):
		return []

	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = {from: 0.0}
	var frontier: Array = [[0.0, from]]
	var found := false

	while frontier.size() > 0:
		frontier.sort_custom(_frontier_less)
		var current_entry = frontier.pop_front()
		var current_cost: float = current_entry[0]
		var current_cell: Vector2i = current_entry[1]

		if current_cost > cost_so_far.get(current_cell, INF):
			continue
		if current_cell == to:
			found = true
			break

		for offset in _NEIGHBOR_OFFSETS:
			var neighbor := current_cell + offset
			if not _bounds.has_point(neighbor):
				continue
			if not _can_move_between(current_cell, neighbor):
				continue

			var new_cost := current_cost + (_spatial_edge(current_cell, neighbor) if _profile == &"spatial_move_v1" else _data.cell_move_cost(neighbor))
			if _profile == &"spatial_move_v1" and not is_finite(new_cost): continue
			if not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current_cell
				frontier.append([new_cost, neighbor])

	if not found:
		return []

	var path: Array[Vector2i] = [to]
	var walk_cell: Vector2i = to
	while walk_cell != from:
		walk_cell = came_from[walk_cell]
		path.append(walk_cell)
	path.reverse()
	return path


## Возвращает словарь [Vector2i -> float] всех клеток, достижимых из `from`
## с суммарной стоимостью пути <= max_cost (включая саму `from` со стоимостью 0).
## Собственная реализация (Dijkstra/BFS с накоплением стоимости), так как
## AStarGrid2D не предоставляет multi-target range queries.
func get_reachable_cells(from: Vector2i, max_cost: float) -> Dictionary:
	var result: Dictionary = {}
	if _profile == &"spatial_move_v1" and (not is_finite(max_cost) or max_cost < 0.0): return result
	if _data == null or not _bounds.has_point(from):
		return result
	if _profile != &"legacy_move_v1" and _profile != &"spatial_move_v1": return result
	if _profile == &"spatial_move_v1" and (not _data.has_spatial_heights() or _max_height_step != 1): return result
	if not _data.cell_is_walkable(from):
		return result

	result[from] = 0.0

	# Простая приоритетная очередь: массив пар (cost, cell), сортируемый
	# при вставке. Для сеток тактического боя (десятки-сотни клеток)
	# этого достаточно, не требует отдельной heap-структуры.
	var frontier: Array = [[0.0, from]]

	while frontier.size() > 0:
		frontier.sort_custom(_frontier_less)
		var current_entry = frontier.pop_front()
		var current_cost: float = current_entry[0]
		var current_cell: Vector2i = current_entry[1]

		if current_cost > result.get(current_cell, INF):
			continue

		for offset in _NEIGHBOR_OFFSETS:
			var neighbor := current_cell + offset
			if not _bounds.has_point(neighbor):
				continue
			if not _can_move_between(current_cell, neighbor):
				continue

			var step_cost := _spatial_edge(current_cell, neighbor) if _profile == &"spatial_move_v1" else _data.cell_move_cost(neighbor)
			var new_cost := current_cost + step_cost
			if _profile == &"spatial_move_v1" and not is_finite(new_cost): continue
			if new_cost > max_cost:
				continue

			if not result.has(neighbor) or new_cost < result[neighbor]:
				result[neighbor] = new_cost
				frontier.append([new_cost, neighbor])

	return result


func is_cell_reachable(from: Vector2i, to: Vector2i, max_cost: float) -> bool:
	return get_reachable_cells(from, max_cost).has(to)

func _frontier_less(a: Array, b: Array) -> bool:
	if a[0] != b[0] or _profile != &"spatial_move_v1": return a[0] < b[0]
	var ac: Vector2i = a[1]
	var bc: Vector2i = b[1]
	return ac.y < bc.y or (ac.y == bc.y and ac.x < bc.x)


## Проверка возможности перехода между соседними (по 4-connectivity) клетками:
## обе должны быть проходимы и разница высот не должна превышать max_height_step.
func _can_move_between(a: Vector2i, b: Vector2i) -> bool:
	if _profile == &"spatial_move_v1":
		return SpatialRules.inspect_edge(_data, a, b).reason == &""
	if not _data.cell_is_walkable(b):
		return false
	var height_diff := absi(_data.cell_height(a) - _data.cell_height(b))
	return height_diff <= _max_height_step

func _spatial_edge(a: Vector2i, b: Vector2i) -> float:
	return SpatialRules.inspect_edge(_data, a, b).cost
