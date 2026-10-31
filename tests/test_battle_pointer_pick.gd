extends SceneTree

const CORE_REACTIONS_SCENE: PackedScene = preload("res://scenes/demo/core_reactions_battle.tscn")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var unit_signal: int = UnitId.NONE
var cell_signal: Vector2i = Vector2i(-1, -1)
var trace: Array[String] = []

class PickVisual extends BattleDemoIsoVisual:
	var hit: bool = false
	var pick_calls: int = 0

	func contains_point(_point: Vector2) -> bool:
		pick_calls += 1
		return hit

class CountingBoard extends BattleDemoBoard:
	var sort_calls: int = 0

	func _ready() -> void:
		pass

	func _notification(_what: int) -> void:
		pass

	func _sort_visuals() -> void:
		sort_calls += 1
		super._sort_visuals()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE POINTER PICK: " + label)

func _on_unit_hovered(id: int) -> void:
	unit_signal = id
	trace.append("unit:%d" % id)

func _on_cell_hovered(cell: Vector2i) -> void:
	cell_signal = cell
	trace.append("cell:%d,%d" % [cell.x, cell.y])

func _on_cell_clicked(cell: Vector2i) -> void:
	cell_signal = cell
	trace.append("click:%d,%d" % [cell.x, cell.y])

func _centroid(poly: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in poly:
		result += point
	return result / float(poly.size()) if not poly.is_empty() else Vector2.ZERO

func _real_world_samples(board: BattleDemoBoard) -> Array[Vector2]:
	var samples: Array[Vector2] = [board.cell_center(Vector2i(4, 5)), board.cell_center(Vector2i(0, 0))]
	var found_unit := false
	var found_wall := false
	var found_floor := false
	var found_overhang := false
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT or visual.unit == null: continue
		var polygons := visual.surface_polygons()
		if polygons.is_empty() or polygons[0].size() < 3: continue
		var polygon: PackedVector2Array = polygons[0]
		var center := _centroid(polygon)
		if not found_unit:
			samples.append(board.world_to_view(visual.position + center))
			found_unit = true
		if not found_overhang:
			# Проверяем настоящую фигуру у верхнего края её pick-области.
			var top_point := (polygon[0] * 0.85 + polygon[1] * 0.15)
			samples.append(board.world_to_view(visual.position + top_point))
			found_overhang = true
	for visual: BattleDemoIsoVisual in board._tile_visuals:
		var polygons := visual.surface_polygons()
		if polygons.is_empty(): continue
		var top := polygons[polygons.size() - 1]
		if top.size() < 3: continue
		var point := board.world_to_view(visual.position + _centroid(top))
		if visual.role == BattleDemoIsoVisual.Role.WALL and not found_wall:
			samples.append(point)
			found_wall = true
		elif visual.role == BattleDemoIsoVisual.Role.FLOOR and not found_floor:
			samples.append(point)
			found_floor = true
		if found_wall and found_floor: break
	return samples

func _check_real_gui_oracle() -> void:
	demo = CORE_REACTIONS_SCENE.instantiate() as BattleDemo
	viewport.add_child(demo)
	await process_frame
	await process_frame
	PlayerTurnFixture.enter_player_turn(demo)
	await process_frame
	demo.set_process(false)
	var board := demo.board_view
	board.displayed_unit_hovered.connect(_on_unit_hovered)
	board.cell_hovered.connect(_on_cell_hovered)
	var points := _real_world_samples(board)
	check(points.size() >= 4, "real fixture supplies unit, overhang, wall and floor picking samples")
	for point: Vector2 in points:
		var expected_unit := board.displayed_unit_at(point)
		var expected_cell := board.displayed_cell_at(point)
		trace.clear()
		board.hover_cell = Vector2i(-100, -100)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		board._gui_input(motion)
		check(unit_signal == expected_unit and cell_signal == expected_cell
			and trace.size() == 2 and trace[0] == "unit:%d" % expected_unit
			and trace[1] == "cell:%d,%d" % [expected_cell.x, expected_cell.y],
			"combined normal motion matches both independent pick APIs and preserves signal order")
	board.pan_camera(Vector2(28.0, -17.0))
	var camera_cell: Vector2i = board._view_units[0].cell
	var camera_point := board.cell_center(camera_cell)
	var expected_camera_unit := board.displayed_unit_at(camera_point)
	var expected_camera_cell := board.displayed_cell_at(camera_point)
	trace.clear()
	board.hover_cell = Vector2i(-100, -100)
	var camera_motion := InputEventMouseMotion.new()
	camera_motion.position = camera_point
	board._gui_input(camera_motion)
	check(unit_signal == expected_camera_unit and cell_signal == expected_camera_cell,
		"combined picking follows camera transform without cached screen geometry")
	board.displayed_unit_hovered.disconnect(_on_unit_hovered)
	board.cell_hovered.disconnect(_on_cell_hovered)
	demo.queue_free()
	await process_frame
	demo = null

func _make_pick_visual(board: CountingBoard, cell: Vector2i, hits: bool, role: BattleDemoIsoVisual.Role, unit_id: int = UnitId.NONE) -> PickVisual:
	var visual := PickVisual.new()
	visual.role = role
	visual.grid_anchor = cell
	visual.position = Vector2(0.0, float(cell.x))
	visual.hit = hits
	if unit_id != UnitId.NONE:
		visual.unit = BattleUnitView.new()
		visual.unit.id = unit_id
	board.add_child(visual)
	return visual

func _reset_pick_counters(board: CountingBoard, visuals: Array[PickVisual]) -> void:
	board.sort_calls = 0
	for visual: PickVisual in visuals:
		visual.pick_calls = 0

func _check_combined_event_counts() -> void:
	var board := CountingBoard.new()
	viewport.add_child(board)
	board._view_width = 4
	board._view_height = 4
	var low := _make_pick_visual(board, Vector2i(0, 0), true, BattleDemoIsoVisual.Role.UNIT, 1001)
	var middle := _make_pick_visual(board, Vector2i(1, 0), false, BattleDemoIsoVisual.Role.FLOOR)
	var top := _make_pick_visual(board, Vector2i(2, 0), true, BattleDemoIsoVisual.Role.WALL)
	var tile_low := _make_pick_visual(board, Vector2i(0, 1), true, BattleDemoIsoVisual.Role.FLOOR)
	var tile_top := _make_pick_visual(board, Vector2i(3, 1), true, BattleDemoIsoVisual.Role.PLATFORM)
	board._entity_visuals.assign([low, middle, top])
	board._tile_visuals.assign([tile_low, tile_top])
	var visuals: Array[PickVisual] = [low, middle, top, tile_low, tile_top]
	board.displayed_unit_hovered.connect(_on_unit_hovered)
	board.cell_hovered.connect(_on_cell_hovered)
	board.cell_clicked.connect(_on_cell_clicked)
	var point := Vector2.ZERO
	trace.clear()
	_reset_pick_counters(board, visuals)
	board._gui_input(_motion(point))
	check(unit_signal == UnitId.NONE and cell_signal == Vector2i(2, 0)
		and trace == ["unit:%d" % UnitId.NONE, "cell:2,0"],
		"top entity without a unit occludes lower unit while returning its cell")
	check(board.sort_calls == 1 and top.pick_calls == 1 and low.pick_calls == 0 and middle.pick_calls == 0
		and tile_top.pick_calls == 0 and tile_low.pick_calls == 0,
		"normal combined motion sorts once and tests only visited entities")

	board.execution_pending = false
	board.forecast_preparation_pending = false
	_reset_pick_counters(board, visuals)
	trace.clear()
	var ordinary_click := InputEventMouseButton.new()
	ordinary_click.button_index = MOUSE_BUTTON_LEFT
	ordinary_click.position = point
	ordinary_click.pressed = true
	board._gui_input(ordinary_click)
	check(board.sort_calls == 0 and top.pick_calls == 1
		and trace == ["click:2,0"], "ordinary left click keeps cell-only behavior")

	board.execution_pending = false
	low.hit = false
	top.hit = false
	_reset_pick_counters(board, visuals)
	trace.clear()
	board.hover_cell = Vector2i(-100, -100)
	board._gui_input(_motion(point))
	check(cell_signal == Vector2i(3, 1) and board.sort_calls == 1
		and low.pick_calls == 1 and middle.pick_calls == 1 and top.pick_calls == 1
		and tile_top.pick_calls == 1 and tile_low.pick_calls == 0,
		"tile fallback runs only after each entity misses and stops at the top tile")

	board.execution_pending = true
	board.forecast_preparation_pending = true
	low.hit = false
	top.hit = true
	_reset_pick_counters(board, visuals)
	trace.clear()
	board.hover_cell = Vector2i(-100, -100)
	board._gui_input(_motion(point))
	check(board.sort_calls == 1 and low.pick_calls + middle.pick_calls + top.pick_calls == 1
		and trace.size() == 2 and trace[0] == "unit:%d" % UnitId.NONE and trace[1] == "cell:2,0",
		"forecast-preparation motion performs one combined inspection pick")

	_reset_pick_counters(board, visuals)
	trace.clear()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.pressed = true
	board._gui_input(click)
	check(board.sort_calls == 1 and low.pick_calls + middle.pick_calls + top.pick_calls == 1
		and trace.size() == 2 and trace[0] == "unit:%d" % UnitId.NONE and trace[1] == "click:2,0",
		"forecast-preparation click emits displayed unit before captured semantic cell")

	board.forecast_preparation_pending = false
	top.hit = false
	_reset_pick_counters(board, visuals)
	trace.clear()
	board.hover_cell = Vector2i(-100, -100)
	board._gui_input(_motion(point))
	check(board.sort_calls == 1 and low.pick_calls == 1 and middle.pick_calls == 1 and top.pick_calls == 1
		and trace.size() == 1 and trace[0] == "unit:%d" % UnitId.NONE
		and board.hover_cell == Vector2i(-100, -100) and cell_signal == Vector2i(2, 0)
		and tile_top.pick_calls == 0 and tile_low.pick_calls == 0,
		"live execution pending still permits combined unit inspection without cell motion")
	board.displayed_unit_hovered.disconnect(_on_unit_hovered)
	board.cell_hovered.disconnect(_on_cell_hovered)
	board.cell_clicked.disconnect(_on_cell_clicked)
	board.queue_free()
	await process_frame

func _motion(point: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = point
	return event

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _check_real_gui_oracle()
	await _check_combined_event_counts()
	viewport.queue_free()
	await process_frame
	print("BATTLE POINTER PICK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
