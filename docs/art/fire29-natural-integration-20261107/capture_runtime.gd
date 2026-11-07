extends SceneTree

const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
var captures: String = ""
var views: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func make_view(tile_px: int) -> Dictionary:
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
	var center: BattleTerrainVisual
	for y: int in range(1, 4):
		for x: int in range(1, 4):
			var tile := TILE.instantiate() as BattleTerrainVisual
			world.add_child(tile)
			tile.apply_view({"cell": Vector2i(x, y), "role": BattleDemoIsoVisual.Role.FLOOR,
				"half_steps": 0, "is_void": false, "deep_acid": false, "reachable": false,
				"enemy_range": false, "burning": x == 2 and y == 2}, config)
			if x == 2 and y == 2: center = tile
	# Геометрия показа прежняя, но огонь создаёт настоящий terrain через burning.
	var animation := center._fire_view.get_node(^"Animation") as AnimatedSprite2D
	animation.pause()
	return {"viewport": viewport, "animation": animation, "size": tile_px}

func run() -> void:
	if captures.is_empty():
		quit(2)
		return
	views.append(make_view(128))
	views.append(make_view(384))
	for slot: int in 12:
		for view: Dictionary in views: view.animation.frame = slot
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		for view: Dictionary in views:
			var path: String = captures.path_join(str(view.size)).path_join("%03d.png" % slot)
			if view.viewport.get_texture().get_image().save_png(path) != OK:
				quit(3)
				return
	print("FIRE29 RUNTIME CAPTURE PASS: 12 slots, 128/384 tile, production terrain and neighbour Y-sort")
	for view: Dictionary in views: view.viewport.queue_free()
	await process_frame
	quit(0)
