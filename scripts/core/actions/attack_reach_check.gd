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
	return inspect_spatial_cells(board, actor.cell, actor.faction, target.cell, attack_range)

## Проекция клетки не меняет UnitState/occupancy при чтении зоны угрозы.
static func inspect_spatial_cells(board: BattleBoard, origin: Vector2i, faction: Faction.Type, destination: Vector2i, attack_range: float) -> StringName:
	if board == null: return &"attack/invalid_runtime"
	if not is_finite(attack_range) or attack_range != floorf(attack_range) or attack_range < 1.0 or attack_range > 4096.0: return &"attack/invalid_range"
	if not board.is_in_bounds(origin) or not board.is_in_bounds(destination): return &"attack/out_of_bounds"
	if origin == destination: return &"attack/not_aligned"
	var dx: int = destination.x - origin.x
	var dy: int = destination.y - origin.y
	if dx != 0 and dy != 0: return &"attack/not_aligned"
	var distance: int = absi(dx) + absi(dy)
	var required: int = distance + floori(float(absi(board.get_height_steps(destination) - board.get_height_steps(origin))) / 2.0)
	if required > int(attack_range): return &"attack/out_of_reach"
	var step := Vector2i(signi(dx), signi(dy))
	for i in range(1, distance):
		var cell := origin + step * i
		var occupant := board.occupant_at(cell)
		if board.get_terrain(cell) == TerrainType.Type.WALL or (occupant != null and occupant.faction != faction): return &"attack/line_blocked"
	var actor_steps := board.get_height_steps(origin)
	var target_steps := board.get_height_steps(destination)
	var previous := actor_steps
	for i in range(1, distance + 1):
		var current := board.get_height_steps(origin + step * i)
		if (target_steps > actor_steps and current < previous) or (target_steps < actor_steps and current > previous): return &"attack/terrain_shape_unsupported"
		if board.get_terrain(origin + step * i) == TerrainType.Type.VOID: return &"attack/terrain_shape_unsupported"
		previous = current
	return &""
