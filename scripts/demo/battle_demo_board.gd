extends Control
class_name BattleDemoBoard

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cancel_requested()

const INK := Color("e6ecf4")
const MUTED := Color("a5b3c5")
const CYAN := Color("65dfcc")
const GOLD := Color("f7c97d")
var session: BattleDemoSession
var attack_mode: bool = false
var hover_cell := Vector2i(-1, -1)
var _reachable: Dictionary = {}
var _path: Array[Vector2i] = []

func _ready() -> void:
	custom_minimum_size = Vector2(520, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_clear_hover)

func refresh() -> void:
	_reachable = session.reachable_cells() if session != null else {}
	_refresh_path()
	queue_redraw()

func grid_rect() -> Rect2:
	var side := minf(size.x - 44.0, size.y - 44.0)
	return Rect2((size - Vector2.ONE * side) * 0.5 + Vector2(10, 10), Vector2.ONE * side)

func cell_center(cell: Vector2i) -> Vector2:
	var area := grid_rect()
	return area.position + (Vector2(cell) + Vector2.ONE * 0.5) * area.size.x / 8.0

func cell_at(point: Vector2) -> Vector2i:
	var area := grid_rect()
	if not area.has_point(point): return Vector2i(-1, -1)
	return Vector2i((point - area.position) / (area.size.x / 8.0))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := cell_at((event as InputEventMouseMotion).position)
		if cell != hover_cell:
			hover_cell = cell
			_refresh_path()
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(button.position)
			if cell.x >= 0: cell_clicked.emit(cell)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			cancel_requested.emit()
			accept_event()

func _clear_hover() -> void:
	hover_cell = Vector2i(-1, -1)
	_path.clear()
	cell_hovered.emit(hover_cell)
	queue_redraw()

func _refresh_path() -> void:
	_path.clear()
	if session != null and not attack_mode and _reachable.has(hover_cell):
		_path = session.path_to(hover_cell)

func _draw() -> void:
	if session == null or session.board == null: return
	var area := grid_rect()
	var edge := area.size.x / 8.0
	var font := ThemeDB.fallback_font
	for n in 8:
		draw_string(font, area.position + Vector2((n + 0.5) * edge - 5, -10), String.chr(65 + n), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
		draw_string(font, area.position + Vector2(-22, (n + 0.5) * edge + 5), str(n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	for y in 8:
		for x in 8:
			var cell := Vector2i(x, y)
			var rect := Rect2(area.position + Vector2(cell) * edge, Vector2.ONE * edge).grow(-2)
			var steps := session.board.get_height_steps(cell)
			var terrain := session.board.get_terrain(cell)
			var color := Color("273749") if (x + y) % 2 == 0 else Color("2c3c4e")
			if steps > 0: color = Color("426967").lightened(float(steps) * 0.045)
			if steps < 0: color = Color("273042")
			if terrain == TerrainType.Type.VOID: color = Color("0b101a")
			if terrain == TerrainType.Type.WALL: color = Color("626979")
			draw_style_box(_tile_style(color), rect)
			if terrain == TerrainType.Type.WALL:
				for i in 3:
					draw_line(rect.position + Vector2(6, 15 + i * 15), rect.position + Vector2(rect.size.x - 6, 15 + i * 15), Color("8992a1"), 1)
			elif terrain == TerrainType.Type.VOID:
				draw_string(font, rect.position + Vector2(7, 18), "ОБРЫВ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8590a6"))
			else:
				draw_string(font, rect.position + Vector2(6, 15), "%+.1f" % (float(steps) / 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
				if not attack_mode and _reachable.has(cell):
					draw_circle(rect.position + Vector2(rect.size.x - 9, 9), 2, CYAN)
			if cell == hover_cell:
				draw_rect(rect.grow(1), GOLD if attack_mode else CYAN, false, 2)
	if _path.size() > 1:
		var points := PackedVector2Array()
		for cell in _path: points.append(cell_center(cell))
		draw_polyline(points, CYAN, 3, true)
	for index in session.units.size():
		var unit := session.units[index]
		var center := cell_center(unit.cell)
		if not unit.is_alive():
			# Труп не занимает клетку; маркер смещён от центра живого персонажа.
			var marker := center + Vector2(edge * 0.3, edge * 0.3)
			draw_line(marker - Vector2(4, 4), marker + Vector2(4, 4), MUTED, 2)
			draw_line(marker - Vector2(4, -4), marker + Vector2(4, -4), MUTED, 2)
			continue
		var tint := CYAN if index % 2 == 0 else GOLD
		if unit.id == session.selected_id: draw_arc(center, edge * 0.31, 0, TAU, 48, tint, 2, true)
		draw_circle(center + Vector2(0, 3), edge * 0.235, Color("111c29"))
		draw_circle(center, edge * 0.235, tint)
		draw_string(font, center + Vector2(-edge * 0.25, 7), unit.debug_name.left(1), HORIZONTAL_ALIGNMENT_CENTER, edge * 0.5, 21, Color("172230"))
		var bar := Rect2(center + Vector2(-edge * 0.30, edge * 0.33), Vector2(edge * 0.60, 4))
		draw_rect(bar, Color("111c29"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(unit.vitals.get_hp() / unit.get_stat(StatTypes.StatType.HP_MAX), 0, 1), 4)), CYAN)
		bar.position.y += 6
		draw_rect(bar, Color("111c29"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(unit.vitals.get_balance() / unit.get_stat(StatTypes.StatType.BALANCE_MAX), 0, 1), 3)), GOLD)

func _tile_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
