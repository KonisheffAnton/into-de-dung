extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
const TRIAL = preload("res://scenes/demo/art_trial_battle.tscn")
const TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ART TRIAL: " + label)

func opaque_uv_boundary(grass: Polygon2D) -> bool:
	var image: Image = grass.texture.get_image()
	if image == null: return false
	var uv := grass.uv
	if uv.size() != 4: return false
	for edge: int in range(4):
		for sample: int in range(65):
			var point: Vector2 = uv[edge].lerp(uv[(edge + 1) % 4], float(sample) / 64.0)
			if not Rect2(Vector2.ZERO, image.get_size()).has_point(point): return false
			var pixel := image.get_pixelv(Vector2i(roundi(point.x), roundi(point.y)))
			if int(round(pixel.a * 255.0)) < 240: return false
	return true

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await live_battle()
	await field_sample()
	viewport.queue_free()
	await process_frame
	print("ART TRIAL BATTLE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func visible_grass(tile: BattleDemoIsoVisual) -> Node2D:
	var chosen: Node2D
	var count: int = 0
	for child: Node in tile.get_node("ArtRoot/GroundSurface").get_children():
		if child is Node2D and String(child.name).begins_with("Grass") and (child as Node2D).visible:
			count += 1
			chosen = child as Node2D
	check(count == 1, "one authored grass variant selected")
	return chosen

func live_battle() -> void:
	var demo := TRIAL.instantiate() as BattleDemo
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	check(demo.get_script() == BattleDemo and demo.session.get_script() == BattleCoreReactionsSession, "exact production scripts retain worker route")
	check(demo._allows_execution_worker() and demo.session.is_deploying(), "playable battle opens in deployment")
	check(demo.board_view.tile_visual_scene == TILE and demo.board_view.unit_visual_scene == UNIT, "nested authored board overrides loaded")
	check(demo.board_view.camera_controls_enabled, "production camera remains enabled")
	var session := demo.session as BattleCoreReactionsSession
	var original := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict()
	var player_id := session.units[0].id
	var enemy_id := session.units[3].id
	var player := demo.board_view._presentation_visual(player_id).get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
	var enemy := demo.board_view._presentation_visual(enemy_id).get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
	check(player.visible and (player.texture as AtlasTexture).atlas.resource_path.ends_with("defender_new.png"), "new player defender visible")
	check(enemy.visible and enemy.flip_h and enemy.texture.resource_path.ends_with("defender_reference_v1.png"), "approved enemy defender visible mirrored")
	# Проверяем отражение относительно опоры, а не случайного центра bbox.
	check(is_equal_approx(enemy.position.x + (312.0 - 180.0) * enemy.scale.x, 0.0), "enemy feet retain reference support after mirror")
	var enemy_transform := enemy.transform
	var assignments: Dictionary = {}
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.FLOOR or visual.is_void: continue
		assignments[visual.grid_anchor] = visible_grass(visual).name
	demo.board_view.refresh()
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if assignments.has(visual.grid_anchor) and visual.role == BattleDemoIsoVisual.Role.FLOOR:
			check(visible_grass(visual).name == assignments[visual.grid_anchor], "refresh retains per-cell art")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == original and session.context.get_rng().to_dict() == rng, "visual refresh leaves snapshot and RNG unchanged")
	await capture("battle-deployment")
	demo.board_view.zoom_camera(0.75, demo.board_view.size * 0.5)
	await capture("battle-overview-75")
	# Известная fixture создаёт допустимый ход игрока для проверки настоящего worker.
	PlayerTurnFixture.enter_player_turn(demo)
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	var deadline := Time.get_ticks_msec() + 30000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		await process_frame
	check(not demo._execution_worker.is_started(), "movement worker completes")
	check(demo.is_presentation_pending(), "real movement enters presentation")
	if demo.is_presentation_pending():
		demo._presentation_player._tween.pause()
		var detached := demo.board_view._presentation_visual(enemy_id).get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		check(detached.visible and detached.flip_h and detached.transform == enemy_transform, "detached playback retains enemy sprite and mirror")
		demo.skip_presentation()
	check(not demo.is_execution_pending() and demo.board_view._view_unit_cell(player_id) == Vector2i(1, 2), "movement publishes its final cell")
	await capture("battle-after-move")
	demo.queue_free()
	await process_frame

func field_sample() -> void:
	var board := BattleDemoBoard.new()
	board.size = Vector2(1440, 1000)
	board.tile_visual_scene = TILE
	board.unit_visual_scene = UNIT
	viewport.add_child(board)
	await process_frame
	var heights := PackedInt32Array()
	var terrain := PackedByteArray()
	heights.resize(36)
	terrain.resize(36)
	terrain.fill(TerrainType.Type.FLOOR)
	var value := {"width": 6, "height": 6, "heights": heights, "terrain": terrain, "units": {}, "fires": [], "corpses": [], "collapse": {}}
	# Это отделённая визуальная проба 6x6, а не новый боевой сценарий.
	for id: int in [1, 2]:
		board._view_visual_classes[id] = &"warrior"
		value.units[id] = {"id": id, "name": "Новый" if id == 1 else "Прежний", "faction": Faction.Type.PLAYER if id == 1 else Faction.Type.ENEMY,
			"cell": Vector2i(1, 2) if id == 1 else Vector2i(4, 2), "alive": true, "hp": 20.0, "hp_max": 20.0,
			"balance": 0.0, "balance_max": 10.0, "armor": {}, "elemental": {}, "bleeding": {}, "control": {}}
	board.show_presentation_state(value)
	var used: Dictionary = {}
	var tile_count: int = 0
	var boundary_by_texture: Dictionary = {}
	var void_cell := Vector2i(-1, -1)
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.FLOOR: continue
		tile_count += 1
		var grass := visible_grass(visual) as Polygon2D
		used[grass.name] = true
		if grass.name == &"Grass0": void_cell = visual.grid_anchor
		check(grass.polygon == PackedVector2Array([Vector2(0, -48), Vector2(64, 0), Vector2(0, 48), Vector2(-64, 0)]), "authored grass fills the complete 128x96 top")
		check(grass.uv == PackedVector2Array([Vector2(724, 110), Vector2(1350, 543), Vector2(724, 975), Vector2(96, 543)]), "grass uses the shared full-top UV diamond")
		var image: Image = grass.texture.get_image()
		var uv_inside: bool = image != null
		if image != null:
			for point: Vector2 in grass.uv:
				uv_inside = uv_inside and point.x >= 0.0 and point.y >= 0.0 and point.x < image.get_width() and point.y < image.get_height()
		check(uv_inside, "all four UV corners stay inside the authored texture")
		check(grass.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and grass.color == Color(0.79, 0.80, 0.75, 1.0) and grass.transform == Transform2D.IDENTITY, "full-top artwork shares the authored palette without extra transform")
		if not boundary_by_texture.has(grass.texture):
			boundary_by_texture[grass.texture] = opaque_uv_boundary(grass)
	check(used.size() == 4, "6x6 sample uses all four full-top compositions")
	for texture: Texture2D in [
		load("res://assets/art_presets/trials/grass_reference_v3/grass_a.png") as Texture2D,
		load("res://assets/art_presets/trials/grass_reference_v3/grass_b.png") as Texture2D,
		load("res://assets/art_presets/trials/grass_reference_v3/grass_c.png") as Texture2D,
		load("res://assets/art_presets/trials/grass_reference_v3/grass_d.png") as Texture2D,
	]:
		check(bool(boundary_by_texture.get(texture, false)), "each complete grass texture has an opaque UV boundary")
	check(tile_count == 36, "6x6 sample contains exactly 36 tile supports")
	await capture("field-6x6")
	var source := Vector2i(1, 2)
	for destination: Vector2i in [source + Vector2i.RIGHT, source + Vector2i.LEFT, source + Vector2i.UP, source + Vector2i.DOWN]:
		board.show_presentation_state(value)
		board._presentation_motion(0.5, 1, source, destination)
		var moving := board._presentation_visual(1)
		var support := board.cell_center(source).lerp(board.cell_center(destination), 0.5)
		check((moving.position + moving.get_visual_offset()).is_equal_approx(support), "new figure keeps interpolated support across tile seam")
		check(board.displayed_unit_at(moving.position + moving.get_visual_offset() + Vector2(0, -25)) == 1, "new figure remains pickable in movement")
	board.show_presentation_state(value)
	value.units[2].alive = false
	board.show_presentation_state(value)
	check(not (board._presentation_visual(2).get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D).visible, "enemy death hides mirrored artwork")
	# Убираем клетку с крупным пучком, чтобы проверить исчезновение всей текстуры.
	check(void_cell != Vector2i(-1, -1), "decorated support exists for void check")
	terrain[void_cell.y * 6 + void_cell.x] = TerrainType.Type.VOID
	board.show_presentation_state(value)
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.grid_anchor == void_cell and visual.role == BattleDemoIsoVisual.Role.FLOOR:
			var ground_surface := visual.get_node("ArtRoot/GroundSurface") as Sprite2D
			check(not ground_surface.visible, "void hides ground container")
			for child: CanvasItem in ground_surface.get_children():
				check(not child.is_visible_in_tree(), "void hides all full-top variants")
	board.queue_free()
	await process_frame
