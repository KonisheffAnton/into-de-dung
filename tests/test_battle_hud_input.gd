extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL BATTLE HUD INPUT: " + label)

func _run() -> void:
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	await _exercise_main()
	await _exercise_hub()
	await _exercise_large_hub()
	await _exercise_legacy()
	viewport.queue_free()
	await process_frame
	print("BATTLE HUD INPUT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _exercise_main() -> void:
	var demo := (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	(demo.session as BattleTacticalSession).phase = BattleTacticalSession.Phase.PLAYER_TURN
	demo.session.selected_id = demo.session.units[0].id
	demo._refresh()
	await _exercise_battle(demo, demo.get_node("BattleHUD") as Control, "main")

func _exercise_hub() -> void:
	var hub := HeroHubBattleView.new()
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	hub.supplied_session = HeroHubBattleFactory.create(profile).session
	viewport.add_child(hub)
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.set_process(false)
	await process_frame
	await process_frame
	await _exercise_battle(hub, hub.get_node("BattleHUD") as Control, "hub")

func _exercise_large_hub() -> void:
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var battle := (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	var route_helper := HeroHubScreen.new()
	check(route_helper._configure_first_room_art(battle, profile), "large hub uses the production first-room art route")
	battle.expedition_battle = true
	battle.supplied_session = HeroHubBattleFactory.create(profile).session
	battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(battle)
	battle.set_process(false)
	battle.end_turn()
	battle._confirm_selected_mulligan()
	var session := battle.session as BattleCoreReactionsSession
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	battle._refresh()
	await process_frame
	await process_frame
	var board := battle.board_view
	check(board._view_width == 24 and board._view_height == 16, "large hub fixture is the authored 24x16 battlefield")
	check(board.tile_visual_scene.resource_path == "res://scenes/demo/visuals/dungeon_comparison_tile.tscn"
		and board.environment_visual_scene.resource_path == "res://scenes/demo/visuals/dungeon_room_environment.tscn",
		"large hub fixture retains the production room art")
	check(not board.clip_contents, "large authored battlefield is not clipped to the old Board rectangle")
	var baseline := ItemSimulationSnapshot.capture(battle.session.state, []).snapshot.to_dict()
	var rng_before := battle.session.context.get_rng().to_dict()
	var counters_before := battle.session.context.simulation_counters()
	var clicked: Array[Vector2i] = []
	var hovered: Array[Vector2i] = []
	board.cell_clicked.connect(func(cell: Vector2i) -> void: clicked.append(cell))
	board.cell_hovered.connect(func(cell: Vector2i) -> void: hovered.append(cell))
	board.zoom_camera(1.04, board.size * 0.5)
	await _check_large_regions(battle, board, clicked, hovered, "initial")
	# Обновление сцены и изменение размера раньше повторно рассчитывали clip_contents.
	board.refresh()
	battle._refresh()
	await process_frame
	await process_frame
	check(not board.clip_contents, "large battlefield remains unclipped after refresh")
	viewport.size = Vector2i(1320, 900)
	await process_frame
	await process_frame
	board.zoom_camera(1.04, board.size * 0.5)
	check(not board.clip_contents, "large battlefield remains unclipped after viewport resize")
	await _check_large_regions(battle, board, clicked, hovered, "resized")
	# execution_pending — тот же режим Board, который удерживается при расчёте и показе кадра.
	board.execution_pending = true
	board._sync_layout_geometry()
	board.refresh()
	check(not board.clip_contents, "large battlefield remains unclipped while presentation is pending")
	if DisplayServer.get_name() != "headless":
		check(await _compare_clipped_roi(board, _cell_screen(board, session.selected_unit().cell)) > 8,
			"published pending geometry still renders outside old Board rect")
	else:
		print("BATTLE HUD INPUT: large-field GPU pixel checks skipped (headless)")
	board.execution_pending = false
	check(ItemSimulationSnapshot.capture(battle.session.state, []).snapshot.to_dict() == baseline
		and battle.session.context.get_rng().to_dict() == rng_before
		and battle.session.context.simulation_counters() == counters_before,
		"large-board hover, clicks, refresh, resize, and camera preserve snapshot, RNG and counters")
	viewport.size = Vector2i(1280, 850)
	route_helper.free()
	battle.queue_free()
	await process_frame

func _check_large_regions(battle: HeroHubBattleView, board: BattleDemoBoard, clicked: Array[Vector2i], hovered: Array[Vector2i], stage: String) -> void:
	var cell := battle.session.selected_unit().cell
	var board_rect := board.get_global_rect()
	var edge_names: Array[String] = ["top", "bottom", "left", "right"]
	for index: int in edge_names.size():
		var target := _clear_edge_target(battle, board_rect, index)
		board.pan_camera(target - _cell_screen(board, cell))
		var cell_screen := _cell_screen(board, cell)
		check(viewport.get_visible_rect().has_point(cell_screen), stage + ": " + edge_names[index] + " test cell stays in viewport")
		check(not board_rect.has_point(cell_screen), stage + ": " + edge_names[index] + " test cell is outside old Board rect")
		if DisplayServer.get_name() != "headless":
			var changed_pixels := await _compare_clipped_roi(board, cell_screen)
			check(changed_pixels > 8, stage + ": " + edge_names[index] + " battlefield pixels render outside old Board rect")
		else:
			check(not board.clip_contents, stage + ": " + edge_names[index] + " clip remains disabled in headless mode")
		_push_motion(cell_screen)
		check(not hovered.is_empty() and hovered.back() == cell, stage + ": " + edge_names[index] + " hover reaches the visible large-board tile")
		var click_count := clicked.size()
		_push_button(cell_screen, MOUSE_BUTTON_LEFT, true)
		_push_button(cell_screen, MOUSE_BUTTON_LEFT, false)
		check(clicked.size() == click_count + 1 and clicked.back() == cell, stage + ": " + edge_names[index] + " click reaches the visible large-board tile once")
		if stage == "initial" and index == 0: await _capture("battle-hud-large-104-under-hud")

func _clear_edge_target(battle: HeroHubBattleView, board_rect: Rect2, edge: int) -> Vector2:
	for step: int in range(2, 9):
		var fraction := float(step) / 10.0
		var candidate := Vector2.ZERO
		match edge:
			0: candidate = Vector2(lerpf(board_rect.position.x, board_rect.end.x, fraction), board_rect.position.y - 16.0)
			1: candidate = Vector2(lerpf(board_rect.position.x, board_rect.end.x, fraction), board_rect.end.y + 16.0)
			2: candidate = Vector2(board_rect.position.x - 6.0, lerpf(board_rect.position.y, board_rect.end.y, fraction))
			_: candidate = Vector2(board_rect.end.x + 16.0, lerpf(board_rect.position.y, board_rect.end.y, fraction))
		if viewport.get_visible_rect().has_point(candidate) and not board_rect.has_point(candidate) and not _interactive_hud_at(battle, candidate):
			return candidate
	match edge:
		0: return Vector2(board_rect.get_center().x, board_rect.position.y - 16.0)
		1: return Vector2(board_rect.get_center().x, board_rect.end.y + 16.0)
		2: return Vector2(board_rect.position.x - 16.0, board_rect.get_center().y)
		_: return Vector2(board_rect.end.x + 16.0, board_rect.get_center().y)

func _interactive_hud_at(node: Node, point: Vector2) -> bool:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree() and (control is Button or control is HScrollBar or control is VScrollBar) and control.get_global_rect().has_point(point):
			return true
	for child: Node in node.get_children():
		if _interactive_hud_at(child, point): return true
	return false

func _compare_clipped_roi(board: BattleDemoBoard, center: Vector2) -> int:
	var original_clip := board.clip_contents
	await process_frame
	await RenderingServer.frame_post_draw
	var visible := viewport.get_texture().get_image()
	board.clip_contents = true
	await process_frame
	await RenderingServer.frame_post_draw
	var clipped := viewport.get_texture().get_image()
	board.clip_contents = original_clip
	var differences: int = 0
	var center_x := roundi(center.x)
	var center_y := roundi(center.y)
	for y: int in range(maxi(center_y - 24, 0), mini(center_y + 25, visible.get_height())):
		for x: int in range(maxi(center_x - 24, 0), mini(center_x + 25, visible.get_width())):
			if board.get_global_rect().has_point(Vector2(x, y)): continue
			var visible_pixel := visible.get_pixel(x, y)
			var clipped_pixel := clipped.get_pixel(x, y)
			if absf(visible_pixel.r - clipped_pixel.r) > 0.03 or absf(visible_pixel.g - clipped_pixel.g) > 0.03 or absf(visible_pixel.b - clipped_pixel.b) > 0.03:
				differences += 1
	return differences

func _exercise_legacy() -> void:
	var demo := (load("res://scenes/demo/tactical_battle.tscn") as PackedScene).instantiate() as BattleDemo
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	# Legacy fixture создаёт собственную сессию; переводим её в тот же безопасный ход игрока.
	(demo.session as BattleTacticalSession).phase = BattleTacticalSession.Phase.PLAYER_TURN
	demo._refresh()
	await _exercise_battle(demo, demo, "legacy")

func _exercise_battle(demo: BattleDemo, hud: Control, label: String) -> void:
	await process_frame
	await process_frame
	var board := demo.board_view
	var proxy := hud.get_node_or_null("BattleHudInput") as BattleHudInput
	check(proxy != null and board.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + ": shared input surface installed")
	if proxy == null:
		demo.queue_free()
		await process_frame
		return
	check(BattleHudInput.install(hud, board) == proxy, label + ": installation is idempotent")
	check(board.size.x > 0.0 and board.size.y > 0.0, label + ": board layout settled before input")
	var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()
	var rng_before := demo.session.context.get_rng().to_dict()
	var counters_before := demo.session.context.simulation_counters()
	var clicked: Array[Vector2i] = []
	var hovered: Array[Vector2i] = []
	board.cell_clicked.connect(func(cell: Vector2i) -> void: clicked.append(cell))
	board.cell_hovered.connect(func(cell: Vector2i) -> void: hovered.append(cell))
	var original_size := board.size
	var cell := demo.session.selected_unit().cell
	var destinations: Array[Vector2] = [
		(_control_center(hud.get_node("Margin/Column/Title/Heading") as Control) if hud.has_node("Margin/Column/Title/Heading") else Vector2(viewport.size.x * 0.5, 76.0)),
		board.global_position + Vector2(-16.0, board.size.y * 0.5),
	]
	var inspection := hud.get_node_or_null("Margin/Column/Content/Left/Inspection") as Control
	if inspection != null: destinations.append(_control_center(inspection))
	var diagnostics_button := hud.get_node_or_null("Margin/Column/Title/Diagnostics") as Button
	if diagnostics_button != null:
		demo.set_diagnostics_visible(true)
		await process_frame
		await process_frame
		var diagnostics_text := hud.get_node_or_null("BattleDiagnostics/Scroll/Side/InspectionScroll") as Control
		if diagnostics_text != null: destinations.append(_control_center(diagnostics_text))
	for index: int in destinations.size():
		# Этот тест проверяет прозрачный HUD; отдельная карточка намеренно закрывает ввод.
		demo._close_character_card()
		var wanted := destinations[index]
		var cell_screen := _cell_screen(board, cell)
		board.pan_camera(wanted - cell_screen)
		cell_screen = _cell_screen(board, cell)
		check(viewport.get_visible_rect().has_point(cell_screen), label + ": panned test tile remains on screen " + str(index))
		if index < 3:
			check(not board.get_global_rect().has_point(cell_screen), label + ": test tile lies outside old board boundary " + str(index))
		_push_motion(cell_screen)
		check(not hovered.is_empty() and hovered.back() == cell, label + ": hover reaches panned tile " + str(index))
		var count_before := clicked.size()
		_push_button(cell_screen, MOUSE_BUTTON_LEFT, true)
		_push_button(cell_screen, MOUSE_BUTTON_LEFT, false)
		check(clicked.size() == count_before + 1 and clicked.back() == cell, label + ": one click reaches tile through HUD region " + str(index))
		check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before, label + ": selecting current tile leaves game snapshot unchanged")
		check(demo.session.context.get_rng().to_dict() == rng_before and demo.session.context.simulation_counters() == counters_before, label + ": click, hover, and pan leave RNG and counters unchanged")
		if index == 0:
			await _capture(label + "-top")
			# Клетка пересекает старую границу Board, но поверхность ввода остаётся непрерывной.
			var edge_target := board.global_position + Vector2(0.0, board.size.y * 0.5)
			board.pan_camera(edge_target - _cell_screen(board, cell))
			var edge_cell := _cell_screen(board, cell)
			var outside_edge := edge_cell + Vector2(-5.0, 0.0)
			var inside_edge := edge_cell + Vector2(5.0, 0.0)
			check(viewport.get_visible_rect().has_point(outside_edge) and viewport.get_visible_rect().has_point(inside_edge), label + ": boundary test points stay inside viewport")
			var invalid_hover_count := _invalid_hover_count(hovered)
			_push_motion(outside_edge)
			await process_frame
			_push_motion(inside_edge)
			await process_frame
			check(hovered.back() == cell and _invalid_hover_count(hovered) == invalid_hover_count, label + ": crossing old Board edge does not clear hover for the same tile")
	# ПКМ-жест меняет только камеру, а отпускание за пределами исходного Board завершает жест.
	var drag_start := destinations[0]
	board.pan_camera(drag_start - _cell_screen(board, cell))
	var offset_before := board.camera_view.offset
	_push_button(drag_start, MOUSE_BUTTON_RIGHT, true)
	var drag_end := drag_start + Vector2(28.0, -19.0)
	_push_motion(drag_end, Vector2(28.0, -19.0))
	_push_button(Vector2(4.0, 4.0), MOUSE_BUTTON_RIGHT, false)
	check(not board.camera_view.offset.is_equal_approx(offset_before) if board.camera_controls_enabled else board.camera_view.offset.is_equal_approx(offset_before), label + ": right drag respects camera availability")
	check(not board._camera_gesture_active, label + ": release outside Board ends camera gesture")
	var anchor_screen := _cell_screen(board, cell)
	board.pan_camera(destinations[0] - anchor_screen)
	anchor_screen = _cell_screen(board, cell)
	var anchor_local := anchor_screen - board.global_position
	var world_anchor := board.view_to_world(anchor_local)
	var zoom_before := board.camera_view.zoom
	_push_wheel(anchor_screen, MOUSE_BUTTON_WHEEL_UP, false)
	check(board.camera_view.zoom > zoom_before if board.camera_controls_enabled else is_equal_approx(board.camera_view.zoom, zoom_before), label + ": wheel respects camera availability")
	check(board.world_to_view(world_anchor).is_equal_approx(anchor_local), label + ": wheel zoom keeps pointer anchor")
	var ctrl_zoom_before := board.camera_view.zoom
	_push_wheel(anchor_screen, MOUSE_BUTTON_WHEEL_UP, true)
	check(board.camera_view.zoom > ctrl_zoom_before if board.camera_controls_enabled else is_equal_approx(board.camera_view.zoom, ctrl_zoom_before), label + ": Ctrl wheel respects camera availability")
	var move_button := demo._move_button
	if move_button.disabled:
		var disabled_clicks := clicked.size()
		_push_button(_control_center(move_button), MOUSE_BUTTON_LEFT, true)
		_push_button(_control_center(move_button), MOUSE_BUTTON_LEFT, false)
		check(clicked.size() == disabled_clicks, label + ": disabled action button still shields field clicks")
		move_button = demo._speed_presentation_button
	var field_clicks_before_button := clicked.size()
	var button_pressed := [0]
	move_button.pressed.connect(func() -> void: button_pressed[0] += 1)
	_push_button(_control_center(move_button), MOUSE_BUTTON_LEFT, true)
	_push_button(_control_center(move_button), MOUSE_BUTTON_LEFT, false)
	check(button_pressed[0] == 1 and clicked.size() == field_clicks_before_button, label + ": action button works without a field click")
	var mage_button := _visible_mage_button(hud)
	if mage_button != null:
		_push_motion(_control_center(mage_button))
		check(viewport.gui_get_hovered_control() == mage_button, label + ": mage button receives GUI hover")
	else:
		check(label == "legacy", label + ": a visible mage button is available for interaction")
	# Небольшой resize меняет layout, после чего вход продолжает приходить в Board.
	viewport.size = Vector2i(1180, 800)
	await process_frame
	await process_frame
	var resized_destination := Vector2(8.0, viewport.size.y * 0.6)
	board.pan_camera(resized_destination - _cell_screen(board, cell))
	var resized_cell := _cell_screen(board, cell)
	check(viewport.get_visible_rect().has_point(resized_cell) and not board.get_global_rect().has_point(resized_cell), label + ": resized tile remains in a former HUD region")
	_push_motion(Vector2(2.0, 2.0))
	var hover_count := hovered.size()
	_push_motion(resized_cell)
	check(hovered.size() > hover_count and hovered.back() == cell, label + ": hover path survives viewport resize")
	viewport.size = Vector2i(1280, 850)
	await process_frame
	await process_frame
	board.reset_camera()
	await _capture(label + "-default")
	check(board.size.x > 0.0 and original_size.x > 0.0, label + ": reset after viewport resize preserves board layout")
	check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before and demo.session.context.get_rng().to_dict() == rng_before and demo.session.context.simulation_counters() == counters_before, label + ": all presentation input leaves battle state unchanged")
	demo.queue_free()
	await process_frame

func _visible_mage_button(root_control: Node) -> Button:
	for child: Node in root_control.get_children():
		if child is Button:
			var button := child as Button
			if button.is_visible_in_tree() and (button.has_meta("spell_id") or button.name.begins_with("MageCardSlot") or button.name in [&"MageFireButton", &"MageHealButton"]): return button
		var nested := _visible_mage_button(child)
		if nested != null: return nested
	return null

func _cell_screen(board: BattleDemoBoard, cell: Vector2i) -> Vector2:
	return board.get_global_transform_with_canvas() * board.cell_center(cell)

func _control_center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func _invalid_hover_count(cells: Array[Vector2i]) -> int:
	var count: int = 0
	for cell: Vector2i in cells:
		if cell == Vector2i(-1, -1): count += 1
	return count

func _push_motion(position: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	viewport.push_input(event, true)

func _push_button(position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	viewport.push_input(event, true)

func _push_wheel(position: Vector2, button: MouseButton, ctrl: bool) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		viewport.push_input(event, true)

func _capture(name: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(name + ".png")) == OK, "capture " + name)
