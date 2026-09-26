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
	demo = (load("res://tests/fixtures/demo/control_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	check(demo.control_mode and demo.session is BattleControlSession, "fixture opens C1 session")
	if not demo.session is BattleControlSession:
		await finish()
		return
	demo.set_process(false)
	board = demo.board_view
	var session := demo.session as BattleControlSession
	check(demo.armor_mode and not demo.environment_mode and not demo.bleeding_mode, "separate scenario capabilities")
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT: check(visual.show_rear, "rear marker on each unit")
	check(demo.size.x <= viewport.size.x, "layout fits viewport width")
	await capture("c1-start")
	var actor := session.units[0]
	var target := session.units[1]
	await click(at(actor))
	await key(KEY_A)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await motion(at(target))
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED, "front critical hover executes preview")
	check(demo._forecast_panel.text.contains("Крит ×2") and not demo._forecast_panel.text.contains("Удар в спину"), "front critical has no backstab bonus")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "hover keeps live state")
	await capture("c1-front-critical")
	await key(KEY_ESCAPE)
	await click(at(target))
	check(demo._stats.text.contains("Оглушён") and demo._stats.text.contains("Тыл:"), "inspection explains stun and rear")
	await capture("c1-stun-inspection")
	await click(at(session.units[2]))
	target = session.units[3]
	await key(KEY_A)
	await motion(at(target))
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED, "rear rooted forecast accepted: selected=%d hover=%s status=%s" % [session.selected_id, str(board.hover_cell), str(demo._forecast.reason) if demo._forecast != null else "null"])
	check(demo._forecast_panel.text.contains("Удар в спину +50%") and demo._forecast_panel.text.contains("Крит ×2"), "backstab and crit both explained")
	check(demo._forecast_panel.text.contains("путы будут сняты"), "preview explains removal after push")
	before = ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var expected: Dictionary = demo._forecast.snapshot_after.duplicate(true) if demo._forecast != null else {}
	await capture("c1-rear-critical")
	var panel := demo._forecast_panel
	await motion(panel.global_position + Vector2(35, 40))
	for _i in 12:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.position = panel.global_position + Vector2(35, 40)
		wheel.global_position = wheel.position
		wheel.pressed = true
		viewport.push_input(wheel, true)
		wheel.pressed = false
		viewport.push_input(wheel, true)
		await process_frame
	check(panel.get_v_scroll_bar().value > 0 and demo._forecast != null, "real forecast scrolling preserves hover result")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "scroll preserves live")
	await capture("c1-forecast-scroll")
	await click(at(target))
	check(target.control.entangled_turns == 0, "real attack/push removes roots")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == expected, "real input attack equals preview snapshot")
	check(demo._log.text.contains("путы сняты толчком"), "journal explains actual removal")
	await capture("c1-pushed-free")
	await key(KEY_R)
	session = demo.session as BattleControlSession
	check(session.units[1].control.stunned_turns == 1 and session.units[3].control.entangled_turns == 1, "reset restores predefined statuses")
	await key(KEY_ENTER)
	check(session.phase == BattleTacticalSession.Phase.ENEMY_TURN, "end turn stays available")
	for _i in 40:
		if session.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	check(session.phase != BattleTacticalSession.Phase.FAULTED, "AI handles stun/root")
	check(session.units[1].control.stunned_turns == 0 and session.units[3].control.entangled_turns == 0, "statuses expire after own turn")
	demo._refresh()
	await capture("c1-after-enemy-turn")
	await click(demo._mode_button.global_position + demo._mode_button.size * 0.5)
	check(not demo.control_mode and not demo.session is BattleControlSession, "mode exit clears capability")
	await finish()

func finish() -> void:
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("CONTROL UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CONTROL UI: " + label)

func at(unit: UnitState) -> Vector2:
	# Соседняя стена может перекрывать стопы; кликаем по видимой верхней части фигуры.
	return board.global_position + board.cell_center(unit.cell) - Vector2(0, 25.0 * board.grid_config.tile_size.x / 128.0)

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
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
