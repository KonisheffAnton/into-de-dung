extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _demo: BattleDemo
var _viewport: SubViewport
var _captures: String = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): _captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		printerr("FAIL MOVE FORECAST UI: " + label)

func _run() -> void:
	_demo = (load("res://scenes/demo/core_combination_battle.tscn") as PackedScene).instantiate() as BattleDemo
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 850)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.add_child(_demo)
	_viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	var s := _demo.session as BattleCoreCombinationSession
	var actor := s.selected_unit()
	s.board.move_unit(actor, Vector2i(0, 1))
	for item: ItemInstance in s.state.get_owner(actor.id)._items.values(): item.armor_remaining = 0
	_demo._refresh()
	var target := Vector2i(2, 1)
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var counters := s.context.simulation_counters()
	var last := s.last_receipt
	await _hover(target)
	var f := _demo._move_forecast
	_check(f != null and f.status == ActionReceipt.APPLIED and f.units[actor.id]["after"]["hp"] == 24, "hover predicts spike damage")
	_check(_demo._forecast_panel.is_visible_in_tree() and _demo._forecast_panel.text.contains("расход 2.0 ОД") and _demo._forecast_panel.text.contains("32.0 → 24.0"), "visible final health and cost")
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.simulation_counters() == counters and s.last_receipt == last, "hover isolates full live state")
	_check(_demo.board_view.move_forecast == f and _demo.board_view._forecast_entry(actor.id)["after"]["hp"] == 24 and _demo.board_view._path == f.traversed_path, "board shows health and actual route")
	await _hover(target)
	_check(_demo._move_forecast == f, "same hover reuses forecast")
	_check(_demo._action_bar.get_global_rect().end.y <= _viewport.size.y, "forecast keeps controls inside viewport")
	await _capture("move-forecast-spikes")
	await _wheel(target)
	_check(_demo._move_forecast == f and _demo._forecast_panel.get_v_scroll_bar().value > 0, "target wheel scrolls without execution")
	await _motion(_demo._forecast_panel.global_position + Vector2(20, 20))
	_check(_demo._move_forecast == f, "panel transition retains movement result")
	await _motion(Vector2(4, 4))
	_check(_demo._move_forecast == null and _demo.board_view.move_forecast == null, "outside clears result and health overlay")
	await _hover(target)
	f = _demo._move_forecast
	await _click(target)
	_check(actor.cell == target and s.last_receipt.get_events() == f.events and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == f.snapshot_after, "click submits matching fresh movement")
	_check(_demo._move_forecast != f, "receipt invalidates old forecast")
	await _key(KEY_R)
	s = _demo.session as BattleCoreCombinationSession
	actor = s.selected_unit()
	s.board.move_unit(actor, Vector2i(0, 1))
	for item: ItemInstance in s.state.get_owner(actor.id)._items.values(): item.armor_remaining = 0
	actor.vitals.set_hp(1)
	_demo._refresh()
	await _hover(target)
	f = _demo._move_forecast
	_check(f != null and f.status == ActionReceipt.INTERRUPTED and f.traversed_path == [Vector2i(0, 1), Vector2i(1, 1)], "lethal route shows only executed prefix")
	_check(_demo._forecast_panel.text.contains("Маршрут прервётся") and _demo._forecast_panel.text.contains("ГИБЕЛЬ") and _demo._forecast_panel.text.contains("расход 1.0 ОД"), "lethal forecast explains endpoint cost and death")
	await _capture("move-forecast-interrupted")
	await _key(KEY_A)
	_check(_demo._move_forecast == null and _demo.board_view.move_forecast == null, "attack mode clears movement forecast")
	await _key(KEY_M)
	await _hover(target)
	actor.move_points_left = 0
	_demo._refresh()
	_check(_demo._move_forecast != f and _demo._move_forecast.status == ActionReceipt.REJECTED and _demo._forecast_panel.text.contains("не хватает"), "refresh without revision invalidates result")
	await _capture("move-forecast-refusal")
	var unchanged := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	await _click(target)
	_check(s.last_receipt.status == ActionReceipt.REJECTED and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == unchanged, "fresh click refuses without spending")
	await _key(KEY_R)
	s = _demo.session as BattleCoreCombinationSession
	await _hover(Vector2i(0, 1))
	f = _demo._move_forecast
	await _click(s.units[4].cell)
	await _hover(Vector2i(4, 5))
	_check(_demo._move_forecast != f and _demo._move_forecast.reason == &"control/stunned", "selection invalidates and stun explains refusal")
	await _click(s.units[1].cell)
	_check(_demo.inspected_id == s.units[1].id and _demo._move_forecast == null, "enemy inspection suppresses movement forecast")
	await _key(KEY_ESCAPE)
	await _click(s.units[0].cell)
	await _key(KEY_6)
	_check(_demo._move_forecast == null, "raise targeting has no movement preview")
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	_check(_demo._move_forecast == null, "enemy phase clears movement forecast")
	await _click_control(_demo._mode_button)
	_check(not _demo.tactical_mode and _demo._move_forecast == null, "scenario switch during AI clears movement forecast")
	await _hover(Vector2i(0, 1))
	_check(_demo._move_forecast != null and _demo._move_forecast.status == ActionReceipt.APPLIED, "sandbox supports movement forecast")
	var sandbox := _demo.session
	var sandbox_actor := sandbox.selected_unit()
	sandbox.board.set_height_steps(sandbox_actor.cell, 6)
	sandbox_actor.height = 3
	_demo._refresh()
	var fall_target := Vector2i(0, 3)
	await _hover(fall_target)
	f = _demo._move_forecast
	_check(_demo.board_view.hover_cell == fall_target, "fall hover hits destination surface")
	_check(f != null and f.status == ActionReceipt.APPLIED and f.units[sandbox_actor.id]["after"]["hp"] < sandbox_actor.vitals.get_hp(), "sandbox predicts existing fall rule")
	await _capture("move-forecast-fall")
	await _click(fall_target)
	_check(sandbox.last_receipt != null and f != null and sandbox.last_receipt.get_events() == f.events and ItemSimulationSnapshot.capture(sandbox.state, []).snapshot.to_dict() == f.snapshot_after, "fall preview matches real click")
	_demo.set_process(false)
	_demo._exit_tree()
	print("MOVE FORECAST UI RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
	await process_frame

func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	_viewport.push_input(event, true)
	await process_frame
	await process_frame

func _hover(cell: Vector2i) -> void:
	await _motion(_demo.board_view.global_position + _demo.board_view.cell_center(cell))

func _click(cell: Vector2i) -> void:
	await _button(_demo.board_view.global_position + _demo.board_view.cell_center(cell), MOUSE_BUTTON_LEFT)

func _wheel(cell: Vector2i) -> void:
	await _button(_demo.board_view.global_position + _demo.board_view.cell_center(cell), MOUSE_BUTTON_WHEEL_DOWN)

func _click_control(control: Control) -> void:
	await _button(control.global_position + control.size * 0.5, MOUSE_BUTTON_LEFT)

func _button(position: Vector2, button: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		_viewport.push_input(event, true)
	await process_frame

func _capture(label: String) -> void:
	if _captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := _viewport.get_texture().get_image()
	_check(picture != null and picture.save_png(_captures.path_join(label + ".png")) == OK, "capture " + label)
