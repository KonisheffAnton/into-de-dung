extends SceneTree

const CURRENT_BATTLE = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const DefenderClothRenderProbe = preload("res://tests/fixtures/defender_cloth_render_probe.gd")
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
		printerr("FAIL DEFENDER CLOTH PALETTE: " + label)


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
	var session := HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	var demo := CURRENT_BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var visual := _find_visual(demo, Faction.Type.PLAYER, &"warrior")
	var enemy := _find_visual(demo, Faction.Type.ENEMY, &"warrior")
	var other := _find_nonwarrior(demo)
	check(visual != null, "seed 9404 routes an allied Defender to its visual")
	check(enemy != null and other != null, "fixture contains enemy Defender and non-warrior visuals")
	if visual != null:
		_check_selector(demo, visual, enemy, other, session)
		_check_all_mask_frames(visual)
		_check_buff_and_death_palette(visual)
		_check_disabled_masks(visual, enemy, other)
		await _check_layout(demo)
		_check_default_and_invalid(visual)
		check(_snapshot(session) == _snapshot_before_cosmetics, "cosmetic palette operations preserve battle state, RNG and counters")
		demo._cloth_palette.select(2)
		demo._cloth_palette.item_selected.emit(2)
	if DisplayServer.get_name() != "headless": await _run_render_probe()
	_run_execution_detached(demo, visual, session)
	# Вернуть синюю одежду и проверить reset на той же доске после detached ownership.
	demo._cloth_palette.select(2)
	demo._cloth_palette.item_selected.emit(2)
	var fresh_board := BattleDemoBoard.new()
	check(fresh_board.defender_cloth_palette == 0, "new board starts at original palette")
	fresh_board.free()
	await _check_real_reset()
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("DEFENDER CLOTH PALETTE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


var _snapshot_before_cosmetics: Dictionary = {}


func _find_visual(demo: BattleDemo, faction: Faction.Type, visual_class: StringName) -> BattleDefenderIdleVisual:
	for item: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		if item.unit.alive and item.unit.faction == faction and item.visual_class_id == visual_class:
			return item as BattleDefenderIdleVisual
	return null


func _check_real_reset() -> void:
	var demo := load("res://scenes/demo/art_trial_battle.tscn").instantiate() as BattleDemo
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var visual := _find_visual(demo, Faction.Type.PLAYER, &"warrior")
	check(visual != null, "art trial scene exposes an allied Defender before reset")
	if visual != null:
		var board_identity := demo.board_view.get_instance_id()
		demo.board_view.set_defender_cloth_palette(3)
		demo._cloth_palette.select(3)
		demo._cloth_palette.item_selected.emit(3)
		demo.reset_demo()
		await process_frame
		visual = _find_visual(demo, Faction.Type.PLAYER, &"warrior")
		var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D if visual != null else null
		check(demo.board_view.get_instance_id() == board_identity and demo.board_view.defender_cloth_palette == 3
			and demo._cloth_palette.selected == 3 and visual != null and visual.cloth_palette == 3
			and idle != null and bool((idle.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
			"real BattleDemo reset retains selected palette and restores it on the allied Defender")
	demo.queue_free()
	await process_frame


func _find_nonwarrior(demo: HeroHubBattleView) -> BattleManagedUnitVisual:
	for item: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		if item.unit.alive and item.visual_class_id not in [&"warrior", &"rogue"]: return item
	return null


func _check_selector(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual,
		enemy: BattleDefenderIdleVisual, other: BattleManagedUnitVisual, session: BattleCoreReactionsSession) -> void:
	var selector := demo._cloth_palette
	check(selector != null and selector.get_item_count() == 7 and selector.selected == 0,
		"authored selector defaults to original and has seven choices")
	check(demo.board_view.defender_cloth_palette == 0 and not _cloth_materials_enabled(visual),
		"new board and allied Defender begin with original clothing")
	check(selector != null and selector.get_signal_connection_list(&"item_selected").size() == 1,
		"selector has one item_selected connection")
	if selector == null or enemy == null or other == null: return
	for index: int in DefenderClothPalette.count():
		check(selector.get_item_text(index) == "Одежда: " + DefenderClothPalette.label(index),
			"choice is labeled as clothing " + str(index))
	var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	var player_still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
	var enemy_idle := enemy.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	var other_enabled := _cloth_materials_enabled(other)
	var ally_material_ids: Array[int] = []
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite"]:
		var sprite := visual.get_node(path) as Sprite2D
		ally_material_ids.append((sprite.material as ShaderMaterial).get_instance_id())
	check(ally_material_ids.size() == 3 and ally_material_ids[0] != ally_material_ids[1]
		and ally_material_ids[0] != ally_material_ids[2] and ally_material_ids[1] != ally_material_ids[2],
		"each Defender cloth shader material belongs to its sprite")
	var enemy_material_ids: Array[int] = []
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite"]:
		enemy_material_ids.append(((enemy.get_node(path) as Sprite2D).material as ShaderMaterial).get_instance_id())
	check(ally_material_ids[0] != enemy_material_ids[0] and ally_material_ids[2] != enemy_material_ids[2],
		"separate Defender instances do not share cloth materials")
	visual.set_process(false)
	var identity := visual.get_instance_id()
	var material_ids := ally_material_ids.duplicate()
	var texture := idle.texture
	var elapsed := visual.idle_clock.get_elapsed()
	var processing := visual.is_processing()
	_snapshot_before_cosmetics = _snapshot(session)
	selector.select(2)
	selector.item_selected.emit(2)
	check(demo.board_view.defender_cloth_palette == 2 and visual.cloth_palette == 2,
		"blue choice routes to board and allied visual")
	check(bool((idle.material as ShaderMaterial).get_shader_parameter("cloth_enabled")), "allied idle material enables cloth mask")
	check(not bool((enemy_idle.material as ShaderMaterial).get_shader_parameter("cloth_enabled")), "enemy Defender stays original")
	check(not _cloth_materials_enabled(other), "non-warrior visual stays original")
	check(visual.get_instance_id() == identity and idle.texture == texture and visual.idle_clock.get_elapsed() == elapsed
		and visual.is_processing() == processing, "selection preserves node, current frame, idle phase and process state")
	check(material_ids == _material_ids(visual), "selection does not replace per-sprite shader materials")
	demo.board_view.refresh()
	check(demo.board_view.defender_cloth_palette == 2 and visual.get_instance_id() == identity,
		"board refresh retains choice and Defender node")
	var old_size := demo.board_view.size
	demo.board_view.size += Vector2(19, 11)
	demo.board_view._rescale_layout()
	check(demo.board_view.defender_cloth_palette == 2 and visual.get_instance_id() == identity,
		"board resize retains choice and Defender node")
	demo.board_view.size = old_size
	demo.board_view._rescale_layout()
	check(player_still.material != enemy.get_node("ArtRoot/PlayerWarriorSprite").material,
		"ally and enemy still materials remain instance-local")


func _cloth_materials_enabled(visual: BattleManagedUnitVisual) -> bool:
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite"]:
		var sprite := visual.get_node_or_null(path) as Sprite2D
		if sprite != null and sprite.material is ShaderMaterial:
			if bool((sprite.material as ShaderMaterial).get_shader_parameter("cloth_enabled")): return true
	return false


func _check_all_mask_frames(visual: BattleDefenderIdleVisual) -> void:
	var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	visual.set_cloth_palette(2)
	var checked := 0
	for clip: StringName in [&"vertical", &"sway"]:
		for frame: int in visual.idle_frames.get_frame_count(clip):
			visual._apply_clip_frame(visual.idle_frames, clip, _frame_elapsed(visual.idle_frames, clip, frame))
			check(_mask_matches(idle), "idle mask matches texture slot " + String(clip) + ":" + str(frame))
			checked += 1
	for frames: SpriteFrames in [visual.buff_frames, visual.death_frames]:
		var clip: StringName = &"buff" if frames == visual.buff_frames else &"death"
		for frame: int in frames.get_frame_count(clip):
			visual._apply_clip_frame(frames, clip, _frame_elapsed(frames, clip, frame))
			check(_mask_matches(idle), "action mask matches texture slot " + String(clip) + ":" + str(frame))
			checked += 1
	check(checked == 90, "all 90 authored idle, buff and death frames use matching mask origins")
	visual._buff_elapsed = -1.0
	visual._death_active = false
	visual.sync_scene_art()


func _frame_elapsed(frames: SpriteFrames, clip: StringName, target: int) -> float:
	var elapsed := 0.0
	for frame: int in target: elapsed += frames.get_frame_duration(clip, frame)
	return elapsed / frames.get_animation_speed(clip)


func _mask_matches(sprite: Sprite2D) -> bool:
	var slot := DefenderClothPalette.mask_slot(sprite.texture)
	var material := sprite.material as ShaderMaterial
	return slot >= 0 and material != null and bool(material.get_shader_parameter("cloth_enabled")) \
		and material.get_shader_parameter("cloth_mask_origin") == DefenderClothPalette.mask_origin(slot)


func _check_buff_and_death_palette(visual: BattleDefenderIdleVisual) -> void:
	var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
	visual.set_process(false)
	visual.set_cloth_palette(3)
	visual.sample_buff(0.7)
	var buff_texture := idle.texture
	var buff_elapsed := visual._buff_elapsed
	visual.set_cloth_palette(4)
	check(idle.texture == buff_texture and visual._buff_elapsed == buff_elapsed and _mask_matches(idle),
		"palette change during buff preserves its frame and elapsed time")
	visual.clear_buff()
	visual.sample_death(0.65)
	visual.sync_scene_art()
	var death_texture := idle.texture
	var death_progress := visual.death_progress
	visual.set_cloth_palette(5)
	check(idle.texture == death_texture and visual.death_progress == death_progress and _mask_matches(idle),
		"palette change during death preserves its frame and progress")
	visual.death_progress = 0.0
	visual.reset_view_pose()
	visual.sync_scene_art()
	check(_mask_matches(idle) and visual.is_processing()
		and bool(((visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D).material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
		"pose reset restores selected palette on idle and still art")
	visual.set_cloth_palette(0)
	check(not bool((idle.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
		"original palette disables cloth mask")
	check(idle.visible and not (visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D).visible,
		"cleared action pose restores idle over the authored still")


func _check_disabled_masks(ally: BattleDefenderIdleVisual, enemy: BattleDefenderIdleVisual,
		other: BattleManagedUnitVisual) -> void:
	ally.set_cloth_palette(2)
	enemy.set_cloth_palette(2)
	check(not _cloth_materials_enabled(enemy), "enemy palette remains disabled even when board sends same index")
	check(not _cloth_materials_enabled(other), "other visual classes have no cloth mask")
	var custom_texture := GradientTexture2D.new()
	check(DefenderClothPalette.mask_slot(custom_texture) == -1, "unknown custom texture has no mask slot")
	custom_texture = null


func _check_layout(demo: HeroHubBattleView) -> void:
	var selector := demo._cloth_palette
	for height: int in [850, 720]:
		viewport.size = Vector2i(1280, height)
		await process_frame
		var rect := selector.get_global_rect()
		check(rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport.size.x
			and rect.end.y <= viewport.size.y, "selector fits 1280x%d viewport" % height)
		var phase := selector.get_parent() as HBoxContainer
		var index := selector.get_index()
		if index > 0:
			var previous := phase.get_child(index - 1) as Control
			if previous.visible:
				check(not rect.intersects(previous.get_global_rect()), "selector does not overlap previous phase control at %d" % height)
		if index + 1 < phase.get_child_count():
			var next := phase.get_child(index + 1) as Control
			if next.visible:
				check(not rect.intersects(next.get_global_rect()), "selector does not overlap next phase control at %d" % height)
	viewport.size = Vector2i(1280, 850)
	await process_frame


func _check_default_and_invalid(visual: BattleDefenderIdleVisual) -> void:
	visual.set_cloth_palette(2)
	visual.set_cloth_palette(99)
	check(visual.cloth_palette == 0 and not _cloth_materials_enabled(visual), "invalid index resets to original")
	check(DefenderClothPalette.valid_index(-1) == 0 and DefenderClothPalette.valid_index(7) == 0,
		"definition clamps out-of-range indices to original")


func _run_execution_detached(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual,
		session: BattleCoreReactionsSession) -> void:
	var baseline := _snapshot(session)
	demo.board_view.session = null
	demo.board_view.execution_pending = true
	demo.board_view.set_defender_cloth_palette(6)
	check(demo.board_view.defender_cloth_palette == 6 and visual.cloth_palette == 6,
		"palette operation remains available while execution owns session")
	check(_snapshot(session) == baseline, "detached palette operation does not touch live state or RNG")
	demo.board_view.execution_pending = false
	demo.board_view.session = session


func _run_render_probe() -> void:
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png(captures.path_join("cloth-battle.png")) == OK,
			"capture selected blue palette in current battle")
	var result: Dictionary = await DefenderClothRenderProbe.run(self, captures)
	passed += int(result.get("passed", 0))
	failed += int(result.get("failed", 0))


func _material_ids(visual: BattleDefenderIdleVisual) -> Array[int]:
	var result: Array[int] = []
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite"]:
		result.append(((visual.get_node(path) as Sprite2D).material as ShaderMaterial).get_instance_id())
	return result
