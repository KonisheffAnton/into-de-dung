extends Node2D

## Тестовый дебаг-визуализатор изометрической сетки.
## Рисует ПЛОСКИЙ пол (всегда на height=0 — слой TILES) и подсвечивает
## клетку под курсором/тапом. Возвышенные клетки (elevated_cells) визуально
## представлены ОТДЕЛЬНЫМИ узлами ElevatedTileVisual, которые спавнятся
## динамически в EntitiesLayer (см. DECISIONS.md: любой объект с визуальной
## высотой должен жить в ENTITIES и участвовать в общем Y-sort, а не быть
## частью плоской тайловой сетки — иначе он не может корректно перекрывать
## юнитов по глубине). elevated_cells остаётся ЕДИНСТВЕННЫМ источником
## правды и для рендера, и для height_query() пасфайндера — нет дублирования
## данных.
##
## Также визуализирует зону хода (flood-fill) и путь для GridPathfinder
## (Модуль 3). Не является частью финальной архитектуры.

@export var grid_config: IsoGridConfig
@export var grid_width: int = 8
@export var grid_height: int = 8

## Единственный источник правды о возвышенных клетках — используется и для
## height_query() пасфайндера, и для спавна визуальных ElevatedTileVisual.
@export var elevated_cells: Array[Vector2i] = []
@export var elevated_height: int = 1

## Путь к ноде-слою ENTITIES, куда динамически спавнятся ElevatedTileVisual,
## чтобы они участвовали в общем Y-sort с юнитами. Назначается в сцене.
@export var entities_layer_path: NodePath
var entities_layer: Node2D

## Тестовые непроходимые клетки (стены).
@export var wall_cells: Array[Vector2i] = []

## Стартовая клетка тестового "юнита" для пути/зоны хода.
@export var unit_start_cell: Vector2i = Vector2i(1, 1)
@export var unit_move_range: float = 4.0
@export var max_height_step: int = 1

var _hover_cell: Vector2i = Vector2i(-9999, -9999)
var _selected_cell: Vector2i = Vector2i(-9999, -9999)

var _pathfinder := GridPathfinder.new()
var _reachable_cells: Dictionary = {}
var _current_path: Array[Vector2i] = []

var _elevated_visuals: Dictionary = {} # Vector2i -> ElevatedTileVisual


func _ready() -> void:
	if grid_config == null:
		grid_config = load("res://resources/grid/default_grid_config.tres")

	if not entities_layer_path.is_empty():
		entities_layer = get_node(entities_layer_path) as Node2D

	InputManager.pointer_moved.connect(_on_pointer_moved)
	InputManager.primary_action.connect(_on_primary_action)

	var data_provider := GridDataProvider.new(_is_cell_walkable, _height_query, _move_cost_query)
	_pathfinder.configure(Rect2i(0, 0, grid_width, grid_height), data_provider, max_height_step)
	_recompute_reachable()

	_spawn_elevated_visuals()


## Создаёт ElevatedTileVisual для каждой клетки из elevated_cells и кладёт
## в entities_layer — системно, без хардкода конкретных клеток здесь.
func _spawn_elevated_visuals() -> void:
	if entities_layer == null:
		push_warning("DebugGridVisualizer: entities_layer не назначен, возвышенные клетки не будут отрисованы объёмно")
		return

	for cell in elevated_cells:
		var visual := ElevatedTileVisual.new()
		visual.grid_config = grid_config
		visual.set_grid_anchor(cell, elevated_height)
		entities_layer.add_child(visual)
		_elevated_visuals[cell] = visual


func _process(_delta: float) -> void:
	_update_elevated_highlights()
	queue_redraw()


func _update_elevated_highlights() -> void:
	for cell in _elevated_visuals.keys():
		var visual: ElevatedTileVisual = _elevated_visuals[cell]
		if cell == _selected_cell:
			visual.set_highlight(Color(0.9, 0.7, 0.1, 0.5))
		elif cell == _hover_cell:
			visual.set_highlight(Color(0.2, 0.6, 0.9, 0.5))
		else:
			visual.set_highlight(Color.TRANSPARENT)


func _draw() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			# Пол ВСЕГДА рисуется на height=0 — визуальный подъём отображает
			# только ElevatedTileVisual в ENTITIES, не плоская сетка.
			var center := IsoGridUtils.grid_to_screen(cell, grid_config, 0)
			var color := _color_for_cell(cell)

			_draw_diamond(center, grid_config.tile_size, color)

	var label_pos := Vector2(16, 16)
	draw_string(
		ThemeDB.fallback_font,
		label_pos,
		"Hover: %s  Selected: %s  Reachable: %d cells" %
			[str(_hover_cell), str(_selected_cell), _reachable_cells.size()],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16
	)


func _color_for_cell(cell: Vector2i) -> Color:
	if wall_cells.has(cell):
		return Color(0.5, 0.15, 0.15, 1.0)
	if cell == unit_start_cell:
		return Color(0.9, 0.9, 0.9, 1.0)
	# Возвышенные клетки НЕ подсвечиваются здесь напрямую (hover/selected) —
	# этим занимается ElevatedTileVisual.set_highlight() поверх, чтобы
	# подсветка была на видимом объёмном блоке, а не на скрытом под ним полу.
	if not _elevated_visuals.has(cell):
		if cell == _selected_cell:
			return Color(0.9, 0.7, 0.1, 1.0)
		if cell == _hover_cell:
			return Color(0.2, 0.6, 0.9, 1.0)
	if _reachable_cells.has(cell):
		return Color(0.25, 0.55, 0.3, 1.0)
	return Color(0.3, 0.3, 0.35, 1.0)


## Публичный доступ для PathOverlay (Модуль 2 UI_PREVIEW layer) — путь
## должен всегда рисоваться НАД платформами/юнитами, поэтому не рисуется
## здесь напрямую (этот узел живёт в TILES, z=100), а читается отдельным
## узлом в слое UI_PREVIEW (z=500), см. debug_path_overlay.gd.
func get_current_path_screen_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for cell in _current_path:
		var h := _height_query(cell)
		points.append(IsoGridUtils.grid_to_screen(cell, grid_config, h))
	return points


func _draw_diamond(center: Vector2, tile_size: Vector2, color: Color) -> void:
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.BLACK, 1.0)


func _height_query(cell: Vector2i) -> int:
	if elevated_cells.has(cell):
		return elevated_height
	return 0


func _is_cell_walkable(cell: Vector2i) -> bool:
	return not wall_cells.has(cell)


func _move_cost_query(_cell: Vector2i) -> float:
	return 1.0


func _to_world(screen_pos: Vector2) -> Vector2:
	# Учитываем pan/zoom камеры: переводим viewport-координаты в world-координаты.
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _recompute_reachable() -> void:
	_reachable_cells = _pathfinder.get_reachable_cells(unit_start_cell, unit_move_range)


func _on_pointer_moved(screen_pos: Vector2) -> void:
	var world_pos := _to_world(screen_pos)
	_hover_cell = IsoGridUtils.resolve_grid_with_height(world_pos, grid_config, _height_query)


func _on_primary_action(screen_pos: Vector2) -> void:
	var world_pos := _to_world(screen_pos)
	_selected_cell = IsoGridUtils.resolve_grid_with_height(world_pos, grid_config, _height_query)
	_current_path = _pathfinder.find_path(unit_start_cell, _selected_cell)
	print("Selected cell: ", _selected_cell, "  path length: ", _current_path.size())
