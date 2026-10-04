extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE CAMERA UI: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {
		"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(),
	}

func capture(label: String) -> void:
	if captures.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

func _run() -> void:
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	await _test_initial_state()
	await _test_viewport_zoom_pan_and_buttons()
	await _test_forecast_wheel_and_cancel()
	await _test_execution_motion()
	await _test_board_reset()
	await _test_hub_view()
	await _test_legacy_cancel()
	print("BATTLE CAMERA UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_initial_state() -> void:
	var board := demo.board_view
	check(demo.core_reactions_mode and board.camera_controls_enabled, "H1 enables camera controls")
	check(board.get_node_or_null("CameraControls") != null, "screen camera controls are present")
	check(board._camera_reset.tooltip_text.contains("перетаскивание ПКМ") and board._camera_reset.tooltip_text.contains("клик ПКМ — отмена"), "camera tooltip distinguishes right-button drag and cancel")
	check(board._camera_reset.tooltip_text.contains("100%") and not board._camera_reset.tooltip_text.contains("Общий вид"), "camera tooltip describes base size")
	check(is_equal_approx(board.camera_view.zoom, 1.0) and board.camera_view.offset == Vector2.ZERO, "initial camera is centered at 100 percent")
	check(board.grid_config.tile_size == Vector2(128, 64) and board.grid_config.height_step == 32.0, "main H1 uses 128x64 tiles and 32 height step at 100 percent")
	await capture("main-100")
	demo._hover(Vector2i(-1, -1))
	check(demo._hint.text.contains("Клик ПКМ — отмена") and demo._hint.text.contains("перетаскивание ПКМ — камера") and demo._hint.text.contains("Esc/M"), "main hint describes right-button click/drag and keyboard cancel")
	var center := board.cell_center(demo.session.selected_unit().cell)
	check(board.cell_at(center) == demo.session.selected_unit().cell, "initial screen cell center picks same cell")
	check(board.displayed_unit_at(center + Vector2(0, -12)) == demo.session.selected_id, "initial unit picking uses view coordinates")
	var head := board.world_to_view(board._world_cell_center(demo.session.selected_unit().cell) + Vector2(0, -55))
	check(board.displayed_unit_at(head) == demo.session.selected_id, "100 percent picking covers placeholder head")
	var saved_size := board.size
	board.size = Vector2(540, board.size.y)
	check(board.grid_config.tile_size == Vector2(128, 64) and board.grid_config.height_step == 32.0, "narrow camera field keeps base tile geometry")
	board.size = saved_size
	await process_frame

func _test_viewport_zoom_pan_and_buttons() -> void:
	var board := demo.board_view
	var actor := demo.session.selected_unit()
	var cell := actor.cell
	var anchor := board.global_position + board.cell_center(cell)
	var world_anchor := board.view_to_world(anchor - board.global_position)
	var toolbar_rect := demo._move_button.get_global_rect()
	var actionbar_rect := demo._action_bar.get_global_rect()
	var before_camera_input := snapshot(demo.session as BattleCoreReactionsSession)
	var wheel_anchor := anchor
	_push_wheel(wheel_anchor, MOUSE_BUTTON_WHEEL_UP, 6.0)
	var expected_zoom: float = pow(1.1, 6.0)
	check(is_equal_approx(board.camera_view.zoom, expected_zoom), "real viewport wheel zooms camera")
	check(board.view_to_world(wheel_anchor - board.global_position).is_equal_approx(world_anchor), "wheel keeps world point under cursor")
	check(board.cell_at(board.cell_center(cell)) == cell, "cell picking follows zoom transform")
	check(board.displayed_unit_at(board.cell_center(cell) + Vector2(0, -12)) == actor.id, "unit picking follows zoom transform")
	check(demo._move_button.get_global_rect().size == toolbar_rect.size and demo._action_bar.get_global_rect().size == actionbar_rect.size, "camera zoom does not resize toolbar or action bar")
	check(snapshot(demo.session as BattleCoreReactionsSession) == before_camera_input, "real camera input leaves snapshot RNG and counters unchanged")
	# Основные сцены проверяются в исходном рабочем размере после новых узких кадров.
	viewport.size = Vector2i(1440, 950)
	await process_frame
	await process_frame
	var layers: Array[Node2D] = [board._tiles, board._entities, board._ghosts, board._impacts, board._numbers, board._overlay]
	for layer: Node2D in layers:
		check(layer.transform.is_equal_approx(board.camera_view.get_transform()), "all six visual layers share camera transform " + layer.name)
	await capture("main-zoomed")
	var before_pan := board.camera_view.offset
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.position = board.global_position + Vector2(100, 100)
	down.global_position = down.position
	viewport.push_input(down, true)
	var drag := InputEventMouseMotion.new()
	drag.position = down.position + Vector2(36, -24)
	drag.global_position = drag.position
	drag.relative = Vector2(36, -24)
	viewport.push_input(drag, true)
	check(board.camera_view.offset.is_equal_approx(before_pan + Vector2(36, -24)), "right-button drag pans camera")
	var zoom_anchor := board.global_position + Vector2(220, 170)
	var anchor_local := zoom_anchor - board.global_position
	var world_before_zoom_out := board.view_to_world(anchor_local)
	var zoom_before_zoom_out := board.camera_view.zoom
	_push_wheel(zoom_anchor, MOUSE_BUTTON_WHEEL_DOWN, 1.0)
	check(is_equal_approx(board.camera_view.zoom, zoom_before_zoom_out / 1.1), "wheel zooms out after pan")
	check(board.world_to_view(world_before_zoom_out).is_equal_approx(anchor_local), "zoom-out after pan preserves cursor anchor")
	var head_after_pan := board.world_to_view(board._world_cell_center(cell) + Vector2(0, -55))
	check(board.displayed_unit_at(head_after_pan) == actor.id, "picking covers placeholder head after pan")
	expected_zoom /= 1.1
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(3, 3)
	release.global_position = release.position
	viewport.push_input(release, true)
	check(not board._camera_dragging, "right-button release outside field ends drag")
	var focus_drag := InputEventMouseButton.new()
	focus_drag.button_index = MOUSE_BUTTON_RIGHT
	focus_drag.pressed = true
	focus_drag.position = zoom_anchor
	focus_drag.global_position = zoom_anchor
	viewport.push_input(focus_drag, true)
	board.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not board._camera_dragging, "window focus loss ends drag")
	var focus_release := focus_drag.duplicate() as InputEventMouseButton
	focus_release.pressed = false
	focus_release.position = Vector2(3, 3)
	focus_release.global_position = focus_release.position
	viewport.push_input(focus_release, true)
	var controls := board.get_node("CameraControls") as HBoxContainer
	var minus := controls.get_child(0) as Button
	var reset := controls.get_child(1) as Button
	var plus := controls.get_child(2) as Button
	await _click_control(minus)
	check(is_equal_approx(board.camera_view.zoom, expected_zoom / 1.1), "minus button zooms out")
	await _click_control(plus)
	check(is_equal_approx(board.camera_view.zoom, expected_zoom), "plus button zooms in")
	await _click_control(reset)
	check(is_equal_approx(board.camera_view.zoom, 1.0) and board.camera_view.offset == Vector2.ZERO, "reset button restores camera")
	check(reset.text == "100%", "reset button shows current zoom percentage")
	viewport.size = Vector2i(1280, 850)
	await process_frame
	await process_frame
	board.reset_camera()
	_push_wheel(board.global_position + Vector2(240, 180), MOUSE_BUTTON_WHEEL_DOWN, 100.0)
	check(is_equal_approx(board.camera_view.zoom, 0.75) and board._camera_reset.text == "75%", "real wheel clamps at 75 percent and updates label")
	var head_at_minimum := board.world_to_view(board._world_cell_center(actor.cell) + Vector2(0, -55))
	check(board.displayed_unit_at(head_at_minimum) == actor.id, "75 percent picking covers placeholder head")
	await capture("main-75")
	board.reset_camera()
	viewport.size = Vector2i(1440, 950)
	await process_frame
	await process_frame

func _push_wheel(position: Vector2, button_index: MouseButton, factor: float, ctrl: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.factor = factor
	event.ctrl_pressed = ctrl
	event.position = position
	event.global_position = position
	for pressed: bool in [true, false]:
		event.pressed = pressed
		viewport.push_input(event, true)

func _push_motion(position: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	viewport.push_input(event, true)

func _test_forecast_wheel_and_cancel() -> void:
	demo.set_diagnostics_visible(true)
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)
	var target := demo.session.units[3]
	var board := demo.board_view
	var point := board.global_position + board.cell_center(target.cell)
	_push_motion(point)
	demo._process_attack_forecast()
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)
	check(demo._forecast != null and demo._forecast_panel.is_visible_in_tree(), "diagnostic attack forecast is visible for target")
	var zoom_before := board.camera_view.zoom
	var offset_before := board.camera_view.offset
	var scroll := demo._forecast_panel.get_v_scroll_bar()
	var scroll_before := scroll.value
	_push_wheel(point, MOUSE_BUTTON_WHEEL_DOWN, 1.0)
	check(board.camera_view.zoom == zoom_before and board.camera_view.offset == offset_before, "ordinary wheel over forecast does not zoom camera")
	if scroll.max_value > scroll.page:
		check(scroll.value > scroll_before, "ordinary target wheel scrolls diagnostic forecast")
	else:
		check(false, "diagnostic forecast content is scrollable")
	var anchor := point - board.global_position
	var world_under_cursor := board.view_to_world(anchor)
	_push_wheel(point, MOUSE_BUTTON_WHEEL_UP, 1.0, true)
	check(is_equal_approx(board.camera_view.zoom, zoom_before * 1.1), "Ctrl plus target wheel zooms camera")
	check(board.world_to_view(world_under_cursor).is_equal_approx(anchor), "Ctrl zoom keeps target under cursor")
	check(demo._forecast != null and demo._forecast_panel.is_visible_in_tree(), "Ctrl zoom preserves visible forecast")
	var selected_before_drag: int = demo.session.selected_id
	var offset_before_click := board.camera_view.offset
	await _right_drag(point, Vector2(22, -14))
	check(demo.attack_mode and demo.session.selected_id == selected_before_drag, "right-button drag preserves attack mode and selected unit")
	check(board.camera_view.offset.is_equal_approx(offset_before_click + Vector2(22, -14)), "right-button drag pans while targeting")
	offset_before_click = board.camera_view.offset
	var click_down := InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_RIGHT
	click_down.pressed = true
	click_down.position = point
	click_down.global_position = point
	viewport.push_input(click_down, true)
	check(demo.attack_mode, "right-button press does not cancel targeting")
	var click_up := click_down.duplicate() as InputEventMouseButton
	click_up.pressed = false
	viewport.push_input(click_up, true)
	await process_frame
	check(not demo.attack_mode and demo.session.selected_id == selected_before_drag, "right-button release cancels targeting and preserves selection")
	check(board.camera_view.offset == offset_before_click and not board._camera_gesture_active, "right click does not pan and releases capture")
	demo.set_attack_mode(true)
	click_down = InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_RIGHT
	click_down.pressed = true
	click_down.position = point
	click_down.global_position = point
	viewport.push_input(click_down, true)
	_push_motion(point + Vector2(3, 2), Vector2(3, 2))
	check(board.camera_view.offset == offset_before_click and demo.attack_mode, "sub-threshold jitter does not pan or cancel before release")
	click_up = click_down.duplicate() as InputEventMouseButton
	click_up.pressed = false
	click_up.position = Vector2(3, 3)
	click_up.global_position = click_up.position
	viewport.push_input(click_up, true)
	await process_frame
	check(not demo.attack_mode and board.camera_view.offset == offset_before_click, "sub-threshold jitter cancels on release without panning")
	demo.set_attack_mode(true)
	click_down = InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_RIGHT
	click_down.pressed = true
	click_down.position = point
	click_down.global_position = point
	viewport.push_input(click_down, true)
	_push_motion(point + Vector2(10, 0), Vector2(10, 0))
	_push_motion(point, Vector2(-10, 0))
	click_up = click_down.duplicate() as InputEventMouseButton
	click_up.pressed = false
	click_up.position = Vector2(3, 3)
	click_up.global_position = click_up.position
	viewport.push_input(click_up, true)
	await process_frame
	check(demo.attack_mode and board.camera_view.offset == offset_before_click, "large out-and-back drag keeps action and pans full path")
	check(not board._camera_gesture_active and not board._camera_dragging, "release outside field ends drag capture")
	click_down = InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_RIGHT
	click_down.pressed = true
	click_down.position = point
	click_down.global_position = point
	viewport.push_input(click_down, true)
	board.reset_camera()
	click_up = click_down.duplicate() as InputEventMouseButton
	click_up.pressed = false
	click_up.position = point
	click_up.global_position = point
	viewport.push_input(click_up, true)
	check(demo.attack_mode, "camera reset clears gesture without cancelling action")
	click_down.pressed = true
	viewport.push_input(click_down, true)
	board.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	click_up = click_down.duplicate() as InputEventMouseButton
	click_up.pressed = false
	viewport.push_input(click_up, true)
	check(demo.attack_mode, "focus loss clears gesture without cancelling action")
	await _key(KEY_M)
	check(not demo.attack_mode and demo._forecast == null, "M cancels targeting")
	demo.set_attack_mode(true)
	await _key(KEY_ESCAPE)
	check(not demo.attack_mode, "Escape cancels targeting")
	demo.inspect_enemy(target.id)
	check(demo.inspected_id == target.id, "fixture enters enemy inspection")
	await _right_click(point)
	check(demo.inspected_id == UnitId.NONE, "right-button click release clears inspection")
	demo.set_diagnostics_visible(false)
	demo.reset_demo()
	await process_frame
	PlayerTurnFixture.enter_player_turn(demo)

func _click_control(control: Control) -> void:
	var point := control.global_position + control.size * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	await process_frame

func _right_click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	await process_frame

func _right_drag(point: Vector2, delta: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.position = point
	down.global_position = point
	viewport.push_input(down, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + delta
	motion.global_position = motion.position
	motion.relative = delta
	viewport.push_input(motion, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	up.position = Vector2(3, 3)
	up.global_position = up.position
	viewport.push_input(up, true)
	await process_frame

func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		viewport.push_input(event, true)
	await process_frame

func _wait_for_presentation() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending():
			break
		await process_frame
	check(demo.is_presentation_pending(), "movement worker joins and starts clip")
	if demo.is_presentation_pending():
		demo._presentation_player._tween.pause()

func _test_execution_motion() -> void:
	var board := demo.board_view
	var session := demo.session as BattleCoreReactionsSession
	var actor := session.selected_unit()
	var actor_id: int = actor.id
	var from: Vector2i = actor.cell
	var destination := Vector2i(1, 2)
	demo._execute_live(&"move_to", [destination])
	check(demo.session == null and board.execution_pending, "camera test runs while worker owns detached runtime")
	# Камерой можно пользоваться, пока worker считает результат; его сессия не читается здесь.
	var camera_point := board.global_position + board.size * 0.5
	_push_wheel(camera_point, MOUSE_BUTTON_WHEEL_UP, 2.0)
	var drag_down := InputEventMouseButton.new()
	drag_down.button_index = MOUSE_BUTTON_RIGHT
	drag_down.pressed = true
	drag_down.position = camera_point
	drag_down.global_position = camera_point
	viewport.push_input(drag_down, true)
	var offset_before := board.camera_view.offset
	_push_motion(camera_point + Vector2(18, 12), Vector2(18, 12))
	check(board.camera_view.zoom > 1.0, "viewport camera controls work while execution worker runs")
	check(board.camera_view.offset.is_equal_approx(offset_before + Vector2(18, 12)), "worker right-button drag moves only view")
	drag_down.pressed = false
	viewport.push_input(drag_down, true)
	await _wait_for_presentation()
	var committed := snapshot(session)
	var visual := board._presentation_visual(actor_id)
	check(visual != null and board._view_unit_cell(actor_id) == from, "clip keeps original shown location before publishing")
	var tween := demo._presentation_player._tween
	var origin_pose := board._world_cell_center(from)
	var destination_pose := board._world_cell_center(destination)
	var current_pose := visual.position + visual.get_visual_offset()
	for step: int in 20:
		if not current_pose.is_equal_approx(origin_pose) and not current_pose.is_equal_approx(destination_pose):
			break
		tween.custom_step(0.025)
		current_pose = visual.position + visual.get_visual_offset()
	check(not current_pose.is_equal_approx(origin_pose) and not current_pose.is_equal_approx(destination_pose), "paused movement tween advances to a mid-segment pose")
	var result_number_count := board._numbers.get_child_count()
	if result_number_count == 0:
		board._add_result_number(actor_id, "+1.0 HP", Color("65dfcc"))
	var result_number := board._numbers.get_child(0) as BattlePresentationNumber
	var number_tween := result_number._tween
	var zoom_anchor := board.global_position + Vector2(340, 260)
	var zoom_before := board.camera_view.zoom
	_push_wheel(zoom_anchor, MOUSE_BUTTON_WHEEL_UP, 1.0)
	check(is_equal_approx(board.camera_view.zoom, zoom_before * 1.1), "viewport wheel zooms during movement clip")
	check(board._presentation_visual(actor_id) == visual and demo._presentation_player._tween == tween, "zoom keeps moving node and active clip tween")
	check((visual.position + visual.get_visual_offset()).is_equal_approx(current_pose), "zoom leaves current tween world pose unchanged")
	check(board.displayed_unit_at(board.world_to_view(current_pose + Vector2(0, -12))) == actor_id, "inspection picks moving body after zoom and pan")
	check(result_number._tween == number_tween and number_tween.is_valid(), "zoom does not restart independent result number")
	check(snapshot(session) == committed, "camera and shown clip preserve committed snapshot RNG and counters")
	await capture("motion-paused")
	demo.skip_presentation()
	check(not demo.is_execution_pending() and board._view_unit_cell(actor_id) == destination, "skip publishes destination after camera changes")
	check(snapshot(session) == committed, "skip preserves committed snapshot RNG and counters")

func _test_board_reset() -> void:
	var board := demo.board_view
	board.zoom_camera(2.0, Vector2(140, 120))
	demo.reset_demo()
	await process_frame
	check(is_equal_approx(board.camera_view.zoom, 1.0) and board.camera_view.offset == Vector2.ZERO, "new battle resets camera")
	check(board.grid_config.tile_size == Vector2(128, 64) and board.grid_config.height_step == 32.0, "new battle reset retains camera base geometry")

func _test_hub_view() -> void:
	demo.queue_free()
	await process_frame
	var hub := HeroHubBattleView.new()
	hub.supplied_session = PlayerTurnFixture.create()
	viewport.add_child(hub)
	# Настоящий HeroHubScreen растягивает view после добавления в host.
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.set_process(false)
	await process_frame
	check(hub.board_view.camera_controls_enabled and hub.board_view.get_node_or_null("CameraControls") != null, "hero hub battle enables camera")
	check(hub.board_view.grid_config.tile_size == Vector2(128, 64) and hub.board_view.grid_config.height_step == 32.0, "hero hub H1 uses base tile geometry at 100 percent")
	viewport.size = Vector2i(1280, 850)
	await process_frame
	await process_frame
	await capture("hub-100")
	_push_wheel(hub.board_view.global_position + hub.board_view.size * 0.5, MOUSE_BUTTON_WHEEL_UP, 3.0)
	check(is_equal_approx(hub.board_view.camera_view.zoom, pow(1.1, 3.0)), "viewport wheel zooms hero hub battlefield")
	hub.board_view.zoom_camera(0.75, hub.board_view.size * 0.5)
	check(is_equal_approx(hub.board_view.camera_view.zoom, 0.75), "hero hub H1 supports 75 percent zoom")
	await capture("hub-75")
	viewport.size = Vector2i(1440, 950)
	await process_frame
	await process_frame
	await capture("hub-battle")
	hub.queue_free()
	await process_frame

func _test_legacy_cancel() -> void:
	var board := BattleDemoBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	await process_frame
	var calls: Array[int] = [0]
	board.cancel_requested.connect(func() -> void: calls[0] += 1)
	var legacy_factor := maxf(0.1, minf((board.size.x - 64) / 1024.0, (board.size.y - 108) / 544.0))
	check(board.grid_config.tile_size == Vector2(128, 64) * legacy_factor and board.grid_config.height_step == 32.0 * legacy_factor, "camera-disabled field keeps legacy auto-fit geometry")
	await _right_click(board.global_position + Vector2(300, 300))
	check(not board.camera_controls_enabled and calls[0] == 1, "camera-disabled field keeps legacy right-click cancel")
	board.queue_free()
	await process_frame
