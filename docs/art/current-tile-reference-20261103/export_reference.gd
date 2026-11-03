extends SceneTree

const TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const TILE_SIZE := Vector2(128.0, 96.0)
const HEIGHT_STEP := 32.0
const LARGE_SIZE := Vector2i(1024, 1024)
const NATIVE_SIZE := Vector2i(256, 256)

var output_dir: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
	call_deferred("_export")

func _export() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Экспорт требует GPU DisplayServer; headless рендер не поддерживается")
		quit(2)
		return
	if output_dir.is_empty():
		printerr("Нужен абсолютный путь в аргументе --output=")
		quit(2)
		return
	if not output_dir.is_absolute_path():
		printerr("Каталог --output= должен быть абсолютным")
		quit(2)
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		printerr("Не удалось создать каталог: %s (%d)" % [output_dir, mkdir_error])
		quit(1)
		return
	var large := await _capture(LARGE_SIZE, 4.0, Vector2(512.0, 400.0))
	if large == null or large.is_empty() or large.save_png(output_dir.path_join("tile.png")) != OK:
		printerr("Не удалось сохранить tile.png")
		quit(1)
		return
	var native := await _capture(NATIVE_SIZE, 1.0, Vector2(128.0, 88.0))
	if native == null or native.is_empty() or native.save_png(output_dir.path_join("tile-native.png")) != OK:
		printerr("Не удалось сохранить tile-native.png")
		quit(1)
		return
	var metadata := _metadata(large, native)
	var json_file := FileAccess.open(output_dir.path_join("reference.json"), FileAccess.WRITE)
	if json_file == null:
		printerr("Не удалось открыть reference.json для записи")
		quit(1)
		return
	json_file.store_string(JSON.stringify(metadata, "\t") + "\n")
	json_file.close()
	print("Экспортировано: tile.png, tile-native.png, reference.json")
	quit(0)

func _capture(size: Vector2i, art_scale: float, anchor: Vector2) -> Image:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var holder := Node2D.new()
	holder.position = anchor
	holder.scale = Vector2.ONE * art_scale
	viewport.add_child(holder)
	var tile := TILE_SCENE.instantiate() as BattleTerrainVisual
	if tile == null:
		printerr("Сцена тайла не является BattleTerrainVisual")
		viewport.queue_free()
		return null
	holder.add_child(tile)
	var config := IsoGridConfig.new()
	config.tile_size = TILE_SIZE
	config.height_step = HEIGHT_STEP
	config.origin_offset = Vector2.ZERO
	var values: Dictionary = {
		"cell": Vector2i.ZERO,
		"role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0,
		"is_void": false,
		"reachable": false,
		"enemy_range": false,
		"burning": false,
	}
	# Сначала задаём конфигурацию и публикуем клетку штатным API, чтобы UV и стороны
	# собрал сам автор сцены, включая зависящую от клетки адресацию текстуры.
	tile.grid_config = config
	if not tile.apply_view(values, config):
		printerr("Сцена отклонила опубликованный снимок клетки")
		viewport.queue_free()
		return null
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image

func _metadata(large: Image, native: Image) -> Dictionary:
	var tile := TILE_SCENE.instantiate() as BattleTerrainVisual
	if tile == null:
		return {}
	root.add_child(tile)
	var config := IsoGridConfig.new()
	config.tile_size = TILE_SIZE
	config.height_step = HEIGHT_STEP
	config.origin_offset = Vector2.ZERO
	tile.grid_config = config
	var values: Dictionary = {
		"cell": Vector2i.ZERO,
		"role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0,
		"is_void": false,
		"reachable": false,
		"enemy_range": false,
		"burning": false,
	}
	if not tile.apply_view(values, config):
		printerr("Нет метаданных: сцена отклонила снимок клетки")
		tile.queue_free()
		return {}
	var floor_polygon := tile.get_node("ArtRoot/GroundSurface/DungeonFloor") as Polygon2D
	var left_side := tile.get_node("ArtRoot/SideLeft") as Polygon2D
	var right_side := tile.get_node("ArtRoot/SideRight") as Polygon2D
	var floor_path := _resource_path(floor_polygon.texture)
	var masonry_path := _resource_path(left_side.texture)
	var result: Dictionary = {
		"scene": "res://scenes/demo/visuals/dungeon_comparison_tile.tscn",
		"grid_config": {"tile_size": [128, 96], "height_step": 32, "origin_offset": [0, 0]},
		"cell": [0, 0],
		"role": "FLOOR",
		"half_steps": 0,
		"anchor_px": [512, 400],
		"scale": 4,
		"native_anchor_px": [128, 88],
		"native_scale": 1,
		"texture_paths": {
			"floor": floor_path,
			"masonry": masonry_path,
		},
		"floor_uv": _points(floor_polygon.uv),
		"side_polygons": {"left": _points(left_side.polygon), "right": _points(right_side.polygon)},
		"side_tints": {"left": _color(left_side.color), "right": _color(right_side.color)},
		"side_vertex_tints": {"left": _colors(left_side.vertex_colors), "right": _colors(right_side.vertex_colors)},
		"side_depth_px": tile.side_depth_pixels,
		"images": {
			"tile.png": _image_info(large),
			"tile-native.png": {"size": [native.get_width(), native.get_height()], "alpha_bbox": _alpha_bbox(native)},
		},
	}
	tile.free()
	return result

func _resource_path(resource: Resource) -> String:
	if resource == null:
		return ""
	var path := resource.resource_path
	return path if not path.is_empty() else "<embedded>"

func _points(points: PackedVector2Array) -> Array[Array]:
	var result: Array[Array] = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result

func _color(color: Color) -> Array[float]:
	return [color.r, color.g, color.b, color.a]

func _colors(colors: PackedColorArray) -> Array[Array]:
	var result: Array[Array] = []
	for color: Color in colors:
		result.append(_color(color))
	return result

func _image_info(image: Image) -> Dictionary:
	return {"size": [image.get_width(), image.get_height()], "alpha_bbox": _alpha_bbox(image)}

func _alpha_bbox(image: Image) -> Array[int]:
	var rect := image.get_used_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
