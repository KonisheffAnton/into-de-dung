extends SceneTree

const HUB_SCENE: PackedScene = preload("res://scenes/demo/hero_hub.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const DEFAULT_TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
const COMPARISON_TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const FLOOR_TEXTURE: Texture2D = preload("res://assets/art_presets/trials/dungeon_room_v2/floor.png")
const MASONRY_TEXTURE: Texture2D = preload("res://assets/art_presets/trials/dungeon_room_v2/masonry.png")
const COLUMN_TEXTURE: Texture2D = preload("res://assets/art_presets/trials/dungeon_room_v2/column.png")

const DUNGEON_ENVIRONMENT: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const FIRE_FRAMES: SpriteFrames = preload("res://assets/art_presets/approved/fire29_natural_v1/fire29_frames.tres")

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
	var floor_count: int = 0
	var column_count: int = 0
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT: continue
		var floor_piece := _visible_floor_piece(visual as BattleTerrainVisual)
		if floor_piece != null:
			floor_count += 1
			check(floor_piece.texture == BiomeArtCatalog.FLOORS[BiomeArtCatalog.index_at(visual.grid_anchor)], "live floor uses the chunk material")
		var column := visual.get_node_or_null("ArtRoot/BrokenColumn") as Sprite2D
		if column != null and column.visible:
			column_count += 1
			check(visual.role == BattleDemoIsoVisual.Role.WALL and BiomeArtCatalog.is_obstacle(visual.grid_anchor),
				"decoration belongs to the existing blocking wall")
			check(column.texture == BiomeArtCatalog.OBSTACLES[BiomeArtCatalog.index_at(visual.grid_anchor)], "obstacle uses its biome drawing")
	check(floor_count == 383, "live room has coherent floor below all non-VOID cells")
	check(column_count == 6, "live room contains six ordinary themed obstacles")

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
			point.x = clampi(point.x, 0, image.get_width() - 1)
			point.y = clampi(point.y, 0, image.get_height() - 1)
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
	var ids: Array[int] = []
	for child: Node in tile.get_node("ArtRoot").get_children(): ids.append(child.get_instance_id())
	var floor_image := FLOOR_TEXTURE.get_image()
	for y: int in range(8):
		for x: int in range(8):
			var cell := Vector2i(x, y)
			tile.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config)
			reference.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config)
			var piece := _visible_floor_piece(tile)
			check(piece != null, "floor exists at %s" % cell)
			if piece == null: continue
			check(piece.texture == FLOOR_TEXTURE, "coherent material at %s" % cell)
			floor_uv[cell] = piece.uv.duplicate()
			check(_uv_is_covered(piece, floor_image), "floor UV has opaque source coverage")
			check(tile.surface_polygons() == reference.surface_polygons(), "floor picking matches existing scene")
			check(not tile.apply_view(_tile_values(cell, BattleDemoIsoVisual.Role.FLOOR), config), "unchanged publication is skipped")
	for cell: Vector2i in floor_uv:
		var uv: PackedVector2Array = floor_uv[cell]
		if cell.x < 7:
			var next: PackedVector2Array = floor_uv[cell + Vector2i.RIGHT]
			check(uv[1] == next[0] and uv[2] == next[3], "adjacent x tile samples exactly the same edge")
		if cell.y < 7:
			var next: PackedVector2Array = floor_uv[cell + Vector2i.DOWN]
			check(uv[3] == next[0] and uv[2] == next[1], "adjacent y tile samples exactly the same edge")
	var expected_density := MASONRY_TEXTURE.get_height() / 256.0
	for factor: float in [0.75, 1.0, 1.25]:
		config.tile_size = Vector2(128, 96) * factor
		config.height_step = 32.0 * factor
		for tile_role: BattleDemoIsoVisual.Role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM, BattleDemoIsoVisual.Role.WALL]:
			for steps: int in [-4, 0, 1, 4]:
				var values := _tile_values(Vector2i(2, 2), tile_role, steps)
				tile.apply_view(values, config)
				reference.apply_view(values, config)
				check(tile.surface_polygons() == reference.surface_polygons(), "role/elevation/scale keeps picking")
				for name: String in ["SideLeft", "SideRight"]:
					var side := tile.get_node("ArtRoot/" + name) as Polygon2D
					var original := reference.get_node("ArtRoot/" + name) as Polygon2D
					check(side.visible == original.visible and side.polygon[0] == original.polygon[0] and side.polygon[1] == original.polygon[1], "higher faces preserve upper edge geometry")
					if tile_role != BattleDemoIsoVisual.Role.WALL:
						check(side.polygon[2].y - side.polygon[1].y >= 63.999, "floor faces have at least64 native pixels of depth")
					check(side.texture == MASONRY_TEXTURE and side.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
						"side uses repeatable independent masonry")
					for edge: Vector2i in [Vector2i(0, 3), Vector2i(1, 2)]:
						var height := side.polygon[edge.y].y - side.polygon[edge.x].y
						var texels := side.uv[edge.y].y - side.uv[edge.x].y
						check(is_equal_approx(texels, height * expected_density), "masonry never stretches vertically with height or viewport scale")
					var points := side.polygon.duplicate()
					var uv := side.uv.duplicate()
					tile.sync_scene_art()
					check(side.polygon == points and side.uv == uv, "repeated sync accumulates neither depth nor texture shift")
				var wall := tile.get_node("ArtRoot/DungeonWallTop") as Polygon2D
				check(wall.visible == (tile_role == BattleDemoIsoVisual.Role.WALL), "ordinary wall keeps masonry and cap")
		for tile_role: BattleDemoIsoVisual.Role in [BattleDemoIsoVisual.Role.WALL, BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.WALL]:
			tile.apply_view(_tile_values(Vector2i(3, 0), tile_role), config)
			reference.apply_view(_tile_values(Vector2i(3, 0), tile_role), config)
			var column := tile.get_node("ArtRoot/BrokenColumn") as Sprite2D
			check(column.visible == (tile_role == BattleDemoIsoVisual.Role.WALL), "column resets across repeated role changes")
			check(is_equal_approx(column.scale.x, column.scale.y), "column has uniform authored scale")
			check(tile.surface_polygons() == reference.surface_polygons(), "column preserves existing obstacle picking footprint")
			if column.visible:
				check(not (tile.get_node("ArtRoot/SideLeft") as Polygon2D).visible
					and not (tile.get_node("ArtRoot/SideRight") as Polygon2D).visible
					and not (tile.get_node("ArtRoot/DungeonWallTop") as Polygon2D).visible,
					"column replaces the old square block")
		for tile_role: BattleDemoIsoVisual.Role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.WALL]:
			tile.apply_view(_tile_values(Vector2i(3, 0), tile_role, 0, true), config)
			check(_visible_floor_piece(tile) == null and not (tile.get_node("ArtRoot/DungeonWallTop") as Polygon2D).visible
				and not (tile.get_node("ArtRoot/BrokenColumn") as Sprite2D).visible, "VOID hides floor, cap and column")
			check(not (tile.get_node("ArtRoot/SideLeft") as Polygon2D).visible and not (tile.get_node("ArtRoot/SideRight") as Polygon2D).visible,
				"VOID hides both masonry sides")
	var after_ids: Array[int] = []
	for child: Node in tile.get_node("ArtRoot").get_children(): after_ids.append(child.get_instance_id())
	check(after_ids == ids, "terrain refresh preserves all authored child nodes")
	tile.free()
	reference.free()

func _check_environment_contract() -> void:
	var overlay := DUNGEON_ENVIRONMENT.instantiate() as BattleManagedEnvironmentVisual
	root.add_child(overlay)
	var corpses: Array[Dictionary] = []
	var values := {"spikes": false, "burning": false, "warning": false, "corpses": corpses,
		"acid": false, "floor_trap": true, "wall_direction": Vector2i.ZERO, "armed": false}
	var presets := {Vector2i.UP: "WallTrapUp", Vector2i.RIGHT: "WallTrapRight",
		Vector2i.DOWN: "WallTrapDown", Vector2i.LEFT: "WallTrapLeft"}
	for direction: Vector2i in presets:
		values.wall_direction = direction
		values.armed = true
		check(overlay.apply_view(values), "dungeon overlay accepts changed hazard view")
		var active := overlay.get_node(presets[direction]) as Node2D
		check(active.visible and (active.get_node("ArmedRim") as Line2D).visible,
			"selected wall direction retains armed warning")
		check((overlay.get_node("FloorTrap/ArmedRim") as Line2D).visible, "floor trap retains armed warning")
		var authored := active.transform
		overlay.trap_progress = 1.0
		var tip := active.get_node("Spikes/Spike01/Tip") as Node2D
		check(is_equal_approx(tip.scale.y, 1.0), "reskinned trap still extends spikes")
		overlay.collapse_progress = 1.0
		check(is_zero_approx(active.modulate.a), "reskinned trap follows collapse fade")
		overlay.reset_view_pose()
		check(active.transform == authored and is_zero_approx(tip.scale.y) and is_equal_approx(active.modulate.a, 1.0),
			"reset restores spike/fade while preserving authored transform")
		values.armed = false
		overlay.apply_view(values)
		check(not (active.get_node("ArmedRim") as Line2D).visible, "disarming removes only armed warning")
		check(not overlay.apply_view(values), "unchanged overlay keeps managed reuse")
	overlay.free()
	var tile := COMPARISON_TILE.instantiate() as BattleTerrainVisual
	root.add_child(tile)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32.0
	var tile_values := _tile_values(Vector2i(4, 4), BattleDemoIsoVisual.Role.FLOOR)
	tile_values.burning = true
	tile.apply_view(tile_values, config)
	var legacy_fire := tile.get_node("ArtRoot/EffectRoot/BurningSprite") as Sprite2D
	var fire := tile._fire_view
	var animation := fire.get_node(^"Animation") as AnimatedSprite2D if fire != null else null
	check(fire != null and fire.visible and animation != null and animation.sprite_frames == FIRE_FRAMES
		and animation.is_playing() and not legacy_fire.visible,
		"burning tile shows selected full-tile fire29 with no old fire underneath")
	tile_values.burning = false
	tile.apply_view(tile_values, config)
	check(fire != null and not fire.visible and not animation.is_playing(), "fire visibility and clock follow published burning state")
	tile.free()

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
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("tile_visual_scene") == DEFAULT_TILE
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("environment_visual_scene") == BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE,
		"later expedition keeps the existing tile scene")
	check(not route_helper._configure_first_room_art(detached_view, legacy)
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("tile_visual_scene") == DEFAULT_TILE
		and detached_view.get_node("BattleHUD/Margin/Column/Content/Left/Field/Board").get("environment_visual_scene") == BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE,
		"legacy battle keeps the existing tile scene")
	detached_view.free()
	route_helper.free()
	check(BattleVisualSceneContract.validate(COMPARISON_TILE, DUNGEON_ENVIRONMENT).is_empty(),
		"comparison preset passes managed terrain lifecycle validation")
	_check_tile_contract()
	_check_environment_contract()
	await _check_hole_pixels()
	_check_all_biome_materials()
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
	check(battle != null and battle.session != null and battle.board_view.tile_visual_scene == COMPARISON_TILE
		and battle.board_view.environment_visual_scene == DUNGEON_ENVIRONMENT,
		"real HeroHubScreen first-room route selects the comparison tile before board setup")
	if battle == null:
		print("DUNGEON ROOM COMPARISON RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	battle.set_process(false)
	_check_first_room_layers(battle.board_view)
	var live_session := battle.session as BattleCoreReactionsSession
	check(live_session.board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.WALL
		and not live_session.board.is_terrain_walkable(Vector2i(3, 0)), "drawn column retains a real blocking obstacle")
	check(not battle.board_view._environment_visuals.has(Vector2i(3, 1)), "column has no attached wall trap")
	var ledge_overlay := battle.board_view._environment_visuals.get(Vector2i(5, 3)) as BattleEnvironmentVisual
	check(ledge_overlay != null and ledge_overlay.wall_trap_direction == Vector2i.LEFT
		and (ledge_overlay.get_node("WallTrapLeft") as Node2D).visible, "live trap panel belongs to raised E4 side")
	var baseline := snapshot(live_session)
	var terrain_ids := _terrain_ids(battle.board_view)
	battle.board_view.refresh()
	check(_terrain_ids(battle.board_view) == terrain_ids, "live refresh preserves terrain identities")
	check(snapshot(live_session) == baseline, "terrain refresh preserves live snapshot and RNG")
	await _capture_showcase(baseline)
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
			and restarted.board_view.tile_visual_scene == COMPARISON_TILE
			and restarted.board_view.environment_visual_scene == DUNGEON_ENVIRONMENT,
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

func _check_all_biome_materials() -> void:
	var tile := COMPARISON_TILE.instantiate() as BattleTerrainVisual
	root.add_child(tile)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32.0
	for index: int in range(6):
		var origin := BiomeShowcaseLayout.CHUNK_ORIGINS[index]
		check(BiomeArtCatalog.index_at(origin) == index, "chunk order follows original six panels")
		for local: Vector2i in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 7), Vector2i(0, 7)]:
			tile.apply_view(_tile_values(origin + local, BattleDemoIsoVisual.Role.FLOOR, 2), config)
			var piece := _visible_floor_piece(tile)
			check(piece.texture == BiomeArtCatalog.FLOORS[index] and _uv_is_covered(piece, piece.texture.get_image()), "each chunk corner has opaque matching material")
			for side_name: String in ["SideLeft", "SideRight"]:
				var side := tile.get_node("ArtRoot/" + side_name) as Polygon2D
				check(side.texture == BiomeArtCatalog.SIDES[index], "each biome owns separate vertical material")
				check(is_equal_approx(side.uv[2].y - side.uv[1].y, (side.polygon[2].y - side.polygon[1].y) * side.texture.get_height() / 256.0), "all biome side materials preserve physical texel density")
		tile.apply_view(_tile_values(origin + Vector2i(3, 0), BattleDemoIsoVisual.Role.WALL), config)
		var prop := tile.get_node("ArtRoot/BrokenColumn") as Sprite2D
		check(prop.visible and prop.texture == BiomeArtCatalog.OBSTACLES[index] and prop.region_rect.has_area(), "all six obstacles have authored sprite regions")
		check(prop.scale.x == prop.scale.y, "obstacle never stretched")
	tile.free()

func _check_hole_pixels() -> void:
	var hole_view := SubViewport.new()
	hole_view.size = Vector2i(640, 480)
	hole_view.transparent_bg = true
	hole_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(hole_view)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 96)
	config.height_step = 32.0
	config.origin_offset = Vector2(320, 140)
	var hole: BattleTerrainVisual
	var sides: Array[Polygon2D] = []
	for diagonal: int in range(5):
		for y: int in range(3):
			var x := diagonal - y
			if x < 0 or x > 2: continue
			var tile := COMPARISON_TILE.instantiate() as BattleTerrainVisual
			hole_view.add_child(tile)
			var values := _tile_values(Vector2i(x, y), BattleDemoIsoVisual.Role.FLOOR, 0, x == 1 and y == 1)
			values.reachable = true if values.is_void else false
			values.enemy_range = true if values.is_void else false
			values.burning = true if values.is_void else false
			tile.apply_view(values, config)
			if values.is_void: hole = tile
			elif Vector2i(x, y) in [Vector2i(0, 1), Vector2i(1, 0)]:
				sides.append(tile.get_node("ArtRoot/SideLeft") as Polygon2D)
				sides.append(tile.get_node("ArtRoot/SideRight") as Polygon2D)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var before := hole_view.get_texture().get_image()
		check(before.get_pixel(320, 270).a < 0.05, "interior hole is transparent down to backdrop")
		check(before.get_pixel(300, 220).a > 0.95 and before.get_pixel(340, 220).a > 0.95, "hole exposes neighboring tall masonry faces")
		hole.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var after := hole_view.get_texture().get_image()
		check(before.get_data() == after.get_data(), "VOID draws no sprite, outline, label, fire or ground marks")
		if not captures.is_empty(): check(before.save_png(captures.path_join("hole-transparent.png")) == OK, "hole render saved")
	for side: Polygon2D in sides: check(side.visible and side.polygon[2].y - side.polygon[1].y >= 63.999, "neighboring faces survive absent support")
	hole_view.queue_free()
	await process_frame

func _capture_showcase(baseline: Dictionary) -> void:
	var board := screen.battle_view.board_view
	check(board._view_width == 24 and board._view_height == 16, "live board displays all384 logical cells")
	check(is_equal_approx(board.camera_view.zoom, board._overview_zoom), "initial large map fits without manual reset")
	board.reset_camera()
	check(board.camera_view.zoom < 0.75, "large map has usable overview below old zoom limit")
	await process_frame
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png(captures.path_join("showcase-overview.png")) == OK, "overview saved")
	for index: int in range(6):
		board.reset_camera()
		board.zoom_camera(0.75, board.size * 0.5)
		var center := BiomeShowcaseLayout.CHUNK_ORIGINS[index] + Vector2i(3, 3)
		board.pan_camera(board.size * 0.5 - board.cell_center(center))
		check(board.cell_center(center).is_equal_approx(board.size * 0.5), "camera reaches each biome center")
		check(board.cell_at(board.cell_center(center)) == center, "picking follows far biome camera")
		await process_frame
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(captures.path_join("biome-%02d.png" % (index + 1))) == OK, "biome detail saved")
	var preserved_ids := _terrain_ids(board)
	var started := Time.get_ticks_usec()
	for _iteration: int in range(10): board.refresh()
	var elapsed := Time.get_ticks_usec() - started
	check(_terrain_ids(board) == preserved_ids, "large-board repeated refresh reuses terrain nodes")
	print("BIOME SHOWCASE METRICS:384 cells; refresh mean %.3f ms; terrain nodes %d" % [float(elapsed) / 10000.0, preserved_ids.size()])
	if not captures.is_empty():
		var metrics := FileAccess.open(captures.path_join("metrics.json"), FileAccess.WRITE)
		metrics.store_string(JSON.stringify({"cells": 384, "terrain_nodes": preserved_ids.size(), "refresh_mean_ms": float(elapsed) / 10000.0}, "  "))
	check(snapshot(screen.battle_view.session as BattleCoreReactionsSession) == baseline, "overview, panning and picking preserve live snapshot and RNG")
	board.reset_camera()
