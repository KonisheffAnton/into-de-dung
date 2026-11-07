extends "res://tests/test_battle_presentation.gd"

class CountingPlacementBoard extends BattleDemoBoard:
	var placement_calls: int = 0

	func _place_result_numbers() -> void:
		placement_calls += 1
		super._place_result_numbers()

func _initialize() -> void:
	call_deferred("_run_owned_tests")

func _run_owned_tests() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 950)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _result_number_placement_batch()
	await fresh()
	await _public_array_ownership()
	await _owned_receipt_integrity()
	await _owned_large_packet()
	await _owned_skip_cancel()
	await _chain_marker_nested_skip_hud()
	# Эти контрактные пробы держат FAULTED-префикс и H1 за тем же refresh guard.
	await technical_frame_budget()
	await hub_terminal_staged_refresh()
	await _empty_capture_worker_refresh()
	await _disabled_presentation_refresh_stays_synchronous()
	viewport.queue_free()
	await process_frame
	print("BATTLE PRESENTATION OWNED RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _result_number_placement_batch() -> void:
	var board := CountingPlacementBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	var session := BattleCoreReactionsSession.new()
	var before := ActionPresentationState.capture(session.state)
	board.show_presentation_state(before)
	await process_frame
	board.placement_calls = 0
	var ids: Array[int] = [session.units[0].id, session.units[1].id, session.units[2].id]
	var events: Array[Dictionary] = []
	for index: int in ids.size():
		events.append({"kind": &"damaged", "actor_unit_id": ids[(index + 1) % ids.size()], "target_unit_id": ids[index], "amount": float(index + 2),
			"root_id": 751, "command_seq": 19, "source": {"kind": "cell"}})
	events.append({"kind": &"balance_changed", "target_unit_id": ids[0], "impact": 1.0,
		"balance_after": 4.0, "balance_max": 10.0, "broke": false, "root_id": 751, "command_seq": 19})
	var step: Dictionary = {}
	var after := before.duplicate(true)
	# Незамедлённые вызовы составляют геометрический oracle до включения frame-batch.
	var strike := board._matching_strike(events, step)
	for feedback: Dictionary in BattleReactionPresentation.feedback(events, step, before, after):
		board._add_result_number(int(feedback.id), String(feedback.text), Color("93dce9"), &"reaction")
	board._show_event_feedback(events, strike, true, true)
	board._show_consequence_feedback(BattleConsequenceFeedback.entries(events, before, after), 751)
	var expected_layout := _number_layout(board)
	var sequential_calls := board.placement_calls
	check(expected_layout.size() >= 3 and sequential_calls > 1,
		"legacy sequential fixture creates several results and consequence leader")
	_clear_number_nodes(board)
	board.placement_calls = 0
	board.finish_presentation_frame(events, step, before, after)
	var frame_layout := _number_layout(board)
	check(board.placement_calls == 1 and frame_layout.size() >= 3,
		"one finish frame places all synchronous result numbers once")
	check(_number_layouts_equal(expected_layout, frame_layout),
		"batched finish preserves sequential collision positions, order and leaders")
	_clear_number_nodes(board)
	var immediate_contact_events: Array[Dictionary] = []
	for index: int in ids.size():
		immediate_contact_events.append({"kind": &"damaged", "actor_unit_id": ids[(index + 1) % ids.size()], "target_unit_id": ids[index],
			"amount": float(index + 2), "root_id": 752, "command_seq": 21,
			"source": {"kind": "cell"}})
	board.placement_calls = 0
	var contact_key := board._result_frame_key(immediate_contact_events)
	check(board._result_number_batch_depth == 0 and not board._result_number_batch_dirty
		and not board._early_result_frames.has(contact_key), "contact probe begins outside any active frame/result scope")
	board._show_contact_result(immediate_contact_events)
	var contact_count := board._numbers.get_child_count()
	check(board.placement_calls == contact_count and contact_count == 3,
		"contact results place each of the three damage numbers immediately (placements %d, nodes %d)" % [board.placement_calls, contact_count])
	_clear_number_nodes(board)
	board.placement_calls = 0
	board._begin_result_number_batch()
	board.finish_presentation_frame(events, step, before, after)
	check(board.placement_calls == 0 and board._result_number_batch_depth == 1,
		"nested placement scope defers the inner frame placement")
	board._end_result_number_batch()
	check(board.placement_calls == 1 and _number_layouts_equal(expected_layout, _number_layout(board)),
		"outer placement scope performs one final ordered collision pass")
	_clear_number_nodes(board)
	board.placement_calls = 0
	board.finish_presentation_frame([], {}, before, after)
	check(board.placement_calls == 0 and board._numbers.get_child_count() == 0,
		"frame without result numbers does not run placement")
	board.queue_free()
	session.close()
	await process_frame

func _clear_number_nodes(board: BattleDemoBoard) -> void:
	for child: Node in board._numbers.get_children():
		board._numbers.remove_child(child)
		child.free()

func _number_layout(board: BattleDemoBoard) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for number: BattlePresentationNumber in board._numbers.get_children():
		var leader := number.get_node_or_null("Leader") as Line2D
		result.append({"id": int(number.get_meta("unit_id", UnitId.NONE)), "kind": number.feedback_kind,
			"text": number._label.text, "position": number.position,
			"leader": leader.points if leader != null else PackedVector2Array()})
	return result

func _number_layouts_equal(expected: Array[Dictionary], actual: Array[Dictionary]) -> bool:
	if expected.size() != actual.size(): return false
	for index: int in expected.size():
		var first: Dictionary = expected[index]
		var second: Dictionary = actual[index]
		if first.id != second.id or first.kind != second.kind or first.text != second.text: return false
		var first_position: Vector2 = first.position
		var second_position: Vector2 = second.position
		if not first_position.is_equal_approx(second_position): return false
		var first_leader: PackedVector2Array = first.leader
		var second_leader: PackedVector2Array = second.leader
		if first_leader.size() != second_leader.size(): return false
		for point_index: int in first_leader.size():
			if not first_leader[point_index].is_equal_approx(second_leader[point_index]): return false
	return true

func _technical_frames(before: Dictionary, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in count:
		var after := before.duplicate(true)
		after["owned_sequence"] = index
		result.append({"events": [], "step": {"kind": &"technical", "command_seq": index + 1}, "after": after})
	return result

func _wait_player(player: BattlePresentationPlayer) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while player.active and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not player.active, "presentation player finishes before deadline")

func _public_array_ownership() -> void:
	var session := demo.session as BattleCoreReactionsSession
	var before := ActionPresentationState.capture(session.state)
	for mode: String in ["natural", "skip", "cancel"]:
		var source := _technical_frames(before, 8)
		var oracle := source.duplicate(true)
		var player := BattlePresentationPlayer.new()
		viewport.add_child(player)
		var finished_count: Array[int] = [0]
		player.frame_finished.connect(func(state: Dictionary) -> void:
			finished_count[0] += 1
			state.clear()
		)
		player.play(demo.board_view, before, source, source[-1].after)
		var count_before_stop: int = finished_count[0]
		match mode:
			"natural":
				await _wait_player(player)
			"skip":
				player.skip()
				await process_frame
			"cancel":
				player.cancel()
				await process_frame
		check(source == oracle, "public play preserves caller frames after %s" % mode)
		if mode == "natural":
			check(finished_count[0] == source.size() + 1, "natural public play emits ordered frames and one final")
		elif mode == "skip":
			check(not player.active and finished_count[0] == count_before_stop + 1, "public skip emits final exactly once")
		else:
			check(not player.active and finished_count[0] == count_before_stop, "public cancel emits no extra final")
		player.queue_free()
		await process_frame

func _owned_receipt_integrity() -> void:
	await fresh()
	var session := demo.session as BattleCoreReactionsSession
	var before_live := snapshot(session)
	var before := ActionPresentationState.capture(session.state)
	var actor := session.units[0]
	session.begin_presentation_capture()
	var receipt := session.move_to(Vector2i(1, 2))
	var packets := session.take_presentation_capture()
	var receipt_oracle := receipt.get_presentation_frames()
	var events_oracle := receipt.get_events()
	var steps_oracle := receipt.get_steps()
	var live_oracle := snapshot(session)
	check(receipt.status == ActionReceipt.APPLIED and packets.size() == 1 and not receipt_oracle.is_empty(),
		"owned playback source is a real successful move receipt")
	if receipt.status != ActionReceipt.APPLIED or packets.is_empty(): return
	# Используем именно отделённый packet.frames: лишняя копия скрыла бы ошибки владения.
	var owned: Array[Dictionary] = packets[0].frames
	var expected_after: Array[Dictionary] = receipt_oracle
	var final_state := ActionPresentationState.capture(session.state)
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	var published: Array[Dictionary] = []
	var expected_published: Array[Dictionary] = []
	player.frame_started.connect(func(frame: Dictionary) -> void:
		frame["events"].clear()
		frame["after"].clear()
	)
	player.frame_finished.connect(func(state: Dictionary) -> void:
		published.append(state.duplicate(true))
		state.clear()
	)
	for frame: Dictionary in expected_after: expected_published.append(frame.after.duplicate(true))
	player.play_owned_frames(demo.board_view, before, owned, final_state)
	owned = []
	await _wait_player(player)
	var expected_receipt_publications := expected_published.duplicate(true)
	if not published.is_empty(): published.pop_back() # У player есть отдельная финальная публикация.
	check(published == expected_receipt_publications,
		"real owned receipt frame after states publish in captured order")
	check(receipt.get_presentation_frames() == receipt_oracle and receipt.get_events() == events_oracle
		and receipt.get_steps() == steps_oracle, "owned playback leaves receipt frames, events and steps unchanged")
	check(snapshot(session) == live_oracle and before_live != live_oracle and actor.cell == Vector2i(1, 2),
		"owned playback leaves the already committed live state and RNG unchanged")
	player.queue_free()
	await process_frame

func _owned_large_packet() -> void:
	var session := demo.session as BattleCoreReactionsSession
	var before := ActionPresentationState.capture(session.state)
	var frames := _technical_frames(before, 120)
	var oracle := frames.duplicate(true)
	var final_state := before.duplicate(true)
	final_state["terminal_marker"] = "H1"
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	var published_sequences: Array[int] = []
	var saw_released_prefix := false
	var saw_retained_suffix := false
	var final_count: Array[int] = [0]
	var final_published: Array[Dictionary] = [{}]
	player.frame_finished.connect(func(state: Dictionary) -> void:
		if state.get("terminal_marker", "") == "H1":
			final_count[0] += 1
			final_published[0] = state.duplicate(true)
		else: published_sequences.append(int(state.get("owned_sequence", -1)))
		state.clear()
	)
	player.play_owned_frames(demo.board_view, before, frames, final_state)
	frames = []
	var deadline := Time.get_ticks_msec() + 30000
	while player.active and Time.get_ticks_msec() < deadline:
		await process_frame
		if not player.active: break
		var released := player._released_index
		if released > 0:
			saw_released_prefix = true
			for index: int in mini(released, player._frames.size()):
				if not player._frames[index].is_empty(): saw_released_prefix = false
		if released < player._frames.size():
			saw_retained_suffix = true
			for index: int in range(released, player._frames.size()):
				if not player._frames[index].has("after"): saw_retained_suffix = false
	check(not player.active and published_sequences.size() == oracle.size(), "all 120 owned technical frames publish")
	var ordered := published_sequences.size() == 120
	for index: int in published_sequences.size():
		if published_sequences[index] != index: ordered = false
	check(ordered, "owned technical publications preserve packet order")
	check(saw_released_prefix and saw_retained_suffix, "consumed prefix releases while future frames remain available")
	check(final_count[0] == 1 and not published_sequences.has(-1)
		and published_sequences.size() == 120, "H1 final state publishes once after packet frames")
	check(player._frames.is_empty() and final_published[0] == final_state,
		"owned packet storage releases after publishing the exact final state")
	player.queue_free()
	await process_frame

func _owned_skip_cancel() -> void:
	var before := ActionPresentationState.capture((demo.session as BattleCoreReactionsSession).state)
	var skip_player := BattlePresentationPlayer.new()
	viewport.add_child(skip_player)
	var skip_published: Array[Dictionary] = []
	skip_player.frame_finished.connect(func(state: Dictionary) -> void: skip_published.append(state.duplicate(true)))
	skip_player.play_owned_frames(demo.board_view, before, _technical_frames(before, 4), {"terminal_marker": "H1"})
	skip_player.skip()
	await process_frame
	check(not skip_player.active and skip_published.size() == 1
		and skip_published[0].get("terminal_marker", "") == "H1", "owned skip publishes only the final H1 state")
	var count_after_skip := skip_published.size()
	for index: int in 3: await process_frame
	check(skip_published.size() == count_after_skip, "owned skip cancels queued frames without extras")
	skip_player.queue_free()
	var cancel_player := BattlePresentationPlayer.new()
	viewport.add_child(cancel_player)
	var cancel_published: Array[int] = [0]
	cancel_player.frame_finished.connect(func(_state: Dictionary) -> void: cancel_published[0] += 1)
	cancel_player.play_owned_frames(demo.board_view, before, _technical_frames(before, 4), {"terminal_marker": "H1"})
	cancel_player.cancel()
	for index: int in 3: await process_frame
	check(not cancel_player.active and cancel_published[0] == 0, "owned cancel publishes no frame or premature H1")
	cancel_player.queue_free()
	await process_frame

func _wait_for_empty_capture_refresh() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while demo._refresh_followup.is_empty() and demo._execution_worker.is_started() \
		and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if not demo._refresh_followup.is_empty(): break
		await process_frame
	return not demo._refresh_followup.is_empty()

func _chain_marker_nested_skip_hud() -> void:
	await fresh()
	var before := ActionPresentationState.capture((demo.session as BattleCoreReactionsSession).state)
	var final_state := before.duplicate(true)
	var id: int = final_state.units.keys()[0]
	final_state.units[id].hp = 3.0
	var original_player := demo._presentation_player
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	demo._presentation_player = player
	player._board = demo.board_view
	player._published = before
	player._final = final_state.duplicate(true)
	player._frames.assign([{"events": [], "step": {"kind": &"push_chain"}, "after": before.duplicate(true)}])
	player.active = true
	var flags: Array[bool] = []
	var publications: Array[Dictionary] = []
	player.frame_started.connect(demo._presentation_frame_started)
	player.frame_finished.connect(demo._presentation_frame_finished)
	player.frame_finished.connect(func(state: Dictionary) -> void:
		flags.append(player.is_repeated_chain_publication())
		publications.append(state.duplicate(true))
		if player.is_repeated_chain_publication(): player.skip()
	)
	demo._render_presentation_hud(before)
	var button := demo._roster_presenter.get_or_create_button(id)
	var before_text := button.text
	player._start_chain_frame(0)
	player._publish_chain_frame(0)
	var actual_text := button.text
	check(flags == [true, false] and publications == [before, final_state],
		"repeated chain marker keeps both public signals and nested skip publishes a fresh final")
	check(actual_text == BattleFrameText.roster(final_state.units[id]) and actual_text != before_text,
		"nested skip within a repeated marker still refreshes HUD with final HP")
	check(not player.is_repeated_chain_publication() and not player.active,
		"repeated-marker hint does not escape its signal scope or skip")
	demo._presentation_player = original_player
	player.queue_free()
	await process_frame

func _empty_capture_worker_refresh() -> void:
	await fresh()
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	var before := snapshot(session)
	var revision := session.context.get_revision()
	var prior_frame_count := frame_sequences.size()
	demo._execute_live(&"attack_unit", [UnitId.NONE], true)
	check(demo._execution_worker.is_started(), "captured invalid-target command enters the exact worker")
	var reached_stage := await _wait_for_empty_capture_refresh()
	var receipt := session.last_receipt
	check(reached_stage and demo._refresh_stage == -1 and demo.is_execution_pending(),
		"empty worker capture schedules the begin-refresh stage")
	check(receipt != null and receipt.status == ActionReceipt.REJECTED and receipt.reason == &"attack/invalid_target"
		and receipt.get_presentation_frames().is_empty(), "invalid target produces an empty rejected receipt")
	check(frame_sequences.size() == prior_frame_count and not demo._presentation_player.active,
		"empty capture starts no presentation frame")
	if not reached_stage: return
	var expected_stages: Array[int] = [-1, 0, 1, 2]
	for stage: int in expected_stages:
		check(demo.is_execution_pending() and demo._refresh_stage == stage,
			"empty capture keeps input pending at refresh stage %d" % stage)
		demo._execute_live(&"guard_selected", [])
		check(session.context.get_revision() == revision and snapshot(session) == before,
			"empty capture blocks a follow-up command at refresh stage %d" % stage)
		demo._poll_execution()
		await process_frame
	check(not demo.is_execution_pending() and demo._refresh_followup.is_empty()
		and demo._refresh_stage == 3, "empty capture releases input only after final refresh")
	check(session.last_receipt == receipt and session.context.get_revision() == revision
		and snapshot(session) == before and frame_sequences.size() == prior_frame_count,
		"staged empty receipt preserves rejection, live state and no-animation projection")
	check(demo._status.text.contains("Действие отклонено"),
		"rejected receipt message survives the final empty-capture refresh")

func _disabled_presentation_refresh_stays_synchronous() -> void:
	await fresh()
	demo.set_process(false)
	demo.presentation_enabled = false
	var session := demo.session as BattleCoreReactionsSession
	var before := snapshot(session)
	var prior_frame_count := frame_sequences.size()
	demo._execute_live(&"attack_unit", [UnitId.NONE], true)
	var deadline := Time.get_ticks_msec() + 15000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		await process_frame
	check(not demo.is_execution_pending() and demo._refresh_followup.is_empty()
		and not demo._stage_next_refresh, "presentation-disabled worker keeps the direct refresh path")
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.REJECTED
		and snapshot(session) == before and frame_sequences.size() == prior_frame_count,
		"presentation-disabled rejected receipt remains synchronous and unchanged")
