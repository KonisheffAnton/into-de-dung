extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL COLLAPSE UI: " + label)

func snapshot() -> Dictionary:
	var result := ItemSimulationSnapshot.capture(demo.session.state, [])
	return result.snapshot.to_dict() if result.code == ItemSnapshotResult.Code.OK else {}

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	var s := demo.session as BattleCoreReactionsSession
	check(s.state.environment.collapse == {"turn": 0, "marked": []}, "battle starts before first environmental turn")
	check(demo._environment_button.visible and demo.board_view._view_collapse.is_empty(), "button present and no initial warning")
	var before := snapshot()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	await motion(button_center()); await settle()
	var first := demo._environment_forecast
	check(first != null and first.status == ActionReceipt.APPLIED, "real hover completes worker preview")
	check(first != null and first.events.size() == 1 and first.events[0].kind == &"environment_turn", "first preview only marks")
	check(snapshot() == before and s.context.get_rng().to_dict() == rng, "hover preserves live and RNG")
	await click(button_center()); await settle()
	check(snapshot() == before, "button only previews and never executes phase")
	check(demo._forecast_panel.text.contains("Будущие действия") and demo._forecast_heading.text.contains("ОКРУЖЕНИЕ"), "conditional scope is explicit")
	await key(KEY_ENTER)
	demo._ai_delay = 9999.0
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN and s.state.environment.collapse.turn == 0, "Enter hands over to enemies without environment")
	check(demo._environment_forecast == null and demo._environment_button.disabled, "enemy phase clears preview and disables request")
	s._enemy_index = s._enemy_ids.size()
	demo._execute_live(&"step_enemy")
	check(demo.is_execution_pending() and demo.session == null, "environment boundary uses live worker ownership")
	check(demo.board_view._view_collapse.is_empty(), "pending renderer keeps completed unmarked view")
	await live_settle()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.round_number == 2 and s.state.environment.collapse.turn == 1, "first environment completes after both teams")
	var marked: Vector2i = s.state.environment.collapse.marked[0]
	check(s.board.get_terrain(marked) == TerrainType.Type.FLOOR and demo.board_view._view_collapse == [marked], "new mark is visible but retains support")
	await motion(at(marked))
	check(demo._hint.text.contains("ОБВАЛ после хода врагов"), "hover explains deadline and death")

	# Прямая правка без revision моделирует внешний авторский сценарий.
	s.state.environment.collapse = {"turn": 1, "marked": [s.units[0].cell]}
	demo._refresh()
	await motion(button_center()); await settle()
	var lethal := demo._environment_forecast
	check(lethal != null and lethal.status == ActionReceipt.APPLIED and not lethal.units_after[s.units[0].id].alive, "preview includes real guarded death")
	check(demo._forecast_panel.text.contains("погибнет в пропасти"), "panel names victim")
	await capture("collapse-forecast")
	var old_revision := s.context.get_revision()
	s.state.environment.collapse.marked = [Vector2i(2, 2)]
	demo._refresh(); await settle()
	check(s.context.get_revision() == old_revision and demo._environment_forecast != null and demo._environment_forecast.units_after[s.units[0].id].alive, "refresh without revision replaces lethal prediction")
	await motion(at(s.units[0].cell))
	check(demo._environment_forecast == null and not demo._environment_forecast_pending, "leaving preview for board clears it")

	s.state.environment.collapse.marked = [s.units[0].cell]
	demo._refresh()
	var fallen := s.units[0]
	var fallen_cell := fallen.cell
	await key(KEY_ENTER)
	demo._ai_delay = 9999.0
	s._enemy_index = s._enemy_ids.size()
	demo._execute_live(&"step_enemy")
	var old_view := demo.board_view._view_collapse.duplicate()
	viewport.size = Vector2i(1300, 870)
	demo.board_view.queue_redraw()
	check(demo.session == null and old_view == [fallen_cell], "resize while pending reads only old presentation")
	await live_settle()
	check(not fallen.is_alive() and s.board.occupant_at(fallen_cell) == null and s.board.get_terrain(fallen_cell) == TerrainType.Type.VOID, "live boundary collapses occupied cell and clears occupancy")
	check(s.state.environment.corpses_at(fallen_cell).is_empty(), "fall leaves no body")
	check(demo.board_view._view_collapse == s.state.environment.collapse.marked and demo.board_view._view_terrain_at(fallen_cell) == TerrainType.Type.VOID, "joined worker publishes fresh geometry and next warning")
	check("\n".join(demo._journal).contains("Обвал:"), "phase events reach journal")
	await motion(Vector2(8, 8))
	await capture("collapse-live")

	await motion(button_center())
	demo._process_environment_forecast()
	demo.reset_demo()
	await settle()
	check((demo.session as BattleCoreReactionsSession).state.environment.collapse.turn == 0 and demo.board_view._view_collapse.is_empty(), "reset discards old warnings")
	check(demo._environment_forecast == null or demo._environment_forecast.snapshot_before == snapshot(), "old worker cannot publish into reset session")
	await motion(button_center()); demo._process_environment_forecast()
	demo.queue_free()
	await process_frame; await process_frame
	viewport.queue_free(); await process_frame
	print("COLLAPSE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func button_center() -> Vector2:
	return demo._environment_button.global_position + demo._environment_button.size * 0.5

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = pressed
		viewport.push_input(event, true)
	await process_frame; await process_frame
	await live_settle()

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.pressed = pressed
		viewport.push_input(event, true)
	await process_frame
	await live_settle()

func live_settle() -> void:
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while (demo._environment_forecast_pending or demo._environment_forecast_worker.is_started()) and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	check(not demo._environment_forecast_pending and not demo._environment_forecast_worker.is_started(), "environment forecast settles")

func capture(label: String) -> void:
	check(demo._instructions.get_global_rect().end.y <= float(viewport.size.y), "instructions fit viewport: " + label + " " + str(demo._instructions.get_global_rect()))
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
