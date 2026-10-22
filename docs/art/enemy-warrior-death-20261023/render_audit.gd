extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
var output: String = ""
var passed: int = 0
var failed: int = 0
var max_transform_delta: float = 0.0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ENEMY DEATH ART: " + label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var view := SubViewport.new()
	view.size = Vector2i(640, 640)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(512, 384)
	config.origin_offset = Vector2(320, 256)
	var tile := TILE.instantiate() as BattleTerrainVisual
	view.add_child(tile)
	tile.apply_view({"cell": Vector2i.ZERO, "role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}, config)
	var unit := UNIT.instantiate() as BattleDefenderIdleVisual
	unit.role = BattleDemoIsoVisual.Role.UNIT
	view.add_child(unit)
	var statuses: Array[Dictionary] = []
	unit.apply_view({"cell": Vector2i.ZERO, "half_steps": 0,
		"unit": {"id": 72, "faction": int(Faction.Type.ENEMY), "name": "", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": &"warrior", "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}, config)
	unit.set_process(false)
	var sprite := unit.get_node("ArtRoot/EnemyWarriorIdleSprite") as Sprite2D
	var still := unit.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
	var hud := unit.get_node("StatusHud") as Node2D
	var shadow := unit.get_node("GroundShadow") as Node2D
	var art := unit.get_node("ArtRoot") as Node2D
	var top := tile.top_polygon()
	var center := tile.to_global((top[0] + top[2]) * 0.5)
	var transforms := [unit.transform, shadow.transform, hud.transform, art.transform]
	check(unit.can_play_death() and is_equal_approx(unit.death_duration(), 2.55), "selected clip available")
	for frame: int in 17:
		unit.sample_death((float(frame) + 0.5) / 17.0)
		unit.sync_scene_art()
		hud.hide()
		check(sprite.texture == unit.enemy_warrior_death_frames.get_frame_texture(&"death", frame), "ordered frame " + str(frame))
		check(sprite.visible and not still.visible and sprite.scale == Vector2(-1, 1), "mirrored death layer " + str(frame))
		check(sprite.to_global(Vector2(71, 83)).is_equal_approx(center), "fixed tile anchor " + str(frame))
		var current := [unit.transform, shadow.transform, hud.transform, art.transform]
		var same_transforms := true
		for index: int in 4:
			var previous: Transform2D = transforms[index]
			var actual: Transform2D = current[index]
			max_transform_delta = maxf(max_transform_delta, maxf(actual.x.distance_to(previous.x),
				maxf(actual.y.distance_to(previous.y), actual.origin.distance_to(previous.origin))))
			same_transforms = same_transforms and actual.is_equal_approx(previous)
		check(same_transforms, "fixed transforms " + str(frame))
		check(is_zero_approx(art.rotation) and unit.modulate.a == 1.0 and sprite.self_modulate.a == 1.0, "no added rotation or fade " + str(frame))
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered := view.get_texture().get_image()
		check(rendered.save_png(output.path_join("frames/frame-%02d.png" % (frame + 1))) == OK, "render frame " + str(frame))
		if frame in [0, 8, 16]:
			check(rendered.save_png(output.path_join("death-%02d.png" % (frame + 1))) == OK, "keyframe capture " + str(frame))
	unit.reset_view_pose()
	unit.sync_scene_art()
	check(not unit._death_active and sprite.visible and sprite.texture.resource_path.contains("enemy_warrior_idle_v1"), "reset restores current idle")
	view.queue_free()
	await process_frame
	print("MAX AFFINE COMPONENT DELTA: %.10f" % max_transform_delta)
	print("ENEMY DEATH ART AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
