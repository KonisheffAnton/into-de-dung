extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""
var callback_on_main: bool = false
var callback_count: int = 0

class FailedLaunchWorker extends BattleExecutionWorker:
	func _start_thread(_args: Array) -> Error:
		return ERR_CANT_CREATE

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE EXECUTION UI: " + label)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(demo) and demo.is_execution_pending() and Time.get_ticks_msec() < deadline:
		# Демонстрация в этом тесте поставлена на паузу; один вызов повторяет её обычный шаг.
		demo._process(1.0 / 60.0)
		await process_frame
	check(not is_instance_valid(demo) or not demo.is_execution_pending(), "staged battle execution settles before timeout")

func _wait_for_staged_refresh() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(demo) and demo._refresh_followup.is_empty() and demo.is_execution_pending() \
		and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		await process_frame
	return is_instance_valid(demo) and not demo._refresh_followup.is_empty()

func _wait_for_current_layout(cell: Vector2i) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	var previous_center := demo.board_view.cell_center(cell)
	var stable_frames := 0
	while stable_frames < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
		var board := demo.board_view
		var expected_dimensions := Vector2i(maxi(board._view_width, 8), maxi(board._view_height, 8))
		var current_center := board.cell_center(cell)
		if board._camera_layout_size == board.size and board._layout_dimensions == expected_dimensions \
			and current_center == previous_center:
			stable_frames += 1
		else:
			stable_frames = 0
		previous_center = current_center
	return stable_frames >= 2

func _assert_stage_input_blocked(label: String, revision: int) -> void:
	demo._execute_live(&"guard_selected", [])
	demo.handle_cell(Vector2i(2, 2))
	check(demo.is_execution_pending() and demo.session.context.get_revision() == revision,
		"%s keeps execution blocked without accepting input" % label)

func _exercise_staged_refresh_end() -> void:
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	demo.presentation_enabled = true
	var actor := demo.session.selected_unit()
	var actor_id := actor.id
	var destination := Vector2i(1, 2)
	demo._execute_live(&"move_to", [destination])
	var reached_first_stage := await _wait_for_staged_refresh()
	check(demo.is_execution_pending() and reached_first_stage,
		"completed presentation reaches its staged refresh follow-up")
	if demo._refresh_followup.is_empty(): return
	var revision := demo.session.context.get_revision()
	check(demo._refresh_stage == -1 and demo._execution_worker.is_started() == false,
		"follow-up begins at refresh-begin stage after worker and presentation finish")
	_assert_stage_input_blocked("refresh-begin stage", revision)
	demo._process(1.0 / 60.0)
	check(not demo._refresh_followup.is_empty() and demo._refresh_stage == 0,
		"refresh-begin stage advances to preparation while remaining pending")
	_assert_stage_input_blocked("prepare stage", revision)
	demo._process(1.0 / 60.0)
	check(not demo._refresh_followup.is_empty() and demo._refresh_stage == 1,
		"prepare stage advances to field publication while remaining pending")
	_assert_stage_input_blocked("publish stage", revision)
	demo._process(1.0 / 60.0)
	check(not demo._refresh_followup.is_empty() and demo._refresh_stage == 2,
		"field publication advances to final HUD refresh while remaining pending")
	_assert_stage_input_blocked("final HUD stage", revision)
	demo._process(1.0 / 60.0)
	check(demo._refresh_followup.is_empty() and not demo.is_presentation_pending()
		and not demo.board_view.execution_pending, "last staged refresh releases input only after HUD completion")
	var actor_view := demo.board_view._unit_visuals.get(actor_id) as BattleManagedUnitVisual
	check(actor.cell == destination and demo.board_view._view_unit_cell(actor_id) == destination
		and actor_view != null and actor_view.action_resources_view.main == actor.action_resources.get_main_left(),
		"final board projection and action resources match the live unit")

	# Новый job завершается до следующего UI refresh; reset обязан отбросить его хвост.
	demo._execute_live(&"guard_selected", [])
	var reached_reset_stage := await _wait_for_staged_refresh()
	check(reached_reset_stage, "second presentation reaches staged refresh before reset")
	if demo._refresh_followup.is_empty(): return
	var session := demo.session as BattleCoreReactionsSession
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	var reset_actor := session.selected_unit()
	var reset_actor_id: int = reset_actor.id
	var reset_snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	check(not demo.is_presentation_pending() and demo._refresh_followup.is_empty()
		and not demo._stage_next_refresh and not demo.is_execution_pending(),
		"reset cancels pending staged follow-up and presentation work")
	await process_frame
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == reset_snapshot
		and reset_actor_id != actor_id and demo.board_view._view_unit_cell(reset_actor_id) == reset_actor.cell
		and demo.board_view._view_unit_cell(actor_id) == Vector2i(-1, -1),
		"cancelled refresh cannot publish stale values after reset")

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func clicked(cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = demo.board_view.global_position + demo.board_view.cell_center(cell)
	event.global_position = event.position
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)

func hp_changed(_before: float, _after: float) -> void:
	callback_on_main = OS.get_thread_caller_id() == OS.get_main_thread_id()
	callback_count += 1

func _assign_slots(actions: Array[StringName]) -> void:
	var session := demo.session as BattleCoreReactionsSession
	session.action_slot_overrides[session.selected_id] = actions.duplicate()
	demo._refresh()

func _assigned_slots_match(unit_id: int, expected: Array[StringName]) -> bool:
	var session := demo.session as BattleCoreReactionsSession
	return session.action_slot_overrides.get(unit_id, []) == expected

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	demo.set_process(false)
	var old_status := demo._stats.text
	var pending_session := demo.session as BattleCoreReactionsSession
	var pending_snapshot := ItemSimulationSnapshot.capture(pending_session.state, []).snapshot.to_dict()
	var first_view: BattleUnitView = demo.board_view._view_units[0].unit
	var old_cell: Vector2i = demo.board_view._view_units[0].cell
	clicked(Vector2i(1, 2))
	check(demo.is_execution_pending(), "real click dispatches background live move")
	check(demo._execution_worker._audit != null and not pending_session._queue.capture_presentation
		and demo._execution_worker.take_presentation_before().is_empty()
		and ItemSimulationSnapshot.capture(pending_session.state, []).snapshot.to_dict() == pending_snapshot,
		"preparation blocks UI while leaving owned live state unexecuted and uncaptured")
	check(demo.session == null and demo._battle == null and demo.board_view.session == null, "UI has no session access before join")
	check(demo.board_view.execution_pending and demo._stats.text == old_status and demo.board_view._view_units[0].cell == old_cell, "last completed view remains consistent")
	# Даже если поток уже завершился, только публикация возвращает UI владение.
	demo.handle_cell(Vector2i(2, 2))
	demo.select_character(first_view.id)
	demo.inspect_enemy(999)
	demo.set_attack_mode(true)
	demo._action_bar_requested(&"guard")
	demo._use_guard()
	demo._use_healing_item()
	demo._choose_summoning()
	demo._choose_raise()
	demo._choose_reaction_guard(CombatPerksState.Mode.COVER)
	demo.end_turn()
	demo._hover(Vector2i(2, 2))
	demo._action_bar_hovered(&"healing_item")
	demo._refresh()
	demo._refresh_inspection()
	demo._process_attack_forecast()
	demo._process_move_forecast()
	demo._process_action_forecast()
	demo.board_view.refresh()
	demo.board_view.refresh_forecast()
	demo.board_view.size += Vector2(12, 8)
	demo.board_view._rescale_layout()
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals: visual.queue_redraw()
	await capture("execution-pending")
	check(demo.session == null and demo.board_view._view_units[0].cell == old_cell and demo.board_view._view_units[0].unit == first_view, "resize redraw and all input preserve detached view")
	await settle()
	check(demo.session.selected_unit().cell == Vector2i(1, 2) and demo.board_view._view_units[0].cell == Vector2i(1, 2), "join publishes one completed move")
	check(first_view != demo.board_view._view_units[0].unit and first_view.hp == demo.session.units[0].vitals.get_hp(), "new projection replaces values")
	await capture("execution-completed")
	# Выбор не пополняет остатки, а reset не принимает receipt в новую сессию.
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)
	var reset_session := demo.session as BattleCoreReactionsSession
	var reset_target_hp := reset_session.units[3].vitals.get_hp()
	clicked(demo.session.units[3].cell)
	check(demo.is_execution_pending(), "attack async")
	check(demo._execution_worker._audit != null
		and is_equal_approx(reset_session.units[3].vitals.get_hp(), reset_target_hp),
		"reset preparation starts before the live attack executes")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	check(not demo.is_execution_pending() and demo.session.units[3].is_alive() and demo.session.selected_unit().action_resources.get_main_left() == 1
		and is_equal_approx(demo.session.units[3].vitals.get_hp(), reset_target_hp),
		"reset joins preparation and restores the untouched target and action resources")
	check(not demo._journal.any(func(line: String) -> bool: return line.contains("атакует")), "old receipt not published after reset")
	var count_before := demo.session.units.size()
	var summon_session := demo.session as BattleCoreReactionsSession
	var summoner_id := summon_session.selected_id
	_assign_slots([&"summoning_item", &"safe_retreat"])
	check(_assigned_slots_match(summoner_id, [&"summoning_item", &"safe_retreat"]), "summoning fixture uses its explicit two-slot loadout")
	demo._action_bar._next_page()
	check(demo._action_bar._page == 0, "compact action bar ignores page navigation")
	demo._choose_summoning()
	clicked(Vector2i(0, 1))
	check(demo.is_execution_pending(), "summon async")
	await settle()
	check(demo._action_bar._page == 0 and _assigned_slots_match(summoner_id, [&"summoning_item", &"safe_retreat"]), "worker publication preserves actor loadout without page state")
	check(demo.session.units.size() == count_before + 1 and demo.board_view._view_units.size() == demo.session.units.size(), "summon publication includes new helper: " + str(demo.session.last_receipt.reason) + " count=" + str(demo.session.units.size()))
	demo.end_turn()
	check(demo.is_execution_pending(), "turn boundary async")
	await settle()
	var steps: int = 0
	while demo._battle.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		demo._process(1.0)
		await settle()
		steps += 1
	check(demo._battle.phase == BattleTacticalSession.Phase.PLAYER_TURN and demo._battle.round_number == 2, "AI and both boundaries publish complete round")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	_assign_slots([&"raise_corpse", &"safe_retreat"])
	count_before = demo.session.units.size()
	demo._choose_raise()
	clicked(Vector2i(0, 3))
	check(demo.is_execution_pending(), "raise async")
	await settle()
	check(demo.session.units.size() == count_before + 1, "raise completes with helper: " + str(demo.session.last_receipt.reason) + " count=" + str(demo.session.units.size()))
	# Отказ ОС возвращает владельца до sync-вызова, сохраняя прежний показ.
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	var fallback_session := demo.session
	demo._execution_worker = FailedLaunchWorker.new()
	demo.presentation_enabled = true
	demo._use_guard()
	check(demo.is_execution_pending() and demo._execution_worker._audit != null
		and demo.session == null and not fallback_session._queue.capture_presentation,
		"OS launch failure is deferred until the ownership audit returns")
	var fallback_deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < fallback_deadline:
		demo._poll_execution()
		if demo._execution_worker.is_started(): await process_frame
	check(demo.session == fallback_session and demo.board_view.session == fallback_session and demo._battle == fallback_session, "launch failure restores all UI owners before fallback")
	check(not demo._execution_worker.is_started() and demo.is_presentation_pending(), "launch failure synchronous result still starts presentation")
	check(demo._presentation_roots.size() == 1 and fallback_session.selected_unit().action_resources.get_main_left() == 0, "launch failure executes and captures guard once")
	await settle()
	check(not fallback_session._queue.capture_presentation and demo._presentation_before.is_empty(), "fallback presentation finishes and clears capture")
	demo._execution_worker = BattleExecutionWorker.new()
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	_assign_slots([&"restore_armor", &"healing_item"])
	demo.session.units[0].vitals.set_hp(10)
	demo.session.units[0].vitals.hp_changed.connect(hp_changed)
	callback_count = 0
	var callback_session := demo.session as BattleCoreReactionsSession
	var callback_snapshot := ItemSimulationSnapshot.capture(callback_session.state, []).snapshot.to_dict()
	demo._use_healing_item()
	check(demo.is_execution_pending() and demo.session == null
		and ItemSimulationSnapshot.capture(callback_session.state, []).snapshot.to_dict() == callback_snapshot,
		"callback rejection is audited before sync fallback execution")
	await settle()
	check(not demo.is_execution_pending() and callback_on_main and callback_count == 1
		and callback_session.units[0].vitals.get_hp() > 10,
		"external callback executes once on main via audited sync fallback")
	callback_session.units[0].vitals.hp_changed.disconnect(hp_changed)
	await _exercise_staged_refresh_end()
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	demo.session._queue._max_commands = 1
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)
	var fault_target_cell: Vector2i = demo.session.units[3].cell
	check(await _wait_for_current_layout(fault_target_cell), "fault input uses the settled board geometry")
	clicked(fault_target_cell)
	check(demo.is_execution_pending(), "real target click dispatches faulted action")
	await settle()
	check(demo._battle.phase == BattleTacticalSession.Phase.FAULTED and demo._status.text.contains("остановлено"), "FAULTED prefix published to UI")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	clicked(Vector2i(1, 2))
	demo.toggle_scenario()
	check(not demo.is_execution_pending() and not demo.session is BattleCoreReactionsSession, "scenario switch joins previous owner")
	demo._open_core_combination_scenario()
	PlayerTurnFixture.enter_player_turn(demo)
	var exit_worker_session := demo.session as BattleCoreReactionsSession
	var exit_actor := exit_worker_session.units[0]
	var exit_destination := Vector2i(1, 2)
	check(await _wait_for_current_layout(exit_destination), "exit input uses the settled board geometry")
	clicked(exit_destination)
	check(demo._execution_worker._audit != null and demo.is_execution_pending(), "exit test interrupts the preparation phase")
	var worker := demo._execution_worker
	demo.queue_free()
	await process_frame
	check(not worker.is_started() and worker._session == null and exit_actor.cell == exit_destination,
		"exit joins the prepared action prefix, returns ownership and releases the worker")
	viewport.queue_free()
	await process_frame
	print("BATTLE EXECUTION UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
