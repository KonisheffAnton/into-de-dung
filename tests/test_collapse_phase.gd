extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL COLLAPSE PHASE: " + label)

func _run() -> void:
	await _test_preview_worker_and_restore()
	await _test_lethal_parity()
	_test_mark_then_collapse()
	_test_turn_boundary_and_legacy()
	_test_death_and_environment_cleanup()
	_test_admission_and_no_candidates()
	_test_guard_fault()
	_test_bt_escape()
	_test_helper_and_terminal()
	_test_queue_capacity_prefix()
	_test_internal_root_rejection()
	print("COLLAPSE PHASE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _session(seed: int = 41) -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	# Проверки отдельной фазы задают состояние хода игрока без решений ИИ.
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	session.context._rng = CombatRng.new(seed)
	if session.state.environment == null: session.state.environment = CombatEnvironmentState.new()
	session.state.environment.collapse = {"turn": 0, "marked": []}
	return session

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	check(result.code == ItemSnapshotResult.Code.OK and result.snapshot != null, "live snapshot captures")
	return result.snapshot.to_dict() if result.snapshot != null else {}

func _run_phase(session: BattleCoreReactionsSession) -> ActionReceipt:
	return session._submit(CollapsePhaseCommand.new(session.context.get_revision()))

func _test_preview_worker_and_restore() -> void:
	var session := _session(809)
	var before := _snapshot(session)
	var bytes_before := ItemSimulationSnapshot.from_dict(before)
	var preview_a := session.preview_environment()
	var preview_b := session.preview_environment()
	check(preview_a.status == ActionReceipt.APPLIED and preview_a.events == preview_b.events and preview_a.steps == preview_b.steps and preview_a.snapshot_after == preview_b.snapshot_after and preview_a.rng_after == preview_b.rng_after and preview_a.counters_after == preview_b.counters_after, "two previews are deterministic")
	check(preview_a.snapshot_before == before and _snapshot(session) == before, "preview preserves full live snapshot")
	check(preview_a.events.size() == 1 and preview_a.events[0]["kind"] == &"environment_turn" and preview_a.steps.size() == 1, "first phase produces only mark event and step")
	var prepared := session.prepare_environment_forecast()
	var worker := ActionForecastWorker.new()
	worker.start(prepared)
	var worker_result: ForecastSimulation
	for attempt: int in 120:
		worker_result = worker.take_finished()
		if worker_result != null: break
		await process_frame
	check(worker_result != null, "forecast worker completes")
	if worker_result != null:
		check(worker_result.status == preview_a.status and worker_result.events == preview_a.events and worker_result.steps == preview_a.steps and worker_result.snapshot_after == preview_a.snapshot_after and worker_result.rng_after == preview_a.rng_after and worker_result.counters_after == preview_a.counters_after, "worker matches inline forecast")
	worker.close()
	var decoded := ItemSimulationSnapshot.from_dict(before)
	var catalogue: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: catalogue[id] = owner._definitions[id]
	var restored := decoded.snapshot.instantiate(catalogue) if decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot != null else ItemSnapshotResult.new()
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state.environment.collapse == {"turn": 0, "marked": []}, "capture restore retains disabled phase")
	if restored.state != null:
		restored.state.environment.collapse["turn"] = 3
		check(session.state.environment.collapse["turn"] == 0 and ItemSimulationSnapshot.from_dict(before).snapshot.to_dict() == before, "restore and DTO do not alias live state")
		ForecastSimulation.close(restored.state)
	var live_receipt := _run_phase(session)
	check(live_receipt.status == preview_a.status and live_receipt.get_events() == preview_a.events and live_receipt.get_steps() == preview_a.steps, "live receipt matches preview event/step prefix")
	check(_snapshot(session) == preview_a.snapshot_after and session.context.get_rng().to_dict() == preview_a.rng_after and session.context.simulation_counters() == preview_a.counters_after, "live result matches preview snapshot/RNG/counters")
	session.close()

func _test_lethal_parity() -> void:
	var session := _session(887)
	var target := session.units[1]
	session.state.environment.collapse = {"turn": 1, "marked": [target.cell]}
	var before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters()
	var allocator := UnitId.get_counter()
	var preview := session.preview_environment()
	var again := session.preview_environment()
	check(preview.status == ActionReceipt.APPLIED and not preview.units_after[target.id].alive, "lethal forecast kills enemy regardless of armor")
	check(preview.events == again.events and preview.steps == again.steps and preview.snapshot_after == again.snapshot_after, "lethal previews reproduce complete cascade")
	check(_snapshot(session) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before and UnitId.get_counter() == allocator, "lethal previews isolate world, resources, RNG, counters and allocator")
	check(preview.events.size() == 3 and preview.events[0].kind == &"environment_turn" and preview.events[1].kind == &"support_collapsed" and preview.events[2].kind == &"died", "mark precedes collapse and one death without corpse")
	var worker := ActionForecastWorker.new()
	worker.start(session.prepare_environment_forecast())
	var result: ForecastSimulation
	var deadline := Time.get_ticks_msec() + 5000
	while result == null and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
		result = worker.take_finished()
	check(result != null and result.snapshot_after == preview.snapshot_after and result.events == preview.events and result.steps == preview.steps and result.rng_after == preview.rng_after and result.counters_after == preview.counters_after, "lethal worker matches isolated execution")
	worker.close()
	var receipt := _run_phase(session)
	check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps and _snapshot(session) == preview.snapshot_after, "lethal live cascade matches complete forecast")
	check(session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after and SummonAdmission.values(session.context) == preview.admission_after, "lethal RNG, counters and admission match")
	check(session.context.get_rng().to_dict().draws == rng_before.draws + 1, "new mark consumes exactly one random selection")
	check(session.board.occupant_at(target.cell) == null and session.state.environment.processed_deaths.count(target.id) == 1, "enemy death releases occupancy and records once")
	session.close()

func _test_mark_then_collapse() -> void:
	var session := _session(13)
	var first := _run_phase(session)
	var first_mark: Vector2i = session.state.environment.collapse["marked"][0] if not session.state.environment.collapse["marked"].is_empty() else Vector2i(-1, -1)
	check(first.status == ActionReceipt.APPLIED and session.state.environment.collapse["turn"] == 1 and session.state.environment.collapse["marked"].size() == 1, "first environment turn marks one cell")
	check(session.board.get_terrain(first_mark) == TerrainType.Type.FLOOR and first.get_events().all(func(event: Dictionary) -> bool: return event["kind"] != &"support_collapsed"), "first mark does not collapse")
	var second := _run_phase(session)
	var next_mark: Vector2i = session.state.environment.collapse["marked"][0] if not session.state.environment.collapse["marked"].is_empty() else Vector2i(-1, -1)
	check(second.status == ActionReceipt.APPLIED and session.state.environment.collapse["turn"] == 2, "second environment turn advances")
	check(session.board.get_terrain(first_mark) == TerrainType.Type.VOID and next_mark != first_mark and session.board.get_terrain(next_mark) == TerrainType.Type.FLOOR, "old mark collapses while fresh mark remains floor")
	check(second.get_events().any(func(event: Dictionary) -> bool: return event["kind"] == &"support_collapsed" and event["cell"] == first_mark), "collapse event identifies prior mark")
	session.close()

func _test_turn_boundary_and_legacy() -> void:
	var session := _session(17)
	var old_turn: int = session.state.environment.collapse["turn"]
	check(session.end_player_turn(), "player boundary starts enemy phase")
	check(session.state.environment.collapse["turn"] == old_turn + 1, "player completion runs environment before enemy refill")
	session._enemy_ids.clear()
	session.step_enemy()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and session.state.environment.collapse["turn"] == old_turn + 1, "enemy completion does not run a second environment phase")
	session.state.environment.collapse = {}
	session.end_player_turn()
	session._enemy_ids.clear()
	session.step_enemy()
	check(session.state.environment.collapse.is_empty(), "legacy empty collapse stays disabled at turn boundary")
	session.close()

func _test_death_and_environment_cleanup() -> void:
	var occupied := _session(23)
	var victim: UnitState = occupied.units[0]
	var cell := victim.cell
	occupied.state.environment.collapse = {"turn": 1, "marked": [cell]}
	var receipt := _run_phase(occupied)
	check(receipt.status == ActionReceipt.APPLIED and not victim.is_alive(), "occupied player is killed by guarded collapse cascade")
	check(occupied.state.environment.corpses_at(cell).is_empty(), "collapse death creates no body")
	check(receipt.get_events().any(func(event: Dictionary) -> bool: return event["kind"] == &"died" and event["target_unit_id"] == victim.id), "guarded death event names occupant")
	occupied.close()

	var environment := _session(29)
	var target: UnitState = environment.units[3]
	var corpse_cell := target.cell
	var death := environment._submit(DeathCommand.new(target.id, DamageSource.new(&"test", 0, corpse_cell)))
	check(death.status == ActionReceipt.APPLIED and not environment.state.environment.corpses_at(corpse_cell).is_empty(), "fixture creates valid corpse at collapse cell")
	environment.state.environment.ignite(corpse_cell)
	environment.state.environment.collapse = {"turn": 1, "marked": [corpse_cell]}
	var collapsed := _run_phase(environment)
	check(collapsed.status == ActionReceipt.APPLIED and environment.board.get_terrain(corpse_cell) == TerrainType.Type.VOID, "empty marked cell becomes void")
	check(environment.state.environment.fire_at(corpse_cell).is_empty() and environment.state.environment.corpses_at(corpse_cell).is_empty(), "collapse removes fire and corpse on cell")
	check(environment.state.environment.processed_deaths.has(target.id), "collapse retains processed death history")
	environment.close()

func _test_admission_and_no_candidates() -> void:
	var session := _session(37)
	var old_revision := session.context.get_revision()
	var stale := CollapsePhaseCommand.new(old_revision)
	session.context._revision += 1
	var stale_receipt := session._submit(stale)
	check(stale_receipt.status == ActionReceipt.REJECTED and stale_receipt.reason == &"collapse/stale_phase", "stale phase is rejected before mutation")
	session.state.environment.collapse["turn"] = 1
	var rng := session.context.get_rng() as CombatRng
	rng._draws = ActionContext.MAX_ID - 1
	var rng_before := rng.to_dict()
	var mark_before: Dictionary = session.state.environment.collapse.duplicate(true)
	var exhausted := _run_phase(session)
	check(exhausted.status == ActionReceipt.FAULTED and exhausted.reason == &"collapse/rng_exhausted", "exhausted random stream faults safely")
	check(rng.to_dict() == rng_before and session.state.environment.collapse == mark_before, "RNG exhaustion preserves live stream and marker")
	session.close()

	var invalid := _session(39)
	invalid.state.environment.collapse = {"turn": 1, "marked": [Vector2i(999, 999)]}
	var invalid_rng_before := invalid.context.get_rng().to_dict()
	var invalid_counters_before := invalid.context.simulation_counters()
	var invalid_mark_before := invalid.state.environment.collapse.duplicate(true)
	var invalid_result := _run_phase(invalid)
	check(invalid_result.status == ActionReceipt.REJECTED and invalid_result.reason == &"environment/collapse_cell", "invalid marker geometry is rejected")
	check(invalid.context.get_rng().to_dict() == invalid_rng_before and invalid.context.simulation_counters() == invalid_counters_before and invalid.state.environment.collapse == invalid_mark_before, "invalid marker refusal leaves runtime unchanged")
	invalid.close()

	var empty := _session(43)
	empty.state.environment.fires.clear()
	empty.state.environment.corpses.clear()
	for y: int in empty.board.height:
		for x: int in empty.board.width:
			empty.board.set_terrain(Vector2i(x, y), TerrainType.Type.VOID)
	var no_candidates_rng := empty.context.get_rng().to_dict()
	var no_candidates := _run_phase(empty)
	check(no_candidates.status == ActionReceipt.APPLIED and empty.state.environment.collapse["marked"].is_empty(), "no floor candidates create no marker")
	check(empty.context.get_rng().to_dict() == no_candidates_rng, "empty candidate set consumes no random draw")
	empty.close()

func _test_guard_fault() -> void:
	var session := _session(53)
	var seed_receipt := _run_phase(session)
	if seed_receipt.status != ActionReceipt.APPLIED or session.state.environment.collapse["marked"].is_empty():
		check(false, "guard fixture receives first mark")
		session.close()
		return
	var marked: Vector2i = session.state.environment.collapse["marked"][0]
	var changed: Array[bool] = [false]
	var callback := func() -> void:
		if not changed[0]:
			changed[0] = true
			session.state.environment.next_fire_id += 1
	session.board.board_changed.connect(callback)
	var receipt := _run_phase(session)
	session.board.board_changed.disconnect(callback)
	check(changed[0] and receipt.status == ActionReceipt.FAULTED and receipt.reason == &"collapse/invalid_binding", "callback mutation trips sealed collapse guard")
	check(session.board.get_terrain(marked) == TerrainType.Type.VOID, "guard fault reports truthful collapsed-cell prefix")
	session.close()

	var vitals_session := _session(59)
	var victim: UnitState = vitals_session.units[0]
	vitals_session.state.environment.collapse = {"turn": 1, "marked": [victim.cell]}
	var hp_changed: Array[bool] = [false]
	var hp_callback := func(_before: float, _after: float) -> void:
		hp_changed[0] = true
		vitals_session.state.environment.next_corpse_id += 1
	victim.vitals.hp_changed.connect(hp_callback)
	var vitals_receipt := _run_phase(vitals_session)
	victim.vitals.hp_changed.disconnect(hp_callback)
	check(hp_changed[0] and vitals_receipt.status == ActionReceipt.FAULTED, "vitals callback mutation faults sealed death continuation")
	vitals_session.close()

func _test_bt_escape() -> void:
	var session := _session(61)
	var enemy: UnitState = session.units[3]
	enemy.control.stunned_turns = 0
	enemy.control.entangled_turns = 0
	session.state.environment.collapse = {"turn": 1, "marked": [enemy.cell]}
	var rng_before := session.context.get_rng().to_dict()
	var intent := BattleDemoBT.new().decide(session, enemy)
	check(intent.kind == BattleAIIntent.Kind.MOVE and intent.actor_id == enemy.id and intent.path.size() > 1 and not session.state.environment.collapse["marked"].has(intent.path[-1]), "enemy on marked cell chooses unmarked escape move")
	check(session.context.get_rng().to_dict() == rng_before, "BT escape choice consumes no RNG")
	enemy.control.stunned_turns = 1
	var stunned := BattleDemoBT.new().decide(session, enemy)
	check(stunned.kind != BattleAIIntent.Kind.MOVE, "stunned enemy does not escape collapse")
	enemy.control.stunned_turns = 0
	enemy.control.entangled_turns = 1
	var entangled := BattleDemoBT.new().decide(session, enemy)
	check(entangled.kind != BattleAIIntent.Kind.MOVE, "entangled enemy does not escape collapse")
	session.close()

func _test_helper_and_terminal() -> void:
	var helper_session := _session(67)
	var item := helper_session.summoning_item()
	var cells := helper_session.summoning_cells()
	if item == null or cells.is_empty():
		check(false, "helper fixture has a summoning action and free cell")
		helper_session.close()
	else:
		var actor_id := helper_session.selected_id
		var receipt := helper_session._submit(helper_session.item_command(actor_id, item.get_item_instance_id(), cells[0]))
		if receipt.status != ActionReceipt.APPLIED: print("DEBUG helper receipt ", receipt.status, " / ", receipt.reason, " / ", receipt.get_events())
		var helper_id := 0
		for event: Dictionary in receipt.get_events():
			if event["kind"] == &"summoned": helper_id = int(event["target_unit_id"])
		var helper := helper_session.board.get_unit_by_id(helper_id)
		check(helper != null and helper_session.state.summon_owner_id(helper_id) == actor_id, "fixture creates owned helper")
		if helper == null: print("DEBUG helper ", helper_id, " event=", receipt.get_events(), " live units=", helper_session.board.get_all_units().size())
		if helper != null:
			helper_session.state.environment.collapse = {"turn": 1, "marked": [helper.cell]}
			var collapsed := _run_phase(helper_session)
			check(collapsed.status == ActionReceipt.APPLIED and not helper.is_alive() and helper_session.state.environment.corpses_at(helper.cell).is_empty(), "collapse kills helper without creating body")
		helper_session.close()

	var terminal := _session(71)
	var players := terminal.living_ids(Faction.Type.PLAYER)
	var last_player: UnitState = terminal.board.get_unit_by_id(players[0])
	for index: int in range(1, players.size()):
		var extra := terminal.board.get_unit_by_id(players[index])
		terminal._submit(DeathCommand.new(extra.id, DamageSource.new(&"test", 0, extra.cell)))
	var remaining_main := last_player.action_resources.get_main_left()
	terminal.state.environment.collapse = {"turn": 1, "marked": [last_player.cell]}
	check(not terminal.end_player_turn(), "terminal collapse stops before enemy turn")
	check(terminal.phase == BattleTacticalSession.Phase.DEFEAT and not last_player.is_alive(), "last player death ends battle during collapse")
	check(last_player.action_resources.get_main_left() == remaining_main, "terminal collapse does not refill outgoing player actions")
	terminal.close()

func _test_queue_capacity_prefix() -> void:
	var command_limited := _session(73)
	var old_cell := command_limited.units[0].cell
	command_limited.state.environment.collapse = {"turn": 1, "marked": [old_cell]}
	command_limited._queue._max_commands = 1
	var command_result := _run_phase(command_limited)
	check(command_result.status == ActionReceipt.FAULTED and command_result.reason == &"command_limit", "command cap faults before collapse child")
	check(command_result.get_steps().size() == 1 and command_result.get_events().size() == 1 and command_limited.board.get_terrain(old_cell) == TerrainType.Type.FLOOR and command_limited.state.environment.collapse["turn"] == 2, "command cap keeps truthful mark-only prefix")
	command_limited.close()

	var event_limited := _session(79)
	var event_cell := event_limited.units[0].cell
	event_limited.state.environment.collapse = {"turn": 1, "marked": [event_cell]}
	event_limited.context._next_event_seq = ActionContext.MAX_ID - 2
	var event_result := _run_phase(event_limited)
	check(event_result.status == ActionReceipt.FAULTED and event_result.reason == &"sequence_exhausted", "event sequence cap faults at mandatory collapse child")
	check(event_result.get_events().size() == 1 and event_limited.board.get_terrain(event_cell) == TerrainType.Type.FLOOR and event_limited.state.environment.collapse["turn"] == 2, "event cap preserves only the executed phase prefix")
	event_limited.close()

func _test_internal_root_rejection() -> void:
	var session := _session(83)
	var before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var receipt := session._submit(CollapseCellCommand.new(Vector2i(0, 0)))
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"collapse/internal_command", "cell-collapse child is rejected as a root command")
	check(_snapshot(session) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before, "internal root rejection leaves snapshot/RNG/counters unchanged")
	session.close()
