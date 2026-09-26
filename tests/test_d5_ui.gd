extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var board: BattleDemoBoard
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://tests/fixtures/demo/environment_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	board = demo.get("board_view") as BattleDemoBoard
	_check(demo.environment_mode and demo.session is BattleEnvironmentSession, "D5 scene and session")
	var session := demo.session as BattleEnvironmentSession
	_check(session.state.environment.fires.size() == 2 and session.state.environment.corpses.size() == 1, "initial fire and corpse markers")
	_check(board != null and board.environment_mode, "environment board mode")
	_check(demo._action_bar._buttons[4].get_meta("action_id") == &"blood_rune" and demo._action_bar._buttons[5].get_meta("action_id") == &"raise_corpse", "action slots five and six")
	await capture("d5-start")
	var actor := session.units[0]
	await click(at(actor))
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var raise_button := demo._action_bar._buttons[5]
	await click(raise_button.global_position + raise_button.size * 0.5)
	_check(demo.raising_mode and board._reachable.has(Vector2i(0, 3)), "raise target mode")
	await key(KEY_M)
	_check(not demo.raising_mode, "movement shortcut clears raise mode")
	await key(KEY_6)
	await key(KEY_ESCAPE)
	_check(not demo.raising_mode, "escape clears raise mode")
	await key(KEY_6)
	await capture("d5-raise-target")
	await click(at_cell(Vector2i(0, 3)))
	_check(not demo.raising_mode and session.state.environment.corpses.is_empty(), "corpse consumed")
	var helper := session.board.get_unit_by_id(session.state.active_summon(actor.id).id)
	_check(helper != null and is_equal_approx(helper.vitals.get_hp(), 16.0) and actor.action_resources.get_main_left() == 0, "helper HP and main cost")
	_check(session.state.is_summon_pending(helper.id) and demo._log.text.contains("поднял тело"), "helper waits and journal")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() != before, "raise mutates state")
	await capture("d5-raised")
	var helper_id := helper.id
	await key(KEY_6)
	_check(not demo.raising_mode and session.state.active_summon(actor.id).id == helper_id, "no duplicate helper")
	await key(KEY_ENTER)
	# Вход в фазу — настоящий Enter; оставшийся ИИ исполняем без кадровых задержек.
	demo.set_process(false)
	for _i in 40:
		if session.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	demo._refresh()
	_check(not session.state.is_summon_pending(helper_id), "helper active after team boundary")
	await key(KEY_R)
	session = demo.session as BattleEnvironmentSession
	board = demo.get("board_view") as BattleDemoBoard
	session.select_unit(session.units[0].id)
	demo._refresh()
	await key(KEY_6)
	var mode_button := demo.get("_mode_button") as Button
	await click(mode_button.global_position + mode_button.size * 0.5)
	_check(not demo.environment_mode and not demo.raising_mode, "scenario switch clears raise mode")
	demo.queue_free()
	await process_frame
	demo = (load("res://tests/fixtures/demo/environment_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	await process_frame; await process_frame
	session = demo.session as BattleEnvironmentSession
	board = demo.get("board_view") as BattleDemoBoard
	_check(demo.environment_mode and demo.armor_mode and demo.bleeding_mode and session != null, "fixture reinstantiates D5 session after polygon switch")
	await key(KEY_R)
	session.select_unit(session.units[0].id)
	demo._refresh()
	_check(session.state.environment.corpses.size() == 1 and session.state.environment.fires.size() == 2, "reset restores environment")
	# Контролируем расстановку, затем весь прогноз/удар идут настоящим UI-вводом.
	for y in session.board.height:
		for x in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	session.state.environment.fires.clear()
	session.state.environment.ignite(Vector2i(3, 3))
	session.board.move_unit(session.units[0], Vector2i(1, 3))
	session.board.move_unit(session.units[1], Vector2i(2, 3))
	for item: ItemInstance in session.state.get_owner(session.units[1].id)._items.values(): item.armor_remaining = 0
	demo._refresh()
	await click(at(session.units[0])); await key(KEY_A); await motion(at(session.units[1]))
	var forecast := demo._forecast
	_check(forecast != null and forecast.status == ActionReceipt.APPLIED and demo._forecast_panel.text.contains("Шипы на D4"), "input forecast push into fire")
	var unchanged := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await capture("d5-forecast")
	var panel := demo._forecast_panel
	await motion(panel.global_position + Vector2(50, 50))
	for _i in 20:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
		wheel.position = panel.global_position + Vector2(50, 50); wheel.global_position = wheel.position
		viewport.push_input(wheel, true)
		wheel = wheel.duplicate(); wheel.pressed = false; viewport.push_input(wheel, true)
	await process_frame
	_check(panel.get_v_scroll_bar().value > 0 and demo._forecast != null, "real forecast scroll")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == unchanged, "hover and scroll preserve live")
	await capture("d5-forecast-scroll")
	await click(at(session.units[1]))
	_check(session.units[1].vitals.get_hp() == 8 and session.units[1].cell == Vector2i(3, 3) and session.last_receipt.get_events() == forecast.events, "UI execution matches forecast")
	await key(KEY_M)
	var body_cell := Vector2i(4, 4)
	for dead: UnitState in [session.units[2], session.units[3]]:
		session.board.move_unit(dead, body_cell)
		var death := session._submit(DeathCommand.new(dead.id, DamageSource.new(&"test", 0, body_cell)))
		demo._show_receipt(death)
	await motion(at_cell(body_cell))
	_check(session.state.environment.corpses_at(body_cell).size() == 2 and demo._hint.text.contains("Тела ×2") and demo._hint.text.contains("союзник") and demo._hint.text.contains("противник") and demo._hint.text.contains("гуманоид"), "multiple bodies faction/type in real hover")
	await capture("d5-corpses")
	viewport.queue_free()
	await process_frame
	print("D5 UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL D5 UI: " + label)

func at(unit: UnitState) -> Vector2:
	return board.global_position + board.cell_center(unit.cell)

func at_cell(cell: Vector2i) -> Vector2:
	return board.global_position + board.cell_center(cell)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	_check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
