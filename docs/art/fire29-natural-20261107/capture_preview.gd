extends SceneTree

const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
var package: String = ""
var repository: String = ""
var captures: String = ""
var selection_path: String = ""
var selection: Dictionary = {}
var views: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--package="): package = argument.trim_prefix("--package=")
		if argument.begins_with("--repository="): repository = argument.trim_prefix("--repository=")
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
		if argument.begins_with("--selection="): selection_path = argument.trim_prefix("--selection=")
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
				"enemy_range": false, "burning": false}, config)
			if x == 2 and y == 2: center = tile
	var art := Node2D.new()
	center.add_child(art)
	art.position = center._top_offset()
	art.scale = Vector2.ONE * (tile_px / 128.0)
	var base := Polygon2D.new()
	art.add_child(base)
	base.polygon = PackedVector2Array([Vector2(0,-48), Vector2(64,0), Vector2(0,48), Vector2(-64,0)])
	base.uv = PackedVector2Array([Vector2(627,265), Vector2(932,496), Vector2(627,727), Vector2(322,496)])
	base.texture = ImageTexture.create_from_image(Image.load_from_file(repository.path_join(selection.source)))
	base.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	base.visible = not selection.get("whole_tile", false)
	var sprites: Array[Sprite2D] = []
	for group: Dictionary in selection.groups:
		var sprite := Sprite2D.new()
		art.add_child(sprite)
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if group.has("mask_image"):
			# Одна неподвижная маска отделяет огонь от пола; кадры PixelLab не меняются.
			var mask_shader := Shader.new()
			mask_shader.code = "shader_type canvas_item; uniform sampler2D fixed_mask : filter_linear; void fragment() { COLOR = texture(TEXTURE, UV); COLOR.a *= texture(fixed_mask, UV).r; }"
			var mask_material := ShaderMaterial.new()
			mask_material.shader = mask_shader
			mask_material.set_shader_parameter("fixed_mask", ImageTexture.create_from_image(Image.load_from_file(package.path_join(group.mask_image))))
			sprite.material = mask_material
		# Координаты и проекция постоянны: новые позы даёт только PNG провайдера.
		sprite.scale = Vector2(128.0 / 610.0, 96.0 / 462.0)
		sprite.position = (Vector2(group.native_crop_xyxy[0], group.native_crop_xyxy[1]) - Vector2(627,496)) * sprite.scale
		if group.get("runtime_projection", false):
			sprite.scale = Vector2(0.555737705, 0.549471147)
			sprite.position = Vector2(-71.1344262, -(99.4580897 + 29.0) * 0.549471147)
		sprites.append(sprite)
	return {"viewport":viewport, "sprites":sprites, "size":tile_px}

func run() -> void:
	if selection_path.is_empty(): selection_path = package.path_join("selection.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
	if not parsed is Dictionary or captures.is_empty() or repository.is_empty():
		quit(2)
		return
	selection = parsed
	views.append(make_view(128))
	views.append(make_view(384))
	var frames: Array[Array] = []
	for group: Dictionary in selection.groups:
		var textures: Array[Texture2D] = []
		for file: String in group.frames:
			var base_path: String = repository if selection.get("frame_path_base", "package") == "repository_root" else package
			var raw := Image.load_from_file(base_path.path_join(file))
			if raw == null:
				quit(3)
				return
			textures.append(ImageTexture.create_from_image(raw))
		frames.append(textures)
	for slot: int in selection.slots:
		for view: Dictionary in views:
			for index: int in selection.groups.size():
				var group: Dictionary = selection.groups[index]
				var pose: int = group.timeline[slot]
				view.sprites[index].texture = frames[index][pose]
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		for view: Dictionary in views:
			var destination: String = captures.path_join(str(view.size)).path_join("%03d.png" % slot)
			if view.viewport.get_texture().get_image().save_png(destination) != OK:
				quit(4)
				return
	print("NATURAL PREVIEW PASS: %d slots, %d raw groups,128/384 tile, ordinary neighbour Y-sort" % [selection.slots, selection.groups.size()])
	for view: Dictionary in views: view.viewport.queue_free()
	await process_frame
	quit(0)
