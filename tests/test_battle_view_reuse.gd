extends SceneTree

var passed: int = 0
var failed: int = 0
var board: BattleDemoBoard
const ART_TRIAL_TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE VIEW REUSE: " + label)

func floor_at(cell: Vector2i) -> BattleDemoIsoVisual:
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.grid_anchor == cell and visual.role in [BattleDemoIsoVisual.Role.FLOOR, BattleDemoIsoVisual.Role.PLATFORM]: return visual
	return null

func wall_at(cell: Vector2i) -> BattleDemoIsoVisual:
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.grid_anchor == cell and visual.role == BattleDemoIsoVisual.Role.WALL: return visual
	return null

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(), "rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters()}

func exercise_environment_reuse(scene: PackedScene, label: String, state: Dictionary, cell: Vector2i, session: BattleCoreReactionsSession, committed: Dictionary) -> void:
	board.tile_visual_scene = scene
	board.environment_visual_scene = BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE
	var effects := state.duplicate(true)
	effects.fires = [{"cell": cell, "effect": "spikes"}]
	effects.hazards = {"acid": [cell], "traps": [{"cell": cell, "kind": "wall", "direction": Vector2i.LEFT, "armed_team": 1}]}
	effects.corpses = [{"cell": cell, "faction": 2, "source_unit_id": 41}]
	board.show_presentation_state(effects)
	var overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	check(overlay != null and overlay.get_parent() == floor_at(cell), label + " default overlay attaches to retained floor")
	check(overlay.acid_pool and overlay.wall_trap_direction == Vector2i.LEFT and overlay.trap_armed and overlay.has_spikes, label + " overlay applies acid, wall trap direction, armed rim and spikes")
	check(overlay.corpse_records.size() == 1 and overlay.corpse_records[0].faction == 2, label + " overlay publishes corpse details")
	board.show_presentation_state(effects)
	check(board._environment_visuals[cell] == overlay, label + " unchanged publication retains overlay identity")
	board._view_corpses[0].faction = 3
	check(overlay.corpse_records[0].faction == 2, label + " overlay corpse records are deeply detached")
	var floor_trap := effects.duplicate(true)
	floor_trap.hazards = {"acid": [], "traps": [{"cell": cell, "kind": "floor", "direction": Vector2i.ZERO, "armed_team": -1}]}
	floor_trap.corpses = []
	var wall_reconfigured := effects.duplicate(true)
	wall_reconfigured.hazards = {"acid": [], "traps": [{"cell": cell, "kind": "wall", "direction": Vector2i.RIGHT, "armed_team": -1}]}
	wall_reconfigured.corpses = [{"cell": cell, "faction": 1, "source_unit_id": 42}]
	board.show_presentation_state(wall_reconfigured)
	check(board._environment_visuals[cell] == overlay and overlay.wall_trap_direction == Vector2i.RIGHT and not overlay.trap_armed and not overlay.acid_pool and overlay.corpse_records[0].faction == 1, label + " fresh wall direction, armed state, acid and corpse values replace old data")
	board.show_presentation_state(floor_trap)
	check(board._environment_visuals[cell] == overlay and overlay.floor_trap and not overlay.acid_pool and overlay.wall_trap_direction == Vector2i.ZERO and not overlay.trap_armed, label + " fresh floor trap values replace prior environment values")
	overlay.trap_progress = 0.6
	overlay.collapse_progress = 0.6
	overlay.hazard_progress = 0.6
	board.show_presentation_state(floor_trap)
	check(board._environment_visuals[cell] == overlay and overlay.trap_progress == -1.0 and overlay.collapse_progress == -1.0 and overlay.hazard_progress == -1.0, label + " new after clears stale overlay progress")
	var collapse_cell := cell + Vector2i(0, 1)
	var pose_state := floor_trap.duplicate(true)
	var collapse_index: int = int(pose_state.width) * collapse_cell.y + collapse_cell.x
	pose_state.terrain[collapse_index] = TerrainType.Type.FLOOR
	board.show_presentation_state(pose_state)
	board._field_presentation.sample_trap(0.5, board, cell, "floor")
	board._field_presentation.sample_cell(0.5, board, collapse_cell, &"collapse")
	var collapse_overlay := board._environment_visuals[collapse_cell] as BattleEnvironmentVisual
	board.execution_pending = true
	var old_size := board.size
	board.size += Vector2(24, 18)
	board._rescale_layout()
	check(board._environment_visuals[cell] == overlay and is_equal_approx(overlay.trap_progress, 0.5), label + " resize restores active floor trap on same overlay")
	check(board._environment_visuals[collapse_cell] == collapse_overlay and is_equal_approx(collapse_overlay.collapse_progress, 0.5), label + " resize restores active collapse on same forced overlay")
	board.size = old_size
	board._rescale_layout()
	board.execution_pending = false
	board._field_presentation.clear()
	board.show_presentation_state(state)
	check(not board._environment_visuals.has(cell) and overlay.is_queued_for_deletion() and overlay.get_parent() == null, label + " expired effect removes and detaches overlay")
	board.show_presentation_state(effects)
	var default_overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	var custom_scene := PackedScene.new()
	var custom_root := BattleEnvironmentVisual.new()
	check(custom_scene.pack(custom_root) == OK, label + " custom environment fixture packs")
	custom_root.free()
	board.environment_visual_scene = custom_scene
	board.show_presentation_state(effects)
	var custom_overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	check(custom_overlay != null and custom_overlay != default_overlay and default_overlay.is_queued_for_deletion() and default_overlay.get_parent() == null, label + " environment scene switch retires default overlay")
	board.show_presentation_state(effects)
	check(board._environment_visuals[cell] != custom_overlay, label + " custom environment scene keeps fresh lifecycle")
	board.environment_visual_scene = BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE
	board.show_presentation_state(effects)
	var restored_overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	check(restored_overlay != custom_overlay and restored_overlay.acid_pool, label + " default environment scene restores authored overlay")
	var smaller := effects.duplicate(true)
	smaller.width = 4
	smaller.height = 4
	smaller.heights = PackedInt32Array()
	smaller.heights.resize(16)
	smaller.terrain = PackedByteArray()
	smaller.terrain.resize(16)
	smaller.terrain.fill(TerrainType.Type.FLOOR)
	smaller.units = {}
	board.show_presentation_state(smaller)
	var resized_overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	check(resized_overlay != restored_overlay and restored_overlay.is_queued_for_deletion() and restored_overlay.get_parent() == null, label + " dimensions change invalidates old floor overlay")
	board.show_presentation_state(state)
	check(snapshot(session) == committed, label + " overlay synchronization leaves snapshot and RNG unchanged")
	var first_board := BattleBoard.new()
	var second_board := BattleBoard.new()
	board._shown_board = first_board
	board.show_presentation_state(effects)
	var first_board_overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	board._shown_board = second_board
	board.show_presentation_state(effects)
	check(first_board_overlay.is_queued_for_deletion() and first_board_overlay.get_parent() == null, label + " board identity change invalidates parent overlay")
	board._shown_board = null
	board.show_presentation_state(state)
	board._field_presentation.clear()

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = Vector2(1280, 850)
	viewport.add_child(board)
	var session := BattleCoreReactionsSession.new()
	var committed := snapshot(session)
	var state := ActionPresentationState.capture(session.state)
	var cell := Vector2i(3, 3)
	var index: int = cell.y * int(state.width) + cell.x
	state.terrain[index] = TerrainType.Type.FLOOR
	state.heights[index] = 0
	state.fires = []
	state.corpses = []
	state.collapse = {"turn": 0, "marked": []}
	board.show_presentation_state(state)
	var original := floor_at(cell)
	var ids: Dictionary = {}
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT: ids[Vector3i(visual.grid_anchor.x, visual.grid_anchor.y, int(visual.role))] = visual.get_instance_id()
	for i: int in 6: board.show_presentation_state(state)
	var stable := true
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT:
			stable = stable and ids.get(Vector3i(visual.grid_anchor.x, visual.grid_anchor.y, int(visual.role))) == visual.get_instance_id()
	check(stable and floor_at(cell) == original, "unchanged publications keep every standard terrain node")
	check(board._entities.get_child_count() == board._entity_visuals.size(), "no retired nodes remain attached")
	var changed := state.duplicate(true)
	changed.heights[index] = 2
	changed.fires = [{"cell": cell, "effect": "burning"}]
	changed.collapse = {"turn": 1, "marked": [cell]}
	board.show_presentation_state(changed)
	check(floor_at(cell) == original and original.role == BattleDemoIsoVisual.Role.PLATFORM and original.half_steps == 2 and original.burning, "height role and fire update on retained floor")
	check(board._environment_visuals.has(cell) and (board._environment_visuals[cell] as BattleEnvironmentVisual).is_warning, "new snapshot builds matching warning overlay")
	board._field_presentation.sample_cell(0.5, board, cell, &"collapse")
	check(original.modulate.a < 1.0 and original.presentation_lift > 0.0, "collapse changes retained support pose")
	board.execution_pending = true
	board.size += Vector2(36, 24)
	board._rescale_layout()
	check(floor_at(cell) == original and is_equal_approx(original.modulate.a, 0.5), "resize restores active collapse pose on same floor")
	var overlay := board._environment_visuals[cell] as BattleEnvironmentVisual
	check(is_equal_approx(overlay.collapse_progress, 0.5) and overlay.get_parent() == original, "resize restores overlay pose and ownership")
	board.show_presentation_state(state)
	check(floor_at(cell) == original and original.presentation_lift == 0.0 and original.modulate == Color.WHITE and not original.burning, "new after resets old collapse and burning")
	check(not board._environment_visuals.has(cell) and not original.get_node("ArtRoot/EffectRoot/BurningSprite").visible, "expired overlay and fire art disappear")
	board.execution_pending = false
	board._reachable = {cell: 0.0}
	board._rebuild_visuals()
	check(original.reachable, "reachable highlight updates retained terrain")
	board.show_presentation_state(state)
	check(not original.reachable, "presentation clears stale movement highlight")
	changed = state.duplicate(true)
	changed.terrain[index] = TerrainType.Type.WALL
	board.show_presentation_state(changed)
	var wall := wall_at(cell)
	check(wall != null and floor_at(cell) == original, "wall adds separate node without replacing support")
	board.show_presentation_state(changed)
	check(wall_at(cell) == wall, "unchanged wall keeps identity")
	check(original.get_index() < wall.get_index(), "wall stays after its support in equal-depth order")
	board.show_presentation_state(state)
	check(wall_at(cell) == null and wall.is_queued_for_deletion() and wall.get_parent() == null, "removed wall leaves picking and scene tree")
	changed = state.duplicate(true)
	changed.terrain[index] = TerrainType.Type.VOID
	board.show_presentation_state(changed)
	check(floor_at(cell) == original and original.is_void, "collapsed support receives VOID state")
	board.show_presentation_state(state)
	check(not original.is_void, "restored floor clears VOID state")
	exercise_environment_reuse(BattleDemoBoard.DEFAULT_TILE_SCENE, "default floor", state, cell, session, committed)
	# Trial сцена проходит тот же жизненный цикл: вариации и seam остаются авторскими.
	board.tile_visual_scene = ART_TRIAL_TILE_SCENE
	board.show_presentation_state(state)
	exercise_environment_reuse(ART_TRIAL_TILE_SCENE, "trial floor", state, cell, session, committed)
	board.show_presentation_state(state)
	var trial_floor := floor_at(cell)
	check(trial_floor != null and trial_floor != original and trial_floor.scene_file_path == ART_TRIAL_TILE_SCENE.resource_path, "default to trial switches to the authored trial scene")
	check(original.is_queued_for_deletion() and original.get_parent() == null, "default node is retired when scene identity changes")
	var expected_variant: int = 2
	var visible_variants: int = 0
	for variant_index: int in range(4):
		var grass := trial_floor.get_node("ArtRoot/GroundSurface/Grass%d" % variant_index) as Polygon2D
		if grass.visible: visible_variants += 1
		check(grass.visible == (variant_index == expected_variant), "trial cell selects authored grass variant %d" % variant_index)
	check(visible_variants == 1, "trial surface shows exactly one grass variant")
	board.show_presentation_state(state)
	check((trial_floor.get_node("ArtRoot/GroundSurface/Grass2") as Polygon2D).visible, "repeated trial apply keeps the selected grass variant")
	for zoom: float in [0.75, 1.0, 1.25]:
		board.zoom_camera(zoom, board.size * 0.5)
		await process_frame
		var seam := trial_floor.get_node("ArtRoot/GroundSurface/QuietSeam") as Line2D
		var transform := seam.get_screen_transform()
		var screen_scale: float = minf(transform.x.length(), transform.y.length())
		check(seam.visible and seam.width * screen_scale >= 1.14, "trial seam stays visible at least 1.15 pixels at zoom %.2f" % zoom)
	var old_canvas_transform: Transform2D = viewport.canvas_transform
	viewport.canvas_transform = Transform2D(Vector2(0.833, 0.0), Vector2(0.0, 0.917), Vector2(0.5, 0.25))
	await process_frame
	await process_frame
	var fractional_seam := trial_floor.get_node("ArtRoot/GroundSurface/QuietSeam") as Line2D
	var fractional_transform := fractional_seam.get_screen_transform()
	var fractional_scale: float = minf(fractional_transform.x.length(), fractional_transform.y.length())
	check(fractional_seam.width * fractional_scale >= 1.14, "trial seam minimum survives fractional canvas scale")
	check(floor_at(cell) == trial_floor, "canvas-only scale updates the seam without replacing the retained tile")
	viewport.canvas_transform = old_canvas_transform
	board.reset_camera()
	check(snapshot(session) == committed, "trial variant and seam synchronization preserve snapshot, RNG and counters")
	var trial_ids: Dictionary = {}
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT: trial_ids[Vector3i(visual.grid_anchor.x, visual.grid_anchor.y, int(visual.role))] = visual.get_instance_id()
	for i: int in 6: board.show_presentation_state(state)
	var trial_stable := true
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT:
			trial_stable = trial_stable and trial_ids.get(Vector3i(visual.grid_anchor.x, visual.grid_anchor.y, int(visual.role))) == visual.get_instance_id()
	check(trial_stable and floor_at(cell) == trial_floor, "unchanged publications keep every trial terrain node")
	board.tile_visual_scene = BattleDemoBoard.DEFAULT_TILE_SCENE
	board.show_presentation_state(state)
	var direct_default := floor_at(cell)
	check(direct_default != trial_floor and direct_default.scene_file_path == BattleDemoBoard.DEFAULT_TILE_SCENE.resource_path and trial_floor.is_queued_for_deletion(), "direct trial to default transition retires trial node")
	board.tile_visual_scene = ART_TRIAL_TILE_SCENE
	board.show_presentation_state(state)
	trial_floor = floor_at(cell)
	check(trial_floor != direct_default and trial_floor.scene_file_path == ART_TRIAL_TILE_SCENE.resource_path, "direct default to trial transition rebuilds correct scene")
	changed = state.duplicate(true)
	changed.heights[index] = 2
	changed.fires = [{"cell": cell, "effect": "burning"}]
	changed.collapse = {"turn": 1, "marked": [cell]}
	board.show_presentation_state(changed)
	check(floor_at(cell) == trial_floor and trial_floor.role == BattleDemoIsoVisual.Role.PLATFORM and trial_floor.half_steps == 2 and trial_floor.burning, "trial floor applies height and burning values")
	board._field_presentation.sample_cell(0.5, board, cell, &"collapse")
	board.execution_pending = true
	board.size += Vector2(36, 24)
	board._rescale_layout()
	check(floor_at(cell) == trial_floor and is_equal_approx(trial_floor.modulate.a, 0.5), "trial resize restores active collapse pose")
	board.show_presentation_state(state)
	check(floor_at(cell) == trial_floor and trial_floor.presentation_lift == 0.0 and trial_floor.modulate == Color.WHITE and not trial_floor.burning, "trial after clears old collapse and burning state")
	board.execution_pending = false
	changed = state.duplicate(true)
	changed.terrain[index] = TerrainType.Type.WALL
	board.show_presentation_state(changed)
	var trial_wall := wall_at(cell)
	check(trial_wall != null and floor_at(cell) == trial_floor, "trial wall adds separate node and keeps support")
	board.show_presentation_state(changed)
	check(wall_at(cell) == trial_wall, "unchanged trial wall keeps identity")
	board.show_presentation_state(state)
	check(trial_wall.is_queued_for_deletion() and trial_wall.get_parent() == null, "removed trial wall leaves scene tree")
	changed = state.duplicate(true)
	changed.terrain[index] = TerrainType.Type.VOID
	board.show_presentation_state(changed)
	check(floor_at(cell) == trial_floor and trial_floor.is_void, "trial support receives VOID state")
	board.show_presentation_state(state)
	check(not trial_floor.is_void, "trial floor clears VOID state")
	board._reachable = {cell: 0.0}
	board.inspection_cells = {cell: true}
	board.inspected_id = 1
	board._rebuild_visuals()
	check(trial_floor.reachable and trial_floor.enemy_range, "trial floor refreshes movement and inspection highlights")
	board._reachable.clear()
	board.inspection_cells.clear()
	board.inspected_id = UnitId.NONE
	board._rebuild_visuals()
	check(not trial_floor.reachable and not trial_floor.enemy_range, "trial floor clears stale movement and inspection highlights")
	var trial_custom := PackedScene.new()
	var trial_template := BattleDemoIsoVisual.new()
	trial_template.scale = Vector2(1.1, 1.2)
	check(trial_custom.pack(trial_template) == OK, "trial custom scene fixture packs")
	trial_template.free()
	board.tile_visual_scene = trial_custom
	board.show_presentation_state(state)
	var trial_custom_floor := floor_at(cell)
	check(trial_custom_floor != trial_floor and trial_custom_floor.scale == Vector2(1.1, 1.2), "custom scene replaces trial and keeps authored transform")
	board.show_presentation_state(state)
	check(floor_at(cell) != trial_custom_floor, "custom scene after trial keeps fresh lifecycle")
	board.tile_visual_scene = null
	board.show_presentation_state(state)
	check(floor_at(cell) != null and floor_at(cell).get_node_or_null("ArtRoot") == null, "null scene after trial keeps procedural fallback")
	board.tile_visual_scene = BattleDemoBoard.DEFAULT_TILE_SCENE
	board.show_presentation_state(state)
	var restored_default := floor_at(cell)
	check(restored_default != trial_floor and restored_default.scene_file_path == BattleDemoBoard.DEFAULT_TILE_SCENE.resource_path, "trial to default switches scene and retires trial node")
	check(trial_floor.is_queued_for_deletion() and trial_floor.get_parent() == null, "trial node is detached on switch back to default")
	var custom := PackedScene.new()
	var template := BattleDemoIsoVisual.new()
	template.scale = Vector2(1.1, 1.2)
	check(custom.pack(template) == OK, "custom scene fixture packs")
	template.free()
	board.tile_visual_scene = custom
	board.show_presentation_state(state)
	var first_custom := floor_at(cell)
	check(first_custom != restored_default and first_custom.scale == Vector2(1.1, 1.2), "custom scene replaces default and preserves authored transform")
	board.show_presentation_state(state)
	check(floor_at(cell) != first_custom, "custom scene keeps fresh lifecycle per publication")
	board.tile_visual_scene = null
	board.show_presentation_state(state)
	check(floor_at(cell) != null and floor_at(cell).get_node_or_null("ArtRoot") == null, "null scene keeps procedural fallback")
	board.tile_visual_scene = BattleDemoBoard.DEFAULT_TILE_SCENE
	board.show_presentation_state(state)
	var restored := floor_at(cell)
	board.session = session
	board.refresh()
	check(floor_at(cell) != restored, "entering live board invalidates detached terrain ownership")
	var live_floor := floor_at(cell)
	board.refresh()
	check(floor_at(cell) == live_floor, "ordinary refresh also keeps terrain identity")
	var next_session := BattleCoreReactionsSession.new()
	board.session = next_session
	board.refresh()
	check(floor_at(cell) != live_floor, "new board cannot retain previous battle nodes")
	board.tile_visual_scene = ART_TRIAL_TILE_SCENE
	board.refresh()
	var live_trial_floor := floor_at(cell)
	board.refresh()
	check(floor_at(cell) == live_trial_floor, "live board refresh reuses trial terrain nodes")
	board.session = session
	board.refresh()
	check(floor_at(cell) != live_trial_floor, "trial terrain cache invalidates when live board changes")
	board.tile_visual_scene = BattleDemoBoard.DEFAULT_TILE_SCENE
	board.refresh()
	var smaller := state.duplicate(true)
	smaller.width = 4
	smaller.height = 4
	smaller.heights = PackedInt32Array()
	smaller.heights.resize(16)
	smaller.terrain = PackedByteArray()
	smaller.terrain.resize(16)
	smaller.terrain.fill(TerrainType.Type.FLOOR)
	smaller.units = {}
	board.show_presentation_state(smaller)
	check(board._entity_visuals.size() == 16 and board._entities.get_child_count() == 16, "smaller projection retires out-of-bounds nodes")
	board.tile_visual_scene = ART_TRIAL_TILE_SCENE
	board.show_presentation_state(state)
	var wide_trial_floor := floor_at(cell)
	board.show_presentation_state(smaller)
	var small_trial_floor := floor_at(Vector2i(3, 3))
	check(board._entity_visuals.size() == 16 and board._entities.get_child_count() == 16 and small_trial_floor != null, "trial dimensions rebuild to the new extent")
	check(small_trial_floor != wide_trial_floor and wide_trial_floor.is_queued_for_deletion() and wide_trial_floor.get_parent() == null, "trial dimensions invalidate the previous extent ownership")
	board.show_presentation_state(smaller)
	check(floor_at(Vector2i(3, 3)) == small_trial_floor, "trial dimensions retain nodes after the resize publication")
	check(snapshot(session) == committed, "display reuse never mutates live snapshot RNG counters")
	board.session = null
	viewport.queue_free()
	await process_frame
	await process_frame
	session.close()
	next_session.close()
	print("BATTLE VIEW REUSE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
