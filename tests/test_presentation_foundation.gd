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
	for unit: UnitState in session.units:
		var visual := board._presentation_visual(unit.id)
		var ally_sprite := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
		var enemy_sprite := visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var is_ally_warrior: bool = session.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"warrior"
		var is_enemy_warrior: bool = unit.faction == Faction.Type.ENEMY and unit.debug_name in ["Страж", "Щит"]
		check(ally_sprite.visible == is_ally_warrior and enemy_sprite.visible == is_enemy_warrior, "role and faction select requested art: " + unit.debug_name)
		check((visual.get_node("ArtRoot/BodySprite") as Sprite2D).visible == not (is_ally_warrior or is_enemy_warrior), "other archetypes retain their body: " + unit.debug_name)
		if is_ally_warrior:
			ally_id = unit.id
			check(ally_sprite.texture.resource_path.ends_with("warrior_ally_retro_v1.png") and ally_sprite.modulate == Color.WHITE, "allied warrior keeps Retro texture and palette")
		if is_enemy_warrior:
			enemy_id = unit.id
			check(enemy_sprite.texture.resource_path.ends_with("warrior_enemy_pixellab_v1.png") and enemy_sprite.modulate == Color.WHITE, "enemy warrior keeps PixelLab texture and palette")
	check(ally_id != UnitId.NONE and enemy_id != UnitId.NONE, "production opening contains both warrior sides")
	await capture("warrior-opening")
	if ally_id != UnitId.NONE and enemy_id != UnitId.NONE:
		var value := ActionPresentationState.capture(session.state)
		board.execution_pending = true
		board.session = null
		# После отделения session смена её метаданных не должна менять показанный рисунок.
		session.unit_visual_classes.clear()
		session.actor_loadouts[ally_id].class_id = &"rogue"
		board.show_presentation_state(value)
		check((board._presentation_visual(ally_id).get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D).visible, "allied art survives detached presentation frame")
		check((board._presentation_visual(enemy_id).get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible, "enemy art survives detached presentation frame")
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
