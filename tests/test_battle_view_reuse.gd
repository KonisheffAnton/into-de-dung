extends SceneTree

var passed: int = 0
var failed: int = 0
var board: BattleDemoBoard

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
	var custom := PackedScene.new()
	var template := BattleDemoIsoVisual.new()
	template.scale = Vector2(1.1, 1.2)
	check(custom.pack(template) == OK, "custom scene fixture packs")
	template.free()
	board.tile_visual_scene = custom
	board.show_presentation_state(state)
	var first_custom := floor_at(cell)
	check(first_custom != original and first_custom.scale == Vector2(1.1, 1.2), "custom scene replaces default and preserves authored transform")
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
	check(snapshot(session) == committed, "display reuse never mutates live snapshot RNG counters")
	board.session = null
	viewport.queue_free()
	await process_frame
	await process_frame
	session.close()
	next_session.close()
	print("BATTLE VIEW REUSE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
