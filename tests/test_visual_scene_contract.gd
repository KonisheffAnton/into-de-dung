extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
const TRIAL_TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL VISUAL SCENE CONTRACT: " + label)


func _pack(node: Node) -> PackedScene:
	var packed := PackedScene.new()
	check(packed.pack(node) == OK, "dynamic fixture scene packs " + node.get_class())
	node.free()
	return packed


func _audit(session: BattleCoreReactionsSession) -> Dictionary:
	return {
		"snapshot": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(),
	}


func _terrain_ids(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {}
	for key: Vector3i in board._terrain_visuals:
		var visual := board._terrain_visuals[key] as BattleTerrainVisual
		result[key] = visual.get_instance_id()
	return result


func _apply_count_snapshot(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {"terrain": {}, "environment": {}}
	for key: Vector3i in board._terrain_visuals:
		var visual := board._terrain_visuals[key] as BattleTerrainVisual
		result.terrain[key] = visual.view_apply_count
	for cell: Vector2i in board._environment_visuals:
		var visual := board._environment_visuals[cell] as BattleManagedEnvironmentVisual
		result.environment[cell] = visual.view_apply_count
	return result


func _exercise_dynamic_scenes(terrain_scene: PackedScene, environment_scene: PackedScene) -> void:
	var custom_board := BattleDemoBoard.new()
	custom_board.size = Vector2(500.0, 360.0)
	custom_board.tile_visual_scene = terrain_scene
	custom_board.environment_visual_scene = environment_scene
	viewport.add_child(custom_board)
	await process_frame
	var heights := PackedInt32Array()
	heights.resize(4)
	var terrain := PackedByteArray()
	terrain.resize(4)
	terrain.fill(TerrainType.Type.FLOOR)
	var cell := Vector2i.ZERO
	var state := {
		"width": 2,
		"height": 2,
		"heights": heights,
		"terrain": terrain,
		"units": {},
		"fires": [{"cell": cell, "effect": "spikes"}],
		"corpses": [],
		"collapse": {},
		"hazards": {"acid": [cell], "traps": []},
	}
	custom_board.show_presentation_state(state)
	var terrain_visual := _terrain_at(custom_board, cell)
	var environment_visual := custom_board._environment_visuals.get(cell) as BattleManagedEnvironmentVisual
	check(terrain_visual != null and environment_visual != null,
		"dynamically packed managed visual scenes instantiate on a production board")
	if terrain_visual != null and environment_visual != null:
		check(terrain_visual.get_script() == BattleTerrainVisual and environment_visual.get_script() == BattleManagedEnvironmentVisual,
			"board retains both dynamically packed root types")
		var ids := _terrain_ids(custom_board)
		var counts := custom_board.visual_lifecycle_counts()
		var applies := _apply_count_snapshot(custom_board)
		custom_board.show_presentation_state(state)
		check(_terrain_ids(custom_board) == ids and custom_board._environment_visuals.get(cell) == environment_visual
			and custom_board.visual_lifecycle_counts() == counts,
			"second publication preserves dynamic scene identities and lifecycle counts")
		check(_apply_count_snapshot(custom_board) == applies,
			"second dynamic publication skips unchanged terrain and environment applies")
	custom_board.queue_free()
	await process_frame


func _run() -> void:
	var environment: PackedScene = BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE
	check(BattleVisualSceneContract.validate(BattleDemoBoard.DEFAULT_TILE_SCENE, environment).is_empty(),
		"default authored visual scenes satisfy the admission gate")
	check(BattleVisualSceneContract.validate(TRIAL_TILE, environment).is_empty(),
		"current art trial scenes satisfy the admission gate")
	var trial_probe := TRIAL_TILE.instantiate()
	var hero_scene: PackedScene = load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene
	var hero_probe := hero_scene.instantiate() if hero_scene != null else null
	var hero_board := hero_probe.get_node_or_null("BattleHUD/Margin/Column/Content/Left/Field/Board") as BattleDemoBoard if hero_probe != null else null
	check(trial_probe is BattleTerrainVisual and hero_board != null
		and BattleVisualSceneContract.validate(hero_board.tile_visual_scene, hero_board.environment_visual_scene).is_empty(),
		"actual trial root and current Hero Hub battle board scenes satisfy admission")
	if trial_probe != null: trial_probe.free()
	if hero_probe != null: hero_probe.free()
	var custom_terrain := _pack(BattleTerrainVisual.new())
	var custom_environment := _pack(BattleManagedEnvironmentVisual.new())
	check(BattleVisualSceneContract.validate(custom_terrain, custom_environment).is_empty(),
		"explicitly managed custom scenes pass without filename allowlisting")
	var legacy_terrain := _pack(BattleDemoIsoVisual.new())
	var legacy_environment := _pack(BattleEnvironmentVisual.new())
	check(not BattleVisualSceneContract.validate(legacy_terrain, custom_environment).is_empty(),
		"legacy terrain parent is rejected")
	check(not BattleVisualSceneContract.validate(custom_terrain, legacy_environment).is_empty(),
		"raw legacy environment parent is rejected")
	check(not BattleVisualSceneContract.validate(null, custom_environment).is_empty()
		and not BattleVisualSceneContract.validate(custom_terrain, null).is_empty(),
		"missing scenes are reported")
	var invalid_environment := _pack(Node2D.new())
	check(not BattleVisualSceneContract.validate(custom_terrain, invalid_environment).is_empty(),
		"wrong environment root type is reported")
	var invalid_terrain := _pack(Node2D.new())
	check(not BattleVisualSceneContract.validate(invalid_terrain, custom_environment).is_empty(),
		"wrong terrain root type is reported")

	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _exercise_dynamic_scenes(custom_terrain, custom_environment)
	var trial := preload("res://scenes/demo/art_trial_battle.tscn").instantiate() as BattleDemo
	viewport.add_child(trial)
	await process_frame
	check(trial.is_processing(), "production scene keeps normal frame processing enabled")
	var session := trial.session as BattleCoreReactionsSession
	var board := trial.board_view
	var published: Dictionary = ActionPresentationState.capture(session.state)
	var cell := _first_floor_cell(board)
	var effects := published.duplicate(true)
	effects["fires"] = [{"cell": cell, "effect": "spikes"}]
	effects["hazards"] = {"acid": [cell], "traps": []}
	var baseline := _audit(session)
	board.show_presentation_state(effects)
	var counts := board.visual_lifecycle_counts()
	var identities := _terrain_ids(board)
	var applies := _apply_count_snapshot(board)
	board.show_presentation_state(effects)
	check(_terrain_ids(board) == identities and board.visual_lifecycle_counts() == counts,
		"identical publications preserve managed terrain identities and lifecycle counts")
	check(_apply_count_snapshot(board) == applies,
		"identical production publication leaves managed apply counts unchanged")
	check(_audit(session) == baseline, "passive visual publication preserves battle snapshot, RNG and counters")

	var terrain := _terrain_at(board, cell)
	if terrain != null:
		var apply_count := terrain.view_apply_count
		board._view_fires = [{"cell": cell, "effect": "burning"}]
		board._rebuild_visuals()
		check(terrain.burning and terrain.view_apply_count > apply_count,
			"changed visual values apply even though no runtime revision changed")
		var config_count := terrain.view_apply_count
		var old_size := board.grid_config.tile_size
		board.grid_config.tile_size = old_size * 1.1
		board._rebuild_visuals()
		var art_root := terrain.get_node_or_null("ArtRoot") as Node2D
		check(terrain.view_apply_count > config_count and art_root != null
			and art_root.scale.is_equal_approx(Vector2.ONE * board.grid_config.tile_size.x / 128.0),
			"in-place tile geometry updates the managed root scale")
		var next_count := terrain.view_apply_count
		board._view_heights[cell.y * board._view_width + cell.x] = 2
		var old_height_step := board.grid_config.height_step
		board.grid_config.height_step = old_height_step + 10.0
		board._rebuild_visuals()
		check(terrain.view_apply_count > next_count and terrain.half_steps == 2
			and is_equal_approx(terrain.get_visual_offset().y, -board.grid_config.height_step),
			"in-place height geometry moves a raised support by its current step")
		var old_origin := board.grid_config.origin_offset
		board.grid_config.origin_offset += Vector2(17.0, 11.0)
		var origin_count := terrain.view_apply_count
		board._rebuild_visuals()
		check(terrain.view_apply_count > origin_count
			and terrain.position.is_equal_approx(IsoGridUtils.grid_to_screen(cell, board.grid_config, 0) + Vector2(0.0, -0.5)),
			"in-place origin geometry updates the support position")
		board.grid_config.tile_size = old_size
		board.grid_config.height_step = old_height_step
		board.grid_config.origin_offset = old_origin
		board._view_heights[cell.y * board._view_width + cell.x] = 0
		board._view_fires.clear()
		board._rebuild_visuals()
		terrain.presentation_lift = 0.5
		terrain.reset_view_pose()
		check(terrain.presentation_lift == 0.0, "terrain pose reset clears a prior sample")
	else:
		check(false, "production board contains a managed terrain support")

	PlayerTurnFixture.enter_player_turn(trial)
	var final_states: Array[Dictionary] = []
	trial._presentation_player.frame_finished.connect(func(value: Dictionary) -> void: final_states.append(value))
	var move_counts := board.visual_lifecycle_counts()
	var move_ids := _terrain_ids(board)
	for _warmup: int in 10:
		await process_frame
	var movement_samples_ms: Array[float] = []
	var deadline := Time.get_ticks_msec() + 30000
	while (movement_samples_ms.size() < 90 or trial._execution_worker.is_started() or trial.is_presentation_pending()) \
		and Time.get_ticks_msec() < deadline:
		var frame_started_usec: int = Time.get_ticks_usec()
		if movement_samples_ms.is_empty(): trial._execute_live(&"move_to", [Vector2i(1, 2)])
		await process_frame
		movement_samples_ms.append(float(Time.get_ticks_usec() - frame_started_usec) / 1000.0)
	check(not trial._execution_worker.is_started() and not trial.is_presentation_pending(),
		"ordinary production movement and presentation complete through normal processing")
	check(movement_samples_ms.size() >= 90, "movement frame diagnostic collects its fixed sample window")
	_report_movement_frame_metrics(movement_samples_ms)
	check(not final_states.is_empty(), "movement publishes a final presentation state")
	var moved_cell := board._view_unit_cell(session.units[0].id)
	check(moved_cell == Vector2i(1, 2) and session.units[0].cell == moved_cell,
		"production movement and its live owner reach the actual destination")
	if not final_states.is_empty():
		var rows: Dictionary = final_states.back().get("units", {})
		check(rows.has(session.units[0].id) and rows[session.units[0].id].cell == moved_cell,
			"final presentation agrees with the live unit position")
	check(_terrain_ids(board) == move_ids and board.visual_lifecycle_counts() == move_counts,
		"ordinary movement retains terrain identities and does not create or retire terrain")

	var lifecycle_before_swap := board.visual_lifecycle_counts()
	board.tile_visual_scene = BattleDemoBoard.DEFAULT_TILE_SCENE
	board.refresh()
	var lifecycle_after_swap := board.visual_lifecycle_counts()
	check(lifecycle_after_swap.terrain_retired > lifecycle_before_swap.terrain_retired,
		"terrain scene swap retires the previous managed supports")
	var replacement_session := BattleCoreReactionsSession.new()
	var before_board_swap := board.visual_lifecycle_counts()
	board.session = replacement_session
	board.refresh()
	var after_board_swap := board.visual_lifecycle_counts()
	check(after_board_swap.terrain_retired > before_board_swap.terrain_retired,
		"battle board identity swap retires previous managed supports")
	replacement_session.close()
	viewport.queue_free()
	await process_frame
	print("VISUAL SCENE CONTRACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _terrain_at(board: BattleDemoBoard, cell: Vector2i) -> BattleTerrainVisual:
	for visual: BattleTerrainVisual in board._terrain_visuals.values():
		if visual.grid_anchor == cell and visual.role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM]:
			return visual
	return null


func _first_floor_cell(board: BattleDemoBoard) -> Vector2i:
	for y: int in board._view_height:
		for x: int in board._view_width:
			var cell := Vector2i(x, y)
			if board._view_terrain_at(cell) == TerrainType.Type.FLOOR: return cell
	return Vector2i(3, 3)


func _report_movement_frame_metrics(samples_ms: Array[float]) -> void:
	# Окно фиксировано для сопоставимых запусков; значения остаются диагностикой, без порога допуска.
	if samples_ms.is_empty(): return
	samples_ms.sort()
	var over_25_ms: int = 0
	var maximum_ms: float = 0.0
	for sample_ms: float in samples_ms:
		if sample_ms > 25.0: over_25_ms += 1
		maximum_ms = maxf(maximum_ms, sample_ms)
	var middle: int = samples_ms.size() / 2
	var median_ms: float = (samples_ms[middle - 1] + samples_ms[middle]) * 0.5 if samples_ms.size() % 2 == 0 else samples_ms[middle]
	var p95_ms: float = samples_ms[ceili(float(samples_ms.size()) * 0.95) - 1]
	print("VISUAL SCENE MOVEMENT FRAME MS: median=%.3f p95=%.3f max=%.3f over25=%d samples=%d" % [
		median_ms, p95_ms, maximum_ms, over_25_ms, samples_ms.size()])
