extends SceneTree

## Сопоставляет двадцать исходных рисунков на настоящих пустых клетках поля.
const BOARD_SCENE: PackedScene = preload("res://scenes/demo/battle/battle_board.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const ENV_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const VIEW_SIZE: Vector2i = Vector2i(1440, 1100)
const VARIANT_COUNT: int = 20

var output_dir: String = ""
var variants_path: String = ""
var viewport: SubViewport
var board: BattleDemoBoard
var session: BattleCoreReactionsSession
var failed: Array[String] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): output_dir = arg.trim_prefix("--captures=")
		elif arg.begins_with("--variants="): variants_path = arg.trim_prefix("--variants=")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failed.append(label)
		printerr("FAIL BONES ALL CAPTURE: " + label)


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


func _safe_floor_cell(cell: Vector2i, occupied: Dictionary) -> bool:
	if occupied.has(cell) or session.state.get_board().get_terrain(cell) != TerrainType.Type.FLOOR: return false
	var floor_found := false
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.grid_anchor != cell: continue
		if visual.role == BattleDemoIsoVisual.Role.FLOOR: floor_found = true
		elif visual.role in [BattleDemoIsoVisual.Role.PLATFORM, BattleDemoIsoVisual.Role.WALL]: return false
	return floor_found


func _away_from_units(cell: Vector2i) -> bool:
	for unit: UnitState in session.units:
		if unit.is_alive() and absi(cell.x - unit.cell.x) + absi(cell.y - unit.cell.y) <= 1: return false
	return true


func _as_int_vector(values: Array, label: String) -> Vector2i:
	if values.size() != 2:
		_check(false, label + " requires two integer values")
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _variant_sprite(entry: Dictionary, cell: Vector2i) -> Dictionary:
	var variant_id: String = String(entry.get("id", ""))
	var path: String = String(entry.get("path", ""))
	var floor_visual := _find_floor(cell)
	if floor_visual == null:
		_check(false, variant_id + " floor visual missing")
		return {}
	var image: Image = Image.load_from_file(path)
	_check(image != null, variant_id + " source PNG loaded")
	if image == null: return {}
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var region_value: Variant = entry.get("region", null)
	var is_pl: bool = variant_id.begins_with("PL")
	var display_size := _as_int_vector(entry.get("display_size", []), variant_id + " display_size")
	var region := Rect2i()
	if is_pl:
		_check(region_value == null, variant_id + " PL source region is null")
		_check(image.get_size() == Vector2i(64, 64), variant_id + " PL source is 64x64")
		sprite.position = floor_visual.get_visual_offset() + Vector2(0.0, 0.5)
	else:
		_check(region_value is Array and (region_value as Array).size() == 4, variant_id + " region has four values")
		if not (region_value is Array) or (region_value as Array).size() != 4: return {}
		var rect_values: Array = region_value
		region = Rect2i(int(rect_values[0]), int(rect_values[1]), int(rect_values[2]), int(rect_values[3]))
		sprite.region_enabled = true
		sprite.region_rect = Rect2(region)
		sprite.position = floor_visual.get_visual_offset() + Vector2(0.0, 4.0)
		_check(display_size.x <= 60 and display_size.y <= 32, variant_id + " display fits 60x32")
		_check(region.size.x > 0 and region.size.y > 0, variant_id + " alpha region is nonempty")
		_check(display_size.x <= region.size.x and display_size.y <= region.size.y,
			variant_id + " variant display does not enlarge source")
		if region.size.x > 0 and region.size.y > 0:
			sprite.scale = Vector2(float(display_size.x) / float(region.size.x), float(display_size.y) / float(region.size.y))
	floor_visual.add_child(sprite)
	var transform := sprite.get_global_transform_with_canvas()
	var origin := transform.origin
	var canvas_scale := transform.get_scale()
	if is_pl: _check(canvas_scale.is_equal_approx(Vector2.ONE), variant_id + " PL canvas scale is one")
	# Transform уже содержит уменьшение G: границы берём в исходных координатах.
	var local_size := Vector2(image.get_size()) if is_pl else Vector2(region.size)
	var half := local_size * 0.5
	var corners: Array[Vector2] = [transform * Vector2(-half.x, -half.y), transform * Vector2(half.x, -half.y),
		transform * Vector2(half.x, half.y), transform * Vector2(-half.x, half.y)]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners: bounds = bounds.expand(corner)
	_check(bounds.position.x >= 0.0 and bounds.position.y >= 0.0
		and bounds.end.x <= VIEW_SIZE.x and bounds.end.y <= VIEW_SIZE.y, variant_id + " sprite bounds inside viewport")
	if is_pl: _check(sprite.scale == Vector2.ONE, variant_id + " PL local scale is one")
	var label := Label.new()
	label.text = variant_id
	label.add_theme_font_size_override("font_size", 12)
	label.position = origin + Vector2(-24.0, half.y + 2.0)
	label.add_theme_color_override("font_color", Color("d8d0b9"))
	label.add_theme_color_override("font_outline_color", Color("171b24"))
	label.add_theme_constant_override("outline_size", 3)
	return {"id": variant_id, "path": path, "cell": [cell.x, cell.y], "canvas_origin": [origin.x, origin.y],
		"local_scale": [sprite.scale.x, sprite.scale.y], "canvas_scale": [canvas_scale.x, canvas_scale.y],
		"region": [region.position.x, region.position.y, region.size.x, region.size.y] if not is_pl else null,
		"display_size": [display_size.x, display_size.y], "source_size": [image.get_width(), image.get_height()],
		"viewport_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"source_alpha_unchanged": true, "label_node": label, "sprite_bounds": bounds,
		"label_offset_y": (float(image.get_used_rect().end.y) - 32.0 if is_pl else float(display_size.y) * 0.5) + 3.0}


func _place_label(label: Label, sprite_bounds: Rect2, sprite_bounds_all: Array[Rect2], placed_labels: Array[Rect2]) -> Rect2:
	var gap := 3.0
	var candidates: Array[Vector2] = [
		Vector2(sprite_bounds.get_center().x - label.size.x * 0.5, sprite_bounds.end.y + gap),
		Vector2(sprite_bounds.get_center().x - label.size.x * 0.5, sprite_bounds.position.y - label.size.y - gap),
		Vector2(sprite_bounds.position.x - label.size.x - gap, sprite_bounds.get_center().y - label.size.y * 0.5),
		Vector2(sprite_bounds.end.x + gap, sprite_bounds.get_center().y - label.size.y * 0.5),
	]
	for position: Vector2 in candidates:
		var bounds := Rect2(position, label.size)
		if bounds.position.x < 0.0 or bounds.position.y < 0.0 or bounds.end.x > VIEW_SIZE.x or bounds.end.y > VIEW_SIZE.y:
			continue
		var intersects := false
		for sprite_bound: Rect2 in sprite_bounds_all:
			if bounds.intersects(sprite_bound): intersects = true; break
		if intersects: continue
		for label_bound: Rect2 in placed_labels:
			if bounds.intersects(label_bound): intersects = true; break
		if intersects: continue
		label.position = position
		return bounds
	return Rect2()


func _read_variants() -> Array[Dictionary]:
	var file := FileAccess.open(variants_path, FileAccess.READ)
	if file == null:
		_check(false, "variants JSON opens")
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(parsed is Array, "variants JSON is an array")
	if not (parsed is Array): return []
	var result: Array[Dictionary] = []
	for value: Variant in parsed:
		if value is Dictionary: result.append(value)
		else: _check(false, "each variant entry is an object")
	_check(result.size() == VARIANT_COUNT, "exactly 20 variants supplied")
	return result


func _run() -> void:
	if output_dir.is_empty() or variants_path.is_empty() or DisplayServer.get_name() == "headless":
		printerr("GPU renderer required: -- --captures=<absolute folder> --variants=<absolute JSON>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var variants := _read_variants()
	var profile := HeroHubState.create(73191, 4)
	_check(profile.start_battle(), "profile starts isolated battle")
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty(): quit(1); return
	session = bundle.session as BattleCoreReactionsSession
	var warrior: UnitState
	for unit: UnitState in session.units:
		if unit.is_alive() and unit.faction == Faction.Type.PLAYER \
				and session.unit_visual_classes.get(unit.id, &"") == &"fighter": warrior = unit; break
	_check(warrior != null, "live PLAYER fighter found")
	if warrior == null: session.close(); quit(1); return
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
	_check(board._view_width == 8 and board._view_height == 8, "factory battle field is 8x8")
	var warrior_visual: BattleDemoIsoVisual
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT and visual.unit != null and visual.unit.id == warrior.id:
			warrior_visual = visual
	_check(warrior_visual != null and warrior_visual.visual_class_id == &"fighter", "fighter visual matches unit")
	if warrior_visual == null: viewport.queue_free(); session.close(); quit(1); return
	var skin_visual := warrior_visual as BattleCharacterSkinVisual
	_check(skin_visual != null and skin_visual.skin_definition != null and skin_visual.skin_definition.id == &"red_bastion",
		"fighter uses red_bastion skin")
	board.set_presentation_animation_events([{"actor_unit_id": warrior.id}])
	var occupied := _occupied_cells()
	var safe_cells: Array[Vector2i] = []
	for y: int in board._view_height:
		for x: int in board._view_width:
			var cell := Vector2i(x, y)
			var visual := _find_floor(cell)
			if _safe_floor_cell(cell, occupied) and _away_from_units(cell) and visual != null and not visual.is_void and not visual.burning:
				safe_cells.append(cell)
	# Удалённые от живых юнитов клетки снижают риск наложения с фигурами и полосами здоровья.
	safe_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance := 1000
		var b_distance := 1000
		for unit: UnitState in session.units:
			if unit.is_alive():
				a_distance = mini(a_distance, absi(a.x - unit.cell.x) + absi(a.y - unit.cell.y))
				b_distance = mini(b_distance, absi(b.x - unit.cell.x) + absi(b.y - unit.cell.y))
		if a_distance != b_distance: return a_distance > b_distance
		return a.y > b.y if a.y != b.y else a.x < b.x)
	_check(safe_cells.size() >= VARIANT_COUNT, "20 safe empty floor cells available")
	if safe_cells.size() < VARIANT_COUNT: viewport.queue_free(); session.close(); quit(1); return
	var cells: Array[Vector2i] = safe_cells.slice(0, VARIANT_COUNT)
	var unique_cells: Dictionary = {}
	for cell: Vector2i in cells: unique_cells[cell] = true
	_check(unique_cells.size() == VARIANT_COUNT, "20 cells are unique")
	var grid_center := Vector2i(board._view_width / 2, board._view_height / 2)
	board.pan_camera(Vector2(VIEW_SIZE) * 0.5 - board.cell_center(grid_center))
	var layer := CanvasLayer.new()
	layer.layer = 1
	viewport.add_child(layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var title := Label.new()
	title.text = "G31–G40 / PL39–PL48 · камера 100% · PL 64×64 · G уменьшены для примерки"
	title.position = Vector2(24, 18)
	title.add_theme_color_override("font_color", Color("d8d0b9"))
	title.add_theme_color_override("font_outline_color", Color("171b24"))
	title.add_theme_constant_override("outline_size", 3)
	overlay.add_child(title)
	var records: Array[Dictionary] = []
	var labels: Array[Label] = []
	var sprite_bounds_all: Array[Rect2] = []
	var unique_ids: Dictionary = {}
	for index: int in mini(variants.size(), VARIANT_COUNT):
		var entry: Dictionary = variants[index]
		var expected_prefix: String = "G" if index < 10 else "PL"
		var variant_id := String(entry.get("id", ""))
		var expected_id := "G%d" % (31 + index) if index < 10 else "PL%d" % (39 + index - 10)
		_check(variant_id == expected_id and variant_id.begins_with(expected_prefix), "variant row %d is %s" % [index, expected_id])
		_check(not unique_ids.has(variant_id) and not variant_id.is_empty(), variant_id + " unique nonempty id")
		unique_ids[variant_id] = true
		var record := _variant_sprite(entry, cells[index])
		if record.is_empty(): continue
		var label := record.label_node as Label
		overlay.add_child(label)
		labels.append(label)
		sprite_bounds_all.append(record.sprite_bounds)
		record.erase("label_node")
		record.erase("sprite_bounds")
		record["region"] = entry.get("region", null)
		record["display_size"] = entry.get("display_size", [])
		records.append(record)
	await process_frame
	var placed_labels: Array[Rect2] = []
	for index: int in labels.size():
		var bounds := _place_label(labels[index], sprite_bounds_all[index], sprite_bounds_all, placed_labels)
		_check(not bounds.size.is_zero_approx(), String(records[index].id) + " label fits without overlap or clipping")
		if not bounds.size.is_zero_approx(): placed_labels.append(bounds)
	await RenderingServer.frame_post_draw
	var unchanged := _snapshot() == before
	_check(unchanged, "state, RNG, counters and revision unchanged")
	_check(is_equal_approx(board.camera_view.zoom, 1.0), "camera remains at zoom 1.0")
	_check(records.size() == VARIANT_COUNT, "all 20 variants were rendered")
	var save_error := viewport.get_texture().get_image().save_png(output_dir.path_join("field-all-100.png"))
	_check(save_error == OK, "full-size viewport PNG saved")
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "capture": output_dir.path_join("field-all-100.png"),
		"variants_json": variants_path, "viewport": [VIEW_SIZE.x, VIEW_SIZE.y],
		"field_size": [board._view_width, board._view_height], "tile_size": [board.grid_config.tile_size.x, board.grid_config.tile_size.y],
		"shallow_projection": board.shallow_projection, "camera_zoom": board.camera_view.zoom,
		"warrior": {"id": warrior.id, "class": String(warrior_visual.visual_class_id),
			"skin": String(skin_visual.skin_definition.id) if skin_visual != null and skin_visual.skin_definition != null else "",
			"art_scale": warrior_visual.get_unit_art_scale(), "cell": [warrior.cell.x, warrior.cell.y]},
		"variants": records, "safe_cells_count": safe_cells.size(), "selected_cells_unique": unique_cells.size(),
		"snapshot_unchanged": unchanged, "failed_checks": failed}
	var report_file := FileAccess.open(output_dir.path_join("capture-all.json"), FileAccess.WRITE)
	if report_file != null: report_file.store_string(JSON.stringify(report, "\t")); report_file.close()
	else: _check(false, "capture-all.json written")
	board.queue_free()
	viewport.queue_free()
	session.close()
	await process_frame
	print("BONES ALL CAPTURE: %d variants, %d failed checks" % [records.size(), failed.size()])
	quit(1 if not failed.is_empty() else 0)
