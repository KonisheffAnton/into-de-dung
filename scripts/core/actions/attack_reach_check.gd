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
