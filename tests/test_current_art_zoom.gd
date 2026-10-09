extends SceneTree

const CURRENT_BATTLE = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: HeroHubBattleView
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL CURRENT ART ZOOM: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	return {
		"state": result.snapshot.to_dict() if result.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(),
		"phase": session.phase,
	}

func capture(label: String) -> void:
	if captures.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

func _run() -> void:
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty() and bundle.has("session"), "current expedition factory creates battle session")
	if bundle.is_empty() or not bundle.has("session"):
		print("CURRENT ART ZOOM RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var session := bundle.session as BattleCoreReactionsSession
	_check_authored_seam_width()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = CURRENT_BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	viewport.add_child(demo)
	# Отключаем только фоновую логику экрана, чтобы кадры оставались стабильными.
	demo.set_process(false)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	check(demo.get_script() == HeroHubBattleView and demo.session == session, "current view keeps the supplied expedition session")
	check(demo.board_view.camera_controls_enabled, "current battle retains authored camera controls")
	check(demo.board_view.tile_visual_scene == TILE and demo.board_view.unit_visual_scene == UNIT, "current board loads trial tile and unit scenes")
	check(demo._heading.text == "intoDeDung · Отряд в бою" and demo._action_bar != null, "current expedition title and battle HUD are present")
	_check_warrior_art()
	var baseline := snapshot(session)
	var heading_rect := demo._heading.get_global_rect()
	var action_rect := demo._action_bar.get_global_rect()
	await _capture_zoom_set("1280x850", baseline, heading_rect, action_rect)
	await _capture_fractional_canvas_set("1280x850", baseline)
	_check_picking_roundtrip()
	viewport.size = Vector2i(1440, 1000)
	await process_frame
	await process_frame
	check(snapshot(session) == baseline, "window resize keeps current snapshot, RNG, counters and phase")
	heading_rect = demo._heading.get_global_rect()
	action_rect = demo._action_bar.get_global_rect()
	await _capture_zoom_set("1440x1000", baseline, heading_rect, action_rect)
	await _capture_fractional_canvas_set("1440x1000", baseline)
	_check_picking_roundtrip()
	if not captures.is_empty():
		var before_comparison: Dictionary = snapshot(session)
		check(await preload("res://tests/helpers/art_zoom_samples.gd").capture_comparison(self, captures), "sprite sampling comparison images")
		check(snapshot(session) == before_comparison, "separate sprite comparison render leaves current battle state unchanged")
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("CURRENT ART ZOOM RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _capture_zoom_set(size_label: String, baseline: Dictionary, heading_rect: Rect2, action_rect: Rect2) -> void:
	var board := demo.board_view
	board.reset_camera()
	await process_frame
	_check_seam_minimum_screen_width("100% " + size_label)
	await capture("current-100-" + size_label)
	_check_camera_preserves_state(baseline, heading_rect, action_rect, "100% " + size_label)
	board.zoom_camera(0.75, board.size * 0.5)
	await process_frame
	_check_seam_minimum_screen_width("75% " + size_label)
	await capture("current-75-" + size_label)
	await _capture_source_sampling(size_label)
	_check_camera_preserves_state(baseline, heading_rect, action_rect, "75% " + size_label)
	board.zoom_camera(1.25, board.size * 0.5)
	await process_frame
	_check_seam_minimum_screen_width("125% " + size_label)
	await capture("current-125-" + size_label)
	_check_camera_preserves_state(baseline, heading_rect, action_rect, "125% " + size_label)

func _capture_fractional_canvas_set(size_label: String, baseline: Dictionary) -> void:
	var old_canvas_transform: Transform2D = viewport.canvas_transform
	# Это дополнительное fractional canvas stretch; игровой масштаб камеры остаётся отдельным.
	var fractional_transform := Transform2D(Vector2(0.833, 0.0), Vector2(0.0, 0.917), Vector2(0.5, 0.25))
	var board := demo.board_view
	board.zoom_camera(0.75, board.size * 0.5)
	viewport.canvas_transform = fractional_transform
	await process_frame
	await process_frame
	_check_seam_minimum_screen_width("fractional canvas notification at 75% " + size_label, true)
	for zoom: float in [0.75, 1.0, 1.25]:
		board.zoom_camera(zoom, board.size * 0.5)
		await process_frame
		await process_frame
		var label := "%d%% fractional canvas %s" % [roundi(zoom * 100.0), size_label]
		_check_seam_minimum_screen_width(label, true)
		check(snapshot(demo.session as BattleCoreReactionsSession) == baseline, "fractional canvas transform preserves battle state " + label)
		await capture("current-fractional-canvas-%d-%s" % [roundi(zoom * 100.0), size_label])
	viewport.canvas_transform = old_canvas_transform
	await process_frame
	await process_frame
	board.reset_camera()
	check(snapshot(demo.session as BattleCoreReactionsSession) == baseline, "fractional canvas roundtrip preserves battle state " + size_label)
	await process_frame
	_check_seam_minimum_screen_width("restored canvas " + size_label)

func _check_camera_preserves_state(baseline: Dictionary, heading_rect: Rect2, action_rect: Rect2, label: String) -> void:
	check(snapshot(demo.session as BattleCoreReactionsSession) == baseline, "camera and refresh preserve snapshot/RNG/counters " + label)
	check(demo._heading.get_global_rect() == heading_rect and demo._action_bar.get_global_rect() == action_rect, "camera leaves title and action HUD scale unchanged " + label)
	demo._refresh()
	check(snapshot(demo.session as BattleCoreReactionsSession) == baseline, "current refresh preserves snapshot/RNG/counters " + label)
	check(demo._heading.get_global_rect() == heading_rect and demo._action_bar.get_global_rect() == action_rect, "refresh leaves title and action HUD geometry unchanged " + label)

func _check_seam_minimum_screen_width(label: String, expect_fractional_transform: bool = false) -> void:
	var seam_count: int = 0
	var minimum_screen_width: float = INF
	var minimum_transform_scale: float = INF
	for tile: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if tile.role not in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM] or tile.is_void:
			continue
		var seam := tile.get_node_or_null("ArtRoot/GroundSurface/QuietSeam") as Line2D
		if seam == null or not seam.is_visible_in_tree():
			continue
		seam_count += 1
		var screen_transform: Transform2D = seam.get_screen_transform()
		var scale_factor: float = minf(screen_transform.x.length(), screen_transform.y.length())
		minimum_screen_width = minf(minimum_screen_width, seam.width * scale_factor)
		minimum_transform_scale = minf(minimum_transform_scale, scale_factor)
	var diagnostic := " count=%d min_width=%.3f min_scale=%.3f" % [seam_count, minimum_screen_width, minimum_transform_scale]
	check(seam_count > 0 and minimum_screen_width >= 1.15 - 0.01, "QuietSeam stays at least 1.15 screen pixels using get_screen_transform " + label + diagnostic)
	if expect_fractional_transform:
		check(seam_count > 0 and not is_equal_approx(minimum_transform_scale, roundf(minimum_transform_scale)), "screen transform includes fractional canvas scale " + label + diagnostic)

func _check_authored_seam_width() -> void:
	var tile := TILE.instantiate()
	var seam := tile.get_node_or_null("ArtRoot/GroundSurface/QuietSeam") as Line2D
	check(seam != null and is_equal_approx(seam.width, 0.7), "QuietSeam keeps its authored 0.7 canvas-pixel width")
	tile.free()

func _capture_source_sampling(size_label: String) -> void:
	var saved_materials: Array[Dictionary] = []
	var before_state: Dictionary = snapshot(demo.session as BattleCoreReactionsSession)
	# Парный кадр отделяет действие временного фильтра от исходной PNG.
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		for sprite_path: NodePath in [NodePath("ArtRoot/PlayerWarriorSprite"), NodePath("ArtRoot/EnemyWarriorSprite")]:
			var sprite := visual.get_node_or_null(sprite_path) as Sprite2D
			if sprite == null or not sprite.visible or sprite.material == null:
				continue
			saved_materials.append({
				"sprite": sprite,
				"material": sprite.material,
				"visible": sprite.visible,
				"modulate": sprite.modulate,
				"self_modulate": sprite.self_modulate,
			})
			sprite.material = null
	check(not saved_materials.is_empty(), "visible warrior sprites expose the current comparison material")
	await capture("current-75-source-sampling-" + size_label)
	for saved: Dictionary in saved_materials:
		var sprite := saved.sprite as Sprite2D
		if is_instance_valid(sprite):
			sprite.material = saved.material as Material
			check(sprite.visible == bool(saved.visible) and sprite.modulate == saved.modulate and sprite.self_modulate == saved.self_modulate, "source-sampling pair restores visible sprite modulation")
			check(sprite.material == saved.material, "source-sampling pair restores original sprite material")
	check(snapshot(demo.session as BattleCoreReactionsSession) == before_state, "source-sampling pair preserves battle snapshot, RNG, counters, revision and phase")

func _check_warrior_art() -> void:
	var player_count: int = 0
	var enemy_count: int = 0
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if visual.unit == null or visual.visual_class_id != &"warrior":
			continue
		if visual.unit.faction == Faction.Type.PLAYER:
			player_count += 1
			var player_sprite := visual.get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
			var player_atlas: AtlasTexture = player_sprite.texture as AtlasTexture if player_sprite != null else null
			check(player_sprite != null and player_sprite.visible and player_atlas != null and player_atlas.atlas.resource_path.ends_with("defender_new.png"), "current party warrior uses the assigned player artwork")
		elif visual.unit.faction == Faction.Type.ENEMY:
			enemy_count += 1
			var enemy_sprite := visual.get_node_or_null("ArtRoot/EnemyWarriorSprite") as Sprite2D
			check(enemy_sprite != null and enemy_sprite.visible and enemy_sprite.flip_h and enemy_sprite.texture.resource_path.ends_with("defender_reference_v1.png"), "current enemy warrior keeps its faction artwork and mirror")
	check(player_count > 0 and enemy_count > 0, "current encounter contains both warrior artwork factions")

func _check_picking_roundtrip() -> void:
	var board := demo.board_view
	var actor: UnitState
	for unit: UnitState in demo.session.units:
		if unit.faction == Faction.Type.PLAYER and unit.is_alive():
			actor = unit
			break
	if actor == null:
		check(false, "current party has a live unit for picking")
		return
	var cell: Vector2i = actor.cell
	check(board.cell_at(board.cell_center(cell)) == cell, "current cell picking works at camera reset")
	var offset: Vector2 = board._world_cell_center(cell) + Vector2(0, -12)
	check(board.displayed_unit_at(board.world_to_view(offset)) == actor.id, "current unit picking works at camera reset")
	board.zoom_camera(0.75, board.size * 0.5)
	board.pan_camera(Vector2(13.5, -7.25))
	check(board.cell_at(board.cell_center(cell)) == cell, "cell picking follows fractional pan and zoom")
	check(board.displayed_unit_at(board.world_to_view(offset)) == actor.id, "unit picking follows fractional pan and zoom")
	board.reset_camera()
	check(board.cell_at(board.cell_center(cell)) == cell and board.displayed_unit_at(board.world_to_view(offset)) == actor.id, "cell and unit picking roundtrip after camera reset")
