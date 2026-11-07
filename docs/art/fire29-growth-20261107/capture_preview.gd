extends SceneTree

const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
var package: String = ""
var captures: String = ""
var tile_px: int = 384

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--package="): package = argument.trim_prefix("--package=")
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
		if argument == "--tile-px=128": tile_px = 128
	call_deferred("run")

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(package.path_join("selection.json")))
	if not parsed is Dictionary or captures.is_empty():
		quit(2)
		return
	var selection: Dictionary = parsed
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 400) if tile_px == 128 else Vector2i(800, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node2D.new()
	world.y_sort_enabled = true
	viewport.add_child(world)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(tile_px, tile_px * 0.75)
	config.height_step = tile_px * 0.25
	config.origin_offset = Vector2(240, -12) if tile_px == 128 else Vector2(400, -296)
	var source: BattleTerrainVisual
	for y: int in range(1, 4):
		for x: int in range(1, 4):
			var tile := TILE.instantiate() as BattleTerrainVisual
			world.add_child(tile)
			tile.apply_view({"cell": Vector2i(x, y), "role": BattleDemoIsoVisual.Role.FLOOR,
				"half_steps": 0, "is_void": false, "deep_acid": false, "reachable": false,
				"enemy_range": false, "burning": false}, config)
			if x == 2 and y == 2: source = tile
	var pose := Node2D.new()
	source.add_child(pose)
	pose.position = source._top_offset()
	pose.scale = Vector2.ONE * (config.tile_size.x / 128.0)
	var sprite := Sprite2D.new()
	pose.add_child(sprite)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Исходная проекция fire29; новый PNG имеет только дополнительные29px прозрачного поля сверху.
	sprite.scale = Vector2(0.555737705, 0.549471147)
	sprite.position = Vector2(-71.1344262, -(99.4580897 + 29.0) * 0.549471147)
	for index: int in selection.frames.size():
		var file: String = selection.frames[index]
		var raw := Image.load_from_file(package.path_join(file))
		if raw == null or raw.get_size() != Vector2i(256, 256):
			quit(3)
			return
		sprite.texture = ImageTexture.create_from_image(raw)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var captured := viewport.get_texture().get_image()
		if captured.save_png(captures.path_join("%03d.png" % index)) != OK:
			quit(4)
			return
	print("GROWTH PREVIEW PASS: %d provider poses, original neighbour Y-sort" % selection.frames.size())
	viewport.queue_free()
	await process_frame
	quit(0)
