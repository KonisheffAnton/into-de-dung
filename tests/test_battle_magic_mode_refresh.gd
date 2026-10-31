extends "res://tests/test_battle_magic_freshness_ui.gd"

const CORE_REACTIONS_SCENE: PackedScene = preload("res://scenes/demo/core_reactions_battle.tscn")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

func _drain_staged_refresh(max_steps: int = 8) -> bool:
	for _step: int in max_steps:
		if demo == null or not is_instance_valid(demo): return false
		if demo._refresh_followup.is_empty(): return true
		demo._poll_execution()
	return demo != null and demo._refresh_followup.is_empty()

func _test_queued_card_click_survives_mode_refresh() -> void:
	session = _new_session()
	check(session != null, "interactive refresh uses a production expedition mage fixture")
	if session == null: return
	if not await _open_demo(): check(false, "production view owns the interactive fixture"); return
	var target := _arrange_elemental_target()
	var fire_slot := _fire_card_slot()
	check(target != null and fire_slot >= 0, "mode-switch fixture has a reachable enemy and fire card")
	if target == null or fire_slot < 0: await _close_demo(); return
	var fire_card_id: int = int(session.state.deck.hand_ids[fire_slot])
	demo.set_process(true)
	demo._choose_elemental(&"wet")
	check(demo._interactive_refresh_pending and not demo._refresh_followup.is_empty()
		and demo.session == session and demo.board_view.execution_pending,
		"elemental mode schedules staged refresh while retaining session ownership and input lock")
	demo.set_process(false)
	demo._choose_card_slot(fire_slot)
	_click_board_cell(target.cell)
	var click_queued: bool = demo._forecast_input_intents.size() == 2
	var initial_click_cell := Vector2i(-1, -1)
	if click_queued and demo._forecast_input_intents[1].method == &"handle_cell":
		initial_click_cell = demo._forecast_input_intents[1].args[0]
	check(click_queued and initial_click_cell == target.cell,
		"card switch and real board click queue the displayed cell: intents=%s expected=%s" % [demo._forecast_input_intents, target.cell])
	demo.board_view.camera_view.pan(Vector2(47.0, -23.0))
	check(await _drain_staged_refresh(), "first mode refresh reaches its published stages")
	demo.set_process(true)
	demo._recover_forecast_input()
	demo.set_process(false)
	check(demo._interactive_refresh_pending and demo._forecast_input_intents.size() == 1
		and demo._forecast_input_intents[0].method == &"handle_cell",
		"queued click survives a second staged refresh caused by the queued card choice")
	check(await _drain_staged_refresh(), "queued card refresh drains without fixed frame-count assumptions")
	demo._recover_forecast_input()
	check(not demo._interactive_refresh_pending and demo._forecast_input_intents.is_empty()
		and demo._card_selected_id > 0 and demo._execution_worker.is_started(),
		"replayed click submits one live card command after the selected mode is published")
	check(initial_click_cell == target.cell, "queued click keeps its original cell after camera pan")
	demo.set_process(true)
	check(await _settle_live_action(), "queued live card command completes and restores UI ownership")
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.APPLIED
		and session.state.deck.spent_ids.has(fire_card_id)
		and demo.session == session,
		"the queued click executes once as a normal APPLIED card command")
	await _close_demo()

func _test_latest_hover_is_replayed() -> void:
	session = _new_session()
	check(session != null, "hover replay fixture is a fresh expedition session")
	if session == null: return
	if not await _open_demo(): check(false, "production view owns the hover replay fixture"); return
	var target := _arrange_elemental_target()
	if target == null: check(false, "hover replay fixture can place its actor in range"); await _close_demo(); return
	var latest_cell := target.cell
	demo.set_process(true)
	demo._choose_elemental(&"wet")
	demo.set_process(false)
	demo._hover(Vector2i(-1, -1))
	# Имитируем уже полученный signal hover: refresh в конце читает опубликованную hover_cell.
	demo.board_view.hover_cell = latest_cell
	demo._hover(latest_cell)
	check(demo._forecast_hover_pending and demo._forecast_latest_hover == latest_cell,
		"multiple hover changes retain the latest semantic board cell while refreshing")
	check(await _drain_staged_refresh(), "staged mode refresh reaches its published stages")
	demo._recover_forecast_input()
	check(not demo._forecast_hover_pending and demo._action_forecast_cell == latest_cell
		and (demo._action_forecast_pending or demo._action_forecast_worker.is_started()
			or demo._elemental_forecast != null),
		"only the latest hover is replayed into the ordinary elemental forecast path")
	await _close_demo()

	session = _new_session()
	check(session != null, "disabled-process case has an independent production session")
	if session == null: return
	if not await _open_demo(): check(false, "production view owns disabled-process fixture"); return
	var original_process_mode: Node.ProcessMode = demo.process_mode
	demo.process_mode = Node.PROCESS_MODE_DISABLED
	demo.set_process(true)
	demo._mage_page_changed(0)
	check(not demo._interactive_refresh_pending and demo._refresh_followup.is_empty(),
		"disabled process mode uses the synchronous compatibility refresh")
	demo.set_process(false)
	demo.process_mode = original_process_mode
	await _close_demo()

func _test_escape_is_deferred_during_refresh() -> void:
	session = _new_session()
	check(session != null, "Escape test has an independent production session")
	if session == null: return
	if not await _open_demo(): check(false, "production view owns Escape fixture"); return
	var fire_slot := _fire_card_slot()
	demo.set_process(true)
	demo._choose_card_slot(fire_slot)
	demo.set_process(false)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	demo._unhandled_input(escape)
	var escape_queued: bool = not demo._forecast_input_intents.is_empty()
	if escape_queued:
		var intent: Dictionary = demo._forecast_input_intents[-1]
		check(intent.method == &"set_attack_mode" and intent.args == [false],
			"Escape during an interactive refresh is retained as mode cancellation")
	else:
		check(false, "Escape during an interactive refresh becomes a queued semantic action")
	demo._join_execution()
	check(demo.session == session and not demo._interactive_refresh_pending
		and demo._forecast_input_intents.is_empty(),
		"joining after deferred Escape restores owner and clears its buffer")
	await _close_demo()

func _test_reset_and_exit_clear_pending_ui() -> void:
	var base_demo := CORE_REACTIONS_SCENE.instantiate() as BattleDemo
	base_demo.presentation_enabled = false
	viewport.add_child(base_demo)
	await process_frame
	await process_frame
	PlayerTurnFixture.enter_player_turn(base_demo)
	var base_session := base_demo.session as BattleCoreReactionsSession
	base_demo.set_process(false)
	base_demo.set_process(true)
	base_demo._mage_page_changed(0)
	base_demo.set_process(false)
	base_demo.handle_cell(Vector2i(0, 0))
	check(base_demo._interactive_refresh_pending and not base_demo._forecast_input_intents.is_empty(),
		"base reset fixture begins with staged mode and buffered semantic click")
	base_demo.reset_demo()
	check(base_demo.session == base_session and not base_demo._interactive_refresh_pending
		and base_demo._refresh_followup.is_empty() and base_demo._forecast_input_intents.is_empty()
		and not base_demo._forecast_preparation_recovering,
		"base reset joins staged mode and clears obsolete input before refreshing")
	await process_frame
	check(not base_demo.is_execution_pending(), "base reset does not replay the obsolete click")
	base_demo.queue_free()
	await process_frame

	session = _new_session()
	check(session != null, "exit cleanup fixture is a separate production session")
	if session == null: return
	if not await _open_demo(): check(false, "production view owns exit cleanup fixture"); return
	var exit_slot := _fire_card_slot()
	demo.set_process(true)
	demo._choose_card_slot(exit_slot)
	demo.set_process(false)
	demo.handle_cell(Vector2i(0, 0))
	var exit_session := session
	var exit_player := session.selected_unit()
	var exit_main: int = exit_player.action_resources.get_main_left() if exit_player != null else -1
	demo.queue_free()
	await process_frame
	check(not is_instance_valid(demo) and exit_session != null
		and (exit_player == null or exit_player.action_resources.get_main_left() == exit_main),
		"tree exit joins and discards staged UI intent without executing it")
	demo = null
	session = null

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _test_queued_card_click_survives_mode_refresh()
	await _test_latest_hover_is_replayed()
	await _test_escape_is_deferred_during_refresh()
	await _test_reset_and_exit_clear_pending_ui()
	viewport.queue_free()
	await process_frame
	print("BATTLE MAGIC MODE REFRESH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
