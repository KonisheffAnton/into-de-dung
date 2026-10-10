class_name BattleTerrainVisual
extends BattleDemoIsoVisual

## Явное согласие сцены на сохранение опоры между публикациями представления.
var view_apply_count: int = 0
var _view_initialized: bool = false
var _view_tile_size: Vector2
var _view_height_step: float
var _view_origin: Vector2
@onready var _rest_modulate: Color = modulate

func apply_view(values: Dictionary, config: IsoGridConfig) -> bool:
	var cell: Vector2i = values["cell"]
	var next_role: Role = values["role"] as Role
	var steps: int = values["half_steps"]
	var void_surface: bool = values["is_void"]
	var can_reach: bool = values["reachable"]
	var in_enemy_range: bool = values["enemy_range"]
	var on_fire: bool = values["burning"]
	# Resource разрешено редактировать на месте: сравниваем значения геометрии,
	# а не identity ресурса или revision игрового состояния.
	var geometry_changed := not _view_initialized or _view_tile_size != config.tile_size \
		or _view_height_step != config.height_step or _view_origin != config.origin_offset
	var changed := geometry_changed or grid_anchor != cell or height_level != 0 \
		or role != next_role or half_steps != steps or is_void != void_surface \
		or reachable != can_reach or enemy_range != in_enemy_range or burning != on_fire
	grid_config = config
	if not changed: return false
	role = next_role
	half_steps = steps
	is_void = void_surface
	reachable = can_reach
	enemy_range = in_enemy_range
	burning = on_fire
	set_grid_anchor(cell)
	_view_tile_size = config.tile_size
	_view_height_step = config.height_step
	_view_origin = config.origin_offset
	_view_initialized = true
	view_apply_count += 1
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

func sync_view_transform() -> void:
	pass
