extends "res://scripts/demo/art_trial_tile.gd"

const ATLAS_A: Texture2D = preload("res://assets/art_presets/trials/dungeon_comparison_v1/atlas_a.png")
const ATLAS_B: Texture2D = preload("res://assets/art_presets/trials/dungeon_comparison_v1/atlas_b.png")

@export_range(1, 7, 1) var split_column: int = 4
var _floor_pieces: Array[Polygon2D] = []
var _wall_top: Polygon2D
var _surface_sprite: Sprite2D
var _left_side: Polygon2D
var _right_side: Polygon2D
var _comparison_ready: bool = false

func _ready() -> void:
	super._ready()
	_surface_sprite = get_node_or_null("ArtRoot/SurfaceSprite") as Sprite2D
	_left_side = get_node_or_null("ArtRoot/SideLeft") as Polygon2D
	_right_side = get_node_or_null("ArtRoot/SideRight") as Polygon2D
	_wall_top = get_node_or_null("ArtRoot/DungeonWallTop") as Polygon2D
	var ground := get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
	if ground != null:
		for index: int in range(6):
			var piece := ground.get_node_or_null("DungeonFloor%d" % index) as Polygon2D
			if piece != null: _floor_pieces.append(piece)
	_comparison_ready = _floor_pieces.size() == 6 and _wall_top != null
	# Отдельный экземпляр сцены может войти в дерево до первой публикации доски.
	if grid_config != null: sync_scene_art()

func _uses_ground_art() -> bool:
	return super._uses_ground_art() and _selected_atlas() != null

# Локальная колонка повторяет раскладку в обеих половинах для честного сравнения атласов.
func _selected_atlas() -> Texture2D:
	return ATLAS_A if grid_anchor.x < split_column else ATLAS_B

# Представление меняет источник/видимость; геометрия и UV остаются авторскими в сцене.
func sync_scene_art() -> void:
	super.sync_scene_art()
	if not _comparison_ready: return
	var atlas := _selected_atlas()
	var floor_active := _uses_ground_art() and atlas != null
	var local_x := posmod(grid_anchor.x, split_column)
	var variant: int = posmod(local_x + 2 * grid_anchor.y, _floor_pieces.size())
	for index: int in range(_floor_pieces.size()):
		var piece := _floor_pieces[index]
		piece.visible = floor_active and index == variant
		piece.texture = atlas
		piece.color = Color.WHITE
	var wall_active := role == Role.WALL and not is_void and atlas != null
	_wall_top.visible = wall_active
	_wall_top.texture = atlas
	_wall_top.position = _surface_sprite.position if _surface_sprite != null else Vector2.ZERO
	_wall_top.color = Color.WHITE
	if wall_active and _surface_sprite != null: _surface_sprite.visible = false
	if atlas == null: return
	for side: Polygon2D in [_left_side, _right_side]:
		if side == null: continue
		side.texture = atlas
		side.color = Color.WHITE
		# Пустая раскраска убирает унаследованный tint, который затемнил бы исходный пиксель.
		side.vertex_colors = PackedColorArray()
