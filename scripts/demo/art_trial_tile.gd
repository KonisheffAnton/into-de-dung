extends BattleTerrainVisual

@export_range(0.0, 3.0, 0.05) var minimum_seam_pixels: float = 1.15
@onready var _seam: Line2D = $ArtRoot/GroundSurface/QuietSeam
@onready var _authored_seam_width: float = _seam.width

func _ready() -> void:
	super._ready()
	set_notify_transform(true)
	_sync_seam_width()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_sync_seam_width()

func sync_view_transform() -> void:
	_sync_seam_width()

func _sync_seam_width() -> void:
	if _seam == null: return
	var screen_transform := _seam.get_screen_transform()
	var scale_factor := minf(screen_transform.x.length(), screen_transform.y.length())
	if scale_factor <= 0.0: return
	# Геометрия остаётся авторской; тонкий стык не исчезает при уменьшении камеры/окна.
	_seam.width = maxf(_authored_seam_width, minimum_seam_pixels / scale_factor)

# Разнообразная постоянная раскладка держит эталонные пучки вне игрового RNG.
const VARIANT_GRID: Array[int] = [
	2, 0, 2, 2, 0, 2, 2, 1,
	2, 3, 2, 1, 2, 0, 2, 1,
	2, 0, 2, 3, 1, 2, 0, 2,
	3, 2, 3, 2, 1, 2, 0, 2,
	2, 0, 2, 1, 3, 2, 0, 2,
	2, 3, 1, 2, 0, 2, 1, 2,
	2, 1, 2, 3, 2, 1, 0, 2,
	1, 2, 3, 2, 0, 2, 1, 0,
]

func sync_scene_art() -> void:
	super.sync_scene_art()
	var table_index: int = posmod(grid_anchor.y, 8) * 8 + posmod(grid_anchor.x, 8)
	var selected_index: int = VARIANT_GRID[table_index]
	for index: int in range(4):
		var variant := get_node_or_null("ArtRoot/GroundSurface/Grass%d" % index) as Polygon2D
		if variant != null:
			# Сетка привязывает рисунок к клетке и не меняет состояние боя.
			variant.visible = index == selected_index and _uses_ground_art()
	_sync_seam_width()
