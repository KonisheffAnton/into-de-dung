extends Control
class_name BattleDemoBoard

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cancel_requested()

const CYAN := Color("65dfcc")
const GOLD := Color("f7c97d")
const MUTED := Color("a5b3c5")
var session: BattleDemoSession
var attack_mode: bool = false
var inspected_id: int = UnitId.NONE
var hover_cell := Vector2i(-1, -1)
var grid_config := IsoGridConfig.new()
var _reachable: Dictionary = {}
var inspection_cells: Dictionary = {}
var _path: Array[Vector2i] = []
var _tiles: Node2D
var _entities: Node2D
var _overlay: Node2D
var _ghosts: Node2D
var _falling: Dictionary = {}
var _fallen_ids: Dictionary = {}
var _shown_board: BattleBoard
var _tile_visuals: Array[BattleDemoIsoVisual] = []
var _entity_visuals: Array[BattleDemoIsoVisual] = []

func _ready() -> void:
	custom_minimum_size = Vector2(520, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_tiles = _layer("TilesLayer", RenderLayers.Layer.TILES)
	_entities = _layer("EntitiesLayer", RenderLayers.Layer.ENTITIES)
	_entities.y_sort_enabled = true
	_ghosts = _layer("FallingFigures", RenderLayers.Layer.VFX_OVERLAY)
	_overlay = _layer("PathOverlay", RenderLayers.Layer.UI_PREVIEW)
	_overlay.draw.connect(_draw_overlay)
	mouse_exited.connect(_clear_hover)
	_rescale_layout()

func _layer(label: String, layer: RenderLayers.Layer) -> Node2D:
	var result := Node2D.new()
	result.name = label
	result.z_index = RenderLayers.z_index_for(layer)
	add_child(result)
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _rescale_layout()

func refresh() -> void:
	inspection_cells.clear()
	var inspected := session.board.get_unit_by_id(inspected_id) if session != null and session.board != null else null
	var inspecting_enemy := inspected != null and inspected.is_alive() and inspected.faction == Faction.Type.ENEMY and session is BattleTacticalSession and (session as BattleTacticalSession).can_player_act()
	if inspecting_enemy:
		# Следующий ход ещё не пополнял врага: показываем полную будущую дальность.
		var finder := GridPathfinder.new()
		finder.configure(session.board.get_bounds(), session.board.make_spatial_data_provider(inspected), 1, &"spatial_move_v1")
		inspection_cells = finder.get_reachable_cells(inspected.cell, inspected.get_stat(StatTypes.StatType.MOVE_RANGE))
		_reachable = {}
	else:
		inspected_id = UnitId.NONE
		_reachable = session.reachable_cells() if session != null else {}
	_refresh_path()
	_rebuild_visuals()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

func cell_center(cell: Vector2i) -> Vector2:
	var steps := session.board.get_height_steps(cell) if session != null and session.board != null else 0
	return IsoGridUtils.grid_to_screen(cell, grid_config, 0) - Vector2(0, float(steps) * 0.5 * grid_config.height_step)

func cell_at(point: Vector2) -> Vector2i:
	if session == null or session.board == null: return Vector2i(-1, -1)
	# Те же поверхности, но в обратном порядке их фактической отрисовки.
	for i in range(_entity_visuals.size() - 1, -1, -1):
		if _entity_visuals[i].contains_point(point): return _entity_visuals[i].grid_anchor
	for i in range(_tile_visuals.size() - 1, -1, -1):
		if _tile_visuals[i].contains_point(point): return _tile_visuals[i].grid_anchor
	return Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := cell_at((event as InputEventMouseMotion).position)
		if cell != hover_cell:
			hover_cell = cell
			_refresh_path()
			cell_hovered.emit(cell)
			_overlay.queue_redraw()
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
	if _overlay != null: _overlay.queue_redraw()

func _refresh_path() -> void:
	_path.clear()
	if session != null and not attack_mode and inspected_id == UnitId.NONE and _reachable.has(hover_cell): _path = session.path_to(hover_cell)

func _rescale_layout() -> void:
	var factor := maxf(0.1, minf((size.x - 64) / 1024.0, (size.y - 108) / 544.0))
	grid_config.tile_size = Vector2(128, 64) * factor
	grid_config.height_step = 32 * factor
	grid_config.origin_offset = Vector2(size.x * 0.5, size.y * 0.5 - grid_config.tile_size.y * 3.5)
	if is_inside_tree():
		_clear_falls()
		_rebuild_visuals()
		queue_redraw()
		if _overlay != null: _overlay.queue_redraw()

func _clear_layer(layer: Node2D) -> void:
	if layer == null: return
	for child in layer.get_children():
		layer.remove_child(child)
		child.queue_free()

func _rebuild_visuals() -> void:
	if _entities == null: return
	var board: BattleBoard = session.board if session != null else null
	if board != _shown_board:
		_clear_falls()
		_fallen_ids.clear()
		_shown_board = board
	_tile_visuals.clear()
	_entity_visuals.clear()
	_clear_layer(_tiles)
	_clear_layer(_entities)
	if board == null: return
	var cells: Array[Vector2i] = []
	for y in board.height:
		for x in board.width: cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.y < b.y))
	for cell in cells:
		var steps := board.get_height_steps(cell)
		var terrain := board.get_terrain(cell)
		var floor_visual := _make_visual(cell, steps, BattleDemoIsoVisual.Role.PLATFORM if steps > 0 else BattleDemoIsoVisual.Role.FLOOR)
		floor_visual.is_void = terrain == TerrainType.Type.VOID
		floor_visual.reachable = not attack_mode and _reachable.has(cell)
		floor_visual.enemy_range = inspected_id != UnitId.NONE and inspection_cells.has(cell)
		# Видимые поверхности всех высот сортируются вместе: ближний пол закрывает
		# дальнюю грань уступа. Разделение по высоте на два слоя ломает это перекрытие.
		_entities.add_child(floor_visual)
		_entity_visuals.append(floor_visual)
		if terrain == TerrainType.Type.WALL:
			var wall := _make_visual(cell, steps, BattleDemoIsoVisual.Role.WALL)
			_entities.add_child(wall)
			_entity_visuals.append(wall)
	for unit in session.units:
		if not unit.is_alive() and (_fallen_ids.has(unit.id) or board.get_terrain(unit.cell) in [TerrainType.Type.VOID, TerrainType.Type.HAZARD]): continue
		var visual := _make_visual(unit.cell, board.get_height_steps(unit.cell), BattleDemoIsoVisual.Role.UNIT)
		visual.unit = unit
		visual.selected = unit.id == session.selected_id and unit.is_alive()
		visual.inspected = unit.id == inspected_id and unit.is_alive()
		_entities.add_child(visual)
		_entity_visuals.append(visual)
	_entity_visuals.sort_custom(func(a: BattleDemoIsoVisual, b: BattleDemoIsoVisual) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.get_index() < b.get_index()))

func _make_visual(cell: Vector2i, steps: int, role: BattleDemoIsoVisual.Role) -> BattleDemoIsoVisual:
	var visual := BattleDemoIsoVisual.new()
	visual.grid_config = grid_config
	visual.role = role
	visual.half_steps = steps
	visual.set_grid_anchor(cell)
	return visual

func _draw() -> void:
	if session == null or session.board == null: return
	var hh := grid_config.tile_size.y * 0.5
	var hw := grid_config.tile_size.x * 0.5
	for n in 8:
		draw_string(ThemeDB.fallback_font, IsoGridUtils.grid_to_screen(Vector2i(n, 0), grid_config, 0) + Vector2(5, -hh - 7), String.chr(65 + n), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		draw_string(ThemeDB.fallback_font, IsoGridUtils.grid_to_screen(Vector2i(0, n), grid_config, 0) + Vector2(-hw - 17, 4), str(n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)

func _draw_overlay() -> void:
	if session == null or session.board == null: return
	if _path.size() > 1:
		var points := PackedVector2Array()
		for cell in _path: points.append(cell_center(cell))
		_overlay.draw_polyline(points, CYAN, 2, true)
	if session.board.is_in_bounds(hover_cell):
		var center := cell_center(hover_cell)
		if session.board.get_terrain(hover_cell) == TerrainType.Type.WALL: center.y -= grid_config.height_step
		var hw := grid_config.tile_size.x * 0.48
		var hh := grid_config.tile_size.y * 0.48
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -hh), center + Vector2(hw, 0), center + Vector2(0, hh), center + Vector2(-hw, 0), center + Vector2(0, -hh)]), GOLD if attack_mode or inspected_id != UnitId.NONE else CYAN, 2, true)

func animate_fall(unit: UnitState, origin: Vector2i, destination: Vector2i) -> void:
	if unit == null or _ghosts == null or _falling.has(unit.id): return
	# При вылете за границу ядро сохраняет последнюю клетку, но фигура уже упала.
	_fallen_ids[unit.id] = true
	_rebuild_visuals()
	var center := cell_center(destination)
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	var mask := Polygon2D.new()
	mask.position = center
	mask.polygon = PackedVector2Array([Vector2(-hw, -160), Vector2(hw, -160), Vector2(hw, 0), Vector2(0, hh), Vector2(-hw, 0)])
	mask.color = Color.TRANSPARENT
	_ghosts.add_child(mask)
	var ghost := BattleDemoIsoVisual.new()
	ghost.grid_config = grid_config
	ghost.role = BattleDemoIsoVisual.Role.UNIT
	ghost.transient_label = unit.debug_name
	ghost.transient_tint = CYAN if unit.faction == Faction.Type.PLAYER else GOLD
	mask.add_child(ghost)
	ghost.position = cell_center(origin) - center
	_falling[unit.id] = mask
	var tween := mask.create_tween()
	tween.tween_property(ghost, "position", Vector2.ZERO, 0.18)
	# После входа в провал передняя кромка скрывает нижнюю часть фигуры.
	tween.tween_callback(func() -> void:
		mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		mask.color = Color.WHITE)
	tween.tween_property(ghost, "fall_drop", grid_config.tile_size.y * 1.4, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ghost, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_fall.bind(unit.id, mask))

func is_fall_animating(unit_id: int) -> bool:
	return _falling.has(unit_id)

func _finish_fall(unit_id: int, mask: Polygon2D) -> void:
	_falling.erase(unit_id)
	if is_instance_valid(mask): mask.queue_free()

func _clear_falls() -> void:
	_falling.clear()
	_clear_layer(_ghosts)
