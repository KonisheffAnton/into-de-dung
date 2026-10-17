extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
var passed: int = 0
var failed: int = 0
var output: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ROUND SHADOW AUDIT: " + label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var gallery := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	# Непрозрачный нейтральный фон делает полупрозрачные пятна видимыми в галерее.
	gallery.fill(Color("596047"))
	var index: int = 0
	for class_id: StringName in [&"warrior", &"rogue", &"archer", &"mage"]:
		for faction: Faction.Type in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
			await _fixture(class_id, faction, gallery, index)
			index += 1
	check(gallery.save_png(output.path_join("all-classes.png")) == OK, "save all-class render pairs")
	await _battle()
	print("ROUND SHADOW AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _fixture(class_id: StringName, faction: Faction.Type, gallery: Image, index: int) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var visual := UNIT.instantiate() as BattleDefenderIdleVisual
	# Доска задаёт роль до _ready; standalone-fixture повторяет этот lifecycle.
	visual.role = BattleDemoIsoVisual.Role.UNIT
	view.add_child(visual)
	await process_frame
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.origin_offset = Vector2(128, 160)
	var values := _values(class_id, faction)
	visual.apply_view(values, config)
	visual.ambient_animation_paused = true
	visual.set_process(false)
	var shadow := visual.get_node_or_null("GroundShadow") as Node2D
	check(shadow != null and shadow.visible, "%s/%d has a visible shadow" % [class_id, faction])
	if shadow == null:
		view.queue_free()
		await process_frame
		return
	visual.show_ground_shadow = false
	visual.sync_scene_art()
	var before := await _capture(view)
	visual.show_ground_shadow = true
	visual.sync_scene_art()
	var after := await _capture(view)
	var opaque_changed: int = 0
	var outside: int = 0
	var changed: int = 0
	var center := shadow.global_position
	var radius := shadow.scale * visual.ground_shadow_radius + Vector2.ONE * 1.5
	for y: int in 256:
		for x: int in 256:
			var old := before.get_pixel(x, y)
			var next := after.get_pixel(x, y)
			if old == next: continue
			changed += 1
			if old.a >= 0.999: opaque_changed += 1
			var normalized := (Vector2(x + 0.5, y + 0.5) - center) / radius
			if normalized.length_squared() > 1.0: outside += 1
	check(changed > 30 and outside == 0, "%s/%d changes only its small oval (%d pixels, outside=%d)" % [class_id, faction, changed, outside])
	check(opaque_changed == 0, "%s/%d opaque character/HUD pixels unchanged (%d)" % [class_id, faction, opaque_changed])
	var cell := Vector2i((index % 2) * 512, (index / 2) * 256)
	gallery.blend_rect(before, Rect2i(0, 0, 256, 256), cell)
	gallery.blend_rect(after, Rect2i(0, 0, 256, 256), cell + Vector2i(256, 0))
	visual.show_ground_shadow = false
	visual.sync_scene_art()
	var restored := await _capture(view)
	check(restored.get_data() == before.get_data(), "%s/%d disabling restores exact previous render" % [class_id, faction])
	view.queue_free()
	await process_frame


func _battle() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1600, 1200)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var session := HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	var demo := BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	view.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var baseline := _snapshot(session)
	var board := demo.board_view
	board.zoom_camera(0.9, board.size * 0.5)
	board.pan_camera(Vector2(0, -50))
	var selected: BattleManagedUnitVisual
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		visual.ambient_animation_paused = true
		visual.set_process(false)
		visual.show_ground_shadow = false
		visual.sync_scene_art()
		if visual.unit.faction == Faction.Type.PLAYER and selected == null: selected = visual
	var before := await _capture(view)
	check(before.save_png(output.path_join("battle-before.png")) == OK, "save battlefield without shadows")
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		visual.show_ground_shadow = true
		visual.sync_scene_art()
	var after := await _capture(view)
	check(after.save_png(output.path_join("battle.png")) == OK, "save actual battlefield with shadows")
	check(before.get_data() != after.get_data(), "real battle visibly changes when shadows are enabled")
	check(selected != null, "real battle supplies an allied movement fixture")
	if selected != null:
		var shadow := selected.get_node("GroundShadow") as Node2D
		var shadow_id := shadow.get_instance_id()
		var from := selected.grid_anchor
		var to := from + Vector2i(1, 0)
		var from_point := IsoGridUtils.grid_to_screen(from, board.grid_config, 0)
		var to_point := IsoGridUtils.grid_to_screen(to, board.grid_config, 0)
		for p: float in [0.25, 0.5, 0.75]:
			board._presentation_motion(p, selected.unit.id, from, to)
			var surface_height := -0.5 * lerpf(board._view_height_steps(from), board._view_height_steps(to), p) * board.grid_config.height_step
			check((selected.position + shadow.position).is_equal_approx(from_point.lerp(to_point, p) + Vector2(0, surface_height)), "movement shadow follows interpolated ground at " + str(p))
		var prior_position := shadow.position
		var prior_scale := shadow.scale
		selected.action_offset = Vector2(18, -10)
		selected.landing_compression = 0.2
		selected.death_progress = 0.3
		check(shadow.position == prior_position and shadow.scale == prior_scale and shadow.rotation == 0.0, "attack/death/landing deformation leaves ground oval unchanged")
		board.refresh()
		check(is_instance_valid(shadow) and shadow.get_instance_id() == shadow_id, "refresh reuses the shadow node")
		var old_size := board.size
		board.size += Vector2(10, 10)
		board._rescale_layout()
		check(is_instance_valid(shadow) and shadow.get_instance_id() == shadow_id, "resize reuses the shadow node")
		board.size = old_size
		board._rescale_layout()
	check(_snapshot(session) == baseline, "shadow capture/movement/refresh preserve state, RNG, counters and revision")
	demo.queue_free()
	await process_frame
	view.queue_free()
	await process_frame


func _capture(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _values(class_id: StringName, faction: Faction.Type) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {"cell": Vector2i.ZERO, "half_steps": 0,
		"unit": {"id": 73, "faction": int(faction), "name": "", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": class_id, "selected": true, "inspected": false, "hovered": true,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}
