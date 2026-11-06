extends SceneTree

const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const ENVIRONMENT: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const FRAMES: SpriteFrames = preload("res://assets/art_presets/approved/fire29_selected_v1/fire29_frames.tres")
var passed: int = 0
var failed: int = 0
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL FIRE29: " + label)

func values(burning: bool, steps: int = 0) -> Dictionary:
	return {"cell": Vector2i(2, 2), "role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": steps, "is_void": false, "deep_acid": false,
		"reachable": false, "enemy_range": false, "burning": burning}

func run() -> void:
	check(FRAMES.get_frame_count(&"fire") == 96 and FRAMES.get_animation_loop(&"fire"), "all 96 selected slots loop")
	check(is_equal_approx(FRAMES.get_animation_speed(&"fire"), 12.5), "selected 80ms cadence")
	for index: int in 96:
		var texture := FRAMES.get_frame_texture(&"fire", index) as AtlasTexture
		var local_slot := index % 16
		check(texture != null and texture.region == Rect2((local_slot % 4) * 256, floori(float(local_slot) / 4.0) * 194, 256, 194)
			and is_equal_approx(FRAMES.get_frame_duration(&"fire", index), 1.0), "exact export cell/duration %d" % index)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 576)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var tile := TILE.instantiate() as BattleTerrainVisual
	viewport.add_child(tile)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.origin_offset = Vector2(384, 40)
	config.height_step = 32
	tile.apply_view(values(false), config)
	var picking := tile.surface_polygons()
	check(tile._fire_view == null, "unlit tile allocates no fire view")
	tile.apply_view(values(true), config)
	var fire := tile._fire_view
	check(fire != null and fire.visible, "current stone terrain uses selected fire")
	if fire != null:
		var sprite := fire.get_node(^"Animation") as AnimatedSprite2D
		check(sprite.is_playing() and sprite.sprite_frames == FRAMES, "selected clip is playing")
		sprite.set_frame_and_progress(95, 0.9)
		await create_timer(0.12).timeout
		check(sprite.frame < 10 and sprite.is_playing(), "engine crosses the real 95 to 0 loop without stopping")
		check(not (tile.get_node(^"ArtRoot/EffectRoot/BurningSprite") as CanvasItem).visible, "old fire is hidden")
		check(tile.surface_polygons() == picking, "fire does not change picking")
		sprite.set_frame_and_progress(37, 0.25)
		check(not tile.apply_view(values(true), config) and sprite.frame == 37, "unchanged publication keeps phase")
		tile.sync_scene_art()
		check(sprite.frame == 37 and is_equal_approx(sprite.frame_progress, 0.25), "explicit sync keeps phase")
		tile.apply_view(values(false), config)
		check(not fire.visible and not sprite.is_playing(), "extinguish pauses")
		tile.apply_view(values(true), config)
		check(fire == tile._fire_view and sprite.is_playing() and sprite.frame == 37, "re-ignite reuses paused view")
		for factor: float in [0.75, 1.0, 1.5]:
			config.tile_size = Vector2(128, 96) * factor
			config.height_step = 32 * factor
			for step: int in [-2, 0, 2]:
				tile.apply_view(values(true, step), config)
				check(fire.position.is_equal_approx(tile._top_offset()) and fire.scale.is_equal_approx(Vector2.ONE * factor), "fire follows elevation and scale once")
				var expected := tile.top_polygon()
				var source_corners: Array[Vector2] = [Vector2(128, 12.1013645), Vector2(243.162242, 99.4580897), Vector2(128, 186.814815), Vector2(12.837758, 99.4580897)]
				for corner: int in 4:
					check((fire.transform * sprite.transform * source_corners[corner]).distance_to(expected[corner]) < 0.02, "fire fits complete surface corner")
		var void_values := values(true)
		void_values.is_void = true
		tile.apply_view(void_values, config)
		check(not fire.visible and not sprite.is_playing(), "VOID stops visible fire")
		var acid_values := values(true)
		acid_values.deep_acid = true
		tile.apply_view(acid_values, config)
		check(not fire.visible, "deep acid surface hides fire")
		tile.apply_view(values(true), config)
		tile.retire_view()
		check(not fire.visible and not sprite.is_playing() and sprite.frame == 0, "retire stops pooled clock")
		tile.apply_view(values(true), config)
		check(fire.visible and sprite.is_playing(), "reuse restores animation after retire")
		if DisplayServer.get_name() != "headless":
			await capture_tiles(viewport, tile, config)
	viewport.queue_free()
	await process_frame
	print("FIRE29 ANIMATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func save_frame(viewport: SubViewport, label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if not captures.is_empty():
		check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

func capture_tiles(viewport: SubViewport, tile: BattleTerrainVisual, config: IsoGridConfig) -> void:
	config.tile_size = Vector2(256, 192)
	config.height_step = 64
	config.origin_offset = Vector2(384, -110)
	tile.apply_view(values(true), config)
	var fire := tile._fire_view
	var sprite := fire.get_node(^"Animation") as AnimatedSprite2D
	sprite.pause()
	for frame_index: int in [0, 24, 48, 95]:
		sprite.frame = frame_index
		await save_frame(viewport, "fire29-%02d" % frame_index)
	# Рендерим настоящий каменный тайл с соседями: прежний прозрачный fixture не выявлял торец плиты.
	tile.apply_view(values(false), config)
	var neighbours: Array[BattleTerrainVisual] = []
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var neighbour := TILE.instantiate() as BattleTerrainVisual
		viewport.add_child(neighbour)
		var neighbour_values := values(false)
		neighbour_values.cell += offset
		neighbour.apply_view(neighbour_values, config)
		neighbours.append(neighbour)
	var environment := ENVIRONMENT.instantiate() as BattleManagedEnvironmentVisual
	viewport.add_child(environment)
	var corpses: Array[Dictionary] = []
	environment.configure(false, false, false, corpses, false, true)
	environment.position = tile.position + tile._top_offset()
	environment.scale = Vector2.ONE * 2.0
	for progress: float in [0.0, 0.5, 1.0]:
		environment.trap_progress = progress
		await save_frame(viewport, "flush-spikes-%d" % int(progress * 2))
	# Контроль берёт исходный торец старой версии; снимок нужен для непосредственного сравнения.
	var pose := environment.get_node(^"FloorTrap/Pose") as AnimatedSprite2D
	pose.material = pose.material.duplicate()
	(pose.material as ShaderMaterial).set_shader_parameter("source_top_center", Vector2(127.5, 94))
	(pose.material as ShaderMaterial).set_shader_parameter("top_half_size", Vector2(75.5, 66))
	pose.position = Vector2(-108.07947, -68.36364)
	pose.scale = Vector2(0.8476821, 0.7272727)
	environment.trap_progress = 0.0
	await save_frame(viewport, "negative-old-trap-lip")
	environment.queue_free()
	for neighbour: BattleTerrainVisual in neighbours: neighbour.queue_free()
