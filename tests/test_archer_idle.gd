extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const ARCHER_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/archer_idle_v1/idle_frames.tres")

var passed: int = 0
var failed: int = 0
var captures: String = ""


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
		printerr("FAIL ARCHER IDLE: " + label)


func _values(faction: Faction.Type, unit_id: int = 73) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {
		"cell": Vector2i(2, 3), "half_steps": 0,
		"unit": {"id": unit_id, "faction": int(faction), "name": "Лучник", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": &"archer", "selected": false, "inspected": false, "hovered": false,
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
	check(visual != null, "art-trial visual instantiates")
	if visual == null:
		quit(1)
		return
	viewport.add_child(visual)
	await process_frame
	_test_resource(visual)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 32.0
	config.origin_offset = Vector2(320.0, 48.0)
	var values := _values(Faction.Type.PLAYER)
	check(visual.apply_view(values, config), "allied Archer DTO applies")
	visual.set_process(false)
	var idle := visual.get_node("ArtRoot/ArcherIdleSprite") as Sprite2D
	var still := visual.get_node("ArtRoot/PlayerArcherSprite") as Sprite2D
	var enemy_still := visual.get_node("ArtRoot/EnemyArcherSprite") as Sprite2D
	var art := visual.get_node("ArtRoot") as Node2D
	check(idle.visible and not still.visible and not enemy_still.visible,
		"idle replaces the allied Archer still and leaves enemy art hidden")
	check(art.scale.is_equal_approx(Vector2(0.6400003306666667, 0.6400003306666667))
		and idle.scale == Vector2.ONE and still.scale == Vector2.ONE
		and idle.position.is_equal_approx(Vector2(-78.9576315297, -97.3771110405)),
		"allied Archer keeps authored scale, anchor, and native sprite scale")
	var allied_pick: PackedVector2Array = visual.surface_polygons()[0]
	var pick_scale: float = 0.64
	check(allied_pick.size() == 4
		and allied_pick[0].is_equal_approx(visual.get_visual_offset() + Vector2(-49, -81) * pick_scale)
		and allied_pick[2].is_equal_approx(visual.get_visual_offset() + Vector2(49, 11) * pick_scale),
		"Archer picking polygon covers the scaled authored body bounds")
	var material := still.material as ShaderMaterial
	check(material != null and material.get_shader_parameter("native_size") == Vector2(128, 128)
		and material.get_shader_parameter("cloth_enabled") == false,
		"Archer keeps native-size sampling and does not inherit a cloth palette")
	visual.set_cloth_palette(2)
	for sprite: Sprite2D in [still, enemy_still, idle]:
		check(not bool((sprite.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
			"shared clothing choice leaves Archer source colors intact: " + String(sprite.name))
	visual.idle_clock.configure(0, 24, 24)
	visual._process(0.0)
	check(idle.texture == ARCHER_IDLE.get_frame_texture(&"idle", 0), "idle starts on its first authored frame")
	for step: int in range(1, 13):
		visual._process(13.0 / 60.0)
		check(idle.texture == ARCHER_IDLE.get_frame_texture(&"idle", step % 12),
			"13 authored ticks sample/wrap frame %02d" % (step % 12 + 1))
	check(is_equal_approx(visual.idle_clock.get_elapsed(), DefenderIdleClock.CYCLE_DURATION)
		and idle.texture == ARCHER_IDLE.get_frame_texture(&"idle", 0),
		"idle returns to its first frame after exactly 2.6 seconds")
	await _capture(viewport, "archer-idle-allied")
	var elapsed := visual.idle_clock.get_elapsed()
	visual.frozen = true
	visual.sync_scene_art()
	visual._process(0.5)
	check(not idle.visible and still.visible and visual.idle_clock.get_elapsed() == elapsed,
		"frozen Archer holds its still without accruing idle time")
	visual.frozen = false
	visual.sync_scene_art()
	check(idle.visible and visual.idle_clock.get_elapsed() == elapsed, "unfreeze resumes the same phase")
	for status: StringName in [&"stunned", &"summon_pending"]:
		visual.set(status, true)
		visual.sync_scene_art()
		var status_elapsed := visual.idle_clock.get_elapsed()
		visual._process(0.2)
		check(not idle.visible and still.visible and visual.idle_clock.get_elapsed() == status_elapsed,
			"status " + String(status) + " pauses Archer idle on its still")
		visual.set(status, false)
		visual.sync_scene_art()
	visual.ambient_animation_paused = true
	visual.sync_scene_art()
	var presentation_elapsed := visual.idle_clock.get_elapsed()
	visual._process(0.2)
	check(not idle.visible and visual.idle_clock.get_elapsed() == presentation_elapsed,
		"presentation pause suspends Archer without accumulating time")
	visual.ambient_animation_paused = false
	visual.sync_scene_art()
	var preserved_elapsed := visual.idle_clock.get_elapsed()
	var resized_config := config.duplicate() as IsoGridConfig
	resized_config.tile_size = Vector2(136.0, 102.0)
	check(visual.apply_view(values.duplicate(true), resized_config)
		and visual.idle_clock.get_elapsed() == preserved_elapsed,
		"same-unit resize preserves Archer clock phase")
	config = resized_config
	visual.action_offset = Vector2(2.0, 0.0)
	visual.sync_scene_art()
	check(not idle.visible and still.visible, "action pose suspends Archer idle")
	visual.reset_view_pose()
	visual.sync_scene_art()
	check(idle.visible, "pose reset restores Archer idle")
	for pose: StringName in [&"presentation_offset", &"presentation_lift", &"fall_drop", &"landing_compression"]:
		if pose == &"presentation_offset": visual.set(pose, Vector2(3.0, 0.0))
		elif pose == &"landing_compression": visual.set(pose, 0.2)
		else: visual.set(pose, 4.0)
		_check_paused_pose(visual, idle, still, String(pose))
		visual.reset_view_pose()
		visual.sync_scene_art()
	visual.hide()
	_check_hidden_or_nonunit(visual, idle, "hidden visual")
	visual.show()
	visual.sync_scene_art()
	var previous_role := visual.role
	visual.role = BattleDemoIsoVisual.Role.WALL
	visual.sync_scene_art()
	_check_hidden_or_nonunit(visual, idle, "non-unit role")
	visual.role = previous_role
	visual.sync_scene_art()
	visual.death_progress = 0.2
	_check_paused_pose(visual, idle, still, "generic death presentation")
	visual.reset_view_pose()
	visual.sync_scene_art()
	check(not visual.can_play_buff() and not visual.can_play_death(),
		"Archer does not borrow another class's buff or death clip")
	visual.archer_idle_frames = null
	visual.sync_scene_art()
	check(not idle.visible and still.visible and not visual.is_processing(),
		"missing Archer animation falls back to the authored still")
	visual.archer_idle_frames = ARCHER_IDLE
	visual.sync_scene_art()
	check(idle.visible and not still.visible, "restored Archer animation resumes its owned resource")
	var zero_speed_frames := ARCHER_IDLE.duplicate() as SpriteFrames
	zero_speed_frames.set_animation_speed(&"idle", 0.0)
	visual.archer_idle_frames = zero_speed_frames
	visual.sync_scene_art()
	check(not idle.visible and still.visible and not visual.is_processing(),
		"zero-speed Archer animation falls back to the authored still")
	visual.archer_idle_frames = ARCHER_IDLE
	visual.sync_scene_art()
	var warrior_values := _values(Faction.Type.PLAYER, 73)
	warrior_values["visual_class_id"] = &"warrior"
	check(visual.apply_view(warrior_values, config) and not idle.visible,
		"same-unit switch to warrior hides stale Archer animation")
	check(visual.apply_view(_values(Faction.Type.PLAYER, 73), config) and idle.visible and not still.visible,
		"same-unit return to Archer selects its idle resource without stale action art")
	values["unit"]["faction"] = int(Faction.Type.ENEMY)
	values["unit"]["id"] = 74
	check(visual.apply_view(values, config), "enemy Archer DTO applies to reused visual")
	visual.set_process(false)
	check(idle.visible and idle.scale == Vector2(-1, 1)
		and idle.position.is_equal_approx(Vector2(78.9576315297, -97.3771110405))
		and not enemy_still.visible and not still.visible,
		"enemy idle mirrors around the Archer anchor and hides both still sprites")
	await _capture(viewport, "archer-idle-enemy")
	visual.frozen = true
	visual.sync_scene_art()
	check(not idle.visible and enemy_still.visible, "paused enemy Archer reveals the mirrored still")
	visual.frozen = false
	visual.sync_scene_art()
	visual.retire_view()
	check(not idle.visible and visual.idle_clock.get_elapsed() == 0.0,
		"retirement hides the animation and resets its clock")
	visual.queue_free()
	viewport.queue_free()
	await process_frame
	print("ARCHER IDLE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _check_paused_pose(visual: BattleDefenderIdleVisual, idle: Sprite2D, still: Sprite2D, label: String) -> void:
	var before := visual.idle_clock.get_elapsed()
	visual._process(0.2)
	check(not idle.visible and still.visible and visual.idle_clock.get_elapsed() == before,
		label + " suspends idle without accruing time")


func _check_hidden_or_nonunit(visual: BattleDefenderIdleVisual, idle: Sprite2D, label: String) -> void:
	var before := visual.idle_clock.get_elapsed()
	visual._process(0.2)
	check(not idle.visible and visual.idle_clock.get_elapsed() == before, label + " does not advance idle")


func _capture(viewport: SubViewport, name: String) -> void:
	if captures.is_empty(): return
	DirAccess.make_dir_recursive_absolute(captures)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK,
		"capture " + name)


func _test_resource(visual: BattleDefenderIdleVisual) -> void:
	var names := ARCHER_IDLE.get_animation_names()
	check(visual.archer_idle_frames == ARCHER_IDLE and names.size() == 1 and names[0] == &"idle"
		and ARCHER_IDLE.get_animation_loop(&"idle") and ARCHER_IDLE.get_animation_speed(&"idle") == 60.0
		and ARCHER_IDLE.get_frame_count(&"idle") == 12,
		"idle resource has one looping 12-frame clip sampled at 60 ticks per second")
	var cycle_seconds: float = 0.0
	for frame: int in 12:
		check(ARCHER_IDLE.get_frame_duration(&"idle", frame) == 13.0,
			"idle frame %02d lasts 13 ticks" % (frame + 1))
		cycle_seconds += ARCHER_IDLE.get_frame_duration(&"idle", frame) / ARCHER_IDLE.get_animation_speed(&"idle")
	check(is_equal_approx(cycle_seconds, 2.6), "idle cycle totals exactly 2.6 seconds")
