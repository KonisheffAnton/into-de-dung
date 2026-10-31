extends SceneTree

const HERO_BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const CORE_REACTIONS_SCENE: PackedScene = preload("res://scenes/demo/core_reactions_battle.tscn")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var session: BattleCoreReactionsSession

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE FORECAST PREPARATION UI: " + label)

func _new_demo() -> void:
	session = PlayerTurnFixture.create()
	demo = HERO_BATTLE_SCENE.instantiate() as HeroHubBattleView
	demo.supplied_session = session
	demo.presentation_enabled = false
	viewport.add_child(demo)
	await process_frame
	await process_frame
	PlayerTurnFixture.enter_player_turn(demo)
	await process_frame
	demo.set_process(false)

func _new_base_demo() -> void:
	demo = CORE_REACTIONS_SCENE.instantiate() as BattleDemo
	viewport.add_child(demo)
	await process_frame
	await process_frame
	PlayerTurnFixture.enter_player_turn(demo)
	session = demo.session as BattleCoreReactionsSession
	await process_frame
	demo.set_process(false)

func _close_demo() -> void:
	if is_instance_valid(demo):
		demo.queue_free()
		await process_frame
	demo = null
	session = null

func _snapshot(value: BattleCoreReactionsSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(value.state, []).snapshot.to_dict()

func _live_values(value: BattleCoreReactionsSession) -> Dictionary:
	return {"snapshot": _snapshot(value), "rng": value.context.get_rng().to_dict(),
		"counters": value.context.simulation_counters(), "revision": value.context.get_revision()}

func _view_values() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in demo.board_view._view_units:
		var unit_view: BattleUnitView = row.unit
		result.append({"id": unit_view.id, "cell": row.cell, "hp": unit_view.hp})
	return result

func _send_motion(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = demo.board_view.cell_center(cell)
	event.global_position = demo.board_view.global_position + event.position
	demo._input(event)
	demo.board_view._gui_input(event)

func _send_click_while_preparing(cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = demo.board_view.cell_center(cell)
	event.global_position = demo.board_view.global_position + event.position
	event.pressed = true
	demo.board_view._gui_input(event)

func _send_motion_outside_board() -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(-100.0, -100.0)
	event.global_position = demo.board_view.global_position + event.position
	demo._input(event)
	demo.board_view._gui_input(event)

func _start_move_forecast(cell: Vector2i) -> bool:
	_send_motion(cell)
	demo._move_forecast_due = 0
	demo._process_move_forecast()
	return demo._forecast_preparation_worker.is_started()

func _start_attack_forecast(target: UnitState) -> bool:
	demo.set_attack_mode(true)
	_send_motion(target.cell)
	demo._process_attack_forecast()
	return demo._forecast_preparation_worker.is_started()

func _poll_preparation() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while demo._forecast_preparation_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_forecast_preparation()
		if demo._forecast_preparation_worker.is_started():
			await process_frame
	return not demo._forecast_preparation_worker.is_started()

func _finish_move_forecast() -> MoveForecast:
	var deadline := Time.get_ticks_msec() + 15000
	while demo._move_forecast == null and Time.get_ticks_msec() < deadline:
		demo._process_move_forecast()
		if demo._move_forecast == null:
			await process_frame
	return demo._move_forecast

func _finish_attack_forecast() -> AttackForecast:
	var deadline := Time.get_ticks_msec() + 15000
	while demo._forecast == null and Time.get_ticks_msec() < deadline:
		demo._process_attack_forecast()
		if demo._forecast == null:
			await process_frame
	return demo._forecast

func _settle_live_action() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while demo.is_execution_pending() and Time.get_ticks_msec() < deadline:
		demo._process(1.0 / 60.0)
		if demo.is_execution_pending():
			await process_frame
	return not demo.is_execution_pending()

func _test_move_and_attack_prepared_parity() -> void:
	await _new_demo()
	var before := _live_values(session)
	var move_cell := Vector2i(1, 2)
	var old_projection := _view_values()
	check(_start_move_forecast(move_cell), "eligible HeroHubBattleView starts a move preparation job")
	check(demo.session == null and demo._battle == null and demo.board_view.session == null
		and demo.board_view.forecast_preparation_pending and demo.is_execution_pending(),
		"live session lease is hidden while cached view remains interactive for hover")
	check(demo.board_view._view_units.size() == old_projection.size() and _view_values() == old_projection,
		"published unit projection stays stable while preparation owns the live session")
	check(await _poll_preparation(), "move preparation joins within its bounded deadline")
	check(demo.session == session and demo.board_view.session == session and not demo.board_view.forecast_preparation_pending,
		"move preparation restores session ownership before forecast publication")
	var move_result := await _finish_move_forecast()
	var move_oracle := session.preview_move(move_cell)
	check(move_result != null and move_result.status == move_oracle.status and move_result.reason == move_oracle.reason
		and move_result.events == move_oracle.events and move_result.steps == move_oracle.steps
		and move_result.snapshot_after == move_oracle.snapshot_after,
		"asynchronous move forecast matches synchronous preview values")
	check(_live_values(session) == before, "prepared move forecast leaves live snapshot, RNG, counters and revision unchanged")
	await _close_demo()

	await _new_demo()
	demo.select_character(session.units[2].id)
	check(session.board.move_unit(session.units[3], Vector2i(4, 5))
		and session.board.move_unit(session.units[1], Vector2i(3, 5)), "fixture places a live enemy beside the attack actor")
	demo._refresh()
	var attack_target := session.units[1]
	var attack_before := _live_values(session)
	check(_start_attack_forecast(attack_target), "eligible HeroHubBattleView starts an attack preparation job")
	check(demo.session == null and demo.board_view.session == null and demo.board_view.execution_pending,
		"attack preparation also keeps the live graph leased")
	check(await _poll_preparation(), "attack preparation joins within its bounded deadline")
	var attack_result := await _finish_attack_forecast()
	var attack_oracle := session.preview_attack(attack_target.id)
	check(attack_result != null and attack_result.status == attack_oracle.status and attack_result.reason == attack_oracle.reason
		and attack_result.events == attack_oracle.events and attack_result.steps == attack_oracle.steps
		and attack_result.snapshot_after == attack_oracle.snapshot_after,
		"asynchronous attack forecast matches synchronous preview values")
	check(_live_values(session) == attack_before, "prepared attack forecast leaves live snapshot, RNG, counters and revision unchanged")
	await _close_demo()

func _test_stale_hover_and_selection_discard() -> void:
	await _new_demo()
	var actor_id := session.selected_id
	var other_id := session.units[2].id
	check(_start_move_forecast(Vector2i(1, 2)), "stale hover case starts forecast preparation")
	_send_motion_outside_board()
	demo.select_character(other_id)
	check(demo._forecast_preparation_discard and demo._forecast_hover_pending
		and demo._forecast_input_intents.size() == 1,
		"new hover and semantic selection mark the in-flight value stale without touching leased state")
	check(await _poll_preparation(), "stale forecast preparation joins")
	check(demo.session == session and demo._move_forecast_worker.is_started() == false
		and demo._move_forecast == null, "stale prepared result is discarded, not published")
	demo._recover_forecast_input()
	check(session.selected_id == other_id and actor_id != other_id and demo._forecast_input_intents.is_empty(),
		"selection intent is evaluated against restored session after preparation")
	if demo._forecast_preparation_recovering:
		demo._recover_forecast_input()
	check(demo.board_view.hover_cell == Vector2i(-1, -1) and demo._move_forecast == null
		and not demo._forecast_preparation_recovering and not demo._forecast_pointer_pending,
		"latest hover is applied after restoration and stale cell preview remains absent")
	await _close_demo()

	await _new_demo()
	var replacement_cell := Vector2i(0, 3)
	check(_start_move_forecast(Vector2i(1, 2)), "replacement-hover case starts old-cell preparation")
	_send_motion(replacement_cell)
	check(demo._forecast_hover_pending and demo.board_view.hover_cell == replacement_cell,
		"pointer motion stores the latest valid cell using displayed geometry during the lease")
	check(await _poll_preparation(), "old-cell preparation joins after hover replacement")
	check(demo._move_forecast == null and not demo._move_forecast_worker.is_started(),
		"prepared result for the previous hover is not published")
	demo._recover_forecast_input()
	check(demo._move_forecast_pending and demo._move_forecast_cell == replacement_cell,
		"recovery requests a fresh preview for the latest cell")
	demo._move_forecast_due = 0
	demo._process_move_forecast()
	check(await _poll_preparation(), "replacement-cell preparation joins")
	var replacement_result := await _finish_move_forecast()
	check(replacement_result != null and not replacement_result.requested_path.is_empty()
		and replacement_result.requested_path.back() == replacement_cell,
		"published forecast is prepared for the replacement hover cell")
	await _close_demo()

func _test_cell_intent_camera_and_bounded_hud_queue() -> void:
	await _new_demo()
	var original_cell := Vector2i(1, 2)
	var old_camera := demo.board_view.camera_view.world_to_view(Vector2.ZERO)
	check(_start_move_forecast(original_cell), "camera case starts move preparation")
	check(demo.board_view.displayed_cell_at(demo.board_view.cell_center(original_cell)) == original_cell,
		"click source cell is resolved from published display geometry")
	_send_click_while_preparing(original_cell)
	check(demo._forecast_input_intents.size() == 1
		and demo._forecast_input_intents[0].method == &"handle_cell"
		and demo._forecast_input_intents[0].args == [original_cell],
		"board click stores semantic cell intent rather than screen coordinates")
	demo.board_view.pan_camera(Vector2(36.0, 18.0))
	check(demo.board_view.camera_view.world_to_view(Vector2.ZERO) != old_camera,
		"camera can move after click while the queued cell remains fixed")
	check(await _poll_preparation(), "cell intent preparation joins")
	check(demo.session == session and demo._move_forecast == null,
		"queued click discards unrelated hover preparation before command recovery")
	demo._recover_forecast_input()
	check(demo._execution_worker.is_started() and demo._forecast_input_intents.is_empty(),
		"captured cell intent starts one live command after owner restoration")
	check(await _settle_live_action(), "cell command settles after camera pan")
	var moved_events := 0
	var move_receipt := session.last_receipt
	if move_receipt != null:
		for event: Dictionary in move_receipt.get_events():
			if event.get("kind") == &"moved": moved_events += 1
	check(move_receipt != null and move_receipt.status == ActionReceipt.APPLIED and session.units[0].cell == original_cell
		and moved_events == 1, "originally clicked cell executes once despite later camera movement")
	await _close_demo()

	await _new_demo()
	var selected_id := session.units[2].id
	check(_start_move_forecast(Vector2i(1, 2)), "HUD queue case starts preparation")
	demo.select_character(selected_id)
	for _i: int in 36:
		demo._action_bar_requested(&"guard")
	check(demo._forecast_input_intents.size() == BattleDemo.MAX_FORECAST_INPUT_INTENTS,
		"semantic HUD intent queue respects its fixed capacity")
	check(await _poll_preparation(), "HUD intent preparation joins")
	demo._recover_forecast_input()
	demo._recover_forecast_input()
	check(session.selected_id == selected_id and demo._execution_worker.is_started(),
		"selection is applied first and HUD action is replayed with the restored current actor")
	check(demo._forecast_input_intents.is_empty(), "first accepted live command clears remaining queued intents")
	check(await _settle_live_action(), "single HUD command settles")
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.APPLIED
		and session.units[2].action_resources.get_main_left() == 0
		and session.units[0].action_resources.get_main_left() == 1,
		"bounded repeated HUD input produces one guard for the selected actor only")
	await _close_demo()

func _test_reading_panel_during_preparation(attack: bool) -> void:
	await _new_demo()
	demo.set_diagnostics_visible(true)
	await process_frame
	await process_frame
	var oracle: Variant
	if attack:
		demo.select_character(session.units[2].id)
		check(session.board.move_unit(session.units[3], Vector2i(4, 5))
			and session.board.move_unit(session.units[1], Vector2i(3, 5)), "reading panel attack fixture has adjacent target")
		demo._refresh()
		oracle = session.preview_attack(session.units[1].id)
		check(_start_attack_forecast(session.units[1]), "reading panel attack starts preparation")
	else:
		oracle = session.preview_move(Vector2i(1, 2))
		check(_start_move_forecast(Vector2i(1, 2)), "reading panel move starts preparation")
	await process_frame
	var reading_point := demo._forecast_panel.get_global_rect().get_center()
	check(demo._forecast_reading_region().has_point(reading_point), "pending forecast has a visible reading region")
	var motion := InputEventMouseMotion.new()
	motion.position = reading_point
	demo._input(motion)
	demo.board_view._clear_hover()
	check(await _poll_preparation(), "reading panel preparation returns owner")
	check((demo._attack_forecast_worker.is_started() and demo._attack_forecast_pending) if attack
		else (demo._move_forecast_worker.is_started() and demo._move_forecast_pending),
		"leaving board for reading panel preserves the prepared target")
	if demo._forecast_preparation_recovering: demo._recover_forecast_input()
	var result: Variant = await _finish_attack_forecast() if attack else await _finish_move_forecast()
	check(result != null and result.status == oracle.status and result.reason == oracle.reason
		and result.events == oracle.events and result.snapshot_after == oracle.snapshot_after,
		"pending forecast publishes while pointer reads its panel: attack=%s result=%s pending=%s/%s hover=%s region=%s" % [attack,
			"null" if result == null else str([result.status, result.reason]), demo._move_forecast_pending,
			demo._attack_forecast_pending, demo.board_view.hover_cell, demo._forecast_reading_region().has_point(demo._pointer_position)])
	await _close_demo()

func _test_reset_and_exit_join_preparation() -> void:
	await _new_demo()
	var hub_worker_session := session
	var reset_selection_id := session.units[2].id
	check(_start_move_forecast(Vector2i(1, 2)), "reset case starts preparation")
	demo.select_character(reset_selection_id)
	demo.reset_demo()
	check(demo._forecast_preparation_worker.is_started() and demo.session == null
		and demo.board_view.session == null and not demo.can_restart_checkpoint(),
		"HeroHub rejects checkpoint restart while the preparation worker leases session")
	demo._join_execution()
	check(not demo._forecast_preparation_worker.is_started() and demo._forecast_preparation_worker._session == null
		and demo._forecast_input_intents.is_empty() and not demo._forecast_preparation_recovering
		and demo.board_view.session == hub_worker_session,
		"explicit lifecycle join restores the lease and clears buffered reset-time input")
	await _close_demo()

	await _new_base_demo()
	var reset_session := session
	var base_reset_selection_id := session.units[2].id
	check(_start_move_forecast(Vector2i(1, 2)), "base reset case starts preparation")
	demo.select_character(base_reset_selection_id)
	demo.reset_demo()
	check(not demo._forecast_preparation_worker.is_started() and demo._forecast_preparation_worker._session == null
		and demo._forecast_input_intents.is_empty() and not demo._forecast_preparation_recovering
		and demo.board_view.session == reset_session,
		"base reset joins preparation and clears stale semantic input before refreshing")
	var reset_snapshot := _snapshot(reset_session)
	await process_frame
	await process_frame
	check(_snapshot(reset_session) == reset_snapshot and demo._move_forecast == null,
		"joined preparation cannot publish stale preview after reset")
	await _close_demo()

	await _new_demo()
	var exit_selection_id := session.units[2].id
	check(_start_move_forecast(Vector2i(1, 2)), "exit case starts preparation")
	demo.select_character(exit_selection_id)
	var worker := demo._forecast_preparation_worker
	var owner_session := session
	var intents := demo._forecast_input_intents
	demo.queue_free()
	await process_frame
	check(not worker.is_started() and worker._session == null and owner_session.state == null and intents.is_empty(),
		"scene exit joins/releases the lease, closes owned session and clears buffered intents")
	demo = null
	session = null

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _test_move_and_attack_prepared_parity()
	await _test_stale_hover_and_selection_discard()
	await _test_cell_intent_camera_and_bounded_hud_queue()
	await _test_reading_panel_during_preparation(false)
	await _test_reading_panel_during_preparation(true)
	await _test_reset_and_exit_join_preparation()
	viewport.queue_free()
	await process_frame
	print("BATTLE FORECAST PREPARATION UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
