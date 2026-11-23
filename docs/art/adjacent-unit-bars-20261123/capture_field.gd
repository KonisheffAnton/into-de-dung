extends SceneTree

## Снимает соседние штатные боевые фигуры при обычных полосах, выборе и наведении атаки.
const BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const VIEW_SIZE: Vector2i = Vector2i(1440, 1100)
const CROPPING_MARGIN: float = 80.0
const FORECAST_FRAME_LIMIT: int = 600

var output_dir: String = ""
var failed: Array[String] = []
var viewport: SubViewport
var demo: HeroHubBattleView
var session: BattleCoreReactionsSession
var board: BattleDemoBoard
var actor: UnitState
var target: UnitState
var actor_cell: Vector2i
var target_cell: Vector2i
var rows: Array[Dictionary] = []
var crop_by_zoom: Dictionary[float, Rect2i] = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): output_dir = argument.trim_prefix("--captures=")
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	if not value:
		failed.append(label)
		printerr("FAIL ADJACENT UNIT BARS: " + label)


func _snapshot() -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision()}


func _safe_floor(board_state: BattleBoard, cell: Vector2i) -> bool:
	if not board_state.is_in_bounds(cell) or board_state.get_terrain(cell) != TerrainType.Type.FLOOR or board_state.is_lethal(cell): return false
	var environment: CombatEnvironmentState = session.state.environment
	if environment != null:
		if not environment.fire_at(cell).is_empty(): return false
		if cell in environment.hazards.get("acid", []): return false
		for trap: Dictionary in environment.hazards.get("traps", []):
			if trap.get("cell", Vector2i(-1, -1)) == cell: return false
		for corpse: Dictionary in environment.corpses:
			if corpse.get("cell", Vector2i(-1, -1)) == cell: return false
	return true


func _choose_adjacent_cells(board_state: BattleBoard) -> bool:
	var preferred_actor := Vector2i(3, 3)
	var preferred_target := Vector2i(4, 3)
	if _safe_floor(board_state, preferred_actor) and _safe_floor(board_state, preferred_target):
		var preferred_actor_owner := board_state.occupant_at(preferred_actor)
		var preferred_target_owner := board_state.occupant_at(preferred_target)
		if (preferred_actor_owner == null or preferred_actor_owner.id in [actor.id, target.id]) \
				and (preferred_target_owner == null or preferred_target_owner.id in [actor.id, target.id]):
			actor_cell = preferred_actor
			target_cell = preferred_target
			return true
	var center := Vector2i(board_state.width / 2, board_state.height / 2)
	var best_score := 2147483647
	var best_actor := Vector2i(-1, -1)
	var best_target := Vector2i(-1, -1)
	for y: int in board_state.height:
		for x: int in board_state.width:
			var first := Vector2i(x, y)
			for delta: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var second := first + delta
				if not _safe_floor(board_state, first) or not _safe_floor(board_state, second): continue
				var first_owner := board_state.occupant_at(first)
				var second_owner := board_state.occupant_at(second)
				if first_owner != null and first_owner.id not in [actor.id, target.id]: continue
				if second_owner != null and second_owner.id not in [actor.id, target.id]: continue
				var score := absi(first.x - center.x) + absi(first.y - center.y) \
					+ absi(second.x - center.x) + absi(second.y - center.y)
				if score < best_score:
					best_score = score
					best_actor = first
					best_target = second
	actor_cell = best_actor
	target_cell = best_target
	return actor_cell.x >= 0 and target_cell.x >= 0


func _arrange_fixture(board_state: BattleBoard) -> bool:
	if not _choose_adjacent_cells(board_state): return false
	var staging: Array[Vector2i] = []
	for y: int in board_state.height:
		for x: int in board_state.width:
			var cell := Vector2i(x, y)
			if cell in [actor_cell, target_cell] or not _safe_floor(board_state, cell) or board_state.occupant_at(cell) != null: continue
			staging.append(cell)
	staging.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(a.x - actor_cell.x) + absi(a.y - actor_cell.y)
		var db := absi(b.x - actor_cell.x) + absi(b.y - actor_cell.y)
		return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
	if staging.size() < 2: return false
	# Перестановка делается до baseline только через BattleBoard, чтобы occupancy и UnitState не расходились.
	return board_state.move_unit(actor, staging[0]) and board_state.move_unit(target, staging[1]) \
		and board_state.move_unit(actor, actor_cell) and board_state.move_unit(target, target_cell)


func _only_pair_visible() -> int:
	var count := 0
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		var keep := visual.unit != null and visual.unit.alive and visual.unit.id in [actor.id, target.id]
		visual.visible = keep
		if keep: count += 1
	return count


func _hud_rect(visual: BattleDemoIsoVisual) -> Rect2:
	var local_anchor := visual.get_visual_offset() + visual.get_unit_bars_offset() * board.grid_config.tile_size.x / 128.0
	var screen_transform := visual._vitals_hud.get_viewport_transform() * visual._vitals_hud.get_global_transform()
	var origin := (screen_transform * local_anchor).round()
	return Rect2(origin + Vector2(-24, 1), Vector2(48, 30))


func _rect_array(rectangles: Array[Rect2]) -> Array[Array]:
	var result: Array[Array] = []
	for rect: Rect2 in rectangles:
		result.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return result


func _visual_record(visual: BattleManagedUnitVisual) -> Dictionary:
	var transform := visual.get_global_transform_with_canvas()
	var body_rects := visual.vitals_body_screen_rects()
	var material := visual._vitals_hud.material as ShaderMaterial
	var skin_id := String(visual.skin_definition.id) if visual.skin_definition != null else ""
	return {"id": visual.unit.id, "faction": int(visual.unit.faction), "class": String(visual.visual_class_id),
		"skin": skin_id, "cell": [visual.grid_anchor.x, visual.grid_anchor.y],
		"screen_origin": [transform.origin.x, transform.origin.y],
		"hud_rect": [ _hud_rect(visual).position.x, _hud_rect(visual).position.y,
			_hud_rect(visual).size.x, _hud_rect(visual).size.y ],
		"body_mask_rects": _rect_array(body_rects),
		"blocker_count": int(material.get_shader_parameter("blocker_count")) if material != null else -1,
		"selected": visual.selected, "hovered": visual.hovered}


func _capture_crop_rect() -> Rect2i:
	var bounds := Rect2()
	var initialized := false
	for id: int in [actor.id, target.id]:
		var visual := board._unit_visuals[id] as BattleManagedUnitVisual
		var pieces := visual.vitals_body_screen_rects()
		pieces.append(_hud_rect(visual))
		for piece: Rect2 in pieces:
			if not piece.has_area(): continue
			if not initialized:
				bounds = piece
				initialized = true
			else:
				bounds = bounds.merge(piece)
	if not initialized: return Rect2i()
	return Rect2i(bounds.grow(CROPPING_MARGIN)).intersection(Rect2i(Vector2i.ZERO, VIEW_SIZE))


func _capture(label: String, zoom: float, crop: Rect2i) -> void:
	_only_pair_visible()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var before := _snapshot()
	var image := viewport.get_texture().get_image()
	var png_path := output_dir.path_join(label + ".png")
	_check(image.save_png(png_path) == OK, label + " full viewport PNG saved")
	var crop_path := output_dir.path_join(label + "-crop.png")
	_check(crop.has_area() and image.get_region(crop).save_png(crop_path) == OK, label + " native crop saved")
	var actor_visual := board._unit_visuals[actor.id] as BattleManagedUnitVisual
	var target_visual := board._unit_visuals[target.id] as BattleManagedUnitVisual
	var visible_count := 0
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		if visual.is_visible_in_tree(): visible_count += 1
	_check(visible_count == 2, label + " shows only the two fixture figures")
	_check(is_equal_approx(board.camera_view.zoom, zoom), label + " uses the requested camera zoom")
	var after := _snapshot()
	_check(before == after, label + " preserves core state, RNG, counters and revision")
	if "no-selection" in label:
		_check(session.selected_id == UnitId.NONE and not actor_visual.selected and not target_visual.selected,
			label + " has no selected figure")
	else:
		_check(session.selected_id == actor.id and actor_visual.selected and not target_visual.selected,
			label + " selects only the fighter")
	rows.append({"capture": label, "zoom": zoom, "camera_zoom": board.camera_view.zoom,
		"crop": [crop.position.x, crop.position.y, crop.size.x, crop.size.y],
		"full_png": png_path, "crop_png": crop_path,
		"cells": {"actor": [actor_cell.x, actor_cell.y], "target": [target_cell.x, target_cell.y], "manhattan": 1},
		"selected_id": session.selected_id, "target_id": target.id,
		"attack_mode": demo.attack_mode, "forecast_ready": demo._forecast != null and not demo._attack_forecast_pending,
		"visible_figures": visible_count,
		"visuals": [_visual_record(actor_visual), _visual_record(target_visual)],
		"snapshot_before": before, "snapshot_after": after})


func _set_none_state() -> void:
	demo.set_attack_mode(false)
	session.selected_id = UnitId.NONE
	board.hover_cell = Vector2i(-1, -1)
	board.set_hovered_unit(UnitId.NONE)
	board.inspected_id = UnitId.NONE
	demo.inspected_id = UnitId.NONE
	demo._refresh()
	_check(_only_pair_visible() == 2, "unselected refresh keeps only fixture visuals visible")


func _set_selected_state() -> void:
	demo.set_attack_mode(false)
	demo.select_character(actor.id)
	board.hover_cell = Vector2i(-1, -1)
	board.set_hovered_unit(UnitId.NONE)
	board.inspected_id = UnitId.NONE
	demo.inspected_id = UnitId.NONE
	_check(session.selected_id == actor.id, "selection state selects only fighter")
	_check(_only_pair_visible() == 2, "selected refresh keeps only fixture visuals visible")


func _set_attack_hover_state() -> bool:
	demo.set_attack_mode(true)
	board.hover_cell = target_cell
	demo._hover(target_cell)
	board.set_hovered_unit(target.id)
	var frames := 0
	var started_at := Time.get_ticks_msec()
	while frames < FORECAST_FRAME_LIMIT and Time.get_ticks_msec() - started_at < 5000:
		demo._poll_forecast_preparation()
		demo._process_attack_forecast()
		await process_frame
		frames += 1
		if demo._forecast != null and not demo._attack_forecast_pending \
				and not demo._forecast_preparation_worker.is_started() and not demo._attack_forecast_worker.is_started(): break
	var ready := demo._forecast != null and not demo._attack_forecast_pending
	_check(ready, "attack forecast becomes ready without executing attack")
	if ready:
		_check(demo.attack_mode and demo._forecast_target_id == target.id and board.hover_cell == target_cell,
			"production attack hover route retains the adjacent target")
		_check(session.selected_id == actor.id and target.id != session.selected_id,
			"hovered enemy never becomes selected")
	_check(_only_pair_visible() == 2, "attack hover keeps only fixture visuals visible")
	return ready


func _run() -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a GPU renderer and -- --captures=<absolute output directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var profile := HeroHubState.create(73191, 4)
	_check(profile != null and profile.start_battle(), "isolated profile starts battle")
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty():
		quit(1)
		return
	session = bundle.session as BattleCoreReactionsSession
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	var fallback_enemy: UnitState
	for unit: UnitState in session.units:
		if not unit.is_alive(): continue
		var class_id: StringName = session.unit_visual_classes.get(unit.id, &"")
		if unit.faction == Faction.Type.PLAYER and class_id == &"fighter": actor = unit
		elif unit.faction == Faction.Type.ENEMY and class_id == TroglodyteKit.ID: target = unit
		elif unit.faction == Faction.Type.ENEMY and class_id == &"sick_hobgoblin": fallback_enemy = unit
	if target == null: target = fallback_enemy
	_check(actor != null, "PLAYER fighter exists")
	_check(target != null, "tamed troglodyte or sick hobgoblin exists")
	if actor == null or target == null:
		session.close(); quit(1); return
	var board_state: BattleBoard = session.state.get_board()
	_check(_arrange_fixture(board_state), "BattleBoard moves fighter and enemy onto safe adjacent floor")
	_check(actor.cell == actor_cell and target.cell == target_cell
		and absi(actor.cell.x - target.cell.x) + absi(actor.cell.y - target.cell.y) == 1,
		"fixture cells are adjacent cardinal neighbours")
	var fixture_before := _snapshot()
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = BATTLE.instantiate() as HeroHubBattleView
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.set_process(false)
	await process_frame
	await process_frame
	board = demo.board_view
	board.set_presentation_animation_events([{"actor_unit_id": actor.id}, {"actor_unit_id": target.id}])
	_check(board._unit_visuals.has(actor.id) and board._unit_visuals.has(target.id), "production board creates both fixture visuals")
	if not board._unit_visuals.has(actor.id) or not board._unit_visuals.has(target.id):
		demo.queue_free(); await process_frame; viewport.queue_free(); session.close(); quit(1); return
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		visual.visible = visual.unit != null and visual.unit.id in [actor.id, target.id]
	board.refresh()
	_only_pair_visible()
	await process_frame
	await process_frame
	var actor_visual := board._unit_visuals[actor.id] as BattleManagedUnitVisual
	var target_visual := board._unit_visuals[target.id] as BattleManagedUnitVisual
	_check(actor_visual.visual_class_id == &"fighter" and actor_visual.skin_definition.id == &"red_bastion",
		"player fighter keeps red_bastion production skin")
	_check(target_visual.visual_class_id in [TroglodyteKit.ID, &"sick_hobgoblin"], "enemy uses the selected production enemy art")
	_check(fixture_before == _snapshot(), "fixture refresh preserves combat state and RNG")
	var zooms: Array[float] = [1.0, 0.75]
	for zoom: float in zooms:
		board.zoom_camera(zoom, board.size * 0.5)
		var pair_center := (board.cell_center(actor_cell) + board.cell_center(target_cell)) * 0.5
		board.pan_camera(board.size * 0.5 - pair_center)
		await process_frame
		await RenderingServer.frame_post_draw
		var crop := _capture_crop_rect()
		crop_by_zoom[zoom] = crop
		_set_none_state()
		await _capture("adjacent-no-selection-%03d" % roundi(zoom * 100.0), zoom, crop)
		_set_selected_state()
		await _capture("adjacent-selected-%03d" % roundi(zoom * 100.0), zoom, crop)
		var forecast_ready := await _set_attack_hover_state()
		if forecast_ready: await _capture("adjacent-attack-hover-%03d" % roundi(zoom * 100.0), zoom, crop)
		else: _check(false, "skip attack capture because forecast is unavailable")
	var final_snapshot := _snapshot()
	_check(fixture_before == final_snapshot, "all UI modes preserve core state, RNG, counters and revision")
	_check(session.selected_id == actor.id, "final hover capture keeps fighter selected")
	var file := FileAccess.open(output_dir.path_join("capture-field.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
			"viewport": [VIEW_SIZE.x, VIEW_SIZE.y], "tile_size": [board.grid_config.tile_size.x, board.grid_config.tile_size.y],
			"actor": actor.id, "target": target.id, "actor_class": String(actor_visual.visual_class_id),
			"actor_skin": String(actor_visual.skin_definition.id), "target_class": String(target_visual.visual_class_id),
			"cells": {"actor": [actor_cell.x, actor_cell.y], "target": [target_cell.x, target_cell.y], "manhattan": 1},
			"zoom_crops": {"100": [crop_by_zoom.get(1.0, Rect2i()).position.x, crop_by_zoom.get(1.0, Rect2i()).position.y,
				crop_by_zoom.get(1.0, Rect2i()).size.x, crop_by_zoom.get(1.0, Rect2i()).size.y],
				"075": [crop_by_zoom.get(0.75, Rect2i()).position.x, crop_by_zoom.get(0.75, Rect2i()).position.y,
				crop_by_zoom.get(0.75, Rect2i()).size.x, crop_by_zoom.get(0.75, Rect2i()).size.y]},
			"fixture_snapshot": fixture_before, "final_snapshot": final_snapshot,
			"failed_checks": failed, "captures": rows}, "\t") + "\n")
		file.close()
	else:
		_check(false, "capture-field.json written")
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("ADJACENT UNIT BARS RESULTS: %d captures, %d failed checks" % [rows.size(), failed.size()])
	quit(1 if not failed.is_empty() else 0)
