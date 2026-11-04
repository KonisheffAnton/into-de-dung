extends SceneTree

const HUB_SCENE: PackedScene = preload("res://scenes/demo/hero_hub.tscn")
const DUNGEON_TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const DUNGEON_ENVIRONMENT: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const ACID_SCENE: PackedScene = preload("res://scenes/demo/visuals/hazards/acid_pool_01.tscn")
const ACID_FRAMES: SpriteFrames = preload("res://assets/art_presets/approved/acid05_selected_v1/acid01_frames.tres")
const ACID_CELL := Vector2i(2, 6)
const BIOME_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(8, 0), Vector2i(16, 0),
	Vector2i(0, 8), Vector2i(8, 8), Vector2i(16, 8)]

var passed: int = 0
var failed: int = 0
var captures: String = ""
var gpu_available: bool = false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	gpu_available = DisplayServer.get_name() != "headless"
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ACID TILE ANIMATION: " + label)

func terrain_values(cell: Vector2i, steps: int = 0) -> Dictionary:
	return {"cell": cell, "role": BattleDemoIsoVisual.Role.PLATFORM if steps > 0 else BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": steps, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}

func make_environment(parent: Node, acid: bool) -> BattleManagedEnvironmentVisual:
	var overlay := DUNGEON_ENVIRONMENT.instantiate() as BattleManagedEnvironmentVisual
	parent.add_child(overlay)
	var corpses: Array[Dictionary] = []
	overlay.configure(false, false, false, corpses, acid)
	return overlay

func pool_sprite(pool: BattleAnimatedAcidPool) -> AnimatedSprite2D:
	return pool.get_node_or_null(^"Animation") as AnimatedSprite2D

func check_resource_contract() -> void:
	check(ACID_FRAMES.has_animation(&"acid"), "selected frames resource defines acid animation")
	if not ACID_FRAMES.has_animation(&"acid"): return
	check(ACID_FRAMES.get_frame_count(&"acid") == 33, "resource contains all 33 supplied frames")
	check(is_equal_approx(ACID_FRAMES.get_animation_speed(&"acid"), 10.0)
		and ACID_FRAMES.get_animation_loop(&"acid"), "resource loops at 10 fps")
	for index: int in range(33):
		var texture := ACID_FRAMES.get_frame_texture(&"acid", index) as AtlasTexture
		var cell := Vector2i(index % 8, floori(float(index) / 8.0))
		check(texture != null and texture.region == Rect2(cell * 256, Vector2(256, 256)),
			"frame %02d maps its full 256px atlas cell" % index)
	check(not ACID_FRAMES.resource_local_to_scene, "shared SpriteFrames remain a definition resource")
	var scene_instance := ACID_SCENE.instantiate()
	check(scene_instance is BattleAnimatedAcidPool, "acid scene instantiates typed runtime overlay")
	scene_instance.free()

func check_pool_lifecycle() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var overlay := make_environment(host, true)
	var pool := overlay.get_node(^"AcidPool") as BattleAnimatedAcidPool
	var sprite := pool_sprite(pool)
	await process_frame
	check(pool.visible and sprite != null and sprite.is_playing(), "active pool starts its own animation clock")
	if sprite == null:
		host.free()
		return
	await create_timer(0.35).timeout
	check(sprite.frame != 0 or sprite.frame_progress > 0.0, "active acid animation advances")
	sprite.speed_scale = 0.0
	sprite.set_frame_and_progress(11, 0.375)
	var held_frame := sprite.frame
	var held_progress := sprite.frame_progress
	for _refresh: int in range(3):
		overlay.configure(false, false, false, [], true)
		check(overlay.get_node(^"AcidPool") == pool and sprite.frame == held_frame
			and is_equal_approx(sprite.frame_progress, held_progress), "refresh preserves pool identity and frame sample")
		await process_frame
	check(sprite.frame == held_frame and is_equal_approx(sprite.frame_progress, held_progress), "refresh cannot advance a frozen frame")
	overlay.configure(false, false, false, [], false)
	check(not pool.visible and not sprite.is_playing(), "inactive pool hides and pauses")
	check(sprite.frame == held_frame and is_equal_approx(sprite.frame_progress, held_progress), "pause preserves current sample")
	overlay.configure(false, false, false, [], true)
	check(pool.visible and sprite.is_playing() and sprite.frame == held_frame
		and is_equal_approx(sprite.frame_progress, held_progress), "reactivation resumes without resetting the frame")
	overlay.retire_view()
	check(not pool.visible and not sprite.is_playing(), "retirement hides and stops pool playback")
	overlay.configure(false, false, false, [], true)
	check(pool.visible and sprite.is_playing(), "reused overlay can reactivate after retirement")
	host.free()
	await process_frame

func check_biome_surfaces() -> void:
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32.0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 520)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var display := Node2D.new()
	viewport.add_child(display)
	for index: int in BIOME_CELLS.size():
		var cell := BIOME_CELLS[index]
		var tile := DUNGEON_TILE.instantiate() as BattleTerrainVisual
		display.add_child(tile)
		tile.apply_view(terrain_values(cell, 2 if index % 2 == 1 else 0), config)
		tile.position = Vector2(120 + (index % 3) * 240, 120 + floori(float(index) / 3.0) * 230)
		await process_frame
		var surface := tile.get_node(^"ArtRoot/SurfaceSprite") as Sprite2D
		var ground_layer := tile.get_node(^"ArtRoot/GroundSurface") as Sprite2D
		var top := tile.get_node(^"ArtRoot/GroundSurface/DungeonFloor") as Polygon2D
		var left := tile.get_node(^"ArtRoot/SideLeft") as Polygon2D
		var right := tile.get_node(^"ArtRoot/SideRight") as Polygon2D
		var original_texture := surface.texture
		var original_ground_visibility := ground_layer.visible
		var original_top_texture := top.texture
		var original_top_uv := top.uv.duplicate()
		var original_left := left.polygon.duplicate()
		var original_right := right.polygon.duplicate()
		var original_left_uv := left.uv.duplicate()
		var original_right_uv := right.uv.duplicate()
		var original_left_texture := left.texture
		var original_right_texture := right.texture
		var overlay := make_environment(tile, true)
		overlay.position = tile.get_visual_offset() + Vector2(0, 0.5)
		var pool := overlay.get_node(^"AcidPool") as BattleAnimatedAcidPool
		var sprite := pool_sprite(pool)
		sprite.speed_scale = 0.0
		sprite.set_frame_and_progress(8, 0.0)
		check(pool.visible and sprite.is_playing(), "acid overlays biome surface %d" % index)
		check(ground_layer.visible == original_ground_visibility and ground_layer.is_visible_in_tree()
			and surface.texture == original_texture, "biome ground layer and base material remain unchanged")
		check(top.is_visible_in_tree() and top.texture == original_top_texture and top.uv == original_top_uv,
			"biome diamond material and UV remain unchanged under acid overlay")
		check(left.visible and right.visible and left.texture == original_left_texture and right.texture == original_right_texture,
			"biome masonry materials remain visible for acid overlay")
		check(left.polygon == original_left and right.polygon == original_right
			and left.uv == original_left_uv and right.uv == original_right_uv,
			"acid overlay does not trim, move, or remap biome sides")
	if gpu_available and not captures.is_empty():
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		check(image != null and image.save_png(captures.path_join("acid-six-biomes.png")) == OK,
			"six-biome acid comparison capture saved")
	viewport.queue_free()
	await process_frame

func check_mask_render() -> void:
	if not gpu_available:
		print("SKIP ACID GPU MASK: headless renderer")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var carrier := Node2D.new()
	carrier.position = Vector2(128, 100)
	viewport.add_child(carrier)
	var pool := ACID_SCENE.instantiate() as BattleAnimatedAcidPool
	carrier.add_child(pool)
	pool.set_active(true)
	var sprite := pool_sprite(pool)
	sprite.speed_scale = 0.0
	var acid_material: Material = sprite.material
	for index: int in range(33):
		sprite.set_frame_and_progress(index, 0.0)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var outside_alpha := 0
		var interior_samples := 0
		var solid_interior := 0
		for y: int in range(256):
			for x: int in range(256):
				var diamond_distance := absf(float(x) + 0.5 - 128.0) / 64.0 + absf(float(y) + 0.5 - 100.0) / 48.0
				var alpha := image.get_pixel(x, y).a
				if diamond_distance > 1.04:
					if alpha > 0.02: outside_alpha += 1
				elif diamond_distance <= 0.94:
					interior_samples += 1
					if alpha >= 0.95: solid_interior += 1
		check(outside_alpha == 0, "frame %02d has no stone or acid outside the logical diamond" % index)
		check(interior_samples > 0 and float(solid_interior) / float(interior_samples) >= 0.99,
			"frame %02d preserves opaque acid across the interior diamond" % index)
		if index == 0:
			sprite.material = null
			await RenderingServer.frame_post_draw
			var raw_image := viewport.get_texture().get_image()
			var raw_outside := 0
			for y: int in range(256):
				for x: int in range(256):
					var distance := absf(float(x) + 0.5 - 128.0) / 64.0 + absf(float(y) + 0.5 - 100.0) / 48.0
					if distance > 1.04 and raw_image.get_pixel(x, y).a > 0.02: raw_outside += 1
			check(raw_outside > 500, "negative control without mask exposes the supplied stone outside the diamond")
			sprite.material = acid_material
			await RenderingServer.frame_post_draw
		if not captures.is_empty():
			check(image.save_png(captures.path_join("acid-frame-%02d.png" % index)) == OK,
				"masked acid frame %02d capture saved" % index)
	viewport.queue_free()
	await process_frame

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var value := ItemSimulationSnapshot.capture(session.state, [])
	return {"state": value.snapshot.to_dict() if value.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}

func check_live_route() -> void:
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	var started := ExpeditionTransitions.apply(profile, "start")
	check(started.is_ok(), "route fixture starts first expedition room")
	if not started.is_ok(): return
	var save_path := "user://acid-animation-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(HeroHubStore.write_run(save_path, started.profile).is_empty(), "route fixture stores isolated checkpoint")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := HUB_SCENE.instantiate() as HeroHubScreen
	screen.save_path = save_path
	screen.expedition_mode = true
	screen.mage_deck_mode = true
	viewport.add_child(screen)
	screen.set_process(false)
	await process_frame
	await process_frame
	var battle := screen.battle_view
	check(battle != null and battle.board_view.tile_visual_scene == DUNGEON_TILE
		and battle.board_view.environment_visual_scene == DUNGEON_ENVIRONMENT,
		"production HeroHub route selects dungeon tile and environment scenes")
	if battle != null:
		battle.set_process(false)
		var tile := battle.board_view._terrain_visuals.get(Vector3i(ACID_CELL.x, ACID_CELL.y, 0)) as BattleTerrainVisual
		var overlay := battle.board_view._environment_visuals.get(ACID_CELL) as BattleManagedEnvironmentVisual
		var top: Polygon2D = tile.get_node(^"ArtRoot/GroundSurface/DungeonFloor") as Polygon2D if tile != null else null
		var pool: BattleAnimatedAcidPool = overlay.get_node(^"AcidPool") as BattleAnimatedAcidPool if overlay != null else null
		var sprite: AnimatedSprite2D = pool_sprite(pool) if pool != null else null
		check(tile != null and overlay != null and pool != null and overlay.acid_pool and pool.visible and sprite.is_playing(),
			"live C7 hazard displays typed acid animation overlay")
		check(top != null and top.is_visible_in_tree(), "live acid overlay preserves native dungeon diamond surface")
		var baseline := snapshot(battle.session as BattleCoreReactionsSession)
		if tile != null and overlay != null and sprite != null:
			sprite.speed_scale = 0.0
			sprite.set_frame_and_progress(17, 0.25)
			var held_frame := sprite.frame
			var held_progress := sprite.frame_progress
			var terrain_id := tile.get_instance_id() if tile != null else 0
			battle.board_view.refresh()
			await process_frame
			check(tile.get_instance_id() == terrain_id and overlay.get_node(^"AcidPool") == pool
				and sprite.frame == held_frame and is_equal_approx(sprite.frame_progress, held_progress),
				"live refresh preserves tile, pool, and animation sample")
			var detached: Dictionary = {"spikes": overlay.has_spikes, "burning": overlay.has_burning_fallback,
				"warning": overlay.is_warning, "corpses": overlay.corpse_records.duplicate(true), "acid": false,
				"floor_trap": overlay.floor_trap, "wall_direction": overlay.wall_trap_direction, "armed": overlay.trap_armed}
			overlay.apply_view(detached)
			check(not pool.visible and not sprite.is_playing() and top.is_visible_in_tree(),
				"detached acid removal reveals unchanged base surface")
			detached.acid = true
			overlay.apply_view(detached)
			check(pool.visible and sprite.is_playing() and sprite.frame == held_frame
				and is_equal_approx(sprite.frame_progress, held_progress), "detached acid re-add resumes existing animation")
			if not captures.is_empty():
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				check(image.save_png(captures.path_join("acid-live-current-room.png")) == OK,
					"live selected room with acid overlay captured")
			var cell_index := ACID_CELL.y * battle.board_view._view_width + ACID_CELL.x
			var terrain_before: int = battle.board_view._view_terrain[cell_index]
			battle.board_view._view_terrain[cell_index] = TerrainType.Type.VOID
			battle.board_view._rebuild_visuals()
			await process_frame
			check(not battle.board_view._environment_visuals.has(ACID_CELL), "detached VOID publication retires acid overlay")
			battle.board_view._view_terrain[cell_index] = terrain_before
			battle.board_view._rebuild_visuals()
			await process_frame
			var restored := battle.board_view._environment_visuals.get(ACID_CELL) as BattleManagedEnvironmentVisual
			var restored_pool: BattleAnimatedAcidPool = restored.get_node(^"AcidPool") as BattleAnimatedAcidPool if restored != null else null
			var restored_sprite: AnimatedSprite2D = pool_sprite(restored_pool) if restored_pool != null else null
			check(restored_pool != null and restored_pool.visible and restored_sprite.is_playing(),
				"restoring detached floor publication recreates active acid overlay")
			if restored_sprite != null:
				restored_sprite.speed_scale = 0.0
				restored_sprite.set_frame_and_progress(9, 0.5)
			for zoom: float in [0.9, 1.1]:
				battle.board_view.zoom_camera(zoom, battle.board_view.size * 0.5)
				await process_frame
				check(restored != null and restored.get_node(^"AcidPool") == restored_pool
					and restored_sprite != null and restored_sprite.frame == 9
					and is_equal_approx(restored_sprite.frame_progress, 0.5),
					"live zoom preserves restored acid overlay and frame progress")
			check(snapshot(battle.session as BattleCoreReactionsSession) == baseline,
				"refresh, acid removal/re-add, VOID, and zoom preserve battle snapshot, RNG, and counters")
		if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		if FileAccess.file_exists(save_path + ".bak"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".bak"))
		screen._clear_battle()
		screen.queue_free()
	viewport.queue_free()
	await process_frame

func run() -> void:
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	check_resource_contract()
	await check_pool_lifecycle()
	await check_biome_surfaces()
	await check_mask_render()
	await check_live_route()
	if not gpu_available: print("SKIP ACID GPU MASK: headless renderer")
	print("ACID TILE ANIMATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
