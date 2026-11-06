class_name BattleTerrainVisual
extends BattleDemoIsoVisual

## Явное согласие сцены на сохранение опоры между публикациями представления.
## Сцены, чей рисунок зависит от подсветки, оставляют полный путь обновления.
@export var highlights_use_ground_overlay: bool = false
@export var selected_fire: bool = false
@export var batch_simple_polygons: bool = false:
	set(value):
		batch_simple_polygons = value
		if is_node_ready(): _configure_polygon_batch()
const DEEP_ACID_SCENE: PackedScene = preload("res://scenes/demo/visuals/hazards/deep_acid_pool.tscn")
const SELECTED_FIRE_SCENE: PackedScene = preload("res://scenes/demo/visuals/hazards/fire29.tscn")
var _deep_acid_view: Node2D
var _fire_view: BattleAnimatedAcidPool
var view_apply_count: int = 0
var _view_initialized: bool = false
var _view_tile_size: Vector2
var _view_height_step: float
var _view_origin: Vector2
@onready var _rest_modulate: Color = modulate

func _ready() -> void:
	super._ready()
	if batch_simple_polygons: _configure_polygon_batch()

func _configure_polygon_batch() -> void:
	for child: Node in find_children("*", "Polygon2D", true, false):
		BattlePolygonBatch.configure(child as Polygon2D, batch_simple_polygons)

func apply_view(values: Dictionary, config: IsoGridConfig) -> bool:
	var cell: Vector2i = values["cell"]
	var next_role: Role = values["role"] as Role
	var steps: int = values["half_steps"]
	var void_surface: bool = values["is_void"]
	var liquid_surface: bool = values.get("deep_acid", false)
	var can_reach: bool = values["reachable"]
	var in_enemy_range: bool = values["enemy_range"]
	var on_fire: bool = values["burning"]
	# Resource разрешено редактировать на месте: сравниваем значения геометрии,
	# а не identity ресурса или revision игрового состояния.
	var geometry_changed := not _view_initialized or _view_tile_size != config.tile_size \
		or _view_height_step != config.height_step or _view_origin != config.origin_offset
	var surface_changed := geometry_changed or grid_anchor != cell or height_level != 0 \
		or role != next_role or half_steps != steps or is_void != void_surface \
		or burning != on_fire or deep_acid != liquid_surface
	var changed := surface_changed or reachable != can_reach or enemy_range != in_enemy_range
	grid_config = config
	if not changed: return false
	role = next_role
	half_steps = steps
	is_void = void_surface
	deep_acid = liquid_surface
	reachable = can_reach
	enemy_range = in_enemy_range
	burning = on_fire
	view_apply_count += 1
	if not surface_changed and highlights_use_ground_overlay and _ground_overlay != null:
		_ground_overlay.queue_redraw()
		return true
	set_grid_anchor(cell)
	_view_tile_size = config.tile_size
	_view_height_step = config.height_step
	_view_origin = config.origin_offset
	_view_initialized = true
	sync_scene_art()
	queue_redraw()
	return true

func reset_view_pose() -> void:
	# Публикация снимает прошлый семпл; resize затем восстанавливает активный
	# семпл из BattleFieldPresentation, не из runtime боя.
	if presentation_lift != 0.0: presentation_lift = 0.0
	if presentation_offset != Vector2.ZERO: presentation_offset = Vector2.ZERO
	if action_offset != Vector2.ZERO: action_offset = Vector2.ZERO
	if fall_drop != 0.0: fall_drop = 0.0
	if landing_compression != 0.0: landing_compression = 0.0
	if death_progress != 0.0: death_progress = 0.0
	if modulate != _rest_modulate: modulate = _rest_modulate

func retire_view() -> void:
	reset_view_pose()
	_view_initialized = false
	if _fire_view != null: _fire_view.retire_view()
	if _deep_acid_view != null:
		(_deep_acid_view.get_node(^"Liquid") as BattleAnimatedAcidPool).retire_view()
		_deep_acid_view.hide()

func sync_scene_art() -> void:
	super.sync_scene_art()
	if not is_inside_tree() or grid_config == null: return
	_sync_selected_fire()
	if deep_acid and _deep_acid_view == null:
		_deep_acid_view = DEEP_ACID_SCENE.instantiate() as Node2D
		add_child(_deep_acid_view)
	if _deep_acid_view != null:
		var active := deep_acid and not is_void and role in [Role.FLOOR, Role.PLATFORM]
		_deep_acid_view.visible = active
		_deep_acid_view.position = _top_offset()
		_deep_acid_view.scale = Vector2.ONE * (grid_config.tile_size.x / 128.0)
		var liquid := _deep_acid_view.get_node(^"Liquid") as BattleAnimatedAcidPool
		liquid.set_active(active)
		if active:
			# Полный ромб жидкости ниже пола; верх кладки следует за ним без отдельного бортика.
			# super каждый раз восстанавливает исходные вершины: смещение не накапливается.
			for path: NodePath in [^"ArtRoot/SideLeft", ^"ArtRoot/SideRight"]:
				var side := get_node_or_null(path) as Polygon2D
				if side == null or not side.visible or side.polygon.size() != 4: continue
				var points := side.polygon
				points[0].y += liquid.position.y
				points[1].y += liquid.position.y
				side.polygon = points

func sync_view_transform() -> void:
	pass


func _sync_selected_fire() -> void:
	var active := selected_fire and burning and not is_void and not deep_acid and role != Role.UNIT
	if active and _fire_view == null:
		_fire_view = SELECTED_FIRE_SCENE.instantiate() as BattleAnimatedAcidPool
		add_child(_fire_view)
	if _fire_view != null:
		# Накладка следует поверхности вместе с высотой/падением; ArtRoot второй раз её не масштабирует.
		_fire_view.position = _top_offset()
		_fire_view.scale = Vector2.ONE * (grid_config.tile_size.x / 128.0)
		_fire_view.set_active(active)
	if selected_fire:
		var legacy := get_node_or_null(^"ArtRoot/EffectRoot/BurningSprite") as CanvasItem
		if legacy != null: legacy.hide()
