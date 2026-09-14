extends RefCounted
class_name AttackReachCheck

static func inspect(board: BattleBoard, actor: UnitState, target: UnitState, attack_range: float) -> StringName:
	if board == null or actor == null or target == null:
		return &"attack/invalid_runtime"
	if not is_finite(attack_range) or attack_range != floorf(attack_range) or attack_range < 1.0 or attack_range > 4096.0:
		return &"attack/invalid_range"
	if attack_range != 1.0:
		return &"attack/reach_unsupported"
	if not board.is_in_bounds(actor.cell) or not board.is_in_bounds(target.cell):
		return &"attack/out_of_bounds"
	var dx: int = int(target.cell.x) - int(actor.cell.x)
	var dy: int = int(target.cell.y) - int(actor.cell.y)
	if absi(dx) + absi(dy) != 1:
		return &"attack/not_adjacent"
	if board.get_height(actor.cell) != board.get_height(target.cell):
		return &"attack/height_unsupported"
	return &""

static func inspect_spatial(board: BattleBoard, actor: UnitState, target: UnitState, attack_range: float) -> StringName:
	if board == null or actor == null or target == null: return &"attack/invalid_runtime"
	if not is_finite(attack_range) or attack_range != floorf(attack_range) or attack_range < 1.0 or attack_range > 4096.0: return &"attack/invalid_range"
	if not board.is_in_bounds(actor.cell) or not board.is_in_bounds(target.cell): return &"attack/out_of_bounds"
	if actor.cell == target.cell: return &"attack/not_aligned"
	var dx: int = target.cell.x - actor.cell.x
	var dy: int = target.cell.y - actor.cell.y
	if dx != 0 and dy != 0: return &"attack/not_aligned"
	var distance: int = absi(dx) + absi(dy)
	var required: int = distance + floori(float(absi(board.get_height_steps(target.cell) - board.get_height_steps(actor.cell))) / 2.0)
	if required > int(attack_range): return &"attack/out_of_reach"
	var step := Vector2i(signi(dx), signi(dy))
	for i in range(1, distance):
		var cell := actor.cell + step * i
		var occupant := board.occupant_at(cell)
		if board.get_terrain(cell) == TerrainType.Type.WALL or (occupant != null and occupant.faction != actor.faction): return &"attack/line_blocked"
	var actor_steps := board.get_height_steps(actor.cell)
	var target_steps := board.get_height_steps(target.cell)
	var previous := actor_steps
	for i in range(1, distance + 1):
		var current := board.get_height_steps(actor.cell + step * i)
		if (target_steps > actor_steps and current < previous) or (target_steps < actor_steps and current > previous): return &"attack/terrain_shape_unsupported"
		if board.get_terrain(actor.cell + step * i) == TerrainType.Type.VOID: return &"attack/terrain_shape_unsupported"
		previous = current
	return &""
