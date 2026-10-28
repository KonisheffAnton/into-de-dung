extends "res://scripts/demo/art_trial_tile.gd"

const FLOOR_TEXTURE: Texture2D = preload("res://assets/art_presets/trials/dungeon_room_v2/floor.png")
const MASONRY_TEXTURE: Texture2D = preload("res://assets/art_presets/trials/dungeon_room_v2/masonry.png")
const COLUMN_CELL := Vector2i(3, 0)
const MASONRY_LEFT_TINT := Color(0.78, 0.78, 0.78, 1.0)
const MASONRY_RIGHT_TINT := Color(0.95, 0.95, 0.95, 1.0)

@onready var _floor_polygon: Polygon2D = $ArtRoot/GroundSurface/DungeonFloor
@onready var _wall_top: Polygon2D = $ArtRoot/DungeonWallTop
@onready var _column: Sprite2D = $ArtRoot/BrokenColumn
@onready var _surface_sprite: Sprite2D = $ArtRoot/SurfaceSprite
@onready var _left_side: Polygon2D = $ArtRoot/SideLeft
@onready var _right_side: Polygon2D = $ArtRoot/SideRight
var _dungeon_nodes_ready: bool = false

func _ready() -> void:
	super._ready()
	_dungeon_nodes_ready = _floor_polygon != null and _wall_top != null and _column != null
	# У отдельного экземпляра grid_config появится только при публикации от доски.
	if _dungeon_nodes_ready and grid_config != null: sync_scene_art()

func sync_scene_art() -> void:
	super.sync_scene_art()
	if not _dungeon_nodes_ready or grid_config == null: return
	var factor: float = grid_config.tile_size.x / 128.0
	if factor <= 0.0: return
	var biome: int = BiomeArtCatalog.index_at(grid_anchor)
	var floor_texture: Texture2D = BiomeArtCatalog.FLOORS[biome]
	var floor_cell_x: int = posmod(grid_anchor.x, 8)
	var floor_cell_y: int = posmod(grid_anchor.y, 8)
	var floor_step: Vector2 = floor_texture.get_size() / 8.0
	var floor_origin := Vector2(float(floor_cell_x), float(floor_cell_y)) * floor_step
	var floor_end := floor_origin + floor_step
	var floor_uv := PackedVector2Array([
		floor_origin, Vector2(floor_end.x, floor_origin.y), floor_end, Vector2(floor_origin.x, floor_end.y),
	])
	_floor_polygon.texture = floor_texture
	_floor_polygon.uv = floor_uv
	_floor_polygon.visible = _uses_ground_art()
	_floor_polygon.color = Color.WHITE
	var wall_active := role == Role.WALL and not is_void
	var column_active := wall_active and BiomeArtCatalog.is_obstacle(grid_anchor)
	_wall_top.visible = wall_active and not column_active
	_wall_top.texture = floor_texture
	_wall_top.uv = floor_uv
	_wall_top.position = _surface_sprite.position
	_wall_top.color = Color.WHITE
	_column.visible = column_active
	_column.texture = BiomeArtCatalog.OBSTACLES[biome]
	_column.region_enabled = true
	_column.region_rect = BiomeArtCatalog.REGIONS[biome]
	var region_height := _column.region_rect.size.y
	if region_height > 0.0:
		_column.scale = Vector2.ONE * BiomeArtCatalog.HEIGHTS[biome] / region_height
		_column.position = Vector2(0, 12.0 - BiomeArtCatalog.HEIGHTS[biome] * 0.5)
	if _surface_sprite != null and wall_active: _surface_sprite.visible = false
	if column_active:
		# Колонна заменяет только декоративный рисунок стены; floor и окружение остаются отдельными узлами доски.
		if _left_side != null: _left_side.visible = false
		if _right_side != null: _right_side.visible = false
		return
	_sync_masonry_side(_left_side, true, factor)
	_sync_masonry_side(_right_side, false, factor)

func _draw() -> void:
	if role == Role.WALL and BiomeArtCatalog.is_obstacle(grid_anchor) and not is_void:
		# У отдельной колонны нет квадратной крышки: её контур выглядел бы висящей рамкой.
		# Игровые маркеры и logical picking остаются у штатного terrain lifecycle.
		if _ground_overlay != null: _ground_overlay.queue_redraw()
		return
	super._draw()

func _sync_masonry_side(side: Polygon2D, is_left: bool, factor: float) -> void:
	if side == null or not side.visible: return
	var points := side.polygon
	if points.size() < 4: return
	var top_left: Vector2 = points[0]
	var top_right: Vector2 = points[1]
	var masonry: Texture2D = BiomeArtCatalog.SIDES[BiomeArtCatalog.index_at(grid_anchor)]
	var span: float = masonry.get_size().x / 4.0
	var vertical_density: float = masonry.get_size().y / 256.0
	var u_origin: float = float(grid_anchor.x) * span if is_left else -float(grid_anchor.y) * span
	var height_steps := float(half_steps) * grid_config.height_step * 0.5
	if role == Role.WALL: height_steps += grid_config.height_step
	var v_origin := -height_steps / factor * vertical_density
	var uv := PackedVector2Array()
	var horizontal_span := top_right.x - top_left.x
	if is_zero_approx(horizontal_span): return
	for point: Vector2 in points:
		var across: float = (point.x - top_left.x) / horizontal_span
		var base_y: float = top_left.y + across * (top_right.y - top_left.y)
		uv.append(Vector2(u_origin + across * span,
			v_origin + (point.y - base_y) * vertical_density))
	side.texture = masonry
	side.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	side.uv = uv
	side.color = MASONRY_LEFT_TINT if is_left else MASONRY_RIGHT_TINT
	# Нейтральный tint убирает устаревший коричневый градиент унаследованной сцены.
	side.vertex_colors = PackedColorArray()
