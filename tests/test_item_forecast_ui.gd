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
		printerr("FAIL ITEM FORECAST UI: " + label)

func _run() -> void:
	var packed := load("res://scenes/demo/tactical_battle.tscn") as PackedScene
	_demo = packed.instantiate() as BattleDemo
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 850)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_demo.deployment_enabled = false
	_viewport.add_child(_demo)
	_viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	var battle := _demo.session as BattleTacticalSession
	var actor := battle.selected_unit()
	var flask_button: Button = _demo._action_bar._buttons[2]
	await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
	_check(_demo._item_forecast != null and _demo._item_forecast.status == ActionReceipt.REJECTED and _demo._forecast_panel.text.contains("полное"), "disabled full flask hover explains refusal")
	await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5 + Vector2(1.0, 0.0))
	_check(_demo._item_forecast != null, "small pointer movement inside slot preserves preview")
	_demo.select_character(battle.units[2].id)
	_check(_demo._item_forecast == null, "selection change clears item forecast")
	_demo.select_character(actor.id)
	await _mouse_motion_global(Vector2(4.0, 4.0))
	await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
	actor.vitals.apply_damage(20.0)
	_demo._refresh()
	await _mouse_motion_global(Vector2(4.0, 4.0))
	await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
	_check(_demo._item_forecast != null and _demo._item_forecast.status == ActionReceipt.APPLIED and _demo._forecast_panel.text.contains("HP 12.0 → 24.0") and _demo._forecast_panel.text.contains("Заряды: 2 → 1"), "healing hover shows isolated result and costs")
	_check(_demo._forecast_panel.is_visible_in_tree() and actor.vitals.get_hp() == 12.0 and battle.healing_item().get_charges_left() == 2, "hover panel is visible without live mutation")
	_check(_demo._action_bar.get_global_rect().end.y <= _viewport.size.y, "item preview keeps action bar inside viewport")
	await _capture("item-forecast-healing")
	await _key(KEY_3)
	_check(actor.vitals.get_hp() == 24.0 and battle.healing_item().get_charges_left() == 1 and _demo._item_forecast == null, "key3 applies live healing and clears preview")
	actor.try_refill_turn_resources()
	_demo.reset_demo()
	battle = _demo.session as BattleTacticalSession
	actor = battle.selected_unit()
	await _key(KEY_4)
	var rejected_cell := Vector2i(1, 2)
	await _mouse_motion(_demo.board_view.cell_center(rejected_cell))
	_check(_demo._item_forecast != null and _demo._item_forecast.status == ActionReceipt.REJECTED and _demo._forecast_panel.text.contains("нужна соседняя"), "invalid summon target hover explains refusal")
	await _click_cell(rejected_cell)
	_check(not _demo.summoning_mode and _demo._item_forecast == null and battle.summoning_item().get_charges_left() == 2, "rejected target returns to movement without spending")
	await _key(KEY_4)
	await _mouse_motion(_demo.board_view.cell_center(Vector2i(2, 1)))
	await _key(KEY_ESCAPE)
	_check(not _demo.summoning_mode and _demo._item_forecast == null, "summon cancel clears forecast")
	await _key(KEY_4)
	var target := Vector2i(0, 1)
	await _mouse_motion(_demo.board_view.cell_center(target))
	_check(_demo._item_forecast != null and _demo._item_forecast.status == ActionReceipt.APPLIED and _demo._forecast_panel.text.contains("помощник") and _demo._forecast_panel.text.contains("владелец"), "summon hover shows new pending helper and owner")
	_check(_demo._forecast_panel.is_visible_in_tree() and battle.state.active_summon(actor.id) == null and battle.units.size() == 6, "summon hover is visible without live spawn")
	await _capture("item-forecast-summon")
	await _click_cell(target)
	var helper := battle.state.active_summon(actor.id)
	_check(helper != null and _demo._item_forecast == null and not _demo.summoning_mode, "summon applies only on click and clears forecast")
	if helper != null: await _capture("item-forecast-helper")
	_demo.select_character(actor.id)
	var combination_button: Button
	for node in _demo.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.contains("Сочетания ядра"):
			combination_button = button
			break
	_check(combination_button != null, "K2 scenario button is present")
	if combination_button != null:
		await _click_control(combination_button)
		battle = _demo.session as BattleTacticalSession
		actor = battle.selected_unit()
		actor.vitals.apply_damage(8.0)
		_demo._refresh()
		flask_button = _demo._action_bar._buttons[2]
		await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
		_check(_demo.core_combination_mode and _demo._item_forecast != null and _demo._item_forecast.status == ActionReceipt.APPLIED, "K2 healing preview uses real slot hover")
		_check(_demo._action_bar.get_global_rect().end.y <= _viewport.size.y, "K2 item preview keeps action bar inside viewport")
		await _capture("item-forecast-k2-healing")
		await _mouse_motion(_demo.board_view.cell_center(Vector2i(0, 1)))
		await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
		_check(_demo._item_forecast != null and _demo._forecast_panel.is_visible_in_tree(), "board exit into slot3 preserves new healing preview")
		await _mouse_motion_global(_demo._forecast_panel.global_position + Vector2(20.0, 20.0))
		await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
		_check(_demo._item_forecast != null and _demo._forecast_panel.is_visible_in_tree(), "panel exit into slot3 preserves healing preview")
		await _mouse_motion_global(_demo._action_bar._buttons[0].global_position + _demo._action_bar._buttons[0].size * 0.5)
		_check(_demo._item_forecast == null, "leaving slot3 for another action clears healing preview")
		await _mouse_motion_global(flask_button.global_position + flask_button.size * 0.5)
		await _mouse_motion_global(Vector2(4.0, 4.0))
		_check(_demo._item_forecast == null, "leaving slot3 for outside clears healing preview")
	await _key(KEY_ENTER)
	_check(_demo._item_forecast == null, "phase change clears item forecast")
	await _key(KEY_R)
	_check(_demo._item_forecast == null, "reset clears item forecast")
	await _key(KEY_ENTER)
	_check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "scenario-switch setup enters enemy phase")
	var old_battle := battle
	await _click_control(_demo._mode_button)
	_check(_demo._item_forecast == null and not _demo.tactical_mode and _demo.session != old_battle, "real scenario switch clears forecast during AI")
	var new_session: BattleDemoSession = _demo.session
	var new_snapshot: Dictionary = new_session.board.to_snapshot_dict()
	var new_revision: int = new_session.context.get_revision()
	await create_timer(0.8).timeout
	_check(old_battle.context == null and new_session.context.get_revision() == new_revision and new_session.board.to_snapshot_dict() == new_snapshot, "scenario switch during AI closes old session without mutating new scenario")
	_demo.set_process(false)
	_demo._exit_tree()
	print("ITEM FORECAST UI RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
	await process_frame

func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _demo.board_view.global_position + position
	event.global_position = event.position
	_viewport.push_input(event, true)
	await process_frame
	await process_frame

func _mouse_motion_global(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	_viewport.push_input(event, true)
	await process_frame
	await process_frame

func _click_cell(cell: Vector2i) -> void:
	var position: Vector2 = _demo.board_view.global_position + _demo.board_view.cell_center(cell)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		_viewport.push_input(event, true)
	await process_frame

func _click_control(control: Control) -> void:
	var position: Vector2 = control.global_position + control.size * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
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
