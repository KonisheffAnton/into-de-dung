extends SceneTree

const CURRENT_BATTLE = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL DEFENDER IDLE: " + label)


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var bundle := HeroHubBattleFactory.create(profile)
	var session := bundle.session as BattleCoreReactionsSession
	var demo := CURRENT_BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var visual: BattleDefenderIdleVisual
	for item: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		if item.unit.alive and item.unit.faction == Faction.Type.PLAYER and item.visual_class_id == &"warrior":
			visual = item as BattleDefenderIdleVisual
			break
	check(visual != null, "real expedition routes its allied Defender to idle visual")
	if visual != null:
		await _check_visual(demo, visual, session)
		await _check_playback(demo, visual, session)
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("DEFENDER IDLE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _check_visual(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual, session: BattleCoreReactionsSession) -> void:
	var baseline := _snapshot(session)
	var still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
	var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	var art := visual.get_node("ArtRoot") as Node2D
	check(idle.visible and not still.visible and visual.is_processing(), "idle replaces only visible allied warrior art")
	check(visual.idle_frames.get_frame_count(&"vertical") == 12 and visual.idle_frames.get_frame_count(&"sway") == 12,
		"both selected twelve-frame clips are packaged")
	check(idle.position.is_equal_approx(Vector2(-69.42, -90.14)) and idle.scale == Vector2.ONE,
		"128px source canvas retains 16px margin and original support")
	check((idle.position + Vector2(25, 25)).is_equal_approx(still.position), "reference top-left agrees with unchanged authored still")
	check(is_equal_approx(visual.warrior_art_scale, 0.8), "existing art scale remains 80 percent")
	var anchor := (visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform
	var pick := visual.warrior_pick_rect
	var still_transform := still.transform
	visual.set_process(false)
	var first_texture := idle.texture
	visual._process(0.61)
	check(idle.texture != first_texture, "idle advances actual displayed textures")
	var elapsed := visual.idle_clock.get_elapsed()
	var texture := idle.texture
	var identity := visual.get_instance_id()
	demo.board_view.refresh()
	visual.set_process(false)
	check(visual.get_instance_id() == identity and visual.idle_clock.get_elapsed() == elapsed and idle.texture == texture,
		"fresh publication preserves root, idle phase and current frame")
	demo.board_view.size += Vector2(17, 9)
	demo.board_view._rescale_layout()
	visual.set_process(false)
	check(visual.idle_clock.get_elapsed() == elapsed and idle.texture == texture, "resize does not restart idle")
	check(still.transform == still_transform and visual.warrior_pick_rect == pick
		and (visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform == anchor,
		"idle and resize preserve authored still, picking and local effect anchor")
	for property: StringName in [&"frozen", &"stunned", &"summon_pending"]:
		visual.set(property, true)
		visual.sync_scene_art()
		check(not idle.visible and still.visible and not visual.is_processing(), "status suspends idle: " + String(property))
		visual.set(property, false)
		visual.sync_scene_art()
		visual.set_process(false)
		check(idle.visible and visual.idle_clock.get_elapsed() == elapsed, "status release resumes same phase: " + String(property))
	visual.action_offset = Vector2(8, -3)
	check(not idle.visible and still.visible, "action pose immediately suspends idle")
	visual.reset_view_pose()
	visual.set_process(false)
	check(idle.visible and art.position == visual.get_visual_offset(), "pose reset restores idle without competing transforms")
	visual.death_progress = 0.5
	check(not idle.visible and still.visible, "death pose suppresses idle")
	visual.reset_view_pose()
	visual.set_process(false)
	var faction := visual.unit.faction
	visual.unit.faction = Faction.Type.ENEMY
	visual.sync_scene_art()
	check(not idle.visible and (visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible, "enemy retains original mirrored still")
	visual.unit.faction = faction
	visual.visual_class_id = &"rogue"
	visual.sync_scene_art()
	check(not idle.visible, "other classes never inherit Defender idle")
	visual.visual_class_id = &"warrior"
	visual.sync_scene_art()
	visual.set_process(false)
	var still_texture := still.texture
	still.texture = null
	visual.sync_scene_art()
	check(not idle.visible and (visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "missing still preserves normal fallback")
	still.texture = still_texture
	visual.sync_scene_art()
	visual.set_process(false)
	for clip: StringName in [&"vertical", &"sway"]:
		var count := visual.idle_clock.get_normal_cycle_count()
		for frame: int in range(12):
			visual.idle_clock.configure(0, count, count)
			visual.idle_clock.advance((float(count) * 2.4 if clip == &"sway" else 0.0) + frame * 0.2)
			visual._process(0.0)
			check(idle.texture == visual.idle_frames.get_frame_texture(clip, frame), "authored texture order " + String(clip) + str(frame))
			if frame in [0, 3, 6, 9]: await _capture(String(clip) + "-" + str(frame), visual)
	visual.idle_clock.configure(0, 24, 24)
	visual._process(57.6)
	check(visual.idle_clock.is_rare(), "rare variant enters after normal cycles")
	visual._process(2.4)
	check(not visual.idle_clock.is_rare(), "rare variant returns automatically to normal")
	check(_snapshot(session) == baseline, "idle, status probes, rare switch and resize leave live state/RNG/counters unchanged")
	var second := UNIT.instantiate() as BattleDefenderIdleVisual
	viewport.add_child(second)
	var values := demo.board_view._unit_view_values(demo.board_view._view_units[0])
	values.visual_class_id = &"warrior"
	values.unit.faction = int(Faction.Type.PLAYER)
	second.apply_view(values, demo.board_view.grid_config)
	second.set_process(false)
	second._process(1.0)
	second.retire_view()
	check(not second.is_processing() and not (second.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D).visible
		and second.idle_clock.get_elapsed() == 0.0, "retirement drops idle lifecycle state")
	second.apply_view(values, demo.board_view.grid_config)
	check(second.idle_clock.get_elapsed() == 0.0, "new lifecycle does not reuse elapsed idle time")
	second.queue_free()
	await process_frame


func _check_playback(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual, session: BattleCoreReactionsSession) -> void:
	var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	var still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
	demo.board_view.execution_pending = true
	check(not idle.visible and still.visible and not visual.is_processing(), "worker pending synchronously suspends idle")
	demo.board_view.execution_pending = false
	check(idle.visible, "worker release resumes idle")
	# Технический кадр проверяет паузу ещё до ненулевого offset и для всех целей.
	var state := ActionPresentationState.capture(session.state)
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	var frames: Array[Dictionary] = [{"events": [], "step": {}, "after": state}]
	var baseline := _snapshot(session)
	player.play(demo.board_view, state, frames, state)
	check(player.active and not idle.visible and still.visible, "playback pauses idle at t=0 before any combat pose")
	player._tween.pause()
	var elapsed := visual.idle_clock.get_elapsed()
	demo.board_view._rescale_layout()
	check(not idle.visible and visual.idle_clock.get_elapsed() == elapsed, "resize during playback cannot resume idle")
	player.set_speed(3.0)
	player.skip()
	check(not player.active and idle.visible and visual.idle_clock.get_elapsed() == elapsed, "skip releases pause without advancing idle")
	player.play(demo.board_view, state, frames, state)
	player.cancel()
	check(idle.visible and not player.active, "cancel releases idle pause")
	player.play(demo.board_view, state, frames, state)
	while player.active: await process_frame
	check(idle.visible, "normal playback completion releases idle pause")
	check(_snapshot(session) == baseline, "presentation-only pause paths leave live state/RNG/counters unchanged")
	player.queue_free()
	await process_frame


func _capture(label: String, visual: BattleDefenderIdleVisual) -> void:
	if captures.is_empty(): return
	DirAccess.make_dir_recursive_absolute(captures)
	visual.set_process(false)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
