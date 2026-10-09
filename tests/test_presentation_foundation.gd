extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION FOUNDATION: " + label)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func state() -> Dictionary:
	var heights := PackedInt32Array()
	var terrain := PackedByteArray()
	heights.resize(64)
	terrain.resize(64)
	terrain.fill(TerrainType.Type.FLOOR)
	return {"width": 8, "height": 8, "heights": heights, "terrain": terrain,
		"units": {1: {"id": 1, "name": "Астра", "faction": Faction.Type.PLAYER,
			"cell": Vector2i(3, 3), "alive": true, "hp": 20.0, "hp_max": 32.0,
			"balance": 0.0, "balance_max": 12.0, "armor": {"current": 8.0, "maximum": 16.0, "extra": 0.0},
			"elemental": {}, "bleeding": {}, "control": {}}}, "fires": [], "corpses": [], "collapse": {}}

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = Vector2(1280, 800)
	viewport.add_child(board)
	await process_frame
	var value := state()
	board.show_presentation_state(value)
	var visual := board._presentation_visual(1)
	check(visual.get_node_or_null("ArtRoot/BodySprite") is Sprite2D, "unit is an instantiated sprite scene")
	var tile := tile_at(Vector2i(3, 3))
	check(tile.get_node_or_null("ArtRoot/SurfaceSprite") is Sprite2D, "tile is an instantiated sprite scene")
	check(visual.get_node("ArtRoot/BodySprite").texture is Texture2D, "placeholder uses imported image")
	var ground := tile.get_node("ArtRoot/GroundSurface") as Sprite2D
	var ground_base := tile.get_node("ArtRoot/GroundBase") as Polygon2D
	var tile_factor := board.grid_config.tile_size.x / 128.0
	check(is_equal_approx(board.grid_config.tile_size.x / board.grid_config.tile_size.y, 4.0 / 3.0), "presentation grid keeps authored 4:3 tile top")
	var authored_top := PackedVector2Array([Vector2(0, -48), Vector2(64, 0), Vector2(0, 48), Vector2(-64, 0)])
	var actual_top := tile.top_polygon()
	for top_index: int in actual_top.size(): actual_top[top_index] = (actual_top[top_index] - tile._top_offset()) / tile_factor
	for top_index: int in actual_top.size():
		check(actual_top[top_index].is_equal_approx(authored_top[top_index]), "tile presentation vertex matches authored 4:3 top")
	check(ground.texture.resource_path.ends_with("grass_reference_v1.png") and ground.texture.get_size() == Vector2(512, 408), "ground uses the full selected PNG")
	check(not ground.centered and ground.offset == Vector2(-256, -192) and ground.scale == Vector2(0.25, 0.25) and ground.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "ground keeps authored full image placement, proportional scale, and nearest filter")
	check(ground_base.polygon == PackedVector2Array([Vector2(0, -48), Vector2(64, 0), Vector2(0, 48), Vector2(-64, 0)]) and tile.ground_base_tint.is_equal_approx(Color("697553")), "ground base keeps authored 4:3 olive diamond")
	var custom_anchor := visual.get_node("ArtRoot/EffectAnchor") as Marker2D
	custom_anchor.position = Vector2(3, -27)
	visual.sync_scene_art()
	check(custom_anchor.position == Vector2(3, -27), "scene-defined attachment point survives refresh")
	# Стык проверяется внутри каждого сегмента, а не только после публикации клетки.
	for destination: Vector2i in [Vector2i(4, 3), Vector2i(2, 3), Vector2i(3, 4), Vector2i(3, 2)]:
		for progress: float in [0.25, 0.5, 0.75]:
			board.show_presentation_state(value)
			board._presentation_motion(progress, 1, Vector2i(3, 3), destination)
			visual = board._presentation_visual(1)
			var foot := board.cell_center(Vector2i(3, 3)).lerp(board.cell_center(destination), progress)
			check((visual.position + visual.get_visual_offset()).is_equal_approx(foot), "continuous foot %s/%s" % [destination, progress])
			check(visual.position.y > tile_at(Vector2i(3, 3)).position.y and visual.position.y > tile_at(destination).position.y, "both supports behind moving feet %s/%s" % [destination, progress])
			check(board.displayed_unit_at(foot + Vector2(0, -12)) == 1, "picking follows visible moving body")
			if progress == 0.5: await capture("seam-%d-%d" % [destination.x, destination.y])
		board._presentation_motion(1.0, 1, Vector2i(3, 3), destination)
		visual = board._presentation_visual(1)
		check(visual.position.is_equal_approx(IsoGridUtils.grid_to_screen(destination, board.grid_config, 0)) and visual.presentation_offset == Vector2.ZERO, "segment endpoint restores ordinary cell depth")
	value.heights[3 * 8 + 4] = 2
	board.show_presentation_state(value)
	board._presentation_motion(0.5, 1, Vector2i(3, 3), Vector2i(4, 3))
	visual = board._presentation_visual(1)
	check((visual.position + visual.get_visual_offset()).is_equal_approx(board.cell_center(Vector2i(3, 3)).lerp(board.cell_center(Vector2i(4, 3)), 0.5)), "climb separates lift from depth")
	await capture("raised-seam")
	# Более близкая настоящая стена остаётся впереди; это не общий верхний слой юнитов.
	value.terrain[4 * 8 + 4] = TerrainType.Type.WALL
	board.show_presentation_state(value)
	board._presentation_motion(0.5, 1, Vector2i(3, 3), Vector2i(4, 3))
	var wall: BattleDemoIsoVisual
	for candidate: BattleDemoIsoVisual in board._entity_visuals:
		if candidate.role == BattleDemoIsoVisual.Role.WALL: wall = candidate
	check(wall != null and wall.position.y > board._presentation_visual(1).position.y, "foreground wall still occludes by depth")
	await capture("foreground-wall")
	value.units[1].elemental = {"frozen_turns": 2}
	value.fires = [{"cell": Vector2i(2, 3), "effect": "burning"}, {"cell": Vector2i(2, 4), "effect": "bleeding"}]
	board.show_presentation_state(value)
	visual = board._presentation_visual(1)
	check(visual.get_node("ArtRoot/EffectRoot/IceSprite").visible, "frozen snapshot displays separate ice shell")
	check(tile_at(Vector2i(2, 3)).get_node("ArtRoot/EffectRoot/BurningSprite").visible, "burning cell displays independent fire")
	check(not tile_at(Vector2i(2, 4)).get_node("ArtRoot/EffectRoot/BurningSprite").visible, "spikes do not become fire")
	var ice := visual.get_node("ArtRoot/EffectRoot/IceSprite") as Sprite2D
	var relative := ice.global_position - (visual.position + visual.get_visual_offset())
	board._presentation_motion(0.5, 1, Vector2i(3, 3), Vector2i(4, 3))
	check((ice.global_position - (visual.position + visual.get_visual_offset())).is_equal_approx(relative), "ice remains attached while displaced")
	await capture("fire-and-ice")
	value.units[1].elemental = {}
	board.show_presentation_state(value)
	check(not board._presentation_visual(1).get_node("ArtRoot/EffectRoot/IceSprite").visible, "published thaw removes shell")
	board.unit_visual_scene = null
	board.tile_visual_scene = null
	board.show_presentation_state(value)
	check(board._presentation_visual(1).get_node_or_null("ArtRoot") == null, "procedural fallback remains available")
	board.queue_free()
	await process_frame
	await warrior_art()
	await live_ui()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION FOUNDATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func tile_at(cell: Vector2i) -> BattleDemoIsoVisual:
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM] and visual.grid_anchor == cell: return visual
	return null

func warrior_art() -> void:
	var hub := HeroHubState.create(443)
	hub.enable_mage_deck()
	var started := ExpeditionTransitions.apply(hub, "start")
	check(started.is_ok(), "warrior art fixture enters production opening")
	if not started.is_ok(): return
	var bundle := HeroHubBattleFactory.create(started.profile)
	check(not bundle.is_empty(), "warrior art uses actual hero and enemy roles")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var original := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict()
	board = BattleDemoBoard.new()
	board.size = Vector2(1280, 800)
	board.session = session
	viewport.add_child(board)
	await process_frame
	board.refresh()
	var ally_id: int = UnitId.NONE
	var enemy_id: int = UnitId.NONE
	var enemy_ids: Array[int] = []
	var enemy_preset_assignments: Dictionary[int, String] = {}
	var tile_factor := board.grid_config.tile_size.x / 128.0
	for unit: UnitState in session.units:
		var visual := board._presentation_visual(unit.id)
		var ally_sprite := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
		var enemy_sprite := visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var preset_root := visual.get_node("ArtRoot/EnemyPresets") as Node2D
		var loadout: Dictionary = session.actor_loadouts.get(unit.id, {})
		var expected_warrior: bool = (unit.faction == Faction.Type.PLAYER and loadout.get("class_id", &"") in [&"warrior", &"shieldbearer"]) or (unit.faction == Faction.Type.ENEMY and unit.debug_name in ["Страж", "Щит"])
		check((visual.visual_class_id == &"warrior") == expected_warrior, "visual class routing matches production loadout/role contract: " + unit.debug_name)
		var visible_presets: Array[Sprite2D] = []
		for child: Node in preset_root.get_children():
			var preset := child as Sprite2D
			if preset.visible: visible_presets.append(preset)
		var is_live_enemy: bool = unit.faction == Faction.Type.ENEMY and unit.is_alive()
		var warrior_sprite: Sprite2D = ally_sprite if unit.faction == Faction.Type.PLAYER else enemy_sprite
		check(warrior_sprite.visible == (expected_warrior and unit.is_alive()) and (unit.faction != Faction.Type.ENEMY or not enemy_sprite.visible or expected_warrior), "warrior class art takes priority for either faction: " + unit.debug_name)
		check(visible_presets.size() == (1 if is_live_enemy and not expected_warrior else 0), "nonwarrior enemy role displays one preset: " + unit.debug_name)
		check((visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible == (unit.is_alive() and not expected_warrior and visible_presets.is_empty()), "other archetypes retain their body: " + unit.debug_name)
		if expected_warrior and unit.is_alive():
			check(warrior_sprite.texture.resource_path.ends_with("defender_reference_v1.png") and warrior_sprite.modulate == Color.WHITE, "both warrior factions use selected neutral defender art")
			check(warrior_sprite.texture.get_size() == Vector2(312, 292) and not warrior_sprite.centered and warrior_sprite.position == Vector2(-45, -56) and warrior_sprite.scale == Vector2(0.25, 0.25) and warrior_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "warrior full image yields approved 78x73 crop at nearest scale")
			check(visual.warrior_pick_rect == Rect2(-45, -56, 78, 73), "warrior picking covers approved visible crop")
			var foot := visual.position + visual.get_visual_offset()
			check(visual.contains_point(foot + Vector2(-30, -48) * tile_factor) and visual.contains_point(foot + Vector2(20, -34) * tile_factor), "warrior head and shield area are pickable")
		if unit.faction == Faction.Type.PLAYER and expected_warrior:
			ally_id = unit.id
		if is_live_enemy and not expected_warrior:
			enemy_ids.append(unit.id)
			var atlas := visible_presets[0].texture as AtlasTexture
			var expected_preset_paths: Array[String] = ["res://assets/battle_units/enemy_iso_bearded_v1.png", "res://assets/battle_units/enemy_iso_helmet_v1.png", "res://assets/battle_units/enemy_iso_redhair_v1.png"]
			enemy_preset_assignments[unit.id] = atlas.atlas.resource_path
			check(atlas.atlas.resource_path == expected_preset_paths[posmod(unit.id, 3)], "nonwarrior preset uses stable id modulo 3 assignment: " + unit.debug_name)
			check(visible_presets[0].modulate == Color.WHITE, "enemy preset preserves source palette: " + unit.debug_name)
		if unit.faction == Faction.Type.ENEMY and expected_warrior and unit.is_alive(): enemy_id = unit.id
	check(ally_id != UnitId.NONE and enemy_id != UnitId.NONE, "production opening contains both warrior sides")
	check(not enemy_ids.is_empty(), "production opening contains a nonwarrior enemy for preset fallback")
	check(not enemy_preset_assignments.is_empty(), "production nonwarrior enemy receives deterministic preset")
	var initial_enemy_preset_assignments := enemy_preset_assignments.duplicate(true)
	var preset_probe := board.unit_visual_scene.instantiate() as BattleDemoIsoVisual
	preset_probe.role = BattleDemoIsoVisual.Role.UNIT
	preset_probe.grid_config = board.grid_config
	preset_probe.visual_class_id = &""
	var preset_probe_unit := BattleUnitView.new()
	preset_probe_unit.faction = Faction.Type.ENEMY
	preset_probe_unit.alive = true
	preset_probe.unit = preset_probe_unit
	var expected_probe_paths: Array[String] = ["res://assets/battle_units/enemy_iso_bearded_v1.png", "res://assets/battle_units/enemy_iso_helmet_v1.png", "res://assets/battle_units/enemy_iso_redhair_v1.png"]
	for residue: int in 3:
		preset_probe_unit.id = 300 + residue
		preset_probe.sync_scene_art()
		var selected_probe_path: String = ""
		var selected_probe_count: int = 0
		for child: Node in (preset_probe.get_node("ArtRoot/EnemyPresets") as Node2D).get_children():
			var preset := child as Sprite2D
			if preset.visible:
				selected_probe_count += 1
				selected_probe_path = (preset.texture as AtlasTexture).atlas.resource_path
		check(selected_probe_count == 1 and selected_probe_path == expected_probe_paths[residue], "isolated nonwarrior visual exercises preset residue %d" % residue)
	preset_probe.free()
	for _refresh_index: int in 3:
		board.refresh()
		enemy_preset_assignments.clear()
		for enemy_unit_id: int in enemy_ids:
			var enemy_visual := board._presentation_visual(enemy_unit_id)
			var enemy_preset_group := enemy_visual.get_node("ArtRoot/EnemyPresets") as Node2D
			for child: Node in enemy_preset_group.get_children():
				var preset := child as Sprite2D
				if preset.visible: enemy_preset_assignments[enemy_unit_id] = (preset.texture as AtlasTexture).atlas.resource_path
		check(enemy_preset_assignments == initial_enemy_preset_assignments, "enemy presets stay stable across repeated refresh")
	var standard_unit_scene := board.unit_visual_scene
	var fallback_visual := load("res://scenes/demo/visuals/placeholder_unit.tscn").instantiate() as BattleDemoIsoVisual
	(fallback_visual.get_node("ArtRoot/EnemyPresets") as Node2D).free()
	var fallback_scene := PackedScene.new()
	check(fallback_scene.pack(fallback_visual) == OK, "custom visual without EnemyPresets packs")
	fallback_visual.free()
	board.unit_visual_scene = fallback_scene
	board.refresh()
	var fallback_enemy := board._presentation_visual(enemy_id)
	check((fallback_enemy.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible and not (fallback_enemy.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "warrior art remains selected without preset group")
	board.unit_visual_scene = standard_unit_scene
	board.refresh()
	var texture_test_visual := board._presentation_visual(enemy_ids[0])
	var texture_test_group := texture_test_visual.get_node("ArtRoot/EnemyPresets") as Node2D
	var replaced_preset: Sprite2D
	var replaced_texture: Texture2D
	for child: Node in texture_test_group.get_children():
		var preset := child as Sprite2D
		if not preset.visible:
			replaced_preset = preset
			replaced_texture = preset.texture
			break
	if replaced_preset != null:
		replaced_preset.texture = null
		texture_test_visual.sync_scene_art()
		var all_presets_hidden: bool = true
		for child: Node in texture_test_group.get_children():
			all_presets_hidden = all_presets_hidden and not (child as Sprite2D).visible
		check(all_presets_hidden and (texture_test_visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "incomplete nonwarrior presets fall back to body")
		replaced_preset.texture = replaced_texture
		texture_test_visual.sync_scene_art()
		var restored_presets: int = 0
		for child: Node in texture_test_group.get_children():
			if (child as Sprite2D).visible: restored_presets += 1
		check(restored_presets == 1 and not (texture_test_visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "restored preset texture reselects one enemy image")
	await capture("warrior-opening")
	if ally_id != UnitId.NONE and enemy_id != UnitId.NONE:
		var selected_enemy_visual := board._presentation_visual(enemy_id)
		var selected_enemy_sprite := selected_enemy_visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var selected_enemy_texture := selected_enemy_sprite.texture
		selected_enemy_sprite.texture = null
		selected_enemy_visual.sync_scene_art()
		var fallback_preset_count := 0
		for child: Node in (selected_enemy_visual.get_node("ArtRoot/EnemyPresets") as Node2D).get_children():
			if (child as Sprite2D).visible: fallback_preset_count += 1
		check(fallback_preset_count == 1 and not (selected_enemy_visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "missing warrior texture falls back to deterministic enemy preset")
		var saved_preset_textures: Array[Texture2D] = []
		for child: Node in (selected_enemy_visual.get_node("ArtRoot/EnemyPresets") as Node2D).get_children():
			var preset := child as Sprite2D
			saved_preset_textures.append(preset.texture)
			preset.texture = null
		selected_enemy_visual.sync_scene_art()
		check((selected_enemy_visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible, "missing warrior and preset textures fall back to body")
		var preset_index: int = 0
		for child: Node in (selected_enemy_visual.get_node("ArtRoot/EnemyPresets") as Node2D).get_children():
			(child as Sprite2D).texture = saved_preset_textures[preset_index]
			preset_index += 1
		selected_enemy_sprite.texture = selected_enemy_texture
		selected_enemy_visual.sync_scene_art()
		var value := ActionPresentationState.capture(session.state)
		board.execution_pending = true
		board.session = null
		# После отделения session смена её метаданных не должна менять показанный рисунок.
		session.unit_visual_classes.clear()
		session.actor_loadouts[ally_id].class_id = &"rogue"
		board.show_presentation_state(value)
		check((board._presentation_visual(ally_id).get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D).visible, "allied art survives detached presentation frame")
		var detached_enemy_visual := board._presentation_visual(enemy_id)
		check((detached_enemy_visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible, "detached frame keeps selected enemy warrior art")
		value.units[ally_id].elemental = {"frozen_turns": 1}
		board.show_presentation_state(value)
		var source: Vector2i = value.units[ally_id].cell
		board._presentation_motion(0.5, ally_id, source, source + Vector2i.RIGHT)
		var moving := board._presentation_visual(ally_id)
		check((moving.get_node("ArtRoot/EffectRoot/IceSprite") as Sprite2D).visible, "warrior keeps existing frozen overlay in motion")
		check(board.displayed_unit_at(moving.position + moving.get_visual_offset() + Vector2(0, -24)) == ally_id, "moving warrior remains pickable")
		await capture("warrior-frozen-motion")
		value.units[ally_id].alive = false
		board.show_presentation_state(value)
		check(not (board._presentation_visual(ally_id).get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D).visible, "published death hides warrior body")
		value.units[enemy_id].alive = false
		board.show_presentation_state(value)
		var dead_enemy_visual := board._presentation_visual(enemy_id)
		var enemy_bodies_hidden: bool = not (dead_enemy_visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible and not (dead_enemy_visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible
		for child: Node in (dead_enemy_visual.get_node("ArtRoot/EnemyPresets") as Node2D).get_children():
			enemy_bodies_hidden = enemy_bodies_hidden and not (child as Sprite2D).visible
		check(enemy_bodies_hidden, "published enemy death hides all body variants")
		board.execution_pending = false
		board.session = session
		board.refresh()
		check((board._presentation_visual(ally_id).get_node("ArtRoot/BodySprite") as Sprite2D).visible, "new live refresh replaces old class copy")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == original and session.context.get_rng().to_dict() == rng, "art refresh and detached playback preserve battle snapshot and RNG")
	board.session = null
	board.queue_free()
	await process_frame
	session.close()

func live_ui() -> void:
	var demo := (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	check(not demo._diagnostics.visible, "diagnostics hidden by default")
	check(demo.size.x <= viewport.size.x and demo.size.y <= viewport.size.y, "compact UI fits viewport")
	var initial_rect := demo.board_view.get_global_rect()
	var mage_visible := demo._mage_row.visible
	demo.set_diagnostics_visible(true)
	demo._stats.text = "Длинная диагностика\n".repeat(100)
	await process_frame
	await process_frame
	check(demo.board_view.get_global_rect() == initial_rect, "diagnostics and long text do not resize board")
	demo.set_diagnostics_visible(false)
	var s := demo.session as BattleCoreReactionsSession
	var actor := s.selected_unit()
	var actor_id := actor.id
	var actor_name := actor.debug_name
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	# Worker владеет runtime; осмотр должен обходиться копией опубликованного вида.
	var moving_view := demo.board_view._presentation_visual(actor_id)
	var motion := InputEventMouseMotion.new()
	motion.position = demo.board_view.global_position + moving_view.position + moving_view.get_visual_offset() + Vector2(0, -18)
	viewport.push_input(motion, true)
	check(demo._compact_inspection.text.contains(actor_name), "real hover can inspect published unit during execution")
	while demo._execution_worker.is_started():
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "movement clip starts")
	demo._presentation_player._tween.pause()
	var committed := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var rng := s.context.get_rng().to_dict()
	var other := s.units[3]
	var other_view := demo.board_view._presentation_visual(other.id)
	motion.position = demo.board_view.global_position + other_view.position + other_view.get_visual_offset() + Vector2(0, -18)
	viewport.push_input(motion, true)
	check(demo._compact_inspection.text.contains(other.debug_name), "hover inspects other shown figure during clip")
	demo.handle_cell(Vector2i(2, 2))
	demo.end_turn()
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == committed and s.context.get_rng().to_dict() == rng, "inspection and blocked commands never mutate committed battle")
	await process_frame
	var moving_rect := demo.board_view.get_global_rect()
	check(demo._action_bar.visible and demo._mage_row.visible == mage_visible and moving_rect.position.is_equal_approx(initial_rect.position) and moving_rect.size.distance_to(initial_rect.size) <= 1.0, "movement preserves controls and layout within one pixel")
	await capture("compact-moving-inspection")
	demo.skip_presentation()
	check(not demo.is_execution_pending() and demo.board_view._view_unit_cell(actor.id) == actor.cell, "skip still publishes final state")
	await capture("compact-battle")
	demo.queue_free()
	await process_frame
