extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

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
		printerr("FAIL SAFE RETREAT UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	var s := fixture()
	var target := Vector2i(3, 2)
	var ordinary := s.preview_move(target)
	check(ordinary.status == ActionReceipt.INTERRUPTED and ordinary.reason == &"perks/opportunist_stopped", "ordinary route is intercepted: %s/%s" % [ordinary.status, ordinary.reason])
	await choose_retreat()
	check(demo.retreat_mode and s.selected_unit().action_resources.get_main_left() == 1, "button selects basic retreat without payment")
	await motion(at(target))
	await settle()
	var forecast := demo._move_forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED and demo._move_forecast_retreat, "hover completes real retreat forecast: %s" % (str([forecast.status, forecast.reason]) if forecast != null else "null"))
	check(forecast != null and forecast.units[s.selected_id].after.main == 0 and forecast.units[s.selected_id].after.cell == target, "forecast pays main and reaches target")
	check(demo._forecast_panel.text.contains("Безопасный отход") and demo._forecast_panel.text.contains("Основные 1 → 0"), "panel names action and shows actual main expense")
	var sync := s.preview_retreat(target)
	check(forecast != null and forecast.snapshot_after == sync.snapshot_after and forecast.events == sync.events and forecast.steps == sync.steps, "worker preview matches synchronous execution")
	await capture("safe-retreat-forecast")
	await click(at(target))
	check(not demo.retreat_mode and not demo.is_execution_pending() and s.last_receipt.status == ActionReceipt.APPLIED, "live worker completes and returns ordinary movement: %s/%s" % [s.last_receipt.status, s.last_receipt.reason])
	check(forecast != null and s.last_receipt.get_events() == forecast.events and s.last_receipt.get_steps() == forecast.steps and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after, "live worker matches full forecast")
	check(s.units[1].action_resources.get_bonus_left() == 1 and not s.units[0].combat_perks.movement_stopped, "opportunist retains charge without stopping mover")
	await capture("safe-retreat-live")

	s = fixture()
	await choose_retreat()
	await key(KEY_ESCAPE)
	check(not demo.retreat_mode and s.selected_unit().action_resources.get_main_left() == 1, "cancel is free")
	await choose_retreat()
	await click(at(s.units[2].cell))
	check(s.selected_id == s.units[2].id and not demo.retreat_mode, "ally selection clears retreat")
	await choose_retreat()
	check(demo.retreat_mode, "basic action available to actor without tank perk")

	s = fixture()
	await choose_retreat()
	await motion(at(target)); await settle()
	var revision := s.context.get_revision()
	s.selected_unit().action_resources.try_spend_main(1)
	demo._refresh()
	await settle()
	check(s.context.get_revision() == revision and demo._move_forecast != null and demo._move_forecast.reason == &"move/insufficient_main", "refresh without revision rejects stale result")
	check(demo.board_view.reachable_cells().is_empty() and demo.board_view.pending_move_path.is_empty(), "unavailable retreat has no provisional route")
	await click(at(target))
	check(s.last_receipt.status == ActionReceipt.REJECTED and s.selected_unit().cell == Vector2i(1, 2) and not demo.retreat_mode, "fresh rejected click clears mode without moving")

	s = fixture()
	await choose_retreat()
	await motion(at(target))
	demo._move_forecast_due = 0
	demo._process_move_forecast()
	check(demo._move_forecast_worker.is_started(), "prepared retreat runs in worker")
	await key(KEY_M)
	await settle()
	check(not demo.retreat_mode and (demo._move_forecast == null or demo._move_forecast.reason == &"perks/opportunist_stopped"), "mode switch cannot publish old safe result")

	s = fixture()
	await choose_retreat()
	await click(at(Vector2i(-1, -1)))
	check(s.selected_unit().cell == Vector2i(1, 2), "outside click does not move")
	demo.handle_cell(s.selected_unit().cell + Vector2i(8, 0))
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	check(not demo.retreat_mode and s.selected_unit().action_resources.get_main_left() == 1, "invalid route attempt does not pay main")

	s = fixture()
	await choose_retreat()
	await motion(at(target))
	demo._move_forecast_due = 0; demo._process_move_forecast()
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	await settle()
	check(not demo.retreat_mode and (demo._move_forecast == null or (not demo._move_forecast_retreat and demo._move_forecast.snapshot_before == ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict())), "reset cannot publish old retreat forecast")

	s = fixture()
	await choose_retreat()
	await motion(at(target)); await settle()
	await key(KEY_ENTER)
	check(not demo.retreat_mode and demo._move_forecast == null, "end turn clears retreat and its forecast")
	demo.queue_free()
	await process_frame; await process_frame
	viewport.queue_free()
	await process_frame
	print("SAFE RETREAT UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func fixture() -> BattleCoreReactionsSession:
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	var s := demo.session as BattleCoreReactionsSession
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	s.state.environment.fires.clear()
	for index: int in s.units.size():
		if not s.units[index].is_alive(): continue
		check(s.board.move_unit(s.units[index], Vector2i(index, 0)), "park fixture")
		if s.units[index].control != null:
			s.units[index].control.stunned_turns = 0
			s.units[index].control.entangled_turns = 0
	s.board.move_unit(s.units[0], Vector2i(1, 2))
	s.board.move_unit(s.units[1], Vector2i(1, 1))
	s.units[1].guard_stance = true
	s.units[1].combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
	s.select_unit(s.units[0].id)
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.OK, "fixture snapshot valid")
	demo._refresh()
	return s

func choose_retreat() -> void:
	await process_frame; await process_frame
	var session := demo.session as BattleCoreReactionsSession
	session.action_slot_overrides[session.selected_id] = [&"safe_retreat", &"healing_item"]
	demo._refresh()
	var bar := demo._action_bar
	check(bar._buttons.size() == 4 and bar._page == 0, "retreat uses the compact four-slot bar without paging")
	check(session.action_slot_overrides[session.selected_id] == [&"safe_retreat", &"healing_item"], "fixture assigns retreat and healing as its requested slots")
	var button := bar._buttons[2]
	check(button.get_meta("action_id", &"") == &"safe_retreat", "retreat action occupies visible slot three")
	await click(button.global_position + button.size * 0.5)

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
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.pressed = pressed
		viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (demo._move_forecast_pending or demo._move_forecast_worker.is_started()) and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	check(not demo._move_forecast_pending and not demo._move_forecast_worker.is_started(), "forecast settles")

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
