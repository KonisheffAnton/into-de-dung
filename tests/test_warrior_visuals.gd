extends SceneTree

const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var passed := 0
var failed := 0
var captures := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL WARRIOR VISUALS: " + label)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 500)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1200, 500)
	background.color = Color("141c2b")
	viewport.add_child(background)
	var biomes := ["forest", "swamp", "desert", "ice", "volcanic", "ice"]
	for row: int in 2:
		for column: int in 6:
			var origin := Vector2(100 + column * 200, 180 + row * 220)
			var floor_sprite := Polygon2D.new()
			floor_sprite.texture = load("res://assets/art_presets/trials/biomes_v1/" + biomes[column] + "/floor.png")
			floor_sprite.polygon = PackedVector2Array([Vector2(-64, 0), Vector2(0, -48), Vector2(64, 0), Vector2(0, 48)])
			floor_sprite.uv = PackedVector2Array([Vector2(0, 48), Vector2(64, 0), Vector2(128, 48), Vector2(64, 96)])
			floor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			floor_sprite.position = origin
			viewport.add_child(floor_sprite)
			var visual := UNIT.instantiate() as BattleDefenderIdleVisual
			visual.role = BattleDemoIsoVisual.Role.UNIT
			visual.unit = BattleUnitView.new()
			visual.unit.id = 10 + row * 6 + column
			visual.unit.faction = Faction.Type.ENEMY if column == 5 else Faction.Type.PLAYER
			visual.unit.alive = true
			visual.visual_class_id = &"shieldbearer" if row == 0 else &"fighter"
			visual.grid_config = IsoGridConfig.new()
			visual.grid_config.tile_size = Vector2(128, 96)
			visual.position = origin
			viewport.add_child(visual)
			visual.sync_scene_art()
			visual.position = origin
			var sprite := visual.class_still_sprite()
			check(sprite != null and sprite.visible and sprite.texture.resource_path.ends_with("shieldbearer-17.png" if row == 0 else "fighter-11.png"), "selected model visible")
			check(not visual.can_play_buff() and not visual.can_play_death() and not visual._can_play_idle(), "old clips cannot replace selected model")
			var authored := sprite.transform
			visual.presentation_facing_x = -1
			visual.sync_scene_art()
			visual.presentation_facing_x = 1
			visual.sync_scene_art()
			visual.presentation_facing_x = 0
			check(sprite.transform.is_equal_approx(authored), "facing restores transform")
			var label := Label.new()
			label.position = origin + Vector2(-85, 60)
			label.text = ("17 Щитоносец" if row == 0 else "11 Воин") + " · " + biomes[column]
			viewport.add_child(label)
	await process_frame
	await process_frame
	if not captures.is_empty():
		check(viewport.get_texture().get_image().save_png(captures.path_join("models-on-tiles.png")) == OK, "save native-scale comparison")
	if DisplayServer.get_name() != "headless": await _no_outline_probe()
	viewport.queue_free()
	await process_frame
	print("WARRIOR VISUALS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _no_outline_probe() -> void:
	var probe := SubViewport.new()
	probe.size = Vector2i(400, 180)
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(probe)
	for column: int in 2:
		var background := ColorRect.new()
		background.position = Vector2(column * 200, 0)
		background.size = Vector2(200, 180)
		background.color = Color.WHITE if column == 0 else Color.BLACK
		probe.add_child(background)
		var visual := UNIT.instantiate() as BattleDefenderIdleVisual
		visual.role = BattleDemoIsoVisual.Role.UNIT
		visual.unit = BattleUnitView.new()
		visual.unit.id = 100 + column
		visual.unit.faction = Faction.Type.PLAYER
		visual.unit.alive = true
		visual.visual_class_id = &"fighter"
		visual.grid_config = IsoGridConfig.new()
		visual.grid_config.tile_size = Vector2(128, 96)
		probe.add_child(visual)
		visual.sync_scene_art()
		visual.position = Vector2(100 + column * 200, 120)
		check((visual.class_still_sprite().material as ShaderMaterial).shader.resource_path.ends_with("pixel_zoom_v1/native_sprite.gdshader"), "shared native shader has no outline")
	await process_frame
	await process_frame
	var pixels := probe.get_texture().get_image()
	var inverted := 0
	for y: int in range(55, 120):
		for x: int in range(55, 145):
			var light := pixels.get_pixel(x, y)
			var dark := pixels.get_pixel(x + 200, y)
			if light.get_luminance() < 0.4 and dark.get_luminance() > 0.5: inverted += 1
	check(inverted == 0, "no adaptive outline on light or dark background")
	if not captures.is_empty(): pixels.save_png(captures.path_join("no-outline-dark-light.png"))
	probe.queue_free()
	await process_frame
