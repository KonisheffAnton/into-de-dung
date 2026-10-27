extends SceneTree

const HUB_SCENE: PackedScene = preload("res://scenes/demo/hero_hub.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const DEFAULT_TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
const COMPARISON_TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const ATLAS_A: Texture2D = preload("res://assets/art_presets/trials/dungeon_comparison_v1/atlas_a.png")
const ATLAS_B: Texture2D = preload("res://assets/art_presets/trials/dungeon_comparison_v1/atlas_b.png")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var screen: HeroHubScreen
var captures: String = ""
var save_path: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL DUNGEON ROOM COMPARISON: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var value := ItemSimulationSnapshot.capture(session.state, [])
	return {
		"state": value.snapshot.to_dict() if value.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(),
		"phase": session.phase,
	}

func _receipt(profile: HeroHubState) -> Dictionary:
	var hp: Dictionary = {}
	var gear: Dictionary = {}
	for id: int in profile.party:
		hp[id] = float((profile.heroes[id] as HeroProgression).max_hp())
	for item: Dictionary in profile.expedition.checkpoint.legacy_inputs.items:
		gear[item.id] = item.remaining
	var receipt := {"run_id": profile.run_serial, "node_id": profile.expedition.current_node().id,
		"serial": profile.expedition.battle_serial, "victory": true, "hp": hp, "gear": gear}
	if profile.expedition.is_deck(): receipt["ruleset_id"] = profile.expedition.ruleset_id
	return receipt

func _later_battle(source: HeroHubState) -> HeroHubState:
	var profile := HeroHubState.from_dict(source.to_dict())
	for _step: int in range(24):
		if profile == null or profile.expedition == null: return null
		var run := profile.expedition
		if run.phase == "battle":
			if int(run.current_node().get("layer", -1)) > 0: return profile
			var outcome := ExpeditionTransitions.apply(profile, "outcome", _receipt(profile))
			if not outcome.is_ok(): return null
			profile = outcome.profile
			continue
		if run.phase == "reward":
			var reward := ExpeditionTransitions.apply(profile, "reward", {"index": -1})
			if not reward.is_ok(): return null
			profile = reward.profile
			continue
		if run.phase == "service":
			var service := ExpeditionTransitions.apply(profile, "service", {"kind": "heal"})
			if not service.is_ok(): return null
			profile = service.profile
			continue
		if run.phase == "camp_departure":
			var leave_camp := ExpeditionTransitions.apply(profile, "continue")
			if not leave_camp.is_ok(): return null
			profile = leave_camp.profile
			continue
		if run.phase != "route": return null
		var selected: int = -1
		for node_id: int in run.available_nodes():
			var node: Dictionary = run.plan.nodes[node_id - 1]
			if int(node.layer) > 0 and node.kind in ["battle", "elite", "final"]:
				selected = node_id
				break
		if selected < 0:
			var options := run.available_nodes()
			if options.is_empty(): return null
			selected = options[0]
		var transition := ExpeditionTransitions.apply(profile, "choose", {"node": selected})
		if not transition.is_ok(): return null
		profile = transition.profile
	return null

func _capture_zoom(zoom: float, baseline: Dictionary) -> void:
	var battle := screen.battle_view
	battle.board_view.zoom_camera(zoom, battle.board_view.size * 0.5)
	await process_frame
	await process_frame
	check(snapshot(battle.session as BattleCoreReactionsSession) == baseline,
		"camera zoom preserves snapshot, RNG, counters, revision and phase at %d%%" % roundi(zoom * 100.0))
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		check(image != null and image.save_png(captures.path_join("first-room-%d.png" % roundi(zoom * 100.0))) == OK,
			"captures live first-room battle at %d%%" % roundi(zoom * 100.0))

func _check_first_room_layers(board: BattleDemoBoard) -> void:
	var by_cell: Dictionary = {}
	var atlas_a_count: int = 0
	var atlas_b_count: int = 0
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT: continue
		by_cell[visual.grid_anchor] = visual
		if visual.is_void: continue
		var top := visual.get_node_or_null("ArtRoot/DungeonWallTop") as Polygon2D
		if top != null and top.visible:
			if top.texture == ATLAS_A: atlas_a_count += 1
			elif top.texture == ATLAS_B: atlas_b_count += 1
			continue
		var ground := visual.get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
		if ground == null: continue
		for child: Node in ground.get_children():
			if child is Polygon2D and String(child.name).begins_with("DungeonFloor") and (child as Polygon2D).visible:
				if (child as Polygon2D).texture == ATLAS_A: atlas_a_count += 1
				elif (child as Polygon2D).texture == ATLAS_B: atlas_b_count += 1
	check(atlas_a_count > 0 and atlas_b_count > 0, "live first room renders both dungeon atlases")
	var matched_pairs: int = 0
	for y: int in range(8):
		var left := by_cell.get(Vector2i(0, y)) as BattleTerrainVisual
		var right := by_cell.get(Vector2i(4, y)) as BattleTerrainVisual
		if left == null or right == null: continue
		var left_piece := _visible_floor_piece(left)
		var right_piece := _visible_floor_piece(right)
		if left_piece == null or right_piece == null: continue
		matched_pairs += 1
		check(left_piece.texture == ATLAS_A and right_piece.texture == ATLAS_B, "same local cell compares atlas A/B at y=%d" % y)
		check(left_piece.uv == right_piece.uv, "x and x+4 retain identical floor UV at y=%d" % y)
	check(matched_pairs > 0, "first room includes at least one paired floor sample")

func _visible_floor_piece(tile: BattleTerrainVisual) -> Polygon2D:
	var ground := tile.get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
	if ground == null: return null
	for child: Node in ground.get_children():
		if child is Polygon2D and String(child.name).begins_with("DungeonFloor") and (child as Polygon2D).visible:
			return child as Polygon2D
	return null


func _tile_values(cell: Vector2i, tile_role: BattleDemoIsoVisual.Role, steps: int = 0, void_surface: bool = false) -> Dictionary:
	return {"cell": cell, "role": tile_role, "half_steps": steps, "is_void": void_surface,
		"reachable": false, "enemy_range": false, "burning": false}

func _terrain_ids(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {}
	for key: Vector3i in board._terrain_visuals:
		var visual: BattleDemoIsoVisual = board._terrain_visuals[key]
		result[key] = visual.get_instance_id()
	return result

func _uv_is_covered(piece: Polygon2D, image: Image) -> bool:
	for edge: int in range(piece.uv.size()):
		for sample: int in range(33):
			var point := Vector2i(piece.uv[edge].lerp(piece.uv[(edge + 1) % piece.uv.size()], float(sample) / 32.0).round())
			if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(point): return false
			if image.get_pixelv(point).a < 240.0 / 255.0: return false
	return true

func _check_tile_contract() -> void:
	var tile := COMPARISON_TILE.instantiate() as BattleTerrainVisual
	var reference := DEFAULT_TILE.instantiate() as BattleTerrainVisual
	root.add_child(tile)
	root.add_child(reference)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32.0
	var floor_uv: Dictionary = {}
	var count_a: int = 0
	var count_b: int = 0
	var ids: Array[int] = []
	for child: Node in tile.get_node("ArtRoot/GroundSurface").get_children():
		ids.append(child.get_instance_id())
	var image_a := ATLAS_A.get_image()
	var image_b := ATLAS_B.get_image()
	for y: int in range(8):
		for x: int in range(8):
			var cell := Vector2i(x, y)
			tile.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config)
			reference.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config)
			var piece := _visible_floor_piece(tile)
			check(piece != null, "floor exists at %s" % cell)
			if piece == null: continue
			check(piece.texture == (ATLAS_A if x < 4 else ATLAS_B), "correct atlas at %s" % cell)
			if piece.texture == ATLAS_A: count_a += 1
			else: count_b += 1
			if x < 4: floor_uv[cell] = piece.uv
			else: check(piece.uv == floor_uv[Vector2i(x - 4, y)], "paired floor layout at %s" % cell)
			check(_uv_is_covered(piece, image_a if x < 4 else image_b), "floor UV has source coverage at %s" % cell)
			check(tile.surface_polygons() == reference.surface_polygons(), "floor picking matches existing scene")
			check(not tile.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config), "unchanged publication is skipped")
	check(count_a == 32 and count_b == 32, "8x8 footprint has exactly 32 cells per atlas")
	for x: int in [1, 5]:
		for tile_role: BattleDemoIsoVisual.Role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM, BattleDemoIsoVisual.Role.WALL]:
			for steps: int in [-4, 0, 4]:
				var values := _tile_values(Vector2i(x, 2), tile_role, steps)
				tile.apply_view(values, config)
				reference.apply_view(values, config)
				check(tile.surface_polygons() == reference.surface_polygons(), "role/elevation keeps picking")
				for name: String in ["SideLeft", "SideRight"]:
					var side := tile.get_node("ArtRoot/" + name) as Polygon2D
					var original := reference.get_node("ArtRoot/" + name) as Polygon2D
					check(side.polygon == original.polygon and side.visible == original.visible, "side geometry/depth unchanged")
					var points := side.polygon.duplicate()
					tile.sync_scene_art()
					check(side.polygon == points, "repeated sync does not accumulate side depth")
				var wall := tile.get_node("ArtRoot/DungeonWallTop") as Polygon2D
				check(wall.visible == (tile_role == BattleDemoIsoVisual.Role.WALL), "wall top follows role")
				if wall.visible: check(_uv_is_covered(wall, image_a if x < 4 else image_b), "wall UV has source coverage")
		tile.apply_view(_tile_values(Vector2i(x, 2), BattleDemoIsoVisual.Role.FLOOR, 0, true), config)
		check(_visible_floor_piece(tile) == null and not (tile.get_node("ArtRoot/DungeonWallTop") as Polygon2D).visible,
			"VOID shows no dungeon top")
		check(not (tile.get_node("ArtRoot/SideLeft") as Polygon2D).visible and not (tile.get_node("ArtRoot/SideRight") as Polygon2D).visible,
			"VOID shows no dungeon sides")
	var after_ids: Array[int] = []
	for child: Node in tile.get_node("ArtRoot/GroundSurface").get_children(): after_ids.append(child.get_instance_id())
	check(after_ids == ids, "terrain refresh preserves all authored child nodes")
	tile.free()
	reference.free()

func run() -> void:
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	var started := ExpeditionTransitions.apply(profile, "start")
	check(started.is_ok() and started.profile.expedition.current_node().layer == 0,
		"fixture starts on a real layer-zero expedition node")
	if not started.is_ok():
		print("DUNGEON ROOM COMPARISON RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	profile = started.profile
	var route_helper := HeroHubScreen.new()
	check(HeroHubScreen._is_first_expedition_run(profile), "production route selector accepts first expedition room")
	var later := _later_battle(profile)
	check(later != null and later.expedition.current_node().layer > 0, "fixture reaches a real later battle node")
	check(not HeroHubScreen._is_first_expedition_run(later), "production route selector rejects later expedition room")
	var legacy := HeroHubState.create(9404)
	check(legacy.start_battle(), "legacy battle fixture starts")
	check(not HeroHubScreen._is_first_expedition_run(legacy), "production route selector rejects legacy battle")
	var detached_view := BATTLE_SCENE.instantiate() as HeroHubBattleView
	check(not route_helper._configure_first_room_art(detached_view, later)
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("tile_visual_scene") == DEFAULT_TILE,
		"later expedition keeps the existing tile scene")
	check(not route_helper._configure_first_room_art(detached_view, legacy)
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("tile_visual_scene") == DEFAULT_TILE,
		"legacy battle keeps the existing tile scene")
	detached_view.free()
	route_helper.free()
	check(BattleVisualSceneContract.validate(COMPARISON_TILE, BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE).is_empty(),
		"comparison preset passes managed terrain lifecycle validation")
	_check_tile_contract()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	save_path = "user://dungeon-comparison-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(HeroHubStore.write_run(save_path, profile).is_empty(), "isolated first-room checkpoint is saved")
	var saved_profile := profile.to_dict()
	screen = HUB_SCENE.instantiate() as HeroHubScreen
	screen.save_path = save_path
	screen.expedition_mode = true
	screen.mage_deck_mode = true
	viewport.add_child(screen)
	screen.set_process(false)
	if screen.battle_view != null: screen.battle_view.set_process(false)
	await process_frame
	await process_frame
	var battle := screen.battle_view
	check(battle != null and battle.session != null and battle.board_view.tile_visual_scene == COMPARISON_TILE,
		"real HeroHubScreen first-room route selects the comparison tile before board setup")
	if battle == null:
		print("DUNGEON ROOM COMPARISON RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	battle.set_process(false)
	_check_first_room_layers(battle.board_view)
	var live_session := battle.session as BattleCoreReactionsSession
	var baseline := snapshot(live_session)
	var terrain_ids := _terrain_ids(battle.board_view)
	battle.board_view.refresh()
	check(_terrain_ids(battle.board_view) == terrain_ids, "live refresh preserves terrain identities")
	check(snapshot(live_session) == baseline, "terrain refresh preserves live snapshot and RNG")
	for zoom: float in [0.75, 1.0, 1.25]: await _capture_zoom(zoom, baseline)
	check(_terrain_ids(battle.board_view) == terrain_ids, "zoom preserves terrain identities")
	check(battle.can_restart_checkpoint(), "first-room battle exposes restart from its checkpoint")
	if battle.can_restart_checkpoint():
		var old_battle_id := battle.get_instance_id()
		battle.restart_requested.emit()
		var restarted := screen.battle_view
		if restarted != null: restarted.set_process(false)
		await process_frame
		await process_frame
		check(restarted != null and restarted.get_instance_id() != old_battle_id
			and restarted.board_view.tile_visual_scene == COMPARISON_TILE,
			"production restart recreates first room with comparison scene")
		check(screen.run.to_dict() == saved_profile and HeroHubStore.read_run(save_path).run.to_dict() == saved_profile,
			"restart preserves profile and stored checkpoint")
		if restarted != null:
			# Фабрика создаёт новые UnitId; сравнивать сырые ID разных сессий неверно.
			var restarted_snapshot := snapshot(restarted.session as BattleCoreReactionsSession)
			check(restarted_snapshot.rng == baseline.rng and restarted_snapshot.counters == baseline.counters
				and restarted_snapshot.phase == baseline.phase,
				"restart restores checkpoint RNG, command counters and phase")
			_check_first_room_layers(restarted.board_view)
	if screen.battle_view != null: screen._clear_battle()
	screen.queue_free()
	viewport.queue_free()
	await process_frame
	if not save_path.is_empty():
		var absolute := ProjectSettings.globalize_path(save_path)
		if FileAccess.file_exists(save_path): DirAccess.remove_absolute(absolute)
		if FileAccess.file_exists(save_path + ".bak"): DirAccess.remove_absolute(absolute + ".bak")
	print("DUNGEON ROOM COMPARISON RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
