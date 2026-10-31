extends "res://tests/test_battle_soak_performance.gd"

class PlannerDemoProbe extends HeroHubBattleView:
	var owned_session: BattleCoreReactionsSession
	var scripted_statuses: Array[StringName] = []
	var submitted_count: int = 0
	var suppress_receipt: bool = false
	var detach_session_on_finish: bool = false
	var switch_to_enemy_phase: bool = false

	func _ready() -> void:
		set_process(false)

	func _process(_delta: float) -> void:
		pass

	func _execute_live(method: StringName, args: Array = [], target_attempt: bool = false) -> void:
		submitted_count += 1
		_refresh_followup = {"planner_probe": true}
		call_deferred("_finish_probe_command", method, args, target_attempt)

	func _finish_probe_command(method: StringName, args: Array, _target_attempt: bool) -> void:
		_refresh_followup.clear()
		if submitted_count <= scripted_statuses.size() and not suppress_receipt:
			var status: StringName = scripted_statuses[submitted_count - 1]
			var receipt := ActionReceipt.new()
			receipt.status = status
			receipt.reason = &"scripted planner probe"
			owned_session.last_receipt = receipt
			if status == ActionReceipt.APPLIED and method == &"attack_unit" and not args.is_empty():
				var target := owned_session.board.get_unit_by_id(int(args[0]))
				if target != null: target.vitals.set_hp(target.vitals.get_hp() - 1.0)
		if switch_to_enemy_phase: owned_session.phase = BattleTacticalSession.Phase.ENEMY_TURN
		if detach_session_on_finish: session = null

var pending_was_observed: bool = false

func _run() -> void:
	await _run_case([ActionReceipt.APPLIED], 1, true, false, "successful candidate")
	await _run_case([ActionReceipt.REJECTED, ActionReceipt.APPLIED], 2, true, false,
		"completed rejection retries and the next candidate succeeds")
	await _run_case([ActionReceipt.FAULTED, ActionReceipt.APPLIED], 1, false, false,
		"faulted candidate aborts without retry")
	await _run_case([ActionReceipt.INTERRUPTED, ActionReceipt.APPLIED], 1, false, false,
		"interrupted candidate aborts without retry")
	await _run_case([ActionReceipt.REJECTED, ActionReceipt.APPLIED], 0, false, true,
		"real pending view refuses dispatch and retry")
	await _run_case([ActionReceipt.REJECTED, ActionReceipt.APPLIED], 1, false, false,
		"missing demo session aborts without retry", true, false, false)
	await _run_case([ActionReceipt.REJECTED, ActionReceipt.APPLIED], 1, false, false,
		"session that cannot act aborts without retry", false, true, false)
	await _run_case([ActionReceipt.APPLIED], 1, false, false,
		"stale APPLIED receipt is not attributed to a command", false, false, true, ActionReceipt.APPLIED)
	await _run_case([ActionReceipt.REJECTED, ActionReceipt.APPLIED], 1, false, false,
		"stale REJECTED receipt does not retry", false, false, true, ActionReceipt.REJECTED)
	await _check_summary_owner_rebind()
	print("BATTLE SOAK PLANNER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run_case(statuses: Array[StringName], expected_submissions: int, expected_success: bool,
		pending_before_dispatch: bool, label: String, detach_session: bool = false,
		enemy_phase: bool = false, no_new_receipt: bool = false,
		stale_status: StringName = &"") -> void:
	session = _make_stress_session()
	check(session != null, label + ": production expedition fixture builds")
	if session == null: return
	var actor := _first_eligible_player()
	check(actor != null and _place_two_reachable_enemies(actor), label + ": fixture has two spatially reachable enemy candidates")
	if actor == null:
		session.close()
		return
	if stale_status != &"":
		var stale := ActionReceipt.new()
		stale.status = stale_status
		session.last_receipt = stale
	demo = PlannerDemoProbe.new() as HeroHubBattleView
	var probe := demo as PlannerDemoProbe
	probe.owned_session = session
	probe.session = session
	probe.scripted_statuses = statuses.duplicate()
	probe.suppress_receipt = no_new_receipt
	probe.detach_session_on_finish = detach_session
	probe.switch_to_enemy_phase = enemy_phase
	root.add_child(probe)
	await process_frame
	submission_trace_buckets.clear()
	pending_was_observed = false
	planning_abort_requested = false
	if pending_before_dispatch:
		probe._refresh_followup = {"test_owned_pending": true}
		pending_was_observed = probe.is_execution_pending()
	var action_succeeded := await _perform_player_action()
	check(probe.submitted_count == expected_submissions,
		"%s: fake view received %d dispatch(es), expected %d" % [label, probe.submitted_count, expected_submissions])
	check(action_succeeded == expected_success, label + ": action completion matches current-call receipt")
	check(planning_abort_requested == (not expected_success),
		label + ": unsuccessful submitted candidate sets abort state")
	if expected_submissions > 1:
		check(submission_trace_buckets.size() >= 2
			and submission_trace_buckets[1] == "test_planning",
			label + ": planning trace bucket is restored before the next candidate")
	if pending_before_dispatch:
		check(pending_was_observed and probe.is_execution_pending(), label + ": base view reports actual pending followup")
	if no_new_receipt:
		check(last_execution_receipt == null, label + ": wrapper rejects a reused receipt instance")
	if demo != null:
		probe._refresh_followup.clear()
		probe.set_process(false)
		probe.queue_free()
	if session != null: session.close()
	await process_frame
	demo = null
	session = null

func _first_eligible_player() -> UnitState:
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.PLAYER and unit.is_alive() and unit.action_resources != null \
			and unit.action_resources.get_main_left() > 0 and ControlRules.action_reason(unit) == &"":
			return unit
	return null

func _place_two_reachable_enemies(actor: UnitState) -> bool:
	var board := session.board
	var range_value: float = actor.stats.get_value(StatTypes.StatType.ATTACK_RANGE)
	var reachable_count: int = 0
	for enemy: UnitState in session.units:
		if enemy.faction != Faction.Type.ENEMY or not enemy.is_alive(): continue
		if AttackReachCheck.inspect_spatial(board, actor, enemy, range_value) == &"":
			reachable_count += 1
			if reachable_count >= 2: return true
			continue
		var original_cell := enemy.cell
		var placed := false
		for y: int in board.height:
			for x: int in board.width:
				var candidate := Vector2i(x, y)
				if candidate == original_cell or board.is_occupied(candidate) \
					or board.get_terrain(candidate) != TerrainType.Type.FLOOR \
					or not session.state.environment.fire_at(candidate).is_empty(): continue
				if not board.move_unit(enemy, candidate): continue
				if AttackReachCheck.inspect_spatial(board, actor, enemy, range_value) == &"":
					reachable_count += 1
					placed = true
					break
				board.move_unit(enemy, original_cell)
			if placed or reachable_count >= 2: break
		if reachable_count >= 2: return true
	return false

func _check_summary_owner_rebind() -> void:
	session = _make_stress_session()
	check(session != null, "summary-owner fixture builds")
	if session == null: return
	demo = PlannerDemoProbe.new() as HeroHubBattleView
	var probe := demo as PlannerDemoProbe
	probe.owned_session = session
	probe.session = session
	root.add_child(probe)
	await process_frame
	var expected_owner := session
	session = null
	probe._refresh_followup = {"test_owned_return": true}
	var restored := _restore_owner_before_summary()
	check(restored and session == expected_owner, "summary helper joins pending view then rebinds its runtime owner")
	check(not probe.is_execution_pending(), "summary helper clears pending presentation before state reads")
	probe.queue_free()
	expected_owner.close()
	await process_frame
	demo = null
	session = null
