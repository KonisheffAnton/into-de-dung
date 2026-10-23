extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
var output: String = ""
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ROGUE ART: " + label)

func values(faction: Faction.Type, class_id: StringName = &"rogue") -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {"cell": Vector2i.ZERO, "half_steps": 0,
		"unit": {"id": 72, "faction": int(faction), "name": "", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": class_id, "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}

func add_tile(view: SubViewport, config: IsoGridConfig) -> BattleTerrainVisual:
	var tile := TILE.instantiate() as BattleTerrainVisual
	view.add_child(tile)
	tile.apply_view({"cell": Vector2i.ZERO, "role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}, config)
	return tile

func capture(view: SubViewport, path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(output.path_join(path)) == OK, "capture " + path)

func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(640, 640)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(512, 384)
	config.origin_offset = Vector2(320, 256)
	var tile := add_tile(view, config)
	var unit := UNIT.instantiate() as BattleDefenderIdleVisual
	unit.role = BattleDemoIsoVisual.Role.UNIT
	view.add_child(unit)
	for faction: Faction.Type in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
		var side := "player" if faction == Faction.Type.PLAYER else "enemy"
		DirAccess.make_dir_recursive_absolute(output.path_join(side))
		unit.reset_view_pose()
		unit.apply_view(values(faction), config)
		unit.set_process(false)
		var sprite := unit.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
		var still := unit.class_still_sprite()
		var hud := unit.get_node("StatusHud") as Node2D
		var shadow := unit.get_node("GroundShadow") as Node2D
		var art := unit.get_node("ArtRoot") as Node2D
		var transforms := [unit.transform, shadow.transform, hud.transform, art.transform]
		var top := tile.top_polygon()
		var center := tile.to_global((top[0] + top[2]) * 0.5)
		check(still.visible and not sprite.visible and not unit.is_processing(), side + " static waiting pose")
		hud.hide()
		await capture(view, side + "/still.png")
		check(is_equal_approx(unit.death_duration(), 3.60), side + " selected clip and lifecycle")
		for frame: int in 17:
			unit.sample_death((float(frame) * 0.15 + 0.075) / 3.60)
			hud.hide()
			check(sprite.texture == unit.rogue_death_frames.get_frame_texture(&"death", frame), side + " ordered frame " + str(frame))
			check(sprite.visible and not still.visible and sprite.scale == Vector2(-1 if faction == Faction.Type.ENEMY else 1, 1), side + " mirror " + str(frame))
			check(sprite.to_global(Vector2(64, 83)).is_equal_approx(center), side + " fixed tile anchor " + str(frame))
			var current := [unit.transform, shadow.transform, hud.transform, art.transform]
			for i: int in 4:
				check((current[i] as Transform2D).is_equal_approx(transforms[i]), side + " fixed transform " + str(i))
			check(is_zero_approx(art.rotation) and unit.modulate.a == 1.0 and sprite.self_modulate.a == 1.0,
				side + " no synthetic pose/fade during clip")
			await capture(view, side + "/frame-%02d.png" % (frame + 1))
		for fade: int in 4:
			unit.sample_death((2.80 + float(fade + 1) * 0.20) / 3.60)
			hud.hide()
			check(is_equal_approx(sprite.self_modulate.a, 1.0 - float(fade + 1) * 0.25), side + " fade " + str(fade))
			await capture(view, side + "/fade-%02d.png" % (fade + 1))
		unit.reset_view_pose()
		check(still.visible and not sprite.visible and is_equal_approx(sprite.self_modulate.a, 1.0), side + " reset static pose")
	view.queue_free()
	await process_frame
	# Сопоставление настоящих сцен на одинаковых тайлах; эталон воина не меняется.
	view = SubViewport.new()
	view.size = Vector2i(1024, 640)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for i: int in 2:
		config = IsoGridConfig.new()
		config.tile_size = Vector2(448, 336)
		config.origin_offset = Vector2(256 + i * 512, 300)
		add_tile(view, config)
		unit = UNIT.instantiate() as BattleDefenderIdleVisual
		unit.role = BattleDemoIsoVisual.Role.UNIT
		view.add_child(unit)
		unit.apply_view(values(Faction.Type.PLAYER if i == 0 else Faction.Type.ENEMY, &"rogue" if i == 0 else &"warrior"), config)
		unit.ambient_animation_paused = true
		unit.get_node("StatusHud").hide()
		check(is_equal_approx(unit.get_unit_art_scale(), 0.8), "equal reference scale " + str(i))
	await capture(view, "rogue-warrior-in-game.png")
	view.queue_free()
	await process_frame
	print("ROGUE ART AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
