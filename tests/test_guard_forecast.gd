extends SceneTree

var passed: int = 0
var failed: int = 0

class DerivedGuardCommand extends GuardCommand:
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
		printerr("FAIL GUARD FORECAST: " + label)

func snapshot(session: BattleTacticalSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return capture.snapshot.to_dict() if capture.code == ItemSnapshotResult.Code.OK else {}

func definitions(session: BattleTacticalSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _run() -> void:
	var session := BattleTacticalSession.new()
	var actor := session.selected_unit()
	var before := snapshot(session)
	var rng := session.context.get_rng().to_dict()
	var counters := session.context.simulation_counters()
	var id_counter := UnitId.get_counter()
	var prior_receipt := ActionReceipt.new()
	session.last_receipt = prior_receipt
	var prior_flow := session.flow_log.duplicate()
	var queue_identity := session._queue
	var sink := CountingSink.new()
	session.context._sink = sink
	var hp_signals: Array[int] = []
	var board_signals: Array[int] = []
	var on_hp := func(_old: float, _new: float) -> void: hp_signals.append(1)
	var on_board := func() -> void: board_signals.append(1)
	actor.vitals.hp_changed.connect(on_hp)
	session.board.board_changed.connect(on_board)
	var forecast := session.preview_guard()
	var repeat := session.preview_guard()
	check(forecast.status == ActionReceipt.APPLIED, "guard preview applies: " + String(forecast.reason))
	check(forecast.actor_id == actor.id and forecast.units.has(actor.id), "actor and unit DTO present")
	check(forecast.snapshot_before == before, "before snapshot captured")
	check(forecast.units == repeat.units and forecast.events == repeat.events and forecast.steps == repeat.steps and forecast.snapshot_after == repeat.snapshot_after and forecast.rng_after == repeat.rng_after and forecast.counters_after == repeat.counters_after and forecast.admission_before == repeat.admission_before and forecast.admission_after == repeat.admission_after, "repeated previews match")
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and SummonAdmission.values(session.context) == forecast.admission_before, "preview leaves live state unchanged")
	check(UnitId.get_counter() == id_counter and session.last_receipt == prior_receipt and session.flow_log == prior_flow and session._queue == queue_identity and sink.calls == 0 and hp_signals.is_empty() and board_signals.is_empty(), "preview leaves allocator/session/sink/signals unchanged")
	check(forecast.units[actor.id]["before"]["main"] == 1 and forecast.units[actor.id]["after"]["main"] == 0 and forecast.units[actor.id]["after"]["guard_stance"], "guard spends one main and sets stance")
	check(forecast.units[actor.id]["after"]["bonus"] == actor.action_resources.get_bonus_left() and forecast.units[actor.id]["after"]["move"] == actor.move_points_left, "other resources preserved")
	var unchanged_units: bool = true
	for id: int in forecast.units:
		if id != actor.id and forecast.units[id]["before"] != forecast.units[id]["after"]: unchanged_units = false
	check(unchanged_units, "non-actor unit capabilities are unchanged")
	var receipt := session.guard_selected()
	actor.vitals.hp_changed.disconnect(on_hp)
	session.board.board_changed.disconnect(on_board)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "live receipt matches forecast")
	check(snapshot(session) == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after and SummonAdmission.values(session.context) == forecast.admission_after, "live final state matches forecast")
	var active := session.preview_guard()
	check(active.reason == &"guard/already_active" and active.units.is_empty(), "already guarded refused")
	var unsupported := GuardForecast.build(session.context, session._queue, DerivedGuardCommand.new(actor.id, session.context.get_revision()))
	check(unsupported.reason == &"preview/unsupported_command", "subclass refused without executing")
	check(GuardForecast.build(session.context, session._queue, AttackCommand.new()).reason == &"preview/unsupported_command", "other command refused")
	var detached := repeat
	forecast.units[actor.id]["after"]["guard_stance"] = false
	check(detached.units[actor.id]["after"]["guard_stance"] and snapshot(session) == detached.snapshot_after, "DTO mutation is isolated")
	var decoded := ItemSimulationSnapshot.from_dict(detached.snapshot_after)
	var restored := decoded.snapshot.instantiate(definitions(session)) if decoded.code == ItemSnapshotResult.Code.OK else ItemSnapshotResult.new()
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null and restored.state.get_board().get_unit_by_id(actor.id).guard_stance, "forecast snapshot restores guarded state: %s / %s" % [str(restored.code), restored.reason])
	if restored.state != null: ForecastSimulation.close(restored.state)
	session.close()
	session = BattleTacticalSession.new()
	actor = session.selected_unit()
	session._queue._busy = true
	check(session.preview_guard().reason == &"BUSY", "busy queue rejected: " + String(session.preview_guard().reason))
	session._queue._busy = false
	actor.action_resources._set_for_refill(0, 1)
	check(session.preview_guard().reason == &"guard/insufficient_main", "bonus does not replace main")
	check(GuardForecast.build(session.context, session._queue, GuardCommand.new(actor.id, session.context.get_revision() - 1)).reason == &"guard/stale_revision", "stale rejected")
	session.context._busy = true
	check(session.preview_guard().reason == &"battle/input_locked", "session busy input gate")
	check(GuardForecast.build(session.context, session._queue, GuardCommand.new(actor.id, session.context.get_revision())).reason == &"BUSY", "busy context rejected by core")
	session.context._busy = false
	session.context._faulted = true
	check(session.preview_guard().reason == &"battle/input_locked", "faulted session input gate")
	session.context._faulted = false
	session._transitioning = true
	check(session.preview_guard().reason == &"battle/input_locked", "transition gate refuses preview")
	session._transitioning = false
	session.end_player_turn()
	check(session.preview_guard().reason == &"battle/input_locked", "phase gate refuses preview")
	session.close()
	_edge_cases()
	_guard_terminal_prefix()
	var production := BattleCoreCombinationSession.new()
	var actor_k2 := production.selected_unit()
	var k2_before := ItemSimulationSnapshot.capture(production.state, []).snapshot.to_dict()
	var k2_forecast := GuardForecast.build(production.context, production._queue, GuardCommand.new(actor_k2.id, production.context.get_revision()))
	var k2_receipt := production._queue.submit(GuardCommand.new(actor_k2.id, production.context.get_revision()), production.context)
	check(k2_forecast.status == ActionReceipt.APPLIED and k2_receipt.status == ActionReceipt.APPLIED, "K2 production guard applies")
	check(k2_forecast.snapshot_before == k2_before and k2_receipt.get_events() == k2_forecast.events and k2_receipt.get_steps() == k2_forecast.steps and ItemSimulationSnapshot.capture(production.state, []).snapshot.to_dict() == k2_forecast.snapshot_after and production.context.get_rng().to_dict() == k2_forecast.rng_after and production.context.simulation_counters() == k2_forecast.counters_after and SummonAdmission.values(production.context) == k2_forecast.admission_after, "K2 full snapshot/RNG/counter/admission parity")
	production.close()
	print("GUARD FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _edge_cases() -> void:
	var session := BattleTacticalSession.new()
	var actor := session.selected_unit()
	for rng: ActionRngPort in [NoCloneRng.new(), AliasRng.new(), WrongRng.new()]:
		session.context._rng = rng
		check(session.preview_guard().reason in [&"preview/rng_not_cloneable", &"preview/rng_state_mismatch"], "RNG capability rejected")
	session.context._rng = ActionRngPort.new()
	var command := GuardCommand.new(actor.id, session.context.get_revision())
	session._queue._faulted = true
	check(GuardForecast.build(session.context, session._queue, command).reason == &"CONTEXT_FAULTED", "faulted queue rejected")
	session._queue._faulted = false
	session.context._faulted = true
	check(GuardForecast.build(session.context, session._queue, command).reason == &"CONTEXT_FAULTED", "faulted context rejected by core")
	session.context._faulted = false
	check(GuardForecast.build(session.context, session._queue, GuardCommand.new(999999, session.context.get_revision())).reason == &"guard/no_selected_unit", "invalid actor id rejected")
	session._queue = ActionQueue.new(0, 1, 1)
	check(GuardForecast.build(session.context, session._queue, command).reason == &"invalid_limits", "invalid queue limits rejected before execution")
	session._queue = ActionQueue.new()
	actor.control = ControlState.new()
	actor.control.stunned_turns = 1
	check(session.preview_guard().reason == &"control/stunned", "stunned actor rejected")
	actor.control.stunned_turns = 0
	actor.control.entangled_turns = 1
	var entangled := session.preview_guard()
	check(entangled.status == ActionReceipt.APPLIED, "entanglement alone does not block non-movement guard: " + String(entangled.reason))
	actor.control = null
	session.context._move_rules = MoveRules.new([])
	check(session.preview_guard().reason == &"guard/not_admitted", "non-admitted actor rejected")
	session.close()

	session = BattleTacticalSession.new()
	actor = session.selected_unit()
	actor.vitals.apply_damage(1000.0)
	check(session.preview_guard().reason == &"guard/no_selected_unit", "dead selected actor rejected")
	session.selected_id = 999999
	check(session.preview_guard().reason == &"guard/no_selected_unit", "missing selection rejected")
	session.close()
	check(session.preview_guard().reason == &"battle/input_locked", "closed session rejected")

	session = BattleTacticalSession.new()
	actor = session.selected_unit()
	var helper := UnitState.create(Faction.Type.PLAYER, Vector2i(0, 3), session._demo_stats(), "Временный помощник")
	helper.enable_action_resources()
	helper.action_resources._set_for_refill(0, 0)
	helper.move_points_left = 0.0
	session.state.register_summon_owner(helper, actor.id)
	check(session.board.add_unit(helper), "register helper on the same board")
	var pending := GuardForecast.build(session.context, session._queue, GuardCommand.new(helper.id, session.context.get_revision()))
	check(session.state.is_summon_pending(helper.id) and pending.reason == &"guard/not_admitted", "pending helper cannot guard")
	var refill := session._queue.submit(BattleTurnRefill.new([helper.id], session.context.get_revision(), Faction.Type.PLAYER), session.context)
	check(refill.status == ActionReceipt.APPLIED and not session.state.is_summon_pending(helper.id), "turn refill readies helper")
	var ready := GuardForecast.build(session.context, session._queue, GuardCommand.new(helper.id, session.context.get_revision()))
	check(ready.status == ActionReceipt.APPLIED and ready.actor_id == helper.id, "admitted helper can guard")
	session.close()
	session = BattleTacticalSession.new()
	actor = session.selected_unit()
	session._queue = ActionQueue.new(1, 1, 1)
	var tight_limits := GuardForecast.build(session.context, session._queue, GuardCommand.new(actor.id, session.context.get_revision()))
	check(tight_limits.status == ActionReceipt.APPLIED and tight_limits.events.size() == 1, "minimum usable queue limits apply complete guard")
	session.close()

	# Завершение боя запускает обязательный ArmorEndBattle cleanup и позволяет проверить prefix.

func _guard_terminal_prefix() -> void:
	var session := BattleCoreCombinationSession.new()
	var actor := session.selected_unit()
	for enemy: UnitState in session.board.get_all_units():
		if enemy.faction != Faction.Type.ENEMY or not enemy.is_alive(): continue
		var death := session._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test", 0, enemy.cell)), session.context)
		check(death.status == ActionReceipt.APPLIED, "terminal guard setup defeats enemy")
	actor.armor = ArmorState.new()
	actor.armor.in_battle = true
	session._queue = ActionQueue.new(1, 512, 32)
	var before_capture := ItemSimulationSnapshot.capture(session.state, [])
	var before: Dictionary = before_capture.snapshot.to_dict()
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var counters := session.context.simulation_counters()
	var admission := SummonAdmission.values(session.context)
	var sink := CountingSink.new()
	session.context._sink = sink
	var forecast := GuardForecast.build(session.context, session._queue, GuardCommand.new(actor.id, session.context.get_revision()))
	check(forecast.status == ActionReceipt.FAULTED and forecast.reason == &"command_limit", "terminal armor cleanup faults after guard prefix: " + String(forecast.reason))
	check(forecast.units.is_empty() and not forecast.events.is_empty() and not forecast.steps.is_empty(), "faulted guard has prefix log, no ready units")
	check(forecast.snapshot_before == before and forecast.snapshot_after != before, "faulted guard snapshots contain applied prefix")
	var receipt := session._queue.submit(GuardCommand.new(actor.id, session.context.get_revision()), session.context)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "live guard receipt matches fault prefix")
	var after_capture := ItemSimulationSnapshot.capture(session.state, [])
	check(after_capture.code == ItemSnapshotResult.Code.OK and after_capture.snapshot.to_dict() == forecast.snapshot_after, "live guard snapshot matches prefix")
	check(session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after and SummonAdmission.values(session.context) == forecast.admission_after, "live prefix matches RNG/counters/admission")
	check(actor.guard_stance and actor.action_resources.get_main_left() == 0 and actor.armor.in_battle, "guard is applied before cleanup refusal")
	check(sink.calls == receipt.get_events().size() and forecast.rng_after == rng and forecast.admission_before == admission and forecast.counters_after != counters, "prefix publishes only through live sink")
	session.close()
