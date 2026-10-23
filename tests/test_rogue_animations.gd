extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const ROGUE_DEATH: SpriteFrames = preload("res://assets/art_presets/trials/rogue_selected_v1/death_frames.tres")
const ROGUE_STILL: Texture2D = preload("res://assets/art_presets/trials/rogue_selected_v1/still.png")

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ROGUE ANIMATIONS: " + label)


func _values(class_id: StringName, faction: Faction.Type, unit_id: int = 41) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {
		"cell": Vector2i(2, 3), "half_steps": 0,
		"unit": {"id": unit_id, "faction": int(faction), "name": "Разбойник", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": class_id, "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false,
		"forecast_entry": {}, "armor_values": {"current": 0.0, "maximum": 0.0},
		"shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0},
		"status_entries": statuses,
	}


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var visual := UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
	check(visual != null, "art trial scene creates BattleDefenderIdleVisual")
	if visual == null:
		viewport.queue_free()
		await process_frame
		quit(1)
		return
	viewport.add_child(visual)
	await process_frame
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 32.0
	config.origin_offset = Vector2(320.0, 48.0)
	check(visual.apply_view(_values(&"rogue", Faction.Type.PLAYER), config), "player rogue DTO applies")
	_test_production_resources(visual)
	_test_static_art(visual, config)
	_test_death_and_lifecycle(visual, config)
	_test_fallbacks(visual, config)
	visual.queue_free()
	viewport.queue_free()
	await process_frame
	print("ROGUE ANIMATIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_production_resources(visual: BattleDefenderIdleVisual) -> void:
	check(visual.rogue_idle_frames == null and visual.rogue_buff_frames == null,
		"production scene leaves legacy rogue idle and buff resources unset")
	var still_image := ROGUE_STILL.get_image()
	check(still_image.get_size() == Vector2i(128, 128) and still_image.get_format() == Image.FORMAT_RGBA8,
		"selected still is native 128px RGBA artwork")
	var alpha_min := Vector2i(128, 128)
	var alpha_max := Vector2i(-1, -1)
	for y: int in 128:
		for x: int in 128:
			if still_image.get_pixel(x, y).a <= 0.0: continue
			alpha_min.x = mini(alpha_min.x, x)
			alpha_min.y = mini(alpha_min.y, y)
			alpha_max.x = maxi(alpha_max.x, x + 1)
			alpha_max.y = maxi(alpha_max.y, y + 1)
	check(alpha_min == Vector2i(31, 20) and alpha_max == Vector2i(97, 92),
		"selected still retains the authored alpha bounds")
	check(visual.rogue_death_frames == ROGUE_DEATH and ROGUE_DEATH.get_animation_names().size() == 1
		and ROGUE_DEATH.get_animation_names()[0] == "death" and not ROGUE_DEATH.get_animation_loop(&"death")
		and ROGUE_DEATH.get_animation_speed(&"death") == 100.0
		and ROGUE_DEATH.get_frame_count(&"death") == 17,
		"selected Death3 is a finite 17-frame clip at 100 fps")
	for frame: int in 17:
		check(ROGUE_DEATH.get_frame_duration(&"death", frame) == 15
			and ROGUE_DEATH.get_frame_texture(&"death", frame) != null,
			"Death3 frame %02d has 15 ticks and a texture" % (frame + 1))
		if frame > 0:
			check(ROGUE_DEATH.get_frame_texture(&"death", frame) != ROGUE_DEATH.get_frame_texture(&"death", frame - 1),
				"Death3 frame %02d is in its own ordered slot" % (frame + 1))
	check(is_equal_approx(BattleDefenderIdleVisual._clip_duration(ROGUE_DEATH, &"death"), 2.55),
		"Death3 duration is 2.55 seconds")
	check(is_equal_approx(visual.death_duration(), 3.60), "rogue death clock retains 0.25s hold and 0.80s fade")


func _test_static_art(visual: BattleDefenderIdleVisual, config: IsoGridConfig) -> void:
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var player := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var enemy := visual.get_node("ArtRoot/EnemyRogueSprite") as Sprite2D
	var art := visual.get_node("ArtRoot") as Node2D
	var body := visual.get_node("ArtRoot/BodySprite") as Sprite2D
	var material := player.material as ShaderMaterial
	check(player.visible and not idle.visible and not body.visible and not visual.is_processing(),
		"player rogue presents the static still without starting the old idle")
	check(visual.rogue_art_scale == 0.8 and visual.rogue_pick_rect == Rect2(-38, -67, 76, 80)
		and art.scale.is_equal_approx(Vector2(0.8, 0.8)), "production scale and pick rectangle match the selected model")
	check(player.texture == ROGUE_STILL and player.position == Vector2(-64, -83)
		and player.scale == Vector2.ONE and idle.position == player.position and idle.scale == player.scale,
		"player still and death sprite share the selected anchor without extra scaling")
	check(material != null and material.get_shader_parameter("source_region") == Vector4(0, 0, 128, 128)
		and material.get_shader_parameter("native_size") == Vector2(128, 128)
		and is_zero_approx(float(material.get_shader_parameter("brighter_palette_strength")))
		and not bool(material.get_shader_parameter("cloth_enabled")),
		"rogue samples native pixels with original palette and no cloth mask")
	visual.sample_buff(0.2)
	check(not visual.can_play_buff() and not idle.visible and player.visible and player.texture == ROGUE_STILL,
		"sampling a buff cannot reveal a legacy rogue animation")
	visual.clear_buff()
	var values := _values(&"rogue", Faction.Type.ENEMY)
	check(visual.apply_view(values, config), "same visual accepts enemy rogue")
	check(enemy.visible and not player.visible and not idle.visible and enemy.position == Vector2(64, -83)
		and enemy.scale == Vector2(-1, 1), "enemy rogue mirrors only its model around the matching anchor")
	check(visual.rogue_death_frames == ROGUE_DEATH, "both factions share the selected Death3 resource")


func _test_death_and_lifecycle(visual: BattleDefenderIdleVisual, config: IsoGridConfig) -> void:
	var values := _values(&"rogue", Faction.Type.PLAYER)
	visual.apply_view(values, config)
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	visual.frozen = true
	visual.stunned = true
	check(visual.can_play_death(), "confirmed rogue death remains available while frozen and stunned")
	for frame: int in 17:
		var elapsed := (float(frame) + 0.5) * 0.15
		visual.sample_death(elapsed / visual.death_duration())
		check(idle.texture == ROGUE_DEATH.get_frame_texture(&"death", frame) and idle.visible and not still.visible,
			"death progress samples ordered frame %02d" % (frame + 1))
		check(is_equal_approx(idle.self_modulate.a, 1.0), "death frame %02d remains opaque" % (frame + 1))
	visual.sample_death((2.55 + 0.25) / 3.60)
	check(idle.texture == ROGUE_DEATH.get_frame_texture(&"death", 16) and is_equal_approx(idle.self_modulate.a, 1.0),
		"last Death3 frame remains held through the opaque pause")
	visual.sample_death((2.55 + 0.25 + 0.40) / 3.60)
	check(is_equal_approx(idle.self_modulate.a, 0.5), "last frame fades to half alpha halfway through fade")
	visual.sample_death(1.0)
	check(is_zero_approx(idle.self_modulate.a), "last frame fades to zero at full duration")
	visual.reset_view_pose()
	check(is_equal_approx(idle.self_modulate.a, 1.0) and still.visible,
		"reset restores static still and authored alpha")
	visual.frozen = false
	visual.stunned = false
	values["visual_class_id"] = &"mage"
	check(visual.apply_view(values, config) and not idle.visible, "same ID class reuse hides old rogue death sprite")
	values["visual_class_id"] = &"rogue"
	check(visual.apply_view(values, config) and not visual._death_active and still.visible,
		"returning to rogue does not resume an old death")
	visual.retire_view()
	check(not idle.visible and not visual.is_processing(), "retirement hides rogue death sprite")


func _test_fallbacks(visual: BattleDefenderIdleVisual, config: IsoGridConfig) -> void:
	var values := _values(&"rogue", Faction.Type.PLAYER)
	visual.apply_view(values, config)
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var good_frames := visual.rogue_death_frames
	visual.rogue_death_frames = null
	check(not visual.can_play_death() and visual._active_death_frames() == null,
		"missing selected clip falls back from custom rogue death")
	visual.rogue_death_frames = good_frames
	var no_animation := SpriteFrames.new()
	no_animation.add_frame(&"default", ROGUE_STILL, 1.0)
	visual.rogue_death_frames = no_animation
	check(visual._active_death_frames() == null, "missing death animation selects generic death fallback")
	var wrong_count := SpriteFrames.new()
	wrong_count.add_animation(&"death")
	wrong_count.set_animation_speed(&"death", 100.0)
	for frame: int in 16:
		wrong_count.add_frame(&"death", good_frames.get_frame_texture(&"death", frame), 15.0)
	visual.rogue_death_frames = wrong_count
	check(visual._active_death_frames() == null, "wrong-count clip selects generic death fallback")
	var zero_speed := good_frames.duplicate() as SpriteFrames
	zero_speed.set_animation_speed(&"death", 0.0)
	visual.rogue_death_frames = zero_speed
	check(visual._active_death_frames() == null, "zero-speed clip selects generic death fallback")
	var broken_texture := good_frames.duplicate() as SpriteFrames
	broken_texture.set_frame(&"death", 0, null, 15.0)
	visual.rogue_death_frames = broken_texture
	check(visual._active_death_frames() == null, "null frame texture selects generic death fallback")
	visual.rogue_death_frames = good_frames
	var old_texture := still.texture
	still.texture = null
	visual.sync_scene_art()
	var body := visual.get_node("ArtRoot/BodySprite") as Sprite2D
	check(not idle.visible and body.visible and not visual.can_play_death(),
		"missing still keeps the generic body fallback")
	still.texture = old_texture
	visual.sync_scene_art()
	check(still.visible and not body.visible, "restoring still returns to static selected art")
