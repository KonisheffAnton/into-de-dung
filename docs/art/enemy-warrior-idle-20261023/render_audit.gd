extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
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
		printerr("FAIL ENEMY WARRIOR ART: " + label)

func capture(view: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "capture " + name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	await fixture()
	await battle()
	print("ENEMY WARRIOR ART AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func fixture() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(384, 384)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(256, 192)
	config.origin_offset = Vector2(192, 192)
	var tile := TILE.instantiate() as BattleTerrainVisual
	view.add_child(tile)
	tile.apply_view({"cell": Vector2i.ZERO, "role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}, config)
	var unit := UNIT.instantiate() as BattleDefenderIdleVisual
	unit.role = BattleDemoIsoVisual.Role.UNIT
	view.add_child(unit)
	var statuses: Array[Dictionary] = []
	unit.apply_view({"cell": Vector2i.ZERO, "half_steps": 0,
		"unit": {"id": 72, "faction": int(Faction.Type.ENEMY), "name": "", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": &"warrior", "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}, config)
	unit.set_process(false)
	var idle := unit.get_node("ArtRoot/EnemyWarriorIdleSprite") as Sprite2D
	var still := unit.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
	var hud := unit.get_node("StatusHud") as Node2D
	# Центр верхнего ромба компенсирует полпикселя сортировки площадки.
	var top := tile.top_polygon()
	var center := tile.to_global((top[0] + top[2]) * 0.5)
	var still_transform := still.transform
	var root_transform := unit.transform
	var shadow := unit.get_node("GroundShadow") as Node2D
	var shadow_transform := shadow.transform
	for frame: int in 17:
		unit.idle_clock.configure(0, 24, 24)
		unit._process(float(frame) * 0.15)
		hud.hide()
		check(idle.texture == unit.enemy_warrior_idle_frames.get_frame_texture(&"idle", frame), "ordered frame " + str(frame))
		check(idle.visible and not still.visible and idle.scale == Vector2(-1, 1), "mirrored idle layer " + str(frame))
		check(idle.to_global(Vector2(68, 64)).is_equal_approx(center), "belt pivot at tile center " + str(frame))
		var used := idle.texture.get_image().get_used_rect()
		var first := idle.position + Vector2(used.position) * idle.scale
		var last := idle.position + Vector2(used.end) * idle.scale
		var bounds := Rect2(first.min(last), (last - first).abs())
		check(unit.get_unit_pick_rect().encloses(bounds), "picking contains full frame " + str(frame))
		check(unit.transform == root_transform and shadow.transform == shadow_transform and still.transform == still_transform,
			"fixed root shadow and still " + str(frame))
		await capture(view, "frames/frame-%02d" % (frame + 1))
		if frame == 0: await capture(view, "enemy-on-tile")
	unit.ambient_animation_paused = true
	hud.hide()
	check(still.visible and not idle.visible and still.to_global(Vector2(68, 64)).is_equal_approx(center), "still aligns with idle pivot")
	await capture(view, "enemy-still-on-tile")
	var guide_layer := CanvasLayer.new()
	view.add_child(guide_layer)
	var guide := Line2D.new()
	guide.points = PackedVector2Array([center + Vector2(-32, 0), center + Vector2(32, 0)])
	guide.default_color = Color("ff4dff")
	guide.width = 2.0
	guide.z_index = 100
	guide_layer.add_child(guide)
	var vertical := guide.duplicate() as Line2D
	vertical.points = PackedVector2Array([center + Vector2(0, -32), center + Vector2(0, 32)])
	guide_layer.add_child(vertical)
	await capture(view, "center-proof")
	view.queue_free()
	await process_frame

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}

func battle() -> void:
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
	var before := snapshot(demo.session as BattleCoreReactionsSession)
	var enemies: int = 0
	var allies: int = 0
	for visual: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		visual.set_process(false)
		if visual.visual_class_id != &"warrior": continue
		var defender := visual as BattleDefenderIdleVisual
		if visual.unit.faction == Faction.Type.ENEMY:
			enemies += 1
			var idle := visual.get_node("ArtRoot/EnemyWarriorIdleSprite") as Sprite2D
			check(idle.visible and idle.texture.resource_path.contains("enemy_warrior_idle_v1"), "production enemy selected new idle")
			check(idle.to_global(Vector2(68, 64)).is_equal_approx(visual.to_global(visual.get_visual_offset())), "production center alignment")
			check(not defender.can_play_buff() and not defender.can_play_death(), "production enemy excludes old character clips")
		else:
			allies += 1
			var idle := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
			check(idle.visible and idle.texture.resource_path.contains("defender_idle_v1"), "production ally retains old approved idle")
	check(enemies > 0 and allies > 0, "production encounter has both factions")
	await capture(view, "battle")
	check(snapshot(demo.session as BattleCoreReactionsSession) == before, "capture preserves state RNG counters and revision")
	view.queue_free()
	await process_frame
