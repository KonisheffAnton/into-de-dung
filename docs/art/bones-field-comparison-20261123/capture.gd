extends SceneTree

## Показывает два исходных PNG рядом с живым бойцом, не меняя состояние боя.
const BOARD_SCENE: PackedScene = preload("res://scenes/demo/battle/battle_board.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const ENV_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const VIEW_SIZE: Vector2i = Vector2i(1280, 720)

var output_dir: String = ""
var pl29_path: String = ""
var pl34_path: String = ""
var viewport: SubViewport
var board: BattleDemoBoard
var session: BattleCoreReactionsSession
var failed: Array[String] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): output_dir = arg.trim_prefix("--captures=")
		elif arg.begins_with("--pl29="): pl29_path = arg.trim_prefix("--pl29=")
		elif arg.begins_with("--pl34="): pl34_path = arg.trim_prefix("--pl34=")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failed.append(label)
		printerr("FAIL BONES FIELD CAPTURE: " + label)


func _snapshot() -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision()}


func _occupied_cells() -> Dictionary:
	var occupied: Dictionary = {}
	for unit: UnitState in session.units:
		if unit.is_alive(): occupied[unit.cell] = true
	var env: CombatEnvironmentState = session.state.environment
	if env != null:
		for fire: Dictionary in env.fires: occupied[fire.get("cell", Vector2i(-1, -1))] = true
		for acid: Vector2i in env.hazards.get("acid", []): occupied[acid] = true
		for trap: Dictionary in env.hazards.get("traps", []): occupied[trap.get("cell", Vector2i(-1, -1))] = true
		for corpse: Dictionary in env.corpses: occupied[corpse.get("cell", Vector2i(-1, -1))] = true
	return occupied


func _find_floor(cell: Vector2i) -> BattleDemoIsoVisual:
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.FLOOR and visual.grid_anchor == cell: return visual
	return null


func _add_bone(cell: Vector2i, path: String, label: String) -> Dictionary:
	var floor_visual := _find_floor(cell)
	if floor_visual == null:
		_check(false, label + " floor visual missing")
		return {}
	var image: Image = Image.load_from_file(path)
	_check(image != null, label + " PNG loaded")
	if image == null: return {}
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = floor_visual.get_visual_offset() + Vector2(0.0, 0.5)
	floor_visual.add_child(sprite)
	_check(image.get_size() == Vector2i(64, 64), label + " texture is 64x64")
	_check(sprite.scale == Vector2.ONE, label + " canvas scale is one")
	var alpha_bounds := image.get_used_rect()
	var expected_alpha := Rect2i(2, 22, 60, 26) if label == "PL29" else Rect2i(2, 22, 60, 31)
	_check(alpha_bounds == expected_alpha, label + " alpha bounds match approved source")
	var canvas_transform := sprite.get_global_transform_with_canvas()
	var screen_position := canvas_transform.origin
	var canvas_scale := canvas_transform.get_scale()
	_check(canvas_scale.is_equal_approx(Vector2.ONE), label + " canvas transform scale is one")
	return {"label": label, "path": path, "cell": [cell.x, cell.y],
		"screen_position": [screen_position.x, screen_position.y],
		"texture_size": [image.get_width(), image.get_height()],
		"alpha_rect": [alpha_bounds.position.x, alpha_bounds.position.y, alpha_bounds.size.x, alpha_bounds.size.y],
		"local_scale": [sprite.scale.x, sprite.scale.y],
		"canvas_scale": [canvas_scale.x, canvas_scale.y], "source_alpha_unchanged": true}


func _safe_floor_cell(cell: Vector2i, occupied: Dictionary) -> bool:
	if occupied.has(cell) or session.state.get_board().get_terrain(cell) != TerrainType.Type.FLOOR: return false
	var floor_found := false
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.grid_anchor != cell: continue
		if visual.role == BattleDemoIsoVisual.Role.FLOOR: floor_found = true
		elif visual.role in [BattleDemoIsoVisual.Role.PLATFORM, BattleDemoIsoVisual.Role.WALL]: return false
	return floor_found


func _run() -> void:
	if output_dir.is_empty() or pl29_path.is_empty() or pl34_path.is_empty() or DisplayServer.get_name() == "headless":
		printerr("GPU renderer required: -- --captures=<absolute folder> --pl29=<absolute PNG> --pl34=<absolute PNG>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var profile := HeroHubState.create(73191, 4)
	_check(profile.start_battle(), "profile starts isolated battle")
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty():
		quit(1)
		return
	session = bundle.session as BattleCoreReactionsSession
	var warrior: UnitState
	for unit: UnitState in session.units:
		if unit.is_alive() and unit.faction == Faction.Type.PLAYER \
				and session.unit_visual_classes.get(unit.id, &"") == &"fighter":
			warrior = unit
			break
	_check(warrior != null, "live PLAYER fighter found")
	if warrior == null:
		session.close()
		quit(1)
		return
	var before := _snapshot()
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BOARD_SCENE.instantiate() as BattleDemoBoard
	board.size = Vector2(VIEW_SIZE)
	board.session = session
	board.camera_controls_enabled = true
	board.unit_visual_scene = UNIT_SCENE
	board.tile_visual_scene = TILE_SCENE
	board.environment_visual_scene = ENV_SCENE
	viewport.add_child(board)
	board.refresh()
	board.get_node("CameraControls").hide()
	await process_frame
	await process_frame
	board.zoom_camera(1.0, board.size * 0.5)
	_check(board.grid_config.tile_size == Vector2(128, 64), "tile size is 128x64")
	_check(board.shallow_projection, "shallow projection is enabled")
	_check(is_equal_approx(board.camera_view.zoom, 1.0), "camera zoom is 1.0")
	var warrior_visual: BattleDemoIsoVisual
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT and visual.unit != null and visual.unit.id == warrior.id:
			warrior_visual = visual
	_check(warrior_visual != null and warrior_visual.visual_class_id == &"fighter", "fighter visual matches unit")
	if warrior_visual == null:
		viewport.queue_free(); session.close(); quit(1); return
	board.set_presentation_animation_events([{"actor_unit_id": warrior.id}])
	var occupied := _occupied_cells()
	var candidates: Array[Vector2i] = []
	for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell := warrior.cell + delta
		var floor_visual := _find_floor(cell)
		if _safe_floor_cell(cell, occupied) and floor_visual != null and not floor_visual.is_void and not floor_visual.burning:
			candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	if candidates.size() < 2:
		var nearby: Array[Vector2i] = []
		for visual: BattleDemoIsoVisual in board._entity_visuals:
			var cell := visual.grid_anchor
			if visual.role == BattleDemoIsoVisual.Role.FLOOR and not visual.is_void and not visual.burning and _safe_floor_cell(cell, occupied): nearby.append(cell)
		nearby.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := absi(a.x - warrior.cell.x) + absi(a.y - warrior.cell.y)
			var db := absi(b.x - warrior.cell.x) + absi(b.y - warrior.cell.y)
			return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
		for cell: Vector2i in nearby:
			if not candidates.has(cell): candidates.append(cell)
			if candidates.size() == 2: break
	_check(candidates.size() >= 2, "two empty safe floor cells found")
	if candidates.size() < 2:
		viewport.queue_free(); session.close(); quit(1); return
	# Перемещаем только камеру: центральная опора группы остаётся видимой при масштабе 100%.
	board.pan_camera(Vector2(VIEW_SIZE) * 0.5 - board.cell_center(warrior.cell))
	var bone29 := _add_bone(candidates[0], pl29_path, "PL29")
	var bone34 := _add_bone(candidates[1], pl34_path, "PL34")
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Подписи сравнения должны лежать над слоями поля с собственным z-порядком.
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 1
	viewport.add_child(overlay_layer)
	overlay_layer.add_child(overlay)
	var title := Label.new()
	title.text = "PL29 / PL34 · 100% · кости 64×64"
	title.position = Vector2(20, 16)
	title.add_theme_color_override("font_color", Color("d8d0b9"))
	overlay.add_child(title)
	for record: Dictionary in [bone29, bone34]:
		if record.is_empty(): continue
		var label := Label.new()
		label.text = record.label
		label.position = Vector2(record.screen_position[0] - 20.0, record.screen_position[1] + 38.0)
		label.add_theme_color_override("font_color", Color("d8d0b9"))
		label.add_theme_color_override("font_outline_color", Color("171b24"))
		label.add_theme_constant_override("outline_size", 3)
		overlay.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var unchanged := _snapshot() == before
	_check(unchanged, "state, RNG, counters, revision unchanged")
	_check(is_equal_approx(board.camera_view.zoom, 1.0), "camera remains at zoom 1.0")
	var save_error := viewport.get_texture().get_image().save_png(output_dir.path_join("field-100.png"))
	_check(save_error == OK, "full-size viewport PNG saved")
	var skin_visual := warrior_visual as BattleCharacterSkinVisual
	var fighter_skin: CharacterSkinDefinition = skin_visual.skin_definition if skin_visual != null else null
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "capture": output_dir.path_join("field-100.png"),
		"viewport": [VIEW_SIZE.x, VIEW_SIZE.y], "tile_size": [board.grid_config.tile_size.x, board.grid_config.tile_size.y],
		"shallow_projection": board.shallow_projection, "camera_zoom": board.camera_view.zoom,
		"warrior": {"id": warrior.id, "class": String(warrior_visual.visual_class_id),
			"skin": String(fighter_skin.id) if fighter_skin != null else "", "art_scale": warrior_visual.get_unit_art_scale(),
			"cell": [warrior.cell.x, warrior.cell.y]},
		"bones": [bone29, bone34], "snapshot_unchanged": unchanged, "failed_checks": failed}
	var file := FileAccess.open(output_dir.path_join("capture.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t")); file.close()
	else:
		_check(false, "capture.json written")
	board.queue_free()
	viewport.queue_free()
	session.close()
	await process_frame
	print("BONES FIELD CAPTURE: %d failed checks" % failed.size())
	quit(1 if not failed.is_empty() else 0)
