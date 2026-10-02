extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

const Forecast = preload("res://scripts/demo/turn_forecast.gd")
const Worker = preload("res://scripts/demo/turn_forecast_worker.gd")
var passed: int = 0
var failed: int = 0

class TracedSession extends BattleCoreReactionsSession:
	var trace: Array[Dictionary] = []
	func _record_receipt(receipt: ActionReceipt) -> void:
		trace.append({"status": receipt.status, "reason": receipt.reason, "events": receipt.get_events(), "steps": receipt.get_steps()})

class UnsupportedRng extends ActionRngPort:
	func clone() -> ActionRngPort: return UnsupportedRng.new()
	func to_dict() -> Dictionary: return {"unknown": true}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL TURN FORECAST: " + label)

func _unknown_health_callback(_old_hp: float, _new_hp: float) -> void:
	pass

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return capture.snapshot.to_dict() if capture.code == ItemSnapshotResult.Code.OK else {}

func _install_prepared(session: BattleCoreReactionsSession, prepared: Forecast.Prepared) -> bool:
	var restored := prepared.snapshot.instantiate(prepared.definitions)
	if restored.code != ItemSnapshotResult.Code.OK: return false
	session.board = restored.state.get_board()
	session.state = restored.state
	session.units = session.board.get_all_units()
	session.context = prepared.context
	session.context._state = session.state
	session._queue = prepared.queue
	session.phase = prepared.phase
	session.round_number = prepared.round_number
	session.selected_id = prepared.selected_id
	session.rune_selected = prepared.rune_selected
	session.entangle_selected = prepared.entangle_selected
	session.stun_selected = prepared.stun_selected
	session.deployment_enabled = prepared.deployment_enabled
	session._setup_revision = prepared.setup_revision
	session._enemy_ids = prepared.enemy_ids.duplicate()
	session._enemy_index = prepared.enemy_index
	session._enemy_actions = prepared.enemy_actions
	return true

func _parity_and_worker() -> void:
	var session := PlayerTurnFixture.create()
	var before := _snapshot(session)
	var counters := session.context.simulation_counters()
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var allocator := UnitId.get_counter()
	var first := Forecast.build(session)
	var second := Forecast.build(session)
	check(first.status == ActionReceipt.APPLIED and first.phase_after == BattleTacticalSession.Phase.ENEMY_TURN and first.transitioned, "boundary predicts enemy phase")
	check(first.events.any(func(event: Dictionary) -> bool: return event.get("kind") == &"environment_turn") and int(first.rng_after.get("draws", -1)) == int(rng.get("draws", 0)) + 1, "boundary includes the environment root and its single random draw")
	check(first.receipts == second.receipts and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after, "two previews are deterministic")
	check(session.context.simulation_counters() == counters and session.context.get_rng().to_dict() == rng and _snapshot(session) == before and UnitId.get_counter() == allocator, "previews preserve live state and allocator")
	var traced := TracedSession.new(false)
	var trace_package := Forecast.prepare(session)
	check(trace_package.reason == &"" and _install_prepared(traced, trace_package), "detached trace fixture restored")
	if trace_package.reason == &"":
		traced.end_player_turn()
		check(first.receipts == traced.trace, "every root receipt status/events/steps match live flow")
		traced.close()
	check(first.status == ActionReceipt.APPLIED and session.end_player_turn(), "live transition applies")
	check(first.snapshot_after == _snapshot(session) and first.counters_after == session.context.simulation_counters() and first.rng_after == session.context.get_rng().to_dict(), "prediction matches live snapshot/counters/RNG")
	check(first.events == session.turn_events + session.last_receipt.get_events(), "all boundary events match live receipts")
	check(first.admission_after == SummonAdmission.values(session.context), "summon admission matches live result")
	var prepared := Forecast.prepare(session)
	check(prepared.reason == &"turn/unsupported_phase", "enemy phase cannot prepare player boundary")
	session.close()

	var worker_session := PlayerTurnFixture.create()
	var expected := Forecast.build(worker_session)
	var worker := Worker.new()
	worker.start(Forecast.prepare(worker_session))
	var deadline := Time.get_ticks_msec() + 5000
	var actual: TurnForecast
	while Time.get_ticks_msec() < deadline and actual == null:
		actual = worker.take_finished()
		if actual == null: await create_timer(0.002).timeout
	check(actual != null and actual.receipts == expected.receipts and actual.snapshot_after == expected.snapshot_after and actual.counters_after == expected.counters_after, "worker matches synchronous forecast")
	worker.close()
	check(not worker.is_started(), "worker close joins execution")
	worker_session.close()

func _early_victory_and_fault_prefix() -> void:
	var terminal := PlayerTurnFixture.create()
	for id: int in [terminal.units[3].id, terminal.units[5].id]:
		terminal._queue.submit(DeathCommand.new(id, DamageSource.new(&"test", 0, terminal.board.get_unit_by_id(id).cell)), terminal.context)
	var last_enemy := terminal.board.get_unit_by_id(terminal.units[1].id)
	last_enemy.vitals.set_hp(1.0)
	last_enemy.bleeding.ticks_left = 1
	last_enemy.bleeding.stacks = 1
	last_enemy.bleeding.source = DamageSource.new(&"attack", 0, terminal.units[0].cell, terminal.units[0].id, terminal.units[0].id).to_dict()
	var before_root := int(terminal.context.simulation_counters()["next_root_id"])
	last_enemy.bleeding.hit_id = "turn-forecast-last-bleed"
	var forecast := Forecast.build(terminal)
	check(forecast.status == ActionReceipt.APPLIED and forecast.phase_after == BattleTacticalSession.Phase.VICTORY and forecast.transitioned, "last enemy bleed predicts victory")
	check(int(forecast.counters_after["next_root_id"]) > before_root + 1, "terminal boundary records environment before lethal enemy tick")
	terminal.close()

	var faulted := PlayerTurnFixture.create()
	faulted.units[1].control.stunned_turns = 1
	faulted.units[3].control.entangled_turns = 1
	faulted._queue._max_commands = 1
	var prefix := Forecast.build(faulted)
	check(prefix.status == ActionReceipt.FAULTED and not prefix.steps.is_empty() and not prefix.snapshot_after.is_empty(), "command limit fault keeps executed prefix")
	check(prefix.units_after.size() == prefix.units_before.size(), "fault result retains unit prefix values")
	var fault_trace := TracedSession.new(false)
	var fault_package := Forecast.prepare(faulted)
	check(fault_package.reason == &"" and _install_prepared(fault_trace, fault_package), "fault trace fixture restored")
	if fault_package.reason == &"":
		fault_trace.end_player_turn()
		check(fault_trace.trace == prefix.receipts and _snapshot(fault_trace) == prefix.snapshot_after, "fault receipt and snapshot prefix match live flow")
		fault_trace.close()
	faulted.close()

func _rejections_and_detachment() -> void:
	var session := PlayerTurnFixture.create()
	session.deployment_enabled = true
	check(Forecast.prepare(session).reason == &"", "deployment opt-in setting does not reject player phase")
	session.phase = BattleTacticalSession.Phase.DEPLOYMENT
	check(Forecast.build(session).reason == &"turn/unsupported_phase", "active deployment rejected")
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.context._busy = true
	check(Forecast.build(session).reason == &"BUSY", "busy session rejected")
	session.context._busy = false
	session.context._faulted = true
	check(Forecast.build(session).reason == &"CONTEXT_FAULTED", "faulted session rejected")
	session.context._faulted = false
	session.context._unsupported_runtime_ids.append(&"unknown_callback")
	check(Forecast.build(session).reason != &"", "unsupported runtime is rejected")
	session.context._unsupported_runtime_ids.clear()
	var hp_signal := session.units[0].vitals.hp_changed
	var callback := Callable(self, "_unknown_health_callback")
	hp_signal.connect(callback)
	check(Forecast.prepare(session).reason == &"turn/unsupported_runtime", "unknown signal callback is rejected")
	hp_signal.disconnect(callback)
	var known_rng := session.context.get_rng()
	session.context._rng = UnsupportedRng.new()
	var rejected_rng := Forecast.prepare(session)
	check(rejected_rng.reason == &"turn/unsupported_runtime", "unknown RNG runtime is rejected")
	session.context._rng = known_rng
	var rejection_worker := Worker.new()
	rejection_worker.start(rejected_rng)
	check(rejection_worker.take_finished().reason == &"turn/unsupported_runtime", "worker returns prepared rejection")
	rejection_worker.start(rejected_rng)
	check(rejection_worker.take_finished().reason == &"preview/request_consumed", "worker consumes rejected package once")
	var prepared := Forecast.prepare(session)
	check(prepared.reason == &"", "prepared detached package available")
	if prepared.reason == &"":
		var live_definition: ItemDef = session.state.get_owners()[0]._definitions.values()[0]
		var detached: ItemDef = prepared.definitions[live_definition.id]
		check(detached != live_definition, "definitions are detached resources")
		var unit_counter := UnitId.get_counter()
		var value := Forecast.run_prepared(prepared)
		check(UnitId.get_counter() == unit_counter and not value.snapshot_after.is_empty(), "snapshot restoration does not allocate global unit IDs")
		check(Forecast.run_prepared(prepared).reason == &"preview/request_consumed", "prepared request is one-shot")
	session.close()

func _summon_and_enemy_refill() -> void:
	var session := PlayerTurnFixture.create()
	var actor := session.board.get_unit_by_id(session.selected_id)
	var summon := session.use_summoning_item(Vector2i(0, 1))
	check(summon.status == ActionReceipt.APPLIED, "real summon command applied")
	var helper := session.state.active_summon(actor.id)
	var helper_id: int = helper.id if helper != null else 0
	check(helper_id > 0 and session.state.is_summon_pending(helper_id), "new helper remains pending through player turn")
	var enemy := session.board.get_unit_by_id(session.units[1].id)
	enemy.action_resources.try_spend_main(1)
	enemy.guard_stance = true
	enemy.combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
	enemy.action_resources._set_for_refill(enemy.action_resources.get_main_left(), 0)
	var before := _snapshot(session)
	var selected_before := session.selected_id
	var receipt_before := session.last_receipt
	var forecast := Forecast.build(session)
	check(forecast.status == ActionReceipt.APPLIED and forecast.phase_after == BattleTacticalSession.Phase.ENEMY_TURN, "summon boundary is admitted")
	check(forecast.units_before[helper_id]["pending"] and forecast.units_after[helper_id]["pending"], "pending helper stays pending through the other team turn")
	check(not forecast.units_after[enemy.id]["guard_stance"] and not forecast.admission_after["movers"].has(helper_id), "enemy guard resets without admitting pending helper")
	check(_snapshot(session) == before and session.phase == BattleTacticalSession.Phase.PLAYER_TURN and session.selected_id == selected_before and session.last_receipt == receipt_before, "build preserves live phase/selection/last receipt")
	check(session.end_player_turn(), "live summon boundary transitions")
	check(forecast.snapshot_after == _snapshot(session) and forecast.admission_after == SummonAdmission.values(session.context), "pending helper and admission match live transition")
	check(session.state.is_summon_pending(helper_id) and enemy.guard_stance == false and enemy.action_resources.get_bonus_left() == 1, "live enemy refill resets stance and restores reaction charge")
	session.close()

func run() -> void:
	await _parity_and_worker()
	_early_victory_and_fault_prefix()
	_rejections_and_detachment()
	_summon_and_enemy_refill()
	print("TURN FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
