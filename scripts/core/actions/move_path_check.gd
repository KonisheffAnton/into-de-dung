extends RefCounted
class_name MovePathCheck

const MAX_PATH_CELLS: int = 33
const MAX_ID: int = 9223372036854775807

var _reason: StringName = &""
var _costs: Array[float] = []
var _total_cost: float = 0.0

static func inspect(board: BattleBoard, actor: UnitState, path: Array[Vector2i], max_height_step: int, budget: float, profile: StringName = &"legacy_move_v1") -> MovePathCheck:
	var result := MovePathCheck.new()
	if board == null or actor == null:
		result._reason = &"move/invalid_runtime"
		return result
	if max_height_step < 0 or max_height_step > 2147483647:
		result._reason = &"move/invalid_rules"
		return result
	if profile != &"legacy_move_v1" and profile != &"spatial_move_v1":
		result._reason = &"move/invalid_rules"
		return result
	if profile == &"spatial_move_v1" and max_height_step != 1:
		result._reason = &"move/invalid_rules"
		return result
	if not is_finite(budget) or budget < 0.0:
		result._reason = &"move/invalid_budget"
		return result
	if path.size() < 2 or path.size() > MAX_PATH_CELLS:
		result._reason = &"move/path_length"
		return result
	if profile == &"legacy_move_v1" and board.has_half_heights():
		result._reason = &"move/height_units_unsupported"
		return result

	# Проверяем bounds всего payload до разностей координат и вызовов provider.
	for cell in path:
		if not board.is_in_bounds(cell):
			result._reason = &"move/out_of_bounds"
			return result
	var provider := board.make_spatial_data_provider(actor) if profile == &"spatial_move_v1" else board.make_data_provider(actor)
	if profile == &"spatial_move_v1" and not provider.has_spatial_heights():
		result._reason = &"move/height_units_unsupported"
		return result
	if not provider.cell_is_walkable(path[0]):
		result._reason = &"move/blocked"
		return result
	var costs: Array[float] = []
	for index in range(1, path.size()):
		var previous: Vector2i = path[index - 1]
		var current: Vector2i = path[index]
		var dx: int = int(current.x) - int(previous.x)
		var dy: int = int(current.y) - int(previous.y)
		if (absi(dx) + absi(dy)) != 1:
			result._reason = &"move/not_adjacent"
			return result
		if not provider.cell_is_walkable(current):
			result._reason = &"move/blocked"
			return result
		if profile == &"spatial_move_v1":
			var edge := SpatialRules.inspect_edge(provider, previous, current)
			if edge.reason != &"":
				result._reason = edge.reason
				return result
			costs.append(edge.cost)
			continue
		var height_delta: int = int(provider.cell_height(current)) - int(provider.cell_height(previous))
		if absi(height_delta) > max_height_step:
			result._reason = &"move/height_step"
			return result
		var cost: float = provider.cell_move_cost(current)
		costs.append(cost)
	var arithmetic := _check_costs(costs, budget)
	result._reason = arithmetic["reason"] as StringName
	if result._reason == &"":
		result._costs = costs.duplicate()
		result._total_cost = float(arithmetic["total"])
	return result

func get_reason() -> StringName:
	return _reason

func get_costs() -> Array[float]:
	return _costs.duplicate()

func get_total_cost() -> float:
	return _total_cost

static func _check_costs(costs: Array[float], budget: float) -> Dictionary:
	var answer: Dictionary = {"reason": &"", "total": 0.0}
	if not is_finite(budget) or budget < 0.0:
		answer["reason"] = &"move/invalid_budget"
		return answer
	var total: float = 0.0
	var remaining: float = budget
	for cost in costs:
		if not is_finite(cost) or cost < 1.0:
			answer["reason"] = &"move/invalid_cost"
			return answer
		var next_total: float = total + cost
		if not is_finite(next_total):
			answer["reason"] = &"move/cost_overflow"
			return answer
		total = next_total
		if total > budget:
			answer["reason"] = &"move/insufficient_move"
			return answer
		if remaining < cost:
			answer["reason"] = &"move/insufficient_move"
			return answer
		var next_remaining: float = remaining - cost
		if next_remaining >= remaining or not is_finite(next_remaining) or remaining - next_remaining != cost:
			answer["reason"] = &"move/unrepresentable_debit"
			return answer
		remaining = next_remaining
	answer["total"] = total
	return answer
