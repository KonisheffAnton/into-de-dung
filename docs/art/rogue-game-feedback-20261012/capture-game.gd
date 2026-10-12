extends SceneTree

const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
var output: String

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	call_deferred("_run")

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var panel := SubViewport.new()
	panel.size = Vector2i(1152, 688)
	panel.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(panel)
	var samples: Array[SubViewport] = []
	var kinds: Array[String] = ["Defender idle / 0.80", "Rogue idle / 0.73", "Rogue buff / 0.73", "Death middle / 0.73", "Death final / player", "Death final / enemy"]
	for index: int in kinds.size():
		var sample := SubViewport.new()
		sample.size = Vector2i(192, 160)
		sample.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sample)
		samples.append(sample)
		var config := IsoGridConfig.new()
		config.tile_size = Vector2(128, 96)
		config.height_step = 32.0
		config.origin_offset = Vector2(96, 93)
		var tile := TILE.instantiate() as BattleTerrainVisual
		sample.add_child(tile)
		await process_frame
		tile.apply_view({"cell": Vector2i.ZERO, "role": BattleDemoIsoVisual.Role.FLOOR,
			"half_steps": 0, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}, config)
		var visual := UNIT.instantiate() as BattleDefenderIdleVisual
		visual.role = BattleDemoIsoVisual.Role.UNIT
		sample.add_child(visual)
		await process_frame
		var statuses: Array[Dictionary] = []
		visual.apply_view({"cell": Vector2i.ZERO, "half_steps": 0,
			"unit": {"id": 0, "faction": int(Faction.Type.ENEMY if index == 5 else Faction.Type.PLAYER),
				"name": "", "alive": true, "hp": 18.0, "hp_max": 18.0, "balance": 4.0, "balance_max": 4.0},
			"visual_class_id": &"warrior" if index == 0 else &"rogue", "selected": false,
			"inspected": false, "hovered": false, "acting": false, "show_rear": false, "summon_pending": false,
			"forecast_entry": {}, "armor_values": {}, "shield_view": {}, "raised_shield_view": {},
			"reaction_view": {}, "action_resources_view": {}, "status_entries": statuses}, config)
		visual.idle_clock.configure(0, 24, 24)
		visual._process(0.0)
		if index == 2: visual.sample_buff(0.58)
		if index == 3: visual.sample_death(0.58)
		if index >= 4: visual.sample_death(1.0)
		visual.set_process(false)
		# Снимок штатного ArtRoot отделяет сравнение рисунка от HP/StatusHud, не меняя игровые сцены.
		var art_copy := visual.get_node("ArtRoot").duplicate() as Node2D
		art_copy.position += visual.position
		sample.add_child(art_copy)
		visual.hide()
		var enlarged := Sprite2D.new()
		enlarged.texture = sample.get_texture()
		enlarged.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		enlarged.centered = false
		enlarged.scale = Vector2(2, 2)
		enlarged.position = Vector2((index % 3) * 384, (index / 3) * 344 + 24)
		panel.add_child(enlarged)
		var label := Label.new()
		label.text = kinds[index] + " / pixels x2"
		label.position = Vector2((index % 3) * 384 + 10, (index / 3) * 344 + 3)
		panel.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = panel.get_texture().get_image().save_png(output.path_join("game-comparison.png"))
	panel.queue_free()
	for sample: SubViewport in samples: sample.queue_free()
	await process_frame
	print("ROGUE FEEDBACK CAPTURE: ", "PASS" if result == OK else "FAIL")
	quit(0 if result == OK else 1)
