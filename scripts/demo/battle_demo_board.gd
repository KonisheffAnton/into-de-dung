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
var summoning_mode: bool = false
var raising_mode: bool = false
var environment_mode: bool = false
var inspected_id: int = UnitId.NONE
var hover_cell := Vector2i(-1, -1)
var grid_config := IsoGridConfig.new()
var _reachable: Dictionary = {}
var inspection_cells: Dictionary = {}
var reaction_zone_cells: Array[Vector2i] = []
var cover_target_ids: Array[int] = []
var sneak_threat_ids: Array[int] = []
var forecast: AttackForecast
var move_forecast: MoveForecast
var move_forecast_pending: bool = false
var pending_move_path: Array[Vector2i] = []
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
	# Состояние ограничивает добровольный путь, но не выбор персонажа и не толчки.
	if inspected != null and ControlRules.action_reason(inspected, true) != &"": inspection_cells.clear()
	if session != null and session.selected_unit() != null and ControlRules.action_reason(session.selected_unit(), true) != &"": _reachable.clear()
	if summoning_mode and session is BattleTacticalSession:
		_reachable = {}
		for cell in (session as BattleTacticalSession).summoning_cells(): _reachable[cell] = 0.0
	if raising_mode and session is BattleEnvironmentSession:
		_reachable = {}
		for cell in (session as BattleEnvironmentSession).raise_hint_cells(): _reachable[cell] = 0.0
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying():
		_reachable = (session as BattleCoreCombinationSession).deployment_cells()
	_refresh_path()
	_rebuild_visuals()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

func refresh_forecast() -> void:
	# Наведение меняет только прогноз: сохраняем узлы доски и уже найденную доступность.
	_refresh_path()
	for visual: BattleDemoIsoVisual in _entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT and visual.unit != null:
			visual.forecast_entry = _forecast_entry(visual.unit.id)
			visual.queue_redraw()
	queue_redraw()
	if _overlay != null: _overlay.queue_redraw()

func reachable_cells() -> Dictionary:
	return inspection_cells if inspected_id != UnitId.NONE else _reachable

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
			cell_hovered.emit(cell)
			if _overlay != null: _overlay.queue_redraw()
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
	cell_hovered.emit(hover_cell)
	refresh_forecast()
	if _overlay != null: _overlay.queue_redraw()

func _refresh_path() -> void:
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying():
		_path.clear()
		return
	_path.clear()
	if move_forecast_pending:
		# Маршрут запроса виден сразу, но не обещает пройти опасные клетки до конца.
		_path = pending_move_path.duplicate()
		return
	if move_forecast != null:
		# После прерывания не рисуем непроходимый остаток как будущий ход.
		if move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]: _path = move_forecast.traversed_path.duplicate()
		return
	if session != null and not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and _reachable.has(hover_cell): _path = session.path_to(hover_cell)

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
		if environment_mode and not unit.is_alive(): continue
		if not unit.is_alive() and (_fallen_ids.has(unit.id) or board.get_terrain(unit.cell) in [TerrainType.Type.VOID, TerrainType.Type.HAZARD]): continue
		var visual := _make_visual(unit.cell, board.get_height_steps(unit.cell), BattleDemoIsoVisual.Role.UNIT)
		visual.unit = unit
		visual.selected = unit.id == session.selected_id and unit.is_alive()
		visual.inspected = unit.id == inspected_id and unit.is_alive()
		visual.forecast_entry = _forecast_entry(unit.id)
		# K2 переиспользует маркер C1, хотя сессия наследуется от среды.
		visual.show_rear = session is BattleControlSession or (session is BattleCoreCombinationSession and not session is BattleCoreReactionsSession)
		if unit.armor != null: visual.armor_values = ArmorRuntime.totals(ArmorRuntime.capture(session.state.get_owner(unit.id)))
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
	var hw := grid_config.tile_size.x * 0.5
	var highlight_hh := grid_config.tile_size.y * 0.48
	var highlight_hw := grid_config.tile_size.x * 0.48
	for cell: Vector2i in reaction_zone_cells:
		var center := cell_center(cell)
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -highlight_hh), center + Vector2(highlight_hw, 0), center + Vector2(0, highlight_hh), center + Vector2(-highlight_hw, 0), center + Vector2(0, -highlight_hh)]), Color("a5b3c5", 0.35), 1.0, true)
	for id: int in cover_target_ids:
		var ally := session.board.get_unit_by_id(id)
		if ally == null: continue
		var center := cell_center(ally.cell)
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -highlight_hh), center + Vector2(highlight_hw, 0), center + Vector2(0, highlight_hh), center + Vector2(-highlight_hw, 0), center + Vector2(0, -highlight_hh)]), CYAN, 2.5, true)
	for id: int in sneak_threat_ids:
		var threat := session.board.get_unit_by_id(id)
		if threat == null: continue
		var center := cell_center(threat.cell)
		_overlay.draw_arc(center, grid_config.tile_size.x * 0.25, 0, TAU, 24, GOLD, 2.5, true)
	if _path.size() > 1:
		var points := PackedVector2Array()
		for cell in _path: points.append(cell_center(cell))
		if move_forecast_pending:
			for i: int in range(1, points.size()):
				_overlay.draw_dashed_line(points[i - 1], points[i], MUTED, 2, 6)
		else:
			_overlay.draw_polyline(points, CYAN, 2, true)
	if session.board.is_in_bounds(hover_cell):
		var center := cell_center(hover_cell)
		if session.board.get_terrain(hover_cell) == TerrainType.Type.WALL: center.y -= grid_config.height_step
		var cell_hw := grid_config.tile_size.x * 0.48
		var hh := grid_config.tile_size.y * 0.48
		_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -hh), center + Vector2(cell_hw, 0), center + Vector2(0, hh), center + Vector2(-cell_hw, 0), center + Vector2(0, -hh)]), GOLD if attack_mode or inspected_id != UnitId.NONE else (Color("f29b9b") if raising_mode else CYAN), 2, true)
	if environment_mode and session is BattleEnvironmentSession:
		var environment := (session as BattleEnvironmentSession).state.environment
		for fire: Dictionary in environment.fires:
			var fire_center := cell_center(fire["cell"])
			_overlay.draw_circle(fire_center, hw * 0.28, Color(0.95, 0.28, 0.12, 0.55))
			_overlay.draw_string(ThemeDB.fallback_font, fire_center + Vector2(-32, 4), "ШИПЫ 8", HORIZONTAL_ALIGNMENT_CENTER, 64, 10, Color("ffd08a"))
		var corpses_by_cell: Dictionary = {}
		for corpse: Dictionary in environment.corpses:
			var corpse_cell: Vector2i = corpse["cell"]
			var records: Array = corpses_by_cell.get(corpse_cell, [])
			records.append(corpse)
			corpses_by_cell[corpse_cell] = records
		for cell_variant: Variant in corpses_by_cell:
			var corpse_cell: Vector2i = cell_variant
			var corpse_center := cell_center(corpse_cell)
			var records: Array = corpses_by_cell[corpse_cell]
			_overlay.draw_circle(corpse_center + Vector2(0, 8), hw * 0.20, Color("a5b3c5"))
			_overlay.draw_string(ThemeDB.fallback_font, corpse_center + Vector2(-35, 25), "ТЕЛА ×%d" % records.size(), HORIZONTAL_ALIGNMENT_CENTER, 70, 10, Color("e6ecf4"))
	if move_forecast != null and move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		var after: Dictionary = move_forecast.units.get(move_forecast.actor_id, {}).get("after", {})
		if not after.is_empty():
			var endpoint := cell_center(after["cell"])
			var color := CYAN if after["alive"] else Color("f29b9b")
			_overlay.draw_arc(endpoint, 10.0, 0, TAU, 24, color, 2.5, true)
	if forecast != null and forecast.status == &"APPLIED":
		for event_variant in forecast.events:
			var event := event_variant as Dictionary
			var kind := StringName(event.get("kind", &""))
			if kind not in [&"moved", &"push_blocked", &"collision", &"fell"]: continue
			var from_cell := Vector2i(-1, -1)
			if event.has("from_cell"): from_cell = event["from_cell"] as Vector2i
			var to_cell := from_cell
			if event.has("to_cell"): to_cell = event["to_cell"] as Vector2i
			elif event.has("attempted_cell"): to_cell = event["attempted_cell"] as Vector2i
			if not session.board.is_in_bounds(from_cell): continue
			var start := cell_center(from_cell)
			var finish := cell_center(to_cell) if session.board.is_in_bounds(to_cell) else start + IsoGridUtils.grid_to_screen(to_cell, grid_config, 0) - IsoGridUtils.grid_to_screen(from_cell, grid_config, 0)
			_overlay.draw_line(start, finish, Color("f29b9b"), 3.0, true)
			var direction := (finish - start).normalized()
			_overlay.draw_line(finish, finish - direction.rotated(0.5) * 10.0, Color("f29b9b"), 3.0, true)
			_overlay.draw_line(finish, finish - direction.rotated(-0.5) * 10.0, Color("f29b9b"), 3.0, true)
			_overlay.draw_arc(finish, 6.0, 0, TAU, 16, Color("f29b9b"), 1.5, true)
			if kind in [&"push_blocked", &"collision"]:
				_overlay.draw_line(finish - Vector2(4, 4), finish + Vector2(4, 4), Color.WHITE, 2, true)
				_overlay.draw_line(finish - Vector2(4, -4), finish + Vector2(4, -4), Color.WHITE, 2, true)

func _forecast_entry(unit_id: int) -> Dictionary:
	if move_forecast != null and move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		return move_forecast.units.get(unit_id, {})
	if forecast == null or forecast.status != ActionReceipt.APPLIED: return {}
	var units: Dictionary = forecast.units
	var entry: Variant = units.get(unit_id, {})
	return entry as Dictionary if entry is Dictionary else {}

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
