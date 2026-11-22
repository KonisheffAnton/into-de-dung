extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const SKINS: Array[Dictionary] = [
	{"id":&"watch_shield","class":&"shieldbearer"}, {"id":&"grey_bastion","class":&"shieldbearer"},
	{"id":&"red_bastion","class":&"fighter"}, {"id":&"short_cape","class":&"rogue"},
	{"id":&"star_hood","class":&"mage"}, {"id":&"silver_ranger","class":&"archer"},
]
var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST GLOW: " + label)

func _values(id: int, entry: Dictionary) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {"cell":Vector2i(1,1),"half_steps":0,
		"unit":{"id":id,"faction":int(Faction.Type.PLAYER),"name":"Host", "alive":true,"hp":30.0,"hp_max":30.0,"balance":5.0,"balance_max":5.0},
		"visual_class_id":entry.class,"visual_skin_id":entry.id,
		"selected":false,"inspected":false,"hovered":false,"acting":false,"forecast_entry":{},"show_rear":false,"summon_pending":false,
		"armor_values":{},"shield_view":{},"raised_shield_view":{},"reaction_view":{},"action_resources_view":{},"status_entries":statuses,
		"is_host":true,"host_glow":{"color":"blue","form":"flame","flicker":"still"}}

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1120,1440)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var config := IsoGridConfig.new()
	for row: int in SKINS.size():
		var entry := SKINS[row]
		for column: int in 4:
			var visual := UNIT_SCENE.instantiate() as BattleCharacterSkinVisual
			visual.role = BattleDemoIsoVisual.Role.UNIT
			visual.show_ground_shadow = false
			viewport.add_child(visual)
			var values := _values(100+row*4+column,entry)
			visual.apply_view(values,config)
			visual.ambient_animation_paused = true
			visual.sync_scene_art()
			var skin := visual.skin_definition
			_check(visual._host_marker.visible and not visual._host_marker.points.is_empty(), "living carrier has eyes " + String(entry.id))
			if column == 0:
				for clip: StringName in skin.animations.get_animation_names():
					if clip == &"death": continue
					for frame: int in skin.animations.get_frame_count(clip):
						var texture := skin.animations.get_frame_texture(clip,frame)
						visual._set_skin_texture(texture)
						_check(visual._host_marker.points.size() == HostGlowAppearance.STILL_EYES[String(entry.id)].size(), "eye count across " + String(clip))
						if texture is AtlasTexture:
							var atlas := texture as AtlasTexture
							var key := "%s@%d,%d" % [atlas.atlas.resource_path.get_file(),int(atlas.region.position.x),int(atlas.region.position.y)]
							_check(HostGlowAppearance._anchors[String(entry.id)].has(key), "authored animation has explicit eye anchor")
				visual._set_skin_texture(skin.still)
			elif column in [1,2]:
				var clip: StringName = &"idle" if column == 1 else &"buff"
				var frame: int = skin.animations.get_frame_count(clip)/2
				visual._set_skin_texture(skin.animations.get_frame_texture(clip,frame))
			else:
				values.unit.faction = int(Faction.Type.ENEMY)
				visual.apply_view(values,config)
				visual.sync_scene_art()
			visual.set_process(false)
			visual.position = Vector2(140+column*280,205+row*240)
			visual.scale = Vector2.ONE*1.8
			var label := Label.new()
			label.text = "%s · %s" % [entry.id,["still","idle","buff","mirror"][column]]
			label.position = Vector2(20+column*280,215+row*240)
			viewport.add_child(label)
			if column == 3:
				var mark := visual._host_marker
				values.is_host = false
				visual.apply_view(values,config)
				_check(not mark.visible, "reuse removes glow from nonhost")
				values.is_host = true
				visual.apply_view(values,config)
				visual._skin_dying = true
				visual._set_skin_texture(skin.still)
				_check(not mark.visible, "death suppresses living eye effect")
				visual._skin_dying = false
				visual._set_skin_texture(skin.still)
				_check(visual._host_marker == mark and mark.visible, "reuse retains one presentation node")
				visual.position = Vector2(140+column*280,205+row*240)
	var captures := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	if not captures.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(captures)
		_check(viewport.get_texture().get_image().save_png(captures.path_join("host-glow-poses.png")) == OK,"GPU captures six skins in four poses")
		await _test_flame_pixels(captures)
	viewport.queue_free()
	await process_frame
	print("HOST GLOW RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _test_flame_pixels(captures: String) -> void:
	# Изолированный крупный огонёк проверяет настоящее движение RGBA, а не только часы.
	var light := HostGlowSprite.new()
	viewport.add_child(light)
	light.configure(&"star_hood",CharacterSkinCatalog.definition(&"mage").still,{"color":"amber","form":"flame","flicker":"soft"},true)
	light.points.assign([Vector2(24,48)])
	light.position = Vector2(860,0)
	light.scale = Vector2.ONE*4.0
	light.set_process(false)
	light.elapsed = 0.0; light.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image().get_region(Rect2i(860,0,240,210))
	light.elapsed = 0.64; light.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image().get_region(Rect2i(860,0,240,210))
	# Верхушка выше круглого свечения: смену позы нельзя подменить пульсацией яркости.
	_check(before.get_region(Rect2i(83,150,26,22)).get_data() != after.get_region(Rect2i(83,150,26,22)).get_data(), "PixelLab flame tip changes visible pixels over time")
	light.style.flicker = "still"
	light.elapsed = 0.0; light.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	before = viewport.get_texture().get_image().get_region(Rect2i(860,0,240,210))
	light.elapsed = 0.64; light.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	after = viewport.get_texture().get_image().get_region(Rect2i(860,0,240,210))
	_check(before.get_data() == after.get_data(), "still option holds exact first flame pixels")
	_check(after.save_png(captures.path_join("host-flame-game-render.png")) == OK,"save rendered PixelLab overlay")
	light.queue_free()
