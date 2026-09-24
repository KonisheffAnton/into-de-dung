extends SceneTree

var passed: int = 0
var failed: int = 0

class DerivedRaiseCommand extends RaiseCorpseCommand:
	func validate(_context: ActionContext) -> StringName:
		push_error("Unsupported derived command must never execute")
		return &""

class TrackingRng extends ActionRngPort:
	var cursor: int = 29
	func clone() -> ActionRngPort:
		var copy := TrackingRng.new()
		copy.cursor = cursor
		return copy
	func to_dict() -> Dictionary: return {"cursor": cursor}

class NoCloneRng extends ActionRngPort:
	func to_dict() -> Dictionary: return {"cursor": 4}

class AliasRng extends ActionRngPort:
	func clone() -> ActionRngPort: return self

class WrongRng extends TrackingRng:
	func clone() -> ActionRngPort:
		var copy := WrongRng.new()
		copy.cursor = 0
		return copy

class CountingSink extends ActionEventSink:
	var calls: int = 0
	func publish(_event: Dictionary) -> void: calls += 1

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL RAISE FORECAST: " + label)

func snapshot(session: BattleEnvironmentSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return capture.snapshot.to_dict() if capture.code == ItemSnapshotResult.Code.OK else {}

func fixture() -> BattleEnvironmentSession:
	var session := BattleEnvironmentSession.new()
	session.context._rng = TrackingRng.new()
	session.context._revision = 13
	session.context._next_root_id = 7
	session.context._next_command_seq = 31
	session.context._next_event_seq = 41
	return session

func corpse_command(session: BattleEnvironmentSession, corpse_id: int = 1, actor_id: int = -1, revision: int = -1) -> RaiseCorpseCommand:
	return RaiseCorpseCommand.new(session.selected_id if actor_id < 0 else actor_id, corpse_id, session.context.get_revision() if revision < 0 else revision)

func definitions(session: BattleEnvironmentSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _run() -> void:
	_success_and_isolation()
	_refusals_and_gates()
	_capabilities_and_limits()
	_restore_and_cleanup()
	print("RAISE FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _success_and_isolation() -> void:
	var session := fixture()
	var actor := session.selected_unit()
	var fallen := session.units[2]
	check(session.board.move_unit(fallen, Vector2i(0, 3)), "place second body at target")
	var second_death := session._queue.submit(DeathCommand.new(fallen.id, DamageSource.new(&"test", 0, fallen.cell)), session.context)
	check(second_death.status == ActionReceipt.APPLIED, "create second body through death command")
	var target_corpses := session.state.environment.corpses_at(Vector2i(0, 3))
	var lowest_id: int = target_corpses[0]["id"]
	var before := snapshot(session)
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var counters := session.context.simulation_counters()
	var admission := SummonAdmission.values(session.context)
	var id_counter := UnitId.get_counter()
	var last := session.last_receipt
	var flow_log := session.flow_log.duplicate()
	var queue := session._queue
	var sink := CountingSink.new()
	session.context._sink = sink
	var actor_hp_signal: Array[int] = []
	var board_signal: Array[int] = []
	var on_hp := func(_old: float, _new: float) -> void: actor_hp_signal.append(1)
	var on_board := func() -> void: board_signal.append(1)
	actor.vitals.hp_changed.connect(on_hp)
	session.board.board_changed.connect(on_board)
	var first := session.preview_raise_corpse(Vector2i(0, 3))
	var second := session.preview_raise_corpse(Vector2i(0, 3))
	check(first.status == ActionReceipt.APPLIED, "D5 raise preview applies: " + String(first.reason))
	check(first.actor_id == actor.id and first.corpse_id == lowest_id, "select first humanoid in ID order")
	check(first.snapshot_before == before and first.snapshot_before == second.snapshot_before and first.admission_before == admission, "complete before values")
	check(first.events == second.events and first.steps == second.steps and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after and first.admission_after == second.admission_after and first.units == second.units and first.corpses == second.corpses, "repeat previews identical")
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and SummonAdmission.values(session.context) == admission, "live state/RNG/counters/admission isolated")
	check(UnitId.get_counter() == id_counter and session.last_receipt == last and session.flow_log == flow_log and session._queue == queue and sink.calls == 0 and actor_hp_signal.is_empty() and board_signal.is_empty(), "allocator/session/queue/sink/signals isolated")
	var helper_id := UseSummoningItemCommand.next_id(session.board)
	check(first.units.has(helper_id) and first.units[helper_id]["before"] == null, "new helper has absent before")
	if first.units.has(helper_id):
		var helper: Dictionary = first.units[helper_id]["after"]
		check(helper["id"] == helper_id and helper["owner_unit_id"] == actor.id and helper["pending"], "helper identity and owner")
		check(helper["hp"] == 16.0 and helper["main"] == 0 and helper["bonus"] == 0 and helper["move"] == 0.0 and helper.has("armor_state"), "helper template and pending action resources: " + str(helper))
	var actor_after: Dictionary = first.units[actor.id]["after"]
	check(actor_after["main"] == 0 and actor_after["bonus"] == actor.action_resources.get_bonus_left() and actor_after["move"] == actor.move_points_left, "only one main action spent")
	check(first.corpses.size() == 1 and first.corpses.has(lowest_id) and first.corpses[lowest_id]["before"] != null and first.corpses[lowest_id]["after"] == null, "only consumed min-ID corpse reported")
	check(first.snapshot_after["environment"]["corpses"].size() == target_corpses.size() - 1, "other bodies remain")
	var receipt := session._queue.submit(corpse_command(session, lowest_id), session.context)
	check(receipt.status == first.status and receipt.reason == first.reason and receipt.get_events() == first.events and receipt.get_steps() == first.steps, "live receipt matches forecast")
	check(snapshot(session) == first.snapshot_after and session.context.get_rng().to_dict() == first.rng_after and session.context.simulation_counters() == first.counters_after and SummonAdmission.values(session.context) == first.admission_after, "live result matches forecast state")
	check(sink.calls == receipt.get_events().size(), "only live submit publishes events")
	actor.vitals.hp_changed.disconnect(on_hp)
	session.board.board_changed.disconnect(on_board)
	session.close()
	var k2 := BattleCoreCombinationSession.new()
	var k2_before := snapshot(k2)
	var k2_forecast := k2.preview_raise_corpse(Vector2i(0, 3))
	var k2_receipt := k2._queue.submit(k2._raise_command(Vector2i(0, 3)), k2.context)
	check(k2_forecast.status == ActionReceipt.APPLIED and k2_receipt.status == k2_forecast.status, "K2 raise preview/live success")
	check(k2_forecast.snapshot_before == k2_before and k2_receipt.get_events() == k2_forecast.events and k2_receipt.get_steps() == k2_forecast.steps and snapshot(k2) == k2_forecast.snapshot_after, "K2 complete parity")
	k2.close()

func _refusals_and_gates() -> void:
	var session := fixture()
	var before := snapshot(session)
	var last := session.last_receipt
	var flow_log := session.flow_log.duplicate()
	var no_corpse := session.preview_raise_corpse(Vector2i(7, 7))
	check(no_corpse.status == ActionReceipt.REJECTED and no_corpse.reason == &"environment/no_corpse", "no corpse refusal")
	check(snapshot(session) == before and session.last_receipt == last and session.flow_log == flow_log, "no corpse refusal is pure")
	var command := corpse_command(session)
	var actor := session.selected_unit()
	actor.action_resources.try_spend_main(1)
	var no_main := RaiseCorpseForecast.build(session.context, session._queue, command)
	check(no_main.reason == &"item/insufficient_main" and no_main.units.is_empty() and no_main.corpses.is_empty(), "main action required")
	session.close()

	var modes: Array[String] = ["phase", "transition", "context_busy", "context_fault", "queue_busy", "queue_fault"]
	for mode: String in modes:
		session = fixture()
		before = snapshot(session)
		last = session.last_receipt
		match mode:
			"phase": session.phase = BattleTacticalSession.Phase.ENEMY_TURN
			"transition": session._transitioning = true
			"context_busy": session.context._busy = true
			"context_fault": session.context._faulted = true
			"queue_busy": session._queue._busy = true
			"queue_fault": session._queue._faulted = true
		var blocked := session.preview_raise_corpse(Vector2i(0, 3))
		var expected_reason: StringName = &"BUSY" if mode == "queue_busy" else (&"CONTEXT_FAULTED" if mode == "queue_fault" else &"battle/input_locked")
		check(blocked.status == ActionReceipt.REJECTED and blocked.reason == expected_reason, "session gate " + mode + ": " + String(blocked.reason))
		check(snapshot(session) == before and session.last_receipt == last and session.context.get_rng().to_dict() == TrackingRng.new().to_dict(), "gate does not mutate state " + mode)
		session.close()
	session = fixture()
	var base_command := corpse_command(session)
	var stale := RaiseCorpseForecast.build(session.context, session._queue, corpse_command(session, 1, -1, session.context.get_revision() + 1))
	check(stale.status == ActionReceipt.REJECTED and stale.reason == &"environment/stale_revision", "stale revision refusal")
	var bad_cell := session.state.environment.corpses[0]
	bad_cell["cell"] = Vector2i(7, 7)
	var invalid_cell := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(invalid_cell.reason == &"environment/corpse_reference", "invalid environment position refused: " + String(invalid_cell.reason))
	session.state.environment.corpses[0]["cell"] = Vector2i(0, 3)
	session.state.environment.ignite(Vector2i(0, 3))
	var fire_cell := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(fire_cell.reason == &"environment/invalid_raise_cell", "fire target refused")
	session.state.environment.fires.clear()
	session.board.set_height_steps(Vector2i(0, 3), 1)
	var height_cell := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(height_cell.reason == &"environment/invalid_raise_cell", "height mismatch refused")
	session.board.set_height_steps(Vector2i(0, 3), 0)
	session.board.move_unit(session.units[2], Vector2i(0, 3))
	var occupied_cell := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(occupied_cell.reason == &"environment/invalid_raise_cell", "occupied target refused")
	session.board.move_unit(session.units[2], Vector2i(2, 5))
	actor = session.selected_unit()
	actor.control = ControlState.new()
	actor.control.stunned_turns = 1
	var controlled := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(controlled.reason == &"control/stunned", "control refusal")
	actor.control = null
	session.context._move_rules = MoveRules.new([])
	var unadmitted := RaiseCorpseForecast.build(session.context, session._queue, base_command)
	check(unadmitted.reason == &"item/not_admitted", "missing admission refusal")
	session.close()

	for active_helper: bool in [false, true]:
		session = fixture()
		var first_raise := session._queue.submit(corpse_command(session), session.context)
		var actor_id := session.selected_id
		var target_actor_id := actor_id
		var helper := session.state.active_summon(actor_id)
		if not active_helper and helper != null: target_actor_id = helper.id
		var helper_refusal := RaiseCorpseForecast.build(session.context, session._queue, corpse_command(session, 1, target_actor_id))
		check(first_raise.status == ActionReceipt.APPLIED, "setup helper for refusal")
		var helper_expected: StringName = &"summon/active_helper" if active_helper else &"summon/helper_cannot_summon"
		check(helper_refusal.reason == helper_expected, "helper guard refusal: " + String(helper_refusal.reason))
		session.close()

func _capabilities_and_limits() -> void:
	var session := fixture()
	check(RaiseCorpseForecast.build(session.context, session._queue, AttackCommand.new()).reason == &"preview/unsupported_command", "unsupported command")
	check(RaiseCorpseForecast.build(session.context, session._queue, DerivedRaiseCommand.new()).reason == &"preview/unsupported_command", "unsupported command subclass")
	var cmd := corpse_command(session)
	session.context._unsupported_runtime_ids = [&"unknown/status"]
	var unknown := RaiseCorpseForecast.build(session.context, session._queue, cmd)
	check(unknown.status == ActionReceipt.REJECTED and unknown.reason == &"unsupported_runtime_ids" and unknown.units.is_empty() and unknown.corpses.is_empty(), "unknown runtime fails closed: " + String(unknown.reason))
	session.context._unsupported_runtime_ids.clear()
	for rng: ActionRngPort in [NoCloneRng.new(), AliasRng.new(), WrongRng.new()]:
		session.context._rng = rng
		var forecast := RaiseCorpseForecast.build(session.context, session._queue, cmd)
		check(forecast.status == ActionReceipt.REJECTED and forecast.reason in [&"preview/rng_not_cloneable", &"preview/rng_state_mismatch"], "RNG capability fails closed")
	session.context._rng = TrackingRng.new()
	var valid_rng := RaiseCorpseForecast.build(session.context, session._queue, cmd)
	check(valid_rng.status == ActionReceipt.APPLIED, "cloneable RNG accepted")
	session.close()

	for limit: String in ["command", "event", "root", "command_seq", "event_seq"]:
		session = fixture()
		match limit:
			"command": session._queue = ActionQueue.new(0, 512, 32)
			"event": session._queue = ActionQueue.new(256, 0, 32)
			"root": session.context._next_root_id = ActionContext.MAX_ID
			"command_seq": session.context._next_command_seq = ActionContext.MAX_ID
			"event_seq": session.context._next_event_seq = ActionContext.MAX_ID - 1
		var limit_forecast := RaiseCorpseForecast.build(session.context, session._queue, corpse_command(session))
		var expected_reason: StringName = &"invalid_limits" if limit in ["command", "event"] else &"sequence_exhausted"
		check(limit_forecast.status == ActionReceipt.REJECTED and limit_forecast.reason == expected_reason, "limit refusal " + limit + ": " + String(limit_forecast.reason))
		check(limit_forecast.units.is_empty() and limit_forecast.corpses.is_empty(), "limit never publishes ready values " + limit)
		session.close()
	# Подъём — одна атомарная команда без реакций. FAULTED prefix достигается только
	# при terminal cleanup: после подъёма очередь должна добавить ArmorEndBattle команды.
	session = fixture()
	for enemy in session.board.get_all_units():
		if enemy.faction == Faction.Type.ENEMY and enemy.is_alive():
			var death := session._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test", 0, enemy.cell)), session.context)
			check(death.status == ActionReceipt.APPLIED, "terminal setup death")
	session._queue = ActionQueue.new(1, 512, 32)
	var terminal_before := snapshot(session)
	var terminal_rng := session.context.get_rng().to_dict().duplicate(true)
	var terminal_counters := session.context.simulation_counters()
	var terminal_admission := SummonAdmission.values(session.context)
	var terminal_fault := session.preview_raise_corpse(Vector2i(0, 3))
	check(terminal_fault.status == ActionReceipt.FAULTED and terminal_fault.reason == &"command_limit", "terminal cleanup reaches fault: " + String(terminal_fault.reason))
	check(terminal_fault.units.is_empty() and terminal_fault.corpses.is_empty(), "faulted raise does not publish ready values")
	check(not terminal_fault.events.is_empty() and not terminal_fault.steps.is_empty() and not terminal_fault.snapshot_after.is_empty() and terminal_fault.snapshot_after != terminal_fault.snapshot_before, "fault retains complete applied prefix")
	check(terminal_fault.snapshot_before == terminal_before, "terminal fault before snapshot")
	var terminal_receipt := session._queue.submit(corpse_command(session), session.context)
	check(terminal_receipt.status == terminal_fault.status and terminal_receipt.reason == terminal_fault.reason and terminal_receipt.get_events() == terminal_fault.events and terminal_receipt.get_steps() == terminal_fault.steps, "terminal fault live receipt parity")
	check(snapshot(session) == terminal_fault.snapshot_after and session.context.get_rng().to_dict() == terminal_fault.rng_after and session.context.simulation_counters() == terminal_fault.counters_after and SummonAdmission.values(session.context) == terminal_fault.admission_after, "terminal fault live prefix snapshot/RNG/counter/admission parity")
	check(terminal_fault.rng_after == terminal_rng and terminal_fault.admission_before == terminal_admission and terminal_fault.counters_after != terminal_counters, "terminal fault outcome values")
	session.close()

func _restore_and_cleanup() -> void:
	var session := fixture()
	var before := snapshot(session)
	var first := session.preview_raise_corpse(Vector2i(0, 3))
	var immutable_expected := first.snapshot_after.duplicate(true)
	var decoded := ItemSimulationSnapshot.from_dict(first.snapshot_after)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.to_dict() == immutable_expected, "forecast snapshot decodes canonically")
	var restored := decoded.snapshot.instantiate(definitions(session))
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null, "forecast snapshot restores independently")
	if restored.state != null:
		restored.state.environment.corpses.clear()
		restored.state.get_board().get_unit_by_id(first.actor_id).vitals.set_hp(1.0)
		check(snapshot(session) == before and first.snapshot_after == immutable_expected, "restored runtime isolated from live/DTO")
		ForecastSimulation.close(restored.state)
	first.snapshot_after["environment"]["corpses"].clear()
	first.units[first.actor_id]["after"]["hp"] = -100.0
	first.events.clear()
	first.steps.clear()
	first.admission_after.clear()
	first.corpses.clear()
	check(session.preview_raise_corpse(Vector2i(0, 3)).snapshot_after == immutable_expected and snapshot(session) == before, "mutated DTO cannot affect next preview")
	session.close()
	for index: int in 12:
		session = fixture()
		var cell := Vector2i(0, 3) if index % 3 != 1 else Vector2i(7, 7)
		if index % 3 == 2: session._queue = ActionQueue.new(0, 1, 1)
		var forecast := session.preview_raise_corpse(cell)
		var expected_status: StringName = ActionReceipt.APPLIED if index % 3 == 0 else ActionReceipt.REJECTED
		check(forecast.status == expected_status, "cleanup path " + str(index) + ": " + String(forecast.reason))
		check(session.state.environment.corpses.size() == 1 and session.selected_unit() != null, "cleanup preserves live session " + str(index))
		session.close()
	session.close()
