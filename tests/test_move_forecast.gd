extends SceneTree

var passed: int = 0
var failed: int = 0

class CountingSink extends ActionEventSink:
	var calls: int = 0
	func publish(_event: Dictionary) -> void: calls += 1

class NoCloneRng extends ActionRngPort:
	func to_dict() -> Dictionary: return {"cursor": 4}

class UnknownMove extends MoveCommand:
	func validate(_context: ActionContext) -> StringName:
		push_error("Unknown movement must never execute")
		return &""

class CustomSession extends BattleTacticalSession:
	func _summoning_definition() -> ItemDef:
		var definition := super._summoning_definition()
		definition.summon_definition.hp_max = 21.0
		definition.summon_definition.name_prefix = "Спутник · "
		return definition

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL MOVE FORECAST: " + label)

func fixture(s: BattleDemoSession = null) -> BattleDemoSession:
	if s == null: s = BattleCoreCombinationSession.new()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	for index: int in s.units.size():
		if s.units[index].is_alive(): s.board.move_unit(s.units[index], Vector2i(index, 7))
	s.board.move_unit(s.units[0], Vector2i(0, 0))
	s.select_unit(s.units[0].id)
	if s.state.environment != null: s.state.environment.fires.clear()
	s.context._sink = CountingSink.new()
	s.context._revision = 13
	s.context._next_root_id = 7
	s.context._next_command_seq = 31
	s.context._next_event_seq = 41
	return s

func snapshot(s: BattleDemoSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "valid fixture: " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func command(s: BattleDemoSession, path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]) -> MoveCommand:
	return MoveCommand.new(s.selected_id, path, s.context.get_revision())

func parity(s: BattleDemoSession, cmd: MoveCommand, label: String, status: StringName = ActionReceipt.APPLIED) -> MoveForecast:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var admission := SummonAdmission.values(s.context)
	var next_id := UnitId.get_counter()
	var selected := s.selected_id
	var last := s.last_receipt
	var phase: int = (s as BattleTacticalSession).phase if s is BattleTacticalSession else -1
	var sink := s.context.get_sink() as CountingSink
	var sink_calls := sink.calls
	var signals: Array[int] = []
	var callback := func() -> void: signals.append(1)
	s.board.board_changed.connect(callback)
	var first := MoveForecast.build(s.context, s._queue, cmd)
	var second := MoveForecast.build(s.context, s._queue, cmd)
	check(first.status == status, label + " status " + String(first.status) + ": " + String(first.reason))
	check(first.snapshot_before == before and first.admission_before == admission, label + " before snapshot/admission")
	check(first.status == second.status and first.reason == second.reason and first.units == second.units and first.events == second.events and first.steps == second.steps and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after and first.admission_after == second.admission_after and first.traversed_path == second.traversed_path, label + " repeat deterministic")
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and SummonAdmission.values(s.context) == admission, label + " full live isolation")
	check(UnitId.get_counter() == next_id and selected == s.selected_id and last == s.last_receipt and sink.calls == sink_calls and signals.is_empty() and not s.context.is_faulted(), label + " allocator/session/sink/signals isolated")
	if s is BattleTacticalSession: check((s as BattleTacticalSession).phase == phase, label + " phase unchanged")
	check(not cmd._is_continuation() and cmd._bound_actor == null and cmd._continuation_index == 0, label + " root command not mutated")
	var actual := s._queue.submit(cmd, s.context)
	s.board.board_changed.disconnect(callback)
	check(first.status == actual.status and first.reason == actual.reason and first.events == actual.get_events() and first.steps == actual.get_steps(), label + " complete receipt parity")
	check(first.snapshot_after == snapshot(s) and first.rng_after == s.context.get_rng().to_dict() and first.counters_after == s.context.simulation_counters() and first.admission_after == SummonAdmission.values(s.context), label + " complete after parity")
	check(sink.calls == sink_calls + actual.get_events().size(), label + " live-only publication")
	if first.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED] and not first.traversed_path.is_empty():
		check(first.units[cmd.get_actor_unit_id()]["after"]["cell"] == s.units[0].cell and first.traversed_path[-1] == s.units[0].cell, label + " real endpoint")
	else: check(first.units.is_empty() and first.traversed_path.is_empty(), label + " no ready result")
	return first

func _run() -> void:
	_paths()
	_hazards()
	await _prepared_workers()
	_refusals()
	_limits()
	_sessions_and_capabilities()
	_helpers()
	_restore_cleanup()
	print("MOVE FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _prepared_workers() -> void:
	var ordinary := fixture()
	await _worker_parity(ordinary, command(ordinary), "ordinary worker", ActionReceipt.APPLIED)
	ordinary.close()

	var combat := fixture(BattleEnvironmentSession.new())
	combat.context._rng = CombatRng.new(913)
	combat.state.environment.ignite(Vector2i(1, 0))
	for item: ItemInstance in combat.state.get_owner(combat.units[0].id)._items.values(): item.armor_remaining = 0
	await _worker_parity(combat, command(combat), "combat rng spikes", ActionReceipt.APPLIED)
	combat.close()

	var falling := fixture()
	falling.context._rng = CombatRng.new(271)
	falling.board.set_height_steps(Vector2i(0, 0), 6)
	falling.units[0].height = 3
	await _worker_parity(falling, command(falling), "combat rng fall", ActionReceipt.APPLIED)
	falling.close()

	var interrupted := fixture(BattleEnvironmentSession.new())
	interrupted.context._rng = CombatRng.new(421)
	interrupted.units[0].vitals.set_hp(1)
	for item: ItemInstance in interrupted.state.get_owner(interrupted.units[0].id)._items.values(): item.armor_remaining = 0
	interrupted.state.environment.ignite(Vector2i(1, 0))
	await _worker_parity(interrupted, command(interrupted), "interrupted worker", ActionReceipt.INTERRUPTED)
	interrupted.close()

	var faulted := fixture()
	faulted._queue = ActionQueue.new(1)
	await _worker_parity(faulted, command(faulted), "faulted prefix worker", ActionReceipt.FAULTED)
	faulted.close()

	var isolated := fixture(BattleDemoSession.new()) as BattleDemoSession
	isolated.board.move_unit(isolated.units[1], Vector2i(1, 0))
	isolated.select_unit(isolated.units[1].id)
	for item: ItemInstance in isolated.state.get_owner(isolated.units[1].id)._items.values(): item.armor_remaining = 0
	var target := Vector2i(3, 0)
	var expected_path := isolated.path_to(target)
	var expected := MoveForecast.build(isolated.context, isolated._queue, MoveCommand.new(isolated.selected_id, expected_path, isolated.context.get_revision()))
	var prepared := isolated.prepare_move_forecast(target)
	var prepared_definition: ItemDef = prepared.definitions[&"demo_guard_amulet"]
	var prepared_heal := (prepared_definition.effects[0] as HealOnDamageEffect).heal_amount
	var saved_snapshot := snapshot(isolated)
	var saved_rng := isolated.context.get_rng().to_dict().duplicate(true)
	var saved_last := isolated.last_receipt
	var saved_sink := isolated.context.get_sink() as CountingSink
	var saved_sink_calls := saved_sink.calls
	var allocator := UnitId.get_counter()
	var live_definition: ItemDef = isolated.state.get_owner(isolated.units[1].id)._definitions[&"demo_guard_amulet"]
	(live_definition.effects[0] as HealOnDamageEffect).heal_amount = 99.0
	(isolated.context._move_rules as MoveRules)._admitted_unit_ids.clear()
	check((prepared_definition.effects[0] as HealOnDamageEffect).heal_amount == prepared_heal and (prepared.context._move_rules as MoveRules).allows(isolated.units[1].id), "prepared definitions and movement rules are detached copies")
	isolated.close()
	var isolated_result := await _run_worker(prepared)
	check(_same_forecast(expected, isolated_result), "prepared worker detaches closed live session and copies definitions/rules")
	check(UnitId.get_counter() == allocator and saved_sink.calls == saved_sink_calls and saved_last == null, "worker leaves live allocator/sink/receipt untouched after close")
	check(expected.snapshot_before == saved_snapshot and expected.rng_after == saved_rng, "detachment fixture matches captured initial live state")

	var discarded_session := fixture()
	var discard_worker := MoveForecastWorker.new()
	discard_worker.start(discarded_session.prepare_move_forecast(Vector2i(3, 0)))
	if discard_worker._thread != null and discard_worker._thread.is_alive():
		check(discard_worker.take_finished() == null, "unfinished worker has no result")
	discard_worker.close()
	check(not discard_worker.is_started(), "closing worker discards and joins outstanding calculation")
	discarded_session.close()

func _worker_parity(s: BattleDemoSession, cmd: MoveCommand, label: String, status: StringName) -> void:
	var expected := MoveForecast.build(s.context, s._queue, cmd)
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var admission := SummonAdmission.values(s.context)
	var allocator := UnitId.get_counter()
	var sink := s.context.get_sink() as CountingSink
	var sink_calls := sink.calls
	var last := s.last_receipt
	var prepared := s.prepare_move_forecast(cmd.get_path()[-1])
	var result := await _run_worker(prepared)
	check(result != null and result.status == status, label + " runs in worker with expected status")
	check(_same_forecast(expected, result), label + " exact prepared/sync parity")
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and SummonAdmission.values(s.context) == admission, label + " leaves live snapshot/RNG/counters/admission unchanged")
	check(UnitId.get_counter() == allocator and sink.calls == sink_calls and s.last_receipt == last, label + " leaves allocator/sink/receipt unchanged")

func _run_worker(prepared: ForecastSimulation.Prepared) -> MoveForecast:
	var worker := MoveForecastWorker.new()
	worker.start(prepared)
	var deadline := Time.get_ticks_msec() + 5000
	var result: MoveForecast
	while Time.get_ticks_msec() < deadline:
		result = worker.take_finished()
		if result != null: break
		await create_timer(0.005).timeout
	if result == null:
		worker.close()
		check(false, "worker completes before 5s deadline")
		return null
	check(worker.take_finished() == null, "worker result can only be taken once")
	worker.close()
	check(not worker.is_started(), "worker close releases finished thread")
	check(MoveForecast.build_prepared(prepared).reason == &"preview/request_consumed", "prepared request is single use")
	return result

func _same_forecast(a: MoveForecast, b: MoveForecast) -> bool:
	return a != null and b != null and a.status == b.status and a.reason == b.reason and a.units == b.units and a.events == b.events and a.steps == b.steps and a.snapshot_before == b.snapshot_before and a.snapshot_after == b.snapshot_after and a.rng_after == b.rng_after and a.counters_after == b.counters_after and a.admission_before == b.admission_before and a.admission_after == b.admission_after and a.actor_id == b.actor_id and a.requested_path == b.requested_path and a.traversed_path == b.traversed_path

func _paths() -> void:
	for kind: int in 4:
		var s := fixture(BattleDemoSession.new() if kind == 0 else null)
		var actor := s.units[0]
		actor.guard_stance = true
		if kind >= 2:
			s.board.move_unit(s.units[2], Vector2i(1, 0))
			s.board.move_unit(s.units[4], Vector2i(2, 0))
		if kind == 3:
			s.board.set_height_steps(Vector2i(1, 0), 2)
			s.board.set_height_steps(Vector2i(2, 0), 4)
			s.units[2].height = 1
			s.units[4].height = 2
		var f := parity(s, command(s), "path " + str(kind))
		check(f.traversed_path == f.requested_path and f.traversed_path.size() == 4, "transit retains every cell")
		check(actor.action_resources.get_main_left() == 1 and actor.action_resources.get_bonus_left() == 1 and not actor.guard_stance, "movement preserves main/bonus and clears stance")
		check(actor.move_points_left == (0.0 if kind == 3 else (5.0 if kind == 0 else 2.0)), "existing cost formula")
		if kind >= 2: check(s.units[2].cell == Vector2i(1, 0) and s.units[4].cell == Vector2i(2, 0), "allies stationary")
		if kind == 3:
			var fall_hit := false
			for event: Dictionary in f.events:
				if event["kind"] == &"hit_resolved" and event.get("source", {}).get("kind") == &"fall": fall_hit = true
			check(fall_hit, "transit exit applies fall and armor")
		s.close()
	var s := fixture(BattleDemoSession.new())
	s.select_unit(s.units[1].id)
	s.board.move_unit(s.units[0], Vector2i(0, 1))
	s.board.move_unit(s.units[1], Vector2i(0, 0))
	s.board.set_height_steps(Vector2i(0, 0), 6)
	s.units[1].height = 3
	# Предметная реакция должна входить в submit движения после падения.
	var f := s.preview_move(Vector2i(1, 0))
	var actual := s.move_to(Vector2i(1, 0))
	check(f.status == ActionReceipt.APPLIED and _has_event(f, &"healed") and f.events == actual.get_events() and f.snapshot_after == snapshot(s), "fall includes item healing")
	s.close()

func _hazards() -> void:
	for kind: int in 5:
		var s := fixture()
		var actor := s.units[0]
		for item: ItemInstance in s.state.get_owner(actor.id)._items.values(): item.armor_remaining = 0
		if kind in [0, 1, 4]: s.state.environment.ignite(Vector2i(1, 0))
		if kind == 1 or kind == 4: actor.vitals.set_hp(1)
		if kind == 2: s.board.set_terrain(Vector2i(1, 0), TerrainType.Type.HAZARD)
		if kind == 3:
			s.board.set_height_steps(Vector2i(0, 0), 6)
			actor.height = 3
			actor.vitals.set_hp(1)
		if kind == 4:
			for other: UnitState in [s.units[2], s.units[4]]:
				s._queue.submit(DeathCommand.new(other.id, DamageSource.new(&"test", 0, other.cell)), s.context)
		var f := parity(s, command(s), "hazard " + str(kind), ActionReceipt.APPLIED if kind == 0 else ActionReceipt.INTERRUPTED)
		if kind == 0: check(actor.vitals.get_hp() == 24 and actor.cell == Vector2i(3, 0), "nonlethal spike continues")
		else:
			check(not actor.is_alive() and actor.cell == Vector2i(1, 0) and actor.move_points_left == (2.0 if kind == 2 else 4.0) and f.traversed_path.size() == 2 and f.requested_path.size() == 4, "lethal pays executed prefix only " + str(kind))
			check(s.board.occupant_at(actor.cell) == null and _count_event(f, &"died") == 1, "single death frees occupancy")
		if kind == 1 or kind == 4: check(_count_event(f, &"corpse_created") == 1, "single corpse")
		if kind == 4:
			check(not actor.armor.in_battle, "terminal interrupted submit expires armor")
			(s as BattleTacticalSession)._check_outcome()
			check((s as BattleTacticalSession).phase == BattleTacticalSession.Phase.DEFEAT, "session evaluates defeat separately")
		s.close()

func _refusals() -> void:
	for kind: String in ["budget", "stun", "entangled", "stale", "admission", "enemy", "ally", "wall", "dead", "start", "height", "outside", "length"]:
		var s := fixture()
		var actor := s.units[0]
		var cmd := command(s)
		var reason: StringName
		match kind:
			"budget":
				actor.move_points_left = 2
				reason = &"move/insufficient_move"
			"stun":
				actor.control.stunned_turns = 1
				reason = &"control/stunned"
			"entangled":
				actor.control.entangled_turns = 1
				reason = &"control/entangled"
			"stale":
				cmd._expected_revision -= 1
				reason = &"move/stale_revision"
			"admission":
				s.context._move_rules = MoveRules.new([], 1, &"spatial_move_v1")
				reason = &"move/not_admitted"
			"enemy", "ally":
				s.board.move_unit(s.units[1 if kind == "enemy" else 2], Vector2i(3, 0))
				reason = &"move/blocked"
			"wall":
				s.board.set_terrain(Vector2i(1, 0), TerrainType.Type.WALL)
				reason = &"move/blocked"
			"dead":
				s._queue.submit(DeathCommand.new(actor.id, DamageSource.new(&"test", 0, actor.cell)), s.context)
				reason = &"move/dead_actor"
			"start":
				cmd = command(s, [Vector2i(1, 0), Vector2i(2, 0)])
				reason = &"move/start_mismatch"
			"height":
				s.board.set_height_steps(Vector2i(1, 0), 3)
				reason = &"move/height_step"
			"outside":
				cmd = command(s, [Vector2i(0, 0), Vector2i(-1, 0)])
				reason = &"move/out_of_bounds"
			"length":
				cmd = command(s, [])
				reason = &"move/path_length"
		var f := parity(s, cmd, kind, ActionReceipt.REJECTED)
		check(f.reason == reason and f.snapshot_before == f.snapshot_after, "refusal without payment " + kind)
		s.close()

func _limits() -> void:
	for kind: int in 4:
		var s := fixture()
		match kind:
			0: s._queue = ActionQueue.new(1)
			1: s._queue = ActionQueue.new(256, 1)
			2: s.context._next_command_seq = ActionContext.MAX_ID - 1
			3: s.context._next_root_id = ActionContext.MAX_ID
		var f := parity(s, command(s), "limit " + str(kind), ActionReceipt.REJECTED if kind == 3 else ActionReceipt.FAULTED)
		if kind != 3: check(not f.events.is_empty() and f.snapshot_after != f.snapshot_before, "fault retains executed prefix")
		s.close()

func _sessions_and_capabilities() -> void:
	var s := fixture() as BattleTacticalSession
	var before := snapshot(s)
	var f := s.preview_move(Vector2i(3, 0))
	var actual := s.move_to(Vector2i(3, 0))
	check(f.events == actual.get_events() and f.snapshot_after == snapshot(s), "session route parity")
	var last := s.last_receipt
	s.phase = BattleTacticalSession.Phase.ENEMY_TURN
	check(s.preview_move(Vector2i(2, 0)).reason == &"battle/input_locked" and s.last_receipt == last, "locked session preserves receipt")
	s.phase = BattleTacticalSession.Phase.PLAYER_TURN
	s.board.set_terrain(Vector2i(2, 0), TerrainType.Type.WALL)
	check(s.preview_move(Vector2i(2, 0)).reason == &"move/unreachable" and s.last_receipt == last, "unreachable session preserves receipt")
	s.close()
	s = fixture() as BattleTacticalSession
	var cmd := command(s)
	before = snapshot(s)
	for kind: int in 5:
		match kind:
			0: s.context._busy = true
			1: s._queue._busy = true
			2: s.context._faulted = true
			3: s._queue._faulted = true
			4: s.context._rng = NoCloneRng.new()
		f = MoveForecast.build(s.context, s._queue, cmd)
		check(f.status == ActionReceipt.REJECTED and f.units.is_empty() and snapshot(s) == before, "capability refusal " + str(kind))
		s.context._busy = false
		s.context._faulted = false
		s._queue._busy = false
		s._queue._faulted = false
	check(f.reason == &"preview/rng_not_cloneable", "unknown RNG refused")
	s.context._rng = ActionRngPort.new()
	check(MoveForecast.build(s.context, s._queue, UnknownMove.new()).reason == &"preview/unsupported_command", "subclass refused")
	check(MoveForecast.build(s.context, s._queue, GuardCommand.new()).reason == &"preview/unsupported_command", "other command refused")
	var continuation := MoveCommand._make_continuation(cmd, 2, s.units[0])
	check(MoveForecast.build(s.context, s._queue, continuation).reason == &"move/internal_continuation", "internal continuation refused")
	s.context._unsupported_runtime_ids = [&"unknown"]
	check(MoveForecast.build(s.context, s._queue, cmd).status == ActionReceipt.REJECTED, "unsupported runtime refused")
	s.close()

func _restore_cleanup() -> void:
	var s := fixture()
	var before := snapshot(s)
	var f := s.preview_move(Vector2i(3, 0))
	var expected := f.snapshot_after.duplicate(true)
	var decoded := ItemSimulationSnapshot.from_dict(expected)
	check(decoded.code == ItemSnapshotResult.Code.OK, "forecast snapshot decodes")
	var definitions: Dictionary = {}
	for owner in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK, "forecast restores")
	if restored.state != null:
		restored.state.get_board().get_unit_by_id(s.selected_id).vitals.set_hp(1)
		check(snapshot(s) == before and f.snapshot_after == expected, "restore independent")
		ForecastSimulation.close(restored.state)
	f.units[s.selected_id]["after"]["hp"] = -100
	f.snapshot_after.clear()
	f.traversed_path.clear()
	f.requested_path.clear()
	check(s.preview_move(Vector2i(3, 0)).snapshot_after == expected and snapshot(s) == before, "DTO independent")
	for index: int in 15:
		s._queue = ActionQueue.new(1 if index % 3 == 2 else 256)
		var cmd := command(s)
		if index % 3 == 1: cmd._expected_revision -= 1
		f = MoveForecast.build(s.context, s._queue, cmd)
		check(f.status == [ActionReceipt.APPLIED, ActionReceipt.REJECTED, ActionReceipt.FAULTED][index % 3], "cleanup branch " + str(index))
	check(snapshot(s) == before, "cleanup leaves live intact")
	s.close()

func _helpers() -> void:
	var s := fixture(CustomSession.new()) as BattleTacticalSession
	var actor := s.selected_unit()
	var summon := s.use_summoning_item(Vector2i(1, 0))
	var helper := s.state.active_summon(actor.id)
	check(summon.status == ActionReceipt.APPLIED and helper != null, "custom helper fixture")
	if helper == null:
		s.close()
		return
	var cmd := MoveCommand.new(helper.id, [Vector2i(1, 0), Vector2i(2, 0)], s.context.get_revision())
	var before := snapshot(s)
	var f := MoveForecast.build(s.context, s._queue, cmd)
	check(f.reason == &"move/not_admitted" and f.units.is_empty() and snapshot(s) == before, "pending helper rejected without refill")
	var receipt := s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
	check(receipt.status == ActionReceipt.APPLIED and not s.state.is_summon_pending(helper.id), "helper joins via real team refill")
	s.select_unit(helper.id)
	before = snapshot(s)
	var admission := SummonAdmission.values(s.context)
	var id_counter := UnitId.get_counter()
	f = s.preview_move(Vector2i(2, 0))
	check(f.status == ActionReceipt.APPLIED and snapshot(s) == before and SummonAdmission.values(s.context) == admission and UnitId.get_counter() == id_counter, "ready custom helper preview isolated")
	receipt = s.move_to(Vector2i(2, 0))
	check(receipt.get_events() == f.events and receipt.get_steps() == f.steps and snapshot(s) == f.snapshot_after and f.admission_after == SummonAdmission.values(s.context), "custom helper complete parity")
	check(s.state.active_summon(actor.id) == helper and helper.vitals.get_hp() == 21 and helper.cell == Vector2i(2, 0), "helper identity ownership and custom definition survive")
	s.close()

func _has_event(f: MoveForecast, kind: StringName) -> bool: return _count_event(f, kind) > 0

func _count_event(f: MoveForecast, kind: StringName) -> int:
	var result: int = 0
	for event: Dictionary in f.events:
		if event["kind"] == kind: result += 1
	return result
