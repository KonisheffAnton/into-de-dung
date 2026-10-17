extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
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
		printerr("FAIL ARCHER PLACEMENT: " + label)

func _capture(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var gallery := Image.create(1024, 768, false, Image.FORMAT_RGBA8)
	gallery.fill(Color("596047"))
	for faction: Faction.Type in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
		await _fixture(faction, gallery)
	check(gallery.save_png(output.path_join("comparison.png")) == OK, "save before/after gallery")
	await _battle()
	print("ARCHER PLACEMENT AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _fixture(faction: Faction.Type, gallery: Image) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var visual := UNIT.instantiate() as BattleDefenderIdleVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	view.add_child(visual)
	await process_frame
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(256, 192)
	config.origin_offset = Vector2(128, 160)
	var statuses: Array[Dictionary] = []
	visual.apply_view({"cell": Vector2i.ZERO, "half_steps": 0,
		"unit": {"id": 73, "faction": int(faction), "name": "", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": &"archer", "selected": true, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}, config)
	visual.set_process(false)
	visual.idle_clock.configure(0, 24, 24)
	visual._process(0.0)
	var idle := visual.get_node("ArtRoot/ArcherIdleSprite") as Sprite2D
	var shadow := visual.get_node("GroundShadow") as Node2D
	var root_transform := visual.transform
	var shadow_transform := shadow.transform
	var new_position := idle.position
	var old_position := Vector2(-78.9576315297, -97.3771110405)
	if faction == Faction.Type.ENEMY: old_position.x *= -1
	var column: int = 0 if faction == Faction.Type.PLAYER else 2
	for frame: int in 12:
		check(idle.texture == visual.archer_idle_frames.get_frame_texture(&"idle", frame), "real idle frame %d/%d" % [faction, frame])
		var used := idle.texture.get_image().get_used_rect()
		var first := new_position + Vector2(used.position) * idle.scale
		var last := new_position + Vector2(used.end) * idle.scale
		var bounds := Rect2(first.min(last), (last - first).abs())
		var pick := visual.archer_pick_rect
		check(bounds.position.x >= pick.position.x and bounds.position.y >= pick.position.y
			and bounds.end.x <= pick.end.x and bounds.end.y <= pick.end.y,
			"unchanged picking bounds cover complete frame %d/%d" % [faction, frame])
		idle.position = old_position
		var before := await _capture(view)
		idle.position = new_position
		var after := await _capture(view)
		check(before.get_data() != after.get_data() and visual.transform == root_transform
			and shadow.transform == shadow_transform, "art moves while root/shadow stay fixed %d/%d" % [faction, frame])
		if frame in [0, 5, 11]:
			var row: int = 0 if frame == 0 else (1 if frame == 5 else 2)
			gallery.blend_rect(before, Rect2i(0, 0, 256, 256), Vector2i(column * 256, row * 256))
			gallery.blend_rect(after, Rect2i(0, 0, 256, 256), Vector2i((column + 1) * 256, row * 256))
		visual._process(13.0 / 60.0)
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
	var demo := BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	view.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	demo.board_view.zoom_camera(0.9, demo.board_view.size * 0.5)
	demo.board_view.pan_camera(Vector2(0, -50))
	for visual: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		visual.ambient_animation_paused = true
		visual.set_process(false)
	var picture := await _capture(view)
	check(picture.save_png(output.path_join("battle.png")) == OK, "save actual field")
	demo.queue_free()
	await process_frame
	view.queue_free()
	await process_frame
