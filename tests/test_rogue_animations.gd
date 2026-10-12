extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const ROGUE_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/idle_frames.tres")
const ROGUE_BUFF: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/buff_frames.tres")
const ROGUE_DEATH: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/death_frames.tres")

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport


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
		printerr("FAIL ROGUE ANIMATIONS: " + label)


func _values(class_id: StringName, faction: Faction.Type, unit_id: int = 41) -> Dictionary:
	# Снимок строится из тех же скалярных полей, что публикует доска, чтобы тестировать границу визуального DTO.
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
	viewport = SubViewport.new()
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
	var values := _values(&"rogue", Faction.Type.PLAYER)
	check(visual.apply_view(values, config), "allied rogue DTO is applied")
	_test_resources(visual)
	await _test_art_and_lifecycle(visual, values, config)
	await _test_playback(visual, values, config)
	_test_fallback_and_palette(visual, values, config)
	visual.queue_free()
	viewport.queue_free()
	await process_frame
	print("ROGUE ANIMATIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_resources(visual: BattleDefenderIdleVisual) -> void:
	check(visual.rogue_idle_frames == ROGUE_IDLE and ROGUE_IDLE.get_animation_names().size() == 1
		and ROGUE_IDLE.get_animation_names()[0] == "idle"
		and ROGUE_IDLE.get_animation_loop(&"idle") and ROGUE_IDLE.get_animation_speed(&"idle") == 5.0
		and ROGUE_IDLE.get_frame_count(&"idle") == 12,
		"idle resource has one looping 12-frame clip at 5 fps")
	check(visual.rogue_buff_frames == ROGUE_BUFF and ROGUE_BUFF.get_animation_names().size() == 1
		and ROGUE_BUFF.get_animation_names()[0] == "buff"
		and not ROGUE_BUFF.get_animation_loop(&"buff") and ROGUE_BUFF.get_animation_speed(&"buff") == 100.0
		and ROGUE_BUFF.get_frame_count(&"buff") == 6,
		"buff resource has one finite six-frame clip at 100 fps")
	check(visual.rogue_death_frames == ROGUE_DEATH and ROGUE_DEATH.get_animation_names().size() == 1
		and ROGUE_DEATH.get_animation_names()[0] == "death"
		and not ROGUE_DEATH.get_animation_loop(&"death") and ROGUE_DEATH.get_animation_speed(&"death") == 20.0
		and ROGUE_DEATH.get_frame_count(&"death") == 13,
		"death resource has one finite 13-frame clip at 20 fps")
	var buff_ticks: Array[float] = [12.0, 24.0, 6.0, 32.0, 12.0, 16.0]
	var buff_total: float = 0.0
	for frame: int in 6:
		var duration := ROGUE_BUFF.get_frame_duration(&"buff", frame)
		check(duration == buff_ticks[frame], "buff frame %02d tick duration" % (frame + 1))
		buff_total += duration / ROGUE_BUFF.get_animation_speed(&"buff")
	check(is_equal_approx(buff_total, 1.02), "buff totals exactly 1020 ms")
	var idle_total: float = 0.0
	for frame: int in 12:
		check(ROGUE_IDLE.get_frame_duration(&"idle", frame) == 1.0, "idle frame %02d is one tick" % (frame + 1))
		idle_total += ROGUE_IDLE.get_frame_duration(&"idle", frame) / ROGUE_IDLE.get_animation_speed(&"idle")
	check(is_equal_approx(idle_total, 2.4), "idle cycle totals 2.4 seconds")
	var death_total: float = 0.0
	for frame: int in 13:
		check(ROGUE_DEATH.get_frame_duration(&"death", frame) == 1.0, "death frame %02d is one tick" % (frame + 1))
		death_total += ROGUE_DEATH.get_frame_duration(&"death", frame) / ROGUE_DEATH.get_animation_speed(&"death")
	check(is_equal_approx(death_total, 0.65), "death clip totals 0.65 seconds without a GIF hold")
	check(is_equal_approx(visual.death_duration(), 1.70), "rogue death clock includes authored clip, hold, and fade")


func _test_art_and_lifecycle(visual: BattleDefenderIdleVisual, values: Dictionary, config: IsoGridConfig) -> void:
	var root_art := visual.get_node("ArtRoot") as Node2D
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var body := visual.get_node("ArtRoot/BodySprite") as Sprite2D
	check(idle.visible and not still.visible and not body.visible and visual.is_processing(),
		"allied rogue idle replaces only the class still")
	check(visual.rogue_pick_rect == Rect2(-40, -65, 80, 73) and root_art.scale.is_equal_approx(Vector2(0.73, 0.73)),
		"rogue keeps the authored picking rectangle and ArtRoot scale")
	check(idle.position == Vector2(-64, -94) and idle.scale == Vector2(0.25, 0.25)
		and still.position == Vector2(-64, -94) and still.scale == Vector2(0.25, 0.25),
		"512px rogue sheets align on allied support at quarter scale")
	var rogue_material := still.material as ShaderMaterial
	check(rogue_material != null and rogue_material.get_shader_parameter("native_size") == Vector2(128, 128)
		and rogue_material.get_shader_parameter("source_region") == Vector4(0, 0, 512, 512),
		"rogue shader samples the 512px source region at 128px native size")
	var elapsed_before := visual.idle_clock.get_elapsed()
	visual._process(0.43)
	var elapsed := visual.idle_clock.get_elapsed()
	check(elapsed > elapsed_before and idle.texture == ROGUE_IDLE.get_frame_texture(&"idle", visual.idle_clock.get_frame_index()),
		"shared idle clock advances the displayed rogue frame")
	var shown := idle.texture
	var identity := visual.get_instance_id()
	check(not visual.apply_view(values.duplicate(true), config), "identical unit-view values are skipped")
	visual.sync_scene_art()
	visual.set_process(false)
	check(visual.get_instance_id() == identity and visual.idle_clock.get_elapsed() == elapsed and idle.texture == shown,
		"refresh of the same view preserves clock phase and sprite")
	for status: StringName in [&"frozen", &"stunned", &"summon_pending"]:
		visual.set(status, true)
		visual.sync_scene_art()
		var paused_elapsed := visual.idle_clock.get_elapsed()
		visual._process(0.2)
		check(not idle.visible and still.visible and visual.idle_clock.get_elapsed() == paused_elapsed,
			"status " + String(status) + " holds the rogue on its still")
		visual.set(status, false)
		visual.sync_scene_art()
		check(idle.visible and visual.idle_clock.get_elapsed() == elapsed,
			"status " + String(status) + " resumes the same clock phase")
	visual.ambient_animation_paused = true
	var paused_elapsed := visual.idle_clock.get_elapsed()
	visual._process(0.2)
	check(not idle.visible and still.visible and visual.idle_clock.get_elapsed() == paused_elapsed,
		"ambient playback pause holds still art and clock")
	visual.ambient_animation_paused = false
	visual.action_offset = Vector2(2.0, 0.0)
	check(not idle.visible and still.visible, "active action pose suspends rogue idle")
	visual.reset_view_pose()
	visual.set_process(false)
	visual.presentation_offset = Vector2(3.0, 0.0)
	check(not idle.visible and still.visible, "presentation offset suspends rogue idle")
	visual.reset_view_pose()
	visual.set_process(false)
	visual.presentation_lift = 4.0
	check(not idle.visible and still.visible, "presentation lift suspends rogue idle")
	visual.reset_view_pose()
	visual.set_process(false)
	visual.fall_drop = 5.0
	check(not idle.visible and still.visible, "fall pose suspends rogue idle")
	visual.reset_view_pose()
	visual.set_process(false)
	visual.landing_compression = 0.2
	check(not idle.visible and still.visible, "landing compression suspends rogue idle")
	visual.reset_view_pose()
	visual.set_process(false)
	check(idle.visible and root_art.position == visual.get_visual_offset(), "pose reset restores aligned rogue idle")
	var phase := visual.idle_clock.get_elapsed()
	visual.sample_buff(0.201)
	check(not visual.is_processing() and idle.texture == ROGUE_BUFF.get_frame_texture(&"buff", 1)
		and not still.visible, "buff sampling selects the second authored frame")
	visual.clear_buff()
	check(visual.is_processing() and visual.idle_clock.get_elapsed() == phase,
		"clearing buff resumes idle at its prior clock phase")
	visual.set_process(false)
	for frame: int in 12:
		visual.idle_clock.configure(0, 24, 24)
		visual.idle_clock.advance(float(frame) * 0.2)
		visual._process(0.0)
		check(idle.texture == ROGUE_IDLE.get_frame_texture(&"idle", frame), "idle samples selected frame %02d" % (frame + 1))
		if frame in [0, 5, 11]: await _capture("rogue-idle-%02d" % frame)
	visual.sample_death(0.5)
	for frame: int in 13:
		var progress := ((float(frame) + 0.5) / 20.0) / visual.death_duration()
		visual.sample_death(progress)
		check(idle.texture == ROGUE_DEATH.get_frame_texture(&"death", frame) and idle.visible and not still.visible,
			"death samples authored frame %02d" % (frame + 1))
		check(is_equal_approx(idle.self_modulate.a, 1.0), "death remains opaque through authored clip")
		if frame in [0, 6, 12]: await _capture("rogue-death-%02d" % frame)
	visual.sample_death((0.65 + 0.25) / visual.death_duration())
	check(idle.texture == ROGUE_DEATH.get_frame_texture(&"death", 12) and is_equal_approx(idle.self_modulate.a, 1.0),
		"death holds the final authored frame through the opaque pause")
	visual.sample_death((0.65 + 0.25 + 0.40) / visual.death_duration())
	check(is_equal_approx(idle.self_modulate.a, 0.5), "rogue body fades linearly through the final 0.8 seconds")
	visual.sample_death(1.0)
	check(is_zero_approx(idle.self_modulate.a), "rogue body reaches transparent at death completion")
	visual.frozen = true
	visual.sync_scene_art()
	check(visual.can_play_death(), "confirmed death presentation remains available while frozen")
	visual.reset_view_pose()
	check(is_equal_approx(idle.self_modulate.a, 1.0), "reset restores authored rogue sprite alpha")
	visual.set_process(false)
	values["unit"].faction = int(Faction.Type.ENEMY)
	values["unit"].id = 42
	check(visual.apply_view(values, config), "same visual accepts the enemy unit snapshot")
	visual.set_process(false)
	var enemy_idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var enemy_still := visual.get_node("ArtRoot/EnemyRogueSprite") as Sprite2D
	check(enemy_idle.visible and not enemy_still.visible and enemy_idle.position == Vector2(64, -94)
		and enemy_idle.scale == Vector2(-0.25, 0.25) and enemy_still.position == Vector2(64, -94)
		and enemy_still.scale.x == -0.25,
		"enemy side flips only the rogue drawing around the same support")
	visual.retire_view()
	check(not visual.is_processing() and not enemy_idle.visible and visual.idle_clock.get_elapsed() == 0.0,
		"retirement hides the sprite and resets its idle lifecycle")


func _test_playback(visual: BattleDefenderIdleVisual, values: Dictionary, config: IsoGridConfig) -> void:
	values["unit"]["faction"] = int(Faction.Type.PLAYER)
	values["unit"]["id"] = 41
	values["visual_class_id"] = &"rogue"
	visual.apply_view(values, config)
	visual.set_process(false)
	visual.sample_buff(0.0)
	var buff := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var buff_elapsed: float = 0.0
	for frame: int in 6:
		var frame_duration := ROGUE_BUFF.get_frame_duration(&"buff", frame) / ROGUE_BUFF.get_animation_speed(&"buff")
		visual.sample_buff(buff_elapsed + frame_duration * 0.5)
		check(buff.texture == ROGUE_BUFF.get_frame_texture(&"buff", frame), "buff samples frame %02d" % (frame + 1))
		if frame in [0, 2, 3, 5]: await _capture("rogue-buff-%02d" % frame)
		buff_elapsed += frame_duration
	visual.clear_buff()
	visual.set_process(false)


func _test_fallback_and_palette(visual: BattleDefenderIdleVisual, values: Dictionary, config: IsoGridConfig) -> void:
	values["unit"]["faction"] = int(Faction.Type.PLAYER)
	values["unit"]["id"] = 41
	values["visual_class_id"] = &"rogue"
	visual.apply_view(values, config)
	visual.set_process(false)
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var rogue_still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var material := rogue_still.material as ShaderMaterial
	visual.set_cloth_palette(2)
	var still_slot := RogueClothPalette.mask_slot(rogue_still.texture)
	check(material != null and still_slot >= 0
		and bool(material.get_shader_parameter("cloth_enabled"))
		and material.get_shader_parameter("cloth_mask_origin") == RogueClothPalette.mask_origin(still_slot),
		"shared allied clothing palette applies the rogue still mask")
	visual.set_cloth_palette(0)
	visual.sample_death((0.65 + 0.25 + 0.40) / visual.death_duration())
	check(is_equal_approx(idle.self_modulate.a, 0.5), "class reuse fixture first enters the rogue fade")
	var mage_values := _values(&"mage", Faction.Type.PLAYER, 41)
	check(visual.apply_view(mage_values, config) and not idle.visible and not rogue_still.visible,
		"same living unit ID changes class without a stale rogue drawing")
	check(is_equal_approx(idle.self_modulate.a, 1.0), "class change restores rogue sprite alpha")
	check(visual.apply_view(values, config) and idle.visible and not rogue_still.visible,
		"same unit ID returns to rogue and resumes its own resource")
	check(not visual._death_active and is_equal_approx(idle.self_modulate.a, 1.0),
		"same ID class reuse cannot resume a stale rogue death fade")
	visual.rogue_idle_frames = null
	visual.rogue_buff_frames = null
	visual.rogue_death_frames = null
	visual.sync_scene_art()
	check(not idle.visible and rogue_still.visible and not visual.is_processing()
		and not visual.can_play_buff() and not visual.can_play_death(),
		"missing rogue animation resources safely fall back to the authored still")
	check(is_equal_approx(idle.self_modulate.a, 1.0), "animation fallback restores rogue sprite alpha")
	visual.rogue_idle_frames = ROGUE_IDLE
	visual.rogue_buff_frames = ROGUE_BUFF
	visual.rogue_death_frames = ROGUE_DEATH
	visual.sample_death((0.65 + 0.25 + 0.40) / visual.death_duration())
	check(is_equal_approx(idle.self_modulate.a, 0.5), "missing-still fallback fixture first enters rogue fade")
	var still_texture := rogue_still.texture
	rogue_still.texture = null
	visual.sync_scene_art()
	var body := visual.get_node("ArtRoot/BodySprite") as Sprite2D
	check(not idle.visible and body.visible and not visual.is_processing() and is_equal_approx(idle.self_modulate.a, 1.0),
		"missing rogue still and animation resources use the generic body fallback")
	rogue_still.texture = still_texture
	visual.sync_scene_art()
	visual.retire_view()
	mage_values = _values(&"mage", Faction.Type.PLAYER, 41)
	check(visual.apply_view(mage_values, config), "retired instance accepts mage fallback values")
	var mage_idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	var mage_still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	check(not mage_idle.visible and not mage_still.visible and (visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible,
		"same id reused by another class cannot retain a rogue idle sprite")


func _capture(name: String) -> void:
	if captures.is_empty(): return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK, "capture " + name)
