extends "res://tests/test_rogue_animations.gd"

const TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")

func _run() -> void:
	if captures.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(captures)
	viewport = SubViewport.new()
	viewport.size = Vector2i(192, 160)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32
	config.origin_offset = Vector2(96, 93)
	var tile := TILE.instantiate() as BattleTerrainVisual
	viewport.add_child(tile)
	await process_frame
	tile.apply_view({"cell":Vector2i.ZERO,"role":BattleDemoIsoVisual.Role.FLOOR,
		"half_steps":0,"is_void":false,"reachable":false,"enemy_range":false,"burning":false},config)
	var visual := UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	viewport.add_child(visual)
	await process_frame
	var values := _values(&"rogue",Faction.Type.PLAYER)
	values["cell"] = Vector2i.ZERO
	visual.apply_view(values,config)
	visual.set_process(false)
	# Каждый кадр копирует настроенный игровой ArtRoot, включая реальную альфу затухания.
	for index: int in 34:
		visual.show()
		visual.sample_death((float(index)*0.05+0.025)/visual.death_duration())
		visual.set_process(false)
		await _capture_art(visual,"death-%02d" % index)
	visual.reset_view_pose()
	var elapsed: float = 0.0
	for index: int in ROGUE_BUFF.get_frame_count(&"buff"):
		var duration := ROGUE_BUFF.get_frame_duration(&"buff",index)/ROGUE_BUFF.get_animation_speed(&"buff")
		visual.show()
		visual.sample_buff(elapsed+duration*0.5)
		visual.set_process(false)
		await _capture_art(visual,"buff-%02d" % index)
		elapsed += duration
	viewport.queue_free()
	await process_frame
	print("ROGUE MOTION CAPTURE RESULTS: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)

func _capture_art(visual: BattleDefenderIdleVisual, label: String) -> void:
	var copy := visual.get_node("ArtRoot").duplicate() as Node2D
	copy.position += visual.position
	viewport.add_child(copy)
	visual.hide()
	await _capture(label)
	copy.queue_free()
	await process_frame
