extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
const TRIAL_TILE = preload("res://scenes/demo/visuals/art_trial_tile.tscn")

class CountingBoard extends BattleDemoBoard:
	var terrain_passes: int = 0
	func _rebuild_terrain() -> void:
		terrain_passes += 1
		super._rebuild_terrain()

class CountingVisual extends BattleDemoIsoVisual:
	var syncs: int = 0
	var redraws: int = 0
	func sync_scene_art() -> void:
		syncs += 1
	func _draw() -> void:
		redraws += 1
		super._draw()

class CountingTerrain extends BattleTerrainVisual:
	var syncs: int = 0
	var ground_overlay_redraws: int = 0
	func sync_scene_art() -> void:
		syncs += 1
	func queue_ground_overlay_redraw() -> void:
		ground_overlay_redraws += 1
		super.queue_ground_overlay_redraw()

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

func _unit_ids(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {}
	for id: int in board._unit_visuals:
		result[id] = board._unit_visuals[id].get_instance_id()
	return result

func _exercise_unit_lifecycle(board: BattleDemoBoard, state: Dictionary) -> void:
	var original_scene := board.unit_visual_scene
	check(BattleVisualSceneContract.validate_unit(original_scene).is_empty(), "actual unit preset accepts lifecycle")
	check(not BattleVisualSceneContract.validate_unit(null).is_empty(), "missing unit preset fails art admission")
	board.show_presentation_state(state)
	var id: int = board._unit_visuals.keys()[0]
	var visual := board._unit_visuals[id]
	var changed := state.duplicate(true)
	changed.units[id].hp -= 1.0
	changed.units[id].main = 0
	changed.units[id].armor["isolation_probe"] = [1]
	board.show_presentation_state(changed)
	check(board._unit_visuals[id] == visual and visual.unit.hp == changed.units[id].hp and visual.action_resources_view.main == 0,
		"unit applies fresh vitals and action resources without a runtime revision")
	changed.units[id].armor.isolation_probe[0] = 2
	check(visual.armor_values.isolation_probe[0] == 1, "unit collections do not alias the publication")
	board.show_presentation_state(state)
	visual.half_steps = 99
	visual.position += Vector2(20, 30)
	visual.presentation_offset = Vector2(4, 5)
	visual.death_progress = 0.7
	board.show_presentation_state(state)
	check(visual.death_progress == 0.0 and visual.presentation_offset == Vector2.ZERO
		and visual.half_steps == board._view_height_steps(state.units[id].cell)
		and visual.position.is_equal_approx(IsoGridUtils.grid_to_screen(state.units[id].cell, board.grid_config, 0)),
		"unchanged publication resets the prior pose and restores actual geometry")
	board._field_presentation.sample_death(0.4, board, id)
	board.execution_pending = true
	var prior_size := board.size
	board.size += Vector2(17, 13)
	board._rescale_layout()
	check(board._unit_visuals[id] == visual and is_equal_approx(visual.death_progress, 0.4),
		"resize restores active unit pose on its retained root")
	board.size = prior_size
	board._rescale_layout()
	board.execution_pending = false
	board._field_presentation.clear()
	var removed := state.duplicate(true)
	removed.units.erase(id)
	board.show_presentation_state(removed)
	check(not board._unit_visuals.has(id) and visual.is_queued_for_deletion() and visual.get_parent() == null,
		"disappeared unit retires and detaches its root")
	board.show_presentation_state(state)
	var custom_scene := _pack(BattleManagedUnitVisual.new())
	check(BattleVisualSceneContract.validate_unit(custom_scene).is_empty(), "new managed unit scene needs no path registration")
	board.unit_visual_scene = custom_scene
	board.show_presentation_state(state)
	var custom_ids := _unit_ids(board)
	board.show_presentation_state(state)
	check(_unit_ids(board) == custom_ids, "unregistered managed unit scene retains all roots")
	var legacy_scene := _pack(BattleDemoIsoVisual.new())
	check(not BattleVisualSceneContract.validate_unit(legacy_scene).is_empty(), "legacy unit fallback fails new-art admission")
	board.unit_visual_scene = legacy_scene
	board.show_presentation_state(state)
	var legacy := board._presentation_visual(id)
	board.show_presentation_state(state)
	check(board._unit_visuals.is_empty() and board._presentation_visual(id) != legacy and legacy.is_queued_for_deletion(),
		"legacy unit scene still uses fresh construction")
	board.unit_visual_scene = original_scene
	board.show_presentation_state(state)


func _apply_count_snapshot(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {"terrain": {}, "environment": {}, "units": {}}
	for id: int in board._unit_visuals:
		result.units[id] = board._unit_visuals[id].view_apply_count
	for key: Vector3i in board._terrain_visuals:
		var visual := board._terrain_visuals[key] as BattleTerrainVisual
		result.terrain[key] = visual.view_apply_count
	for cell: Vector2i in board._environment_visuals:
		var visual := board._environment_visuals[cell] as BattleManagedEnvironmentVisual
		result.environment[cell] = visual.view_apply_count
	return result


func _exercise_dynamic_scenes(terrain_scene: PackedScene, environment_scene: PackedScene) -> void:
	var custom_board := CountingBoard.new()
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
		var terrain_passes := custom_board.terrain_passes
		custom_board.show_presentation_state(state)
		check(custom_board.terrain_passes == terrain_passes, "unchanged publication does not revisit static terrain")
		check(_terrain_ids(custom_board) == ids and custom_board._environment_visuals.get(cell) == environment_visual
			and custom_board.visual_lifecycle_counts() == counts,
			"second publication preserves dynamic scene identities and lifecycle counts")
		check(_apply_count_snapshot(custom_board) == applies,
			"second dynamic publication skips unchanged terrain and environment applies")
		terrain_visual.presentation_lift = 0.5
		custom_board.show_presentation_state(state)
		check(terrain_visual.presentation_lift == 0.0, "terrain reuse still resets old presentation pose")
		state.heights[0] = 2
		custom_board.show_presentation_state(state)
		check(custom_board.terrain_passes > terrain_passes and terrain_visual.half_steps == 2,
			"in-place height edit invalidates publication terrain reuse")
		state.fires[0].effect = "burning"
		custom_board.show_presentation_state(state)
		check(terrain_visual.burning and not environment_visual.has_spikes, "in-place hazard edit republishes current values")
		state.terrain[0] = TerrainType.Type.VOID
		custom_board.show_presentation_state(state)
		check(terrain_visual.is_void and not custom_board._environment_visuals.has(cell), "collapse removes overlay under reuse path")
		state.terrain[0] = TerrainType.Type.FLOOR
		custom_board.environment_visual_scene = _pack(BattleEnvironmentVisual.new())
		custom_board.show_presentation_state(state)
		custom_board.show_presentation_state(state)
		check(custom_board._environment_visuals.has(cell), "legacy environment rebuild remains available after repeated publication")
	var unchanged := CountingVisual.new()
	custom_board._entity_visuals.append(unchanged)
	custom_board.clear_strike_poses()
	check(unchanged.syncs == 0, "reset of already-zero poses does not resynchronize static art")
	unchanged.action_offset = Vector2.ONE
	unchanged.presentation_facing_x = -1
	var prior := unchanged.syncs
	custom_board.clear_strike_poses()
	check(unchanged.syncs == prior + 2 and unchanged.action_offset == Vector2.ZERO and unchanged.presentation_facing_x == 0,
		"reset still clears actual action and facing poses")
	custom_board._entity_visuals.erase(unchanged)
	unchanged.free()
	custom_board.queue_free()
	await process_frame


func _exercise_vector_sort_order() -> void:
	var board := CountingBoard.new()
	viewport.add_child(board)
	await process_frame
	var first := CountingVisual.new()
	var second := CountingVisual.new()
	var fractional := CountingVisual.new()
	for visual: CountingVisual in [first, second, fractional]:
		board._entities.add_child(visual)
	first.position.y = 12.75
	second.position.y = 12.75
	fractional.position.y = 12.5
	board._entity_visuals.assign([first, second, fractional])
	board._sort_visuals()
	check(board._entity_visuals == [fractional, first, second],
		"native Vector3 sort preserves fractional Y and child-index tie ordering")
	board._entities.move_child(second, first.get_index())
	board._sort_visuals()
	check(board._entity_visuals == [fractional, second, first],
		"native sort updates tied visual order after child reordering")
	board.queue_free()
	await process_frame


func _exercise_hover_acting_redraw() -> void:
	var board := CountingBoard.new()
	viewport.add_child(board)
	await process_frame
	var first := CountingVisual.new()
	var second := CountingVisual.new()
	first.role = BattleDemoIsoVisual.Role.UNIT
	second.role = BattleDemoIsoVisual.Role.UNIT
	first.grid_config = board.grid_config
	second.grid_config = board.grid_config
	first.unit = BattleUnitView.new()
	second.unit = BattleUnitView.new()
	first.unit.id = 801
	second.unit.id = 802
	first.unit.alive = true
	second.unit.alive = true
	board._entities.add_child(first)
	board._entities.add_child(second)
	board._entity_visuals.assign([first, second])
	first.queue_redraw()
	second.queue_redraw()
	await process_frame
	board.set_hovered_unit(801)
	board.set_acting_unit(801)
	await process_frame
	check(first.hovered and first.acting and not second.hovered and not second.acting,
		"hover and acting flags are applied to the selected visual")
	var first_draws := first.redraws
	var second_draws := second.redraws
	board.set_hovered_unit(801)
	board.set_acting_unit(801)
	await process_frame
	check(first.redraws == first_draws and second.redraws == second_draws,
		"unchanged hover and acting flags do not queue redraws")
	board.set_hovered_unit(802)
	board.set_acting_unit(802)
	await process_frame
	check(not first.hovered and not first.acting and second.hovered and second.acting,
		"changing target clears old flags and applies new hover and acting flags")
	var first_before_tamper := first.redraws
	var second_before_tamper := second.redraws
	first.hovered = true
	first.acting = true
	second.hovered = false
	second.acting = false
	board.set_hovered_unit(802)
	board.set_acting_unit(802)
	await process_frame
	check(not first.hovered and not first.acting and second.hovered and second.acting
		and first.redraws > first_before_tamper and second.redraws > second_before_tamper,
		"directly tampered flags are repaired and redraw both changed visuals")
	board.queue_free()
	await process_frame


func _exercise_highlight_terrain_reuse(highlights_on_overlay: bool) -> void:
	var tile := CountingTerrain.new()
	tile.highlights_use_ground_overlay = highlights_on_overlay
	var scene := _pack(tile)
	var board := CountingBoard.new()
	board.size = Vector2(500.0, 360.0)
	board.tile_visual_scene = scene
	viewport.add_child(board)
	await process_frame
	var heights := PackedInt32Array()
	heights.resize(4)
	var terrain := PackedByteArray()
	terrain.resize(4)
	terrain.fill(TerrainType.Type.FLOOR)
	terrain[1] = TerrainType.Type.WALL
	var state := {"width": 2, "height": 2, "heights": heights, "terrain": terrain,
		"units": {}, "fires": [], "corpses": [], "collapse": {}}
	board.show_presentation_state(state)
	var floor_cell := Vector2i.ZERO
	var wall_cell := Vector2i(1, 0)
	var floor_visual := _terrain_at_any(board, floor_cell)
	var wall_visual := _terrain_at_any(board, wall_cell, true)
	check(floor_visual is CountingTerrain and wall_visual is CountingTerrain,
		"highlight reuse fixture creates managed floor and wall visuals")
	if floor_visual is CountingTerrain and wall_visual is CountingTerrain:
		var floor_id := floor_visual.get_instance_id()
		var wall_id := wall_visual.get_instance_id()
		var terrain_passes := board.terrain_passes
		var floor_syncs := floor_visual.syncs
		var wall_syncs := wall_visual.syncs
		board._reachable[floor_cell] = 1.0
		board._reachable[wall_cell] = 1.0
		board._rebuild_visuals(true)
		check(board.terrain_passes == terrain_passes and floor_visual.get_instance_id() == floor_id
			and wall_visual.get_instance_id() == wall_id and floor_visual.reachable and not wall_visual.reachable,
			"hint-only publication reuses terrain and updates floor reachable while walls stay false")
		var expected_sync_delta := 0 if highlights_on_overlay else 1
		check(floor_visual.syncs == floor_syncs + expected_sync_delta
			and wall_visual.syncs == wall_syncs,
			"hint-only floor and wall refresh uses the configured highlight fallback")
		floor_syncs = floor_visual.syncs
		wall_syncs = wall_visual.syncs
		board._reachable.clear()
		board._rebuild_visuals(true)
		check(board.terrain_passes == terrain_passes and not floor_visual.reachable and not wall_visual.reachable
			and floor_visual.syncs == floor_syncs + expected_sync_delta
			and wall_visual.syncs == wall_syncs,
			"clearing hints updates current floor and wall values without rebuilding terrain")
		var visual_key: BattleDemoIsoVisual = floor_visual
		var values: Dictionary = board._terrain_draw_values[visual_key]
		floor_syncs = floor_visual.syncs
		board.grid_config.tile_size += Vector2.ONE
		floor_visual.apply_view(values, board.grid_config)
		check(floor_visual.syncs == floor_syncs + 1,
			"in-place geometry change forces a full scene-art synchronization")
	else:
		check(false, "highlight reuse fixture visual types are available")
	board.queue_free()
	await process_frame


func _terrain_at_any(board: BattleDemoBoard, cell: Vector2i, wall_surface: bool = false) -> CountingTerrain:
	for visual: BattleTerrainVisual in board._terrain_visuals.values():
		if visual.grid_anchor != cell: continue
		if wall_surface and visual.role != BattleDemoIsoVisual.Role.WALL: continue
		if not wall_surface and visual.role == BattleDemoIsoVisual.Role.WALL: continue
		return visual as CountingTerrain
	return null


func _ground_marks_snapshot(board: BattleDemoBoard) -> Dictionary:
	var result: Dictionary = {}
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT or not visual is CountingTerrain: continue
		result[visual.get_instance_id()] = (visual as CountingTerrain).ground_overlay_redraws
	return result


func _changed_ground_visuals(before: Dictionary, after: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for instance_id: int in before:
		if before[instance_id] != after.get(instance_id, before[instance_id]): result.append(instance_id)
	result.sort()
	return result


func _expected_top_visuals(board: BattleDemoBoard, cells: Array[Vector2i]) -> Array[int]:
	var result: Array[int] = []
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT or visual.grid_anchor not in cells: continue
		var top := (board._view_terrain_at(visual.grid_anchor) == TerrainType.Type.WALL) == (visual.role == BattleDemoIsoVisual.Role.WALL)
		if top: result.append(visual.get_instance_id())
	result.sort()
	return result


func _check_ground_mark_oracle(board: BattleDemoBoard, label: String) -> void:
	var map := board._ground_mark_map()
	var cells: Array[Vector2i] = [Vector2i(-1, -1)]
	for y: int in board._view_height:
		for x: int in board._view_width: cells.append(Vector2i(x, y))
	for cell_variant: Variant in map.keys():
		if cell_variant is Vector2i and not cells.has(cell_variant): cells.append(cell_variant)
	for cell: Vector2i in cells:
		check(map.get(cell, []) == board._ground_marks_for(cell),
			"%s batch map matches per-cell oracle at %s" % [label, cell])


func _exercise_ground_mark_batch() -> void:
	var scene := _pack(CountingTerrain.new())
	var board := CountingBoard.new()
	board.size = Vector2(500.0, 360.0)
	board.tile_visual_scene = scene
	viewport.add_child(board)
	await process_frame
	var heights := PackedInt32Array()
	heights.resize(4)
	var terrain := PackedByteArray()
	terrain.resize(4)
	terrain.fill(TerrainType.Type.FLOOR)
	terrain[1] = TerrainType.Type.WALL
	board.show_presentation_state({"width": 2, "height": 2, "heights": heights, "terrain": terrain,
		"units": {}, "fires": [], "corpses": [], "collapse": {}})
	var floor_cell := Vector2i.ZERO
	var wall_cell := Vector2i(1, 0)
	var mark_cell := Vector2i(0, 1)
	var endpoint := Vector2i(1, 1)
	var first_view := BattleUnitView.new()
	first_view.id = 501
	var second_view := BattleUnitView.new()
	second_view.id = 502
	board._view_units.assign([{"unit": first_view, "cell": floor_cell}, {"unit": second_view, "cell": wall_cell}])
	board.reaction_zone_cells = [floor_cell, Vector2i(-1, -1), wall_cell]
	board.cover_target_ids = [first_view.id]
	board.sneak_threat_ids = [second_view.id]
	board.action_areas = [
		{"owner_id": 501, "ready": true, "faction": Faction.Type.PLAYER, "origin": floor_cell,
			"cells": [floor_cell, floor_cell, wall_cell]},
		{"owner_id": 502, "ready": false, "faction": Faction.Type.ENEMY, "origin": wall_cell,
			"cells": [floor_cell, endpoint]},
		{"owner_id": 503, "ready": false, "faction": Faction.Type.PLAYER, "origin": endpoint,
			"cells": [endpoint]},
	]
	board.area_preview_owner = 502
	board.hover_cell = floor_cell
	board.attack_mode = true
	var move := MoveForecast.new()
	move.status = ActionReceipt.APPLIED
	move.actor_id = first_view.id
	move.units[first_view.id] = {"after": {"cell": endpoint, "alive": true}}
	board.move_forecast = move
	_check_ground_mark_oracle(board, "ready, preview, reaction, cover, sneak, hover, endpoint, wall and invalid")
	var overlap_kinds: Array[String] = []
	for mark: Dictionary in board._ground_mark_map().get(floor_cell, []): overlap_kinds.append(String(mark.kind))
	check(overlap_kinds == ["reaction_zone", "cover_target", "action_area", "action_origin", "action_area", "hover"],
		"batch map preserves per-cell mark order and deduplicates repeated action-area cells")

	board._sync_ground_overlays()
	await process_frame
	var unchanged := _ground_marks_snapshot(board)
	board._sync_ground_overlays()
	check(_ground_marks_snapshot(board) == unchanged,
		"unchanged batch input does not queue ground-overlay redraws")
	var old_hover := board.hover_cell
	board.hover_cell = mark_cell
	var before_hover := _ground_marks_snapshot(board)
	board._sync_ground_overlays()
	var after_hover := _ground_marks_snapshot(board)
	var hover_cells: Array[Vector2i] = [old_hover, mark_cell]
	check(_changed_ground_visuals(before_hover, after_hover) == _expected_top_visuals(board, hover_cells),
		"hover change redraws only the old and new top-cell ground overlays")
	_check_ground_mark_oracle(board, "direct hover field update")

	var direct_cell := endpoint
	var before_direct := _ground_marks_snapshot(board)
	board.reaction_zone_cells.append(direct_cell)
	board.action_areas[0].cells.append(direct_cell)
	board._sync_ground_overlays()
	var after_direct := _ground_marks_snapshot(board)
	var direct_cells: Array[Vector2i] = [direct_cell]
	check(_changed_ground_visuals(before_direct, after_direct) == _expected_top_visuals(board, direct_cells),
		"in-place reaction and action-area changes redraw only their affected ground overlay")
	_check_ground_mark_oracle(board, "direct in-place array update")
	var before_duplicate := _ground_marks_snapshot(board)
	board.action_areas[0].cells.append(direct_cell)
	board._sync_ground_overlays()
	check(_ground_marks_snapshot(board) == before_duplicate,
		"duplicate cell within an action area preserves old single-mark semantics")
	_check_ground_mark_oracle(board, "duplicate action-area cell")
	board.queue_free()
	await process_frame


func _run() -> void:
	var environment: PackedScene = BattleDemoBoard.DEFAULT_ENVIRONMENT_SCENE
	check(BattleVisualSceneContract.validate(BattleDemoBoard.DEFAULT_TILE_SCENE, environment).is_empty(),
		"default authored visual scenes satisfy the admission gate")
	check(BattleVisualSceneContract.validate(TRIAL_TILE, environment).is_empty(),
		"current art trial scenes satisfy the admission gate")
	var trial_probe := TRIAL_TILE.instantiate()
	check(trial_probe is BattleTerrainVisual and (trial_probe as BattleTerrainVisual).highlights_use_ground_overlay,
		"art trial tile explicitly opts in to ground-overlay highlight updates")
	var hero_scene: PackedScene = load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene
	var hero_probe := hero_scene.instantiate() if hero_scene != null else null
	var hero_board := hero_probe.get_node_or_null("BattleHUD/Margin/Column/Content/Left/Field/Board") as BattleDemoBoard if hero_probe != null else null
	check(trial_probe is BattleTerrainVisual and hero_board != null
		and BattleVisualSceneContract.validate(hero_board.tile_visual_scene, hero_board.environment_visual_scene).is_empty()
		and BattleVisualSceneContract.validate_unit(hero_board.unit_visual_scene).is_empty(),
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
	await _exercise_vector_sort_order()
	await _exercise_hover_acting_redraw()
	await _exercise_highlight_terrain_reuse(true)
	await _exercise_highlight_terrain_reuse(false)
	await _exercise_ground_mark_batch()
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
	_exercise_unit_lifecycle(board, effects)
	check(_audit(session) == baseline, "unit lifecycle preserves live snapshot, RNG and counters")

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
	var move_unit_ids := _unit_ids(board)
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
	check(not move_unit_ids.is_empty() and _unit_ids(board) == move_unit_ids,
		"ordinary movement retains every unit root through worker and ordered publications")

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
	check(after_board_swap.unit_retired > before_board_swap.unit_retired,
		"battle owner swap retires previous managed unit roots")
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
