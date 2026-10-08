extends RefCounted
class_name BattleFieldPresentation

## Только позы показанного мира. Повторная выборка после resize не читает runtime.
const FALL_SECONDS: float = 0.22
const LAND_SECONDS: float = 0.07
const COLLAPSE_SECONDS: float = 0.22
const DEATH_SECONDS: float = 0.20
const HAZARD_SECONDS: float = 0.12
const SPIKE_EXTEND_SECONDS: float = 0.04
const SPIKE_HOLD_SECONDS: float = 0.70
const SPIKE_RETRACT_SECONDS: float = 0.10
var poses: Dictionary = {}
var cells: Dictionary = {}

func clear() -> void:
	poses.clear()
	cells.clear()

func restore(board: BattleDemoBoard) -> void:
	for id: int in poses.keys():
		var pose: Dictionary = poses[id]
		match pose.kind:
			&"fall": sample_fall(pose.progress, board, id, pose.from, pose.to, pose.vanish)
			&"death": sample_death(pose.progress, board, id)
			&"land": sample_land(pose.progress, board, id)
	for cell: Vector2i in cells.keys():
		var pose: Dictionary = cells[cell]
		if pose.kind == &"trap": sample_trap(pose.progress, board, cell, pose.get("trap_kind", "floor"), pose.get("direction", Vector2i.ZERO))
		else: sample_cell(pose.progress, board, cell, pose.kind)

func sample_fall(progress: float, board: BattleDemoBoard, id: int, from: Vector2i, to: Vector2i, vanish: bool) -> void:
	poses[id] = {"kind": &"fall", "progress": progress, "from": from, "to": to, "vanish": vanish}
	var visual := board._presentation_visual(id)
	if visual == null: return
	var p := clampf(progress, 0.0, 1.0)
	var origin := IsoGridUtils.grid_to_screen(from, board.grid_config, 0)
	var destination := IsoGridUtils.grid_to_screen(to, board.grid_config, 0)
	var foot := origin.lerp(destination, minf(1.0, p / 0.65))
	visual.half_steps = 0
	visual.position = Vector2(foot.x, maxf(origin.y, destination.y) - 0.25)
	visual.presentation_offset = foot - visual.position
	var from_height := -0.5 * board._view_height_steps(from) * board.grid_config.height_step
	var to_height := from_height + board.grid_config.tile_size.y * 1.6 if vanish else -0.5 * board._view_height_steps(to) * board.grid_config.height_step
	visual.presentation_lift = lerpf(from_height, to_height, p * p)
	visual.modulate.a = 1.0 - clampf((p - 0.45) / 0.55, 0.0, 1.0) if vanish else 1.0
	board._sort_visuals()
	if p >= 1.0 and not vanish:
		visual.position = destination
		visual.presentation_offset = Vector2.ZERO
		for row: Dictionary in board._view_units:
			if row.unit.id == id: row.cell = to

func sample_land(progress: float, board: BattleDemoBoard, id: int) -> void:
	poses[id] = {"kind": &"land", "progress": progress}
	var visual := board._presentation_visual(id)
	if visual != null: visual.landing_compression = sin(clampf(progress, 0.0, 1.0) * PI) * 0.22

func sample_death(progress: float, board: BattleDemoBoard, id: int) -> void:
	poses[id] = {"kind": &"death", "progress": progress}
	var visual := board._presentation_visual(id)
	if visual == null: return
	visual.death_progress = progress
	visual.modulate.a = 1.0 - progress * 0.25

func sample_cell(progress: float, board: BattleDemoBoard, cell: Vector2i, kind: StringName) -> void:
	cells[cell] = {"kind": kind, "progress": progress}
	var overlay := board._ensure_environment_visual(cell)
	if overlay == null: return
	if kind == &"collapse":
		overlay.collapse_progress = progress
		var floor_visual := overlay.get_parent() as BattleDemoIsoVisual
		if floor_visual != null:
			floor_visual.presentation_lift = progress * progress * board.grid_config.tile_size.y * 0.3
			floor_visual.modulate.a = 1.0 - progress
			overlay.position = floor_visual.get_visual_offset() + Vector2(0, 0.5)
	else:
		overlay.hazard_progress = progress

func sample_trap(progress: float, board: BattleDemoBoard, cell: Vector2i, trap_kind: String = "floor", direction: Vector2i = Vector2i.ZERO) -> void:
	cells[cell] = {"kind": &"trap", "progress": progress, "trap_kind": trap_kind, "direction": direction}
	var overlay := board._ensure_environment_visual(cell)
	if overlay != null:
		overlay.floor_trap = trap_kind == "floor"
		overlay.wall_trap_direction = direction if trap_kind == "wall" else Vector2i.ZERO
		overlay.trap_progress = progress

static func trap_event(events: Array) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == &"trap_fired": return event.duplicate(true)
	return {}

static func hazard_cell(events: Array, fires: Array[Dictionary]) -> Vector2i:
	for event: Dictionary in events:
		if event.get("kind") not in [&"hit_resolved", &"elemental_changed"]: continue
		var source: Dictionary = event.get("source", {})
		if event.get("kind") == &"elemental_changed" and event.get("reason") == &"burning":
			source = event.get("after", {}).get("burning_source", {})
		if source.get("kind") != &"cell": continue
		var cell: Vector2i = source.get("origin_cell", Vector2i(-1, -1))
		for fire: Dictionary in fires:
			if fire.cell == cell: return cell
	return Vector2i(-1, -1)
