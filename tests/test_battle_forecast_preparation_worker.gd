extends SceneTree

const Worker = preload("res://scripts/demo/battle_forecast_preparation_worker.gd")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

class FailedStartWorker extends Worker:
	func _start_thread() -> Error:
		return ERR_CANT_CREATE

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE FORECAST PREPARATION WORKER: " + label)

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()

func _live_state(session: BattleCoreReactionsSession) -> Dictionary:
	return {"snapshot": _snapshot(session), "rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(), "revision": session.context.get_revision()}

func _take(worker: Worker) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var result := worker.take_finished()
		if not result.is_empty():
			return result
		await process_frame
	return worker.take_finished(true)

func _result_values(result: ForecastSimulation) -> Dictionary:
	return {"status": result.status, "reason": result.reason, "events": result.events,
		"steps": result.steps, "snapshot_before": result.snapshot_before,
		"snapshot_after": result.snapshot_after, "units_before": result.units_before,
		"units_after": result.units_after, "rng_after": result.rng_after,
		"counters_after": result.counters_after, "admission_after": result.admission_after}

func _prepared_values(prepared: ForecastSimulation.Prepared, method: StringName) -> Dictionary:
	var command_values: Dictionary = {"script": prepared.command.get_script()}
	if method == &"move":
		var move := prepared.command as MoveCommand
		command_values.merge({"actor": move.get_actor_unit_id(), "path": move.get_path(),
			"revision": move.get_expected_revision(), "kind": move.get_movement_kind()})
	elif method == &"attack":
		var attack := prepared.command as AttackCommand
		command_values.merge({"actor": attack.get_actor_unit_id(), "target": attack.get_target_unit_id(),
			"revision": attack.get_expected_revision()})
	return {"command": command_values, "snapshot": prepared.snapshot.to_dict(),
		"context_revision": prepared.context.get_revision(),
		"context_rng": prepared.context.get_rng().to_dict(),
		"context_counters": prepared.context.simulation_counters()}

func _prepared_parity(method: StringName, requested_args: Array, expected_builder: Callable) -> void:
	var session := PlayerTurnFixture.create()
	var args := requested_args.duplicate()
	if method == &"attack":
		session.select_unit(session.units[2].id)
		args[0] = session.units[3].id
	if method == &"move":
		session.select_unit(session.units[0].id)
	var before := _live_state(session)
	var expected_prepared: ForecastSimulation.Prepared = expected_builder.call(session, args)
	var expected_prepared_values := _prepared_values(expected_prepared, method)
	var expected := ForecastSimulation.run_prepared(expected_prepared)
	var worker := Worker.new()
	check(worker.start(session, method, args), String(method) + " request accepted")
	check(worker.is_started(), String(method) + " immediately owns session for audit")
	check(worker.take_finished().is_empty(), String(method) + " unfinished audit/result is not exposed")
	var completed := await _take(worker)
	check(completed.get("session") == session and not completed.get("sync_fallback", true), String(method) + " returns session only after completion")
	check(completed.get("prepared") is ForecastSimulation.Prepared, String(method) + " returns detached prepared value")
	check(_prepared_values(completed.prepared, method) == expected_prepared_values,
		String(method) + " detached snapshot, context and command match synchronous preparation")
	var actual := ForecastSimulation.run_prepared(completed.prepared)
	check(_result_values(actual) == _result_values(expected), String(method) + " prepared preview matches synchronous oracle")
	check(_live_state(session) == before, String(method) + " preparation and preview preserve live session")
	check(not worker.is_started() and worker.take_finished().is_empty(), String(method) + " releases ownership and transfers once")
	session.close()

func _build_move(session: BattleCoreReactionsSession, args: Array) -> ForecastSimulation.Prepared:
	return session.prepare_move_forecast(args[0])

func _build_attack(session: BattleCoreReactionsSession, args: Array) -> ForecastSimulation.Prepared:
	return session.prepare_attack_forecast(args[0])

func _build_turn(session: BattleCoreReactionsSession, _args: Array) -> TurnForecast.Prepared:
	return TurnForecast.prepare(session)

func _audit_refusal() -> void:
	var session := PlayerTurnFixture.create()
	session.board.board_changed.connect(_callback)
	var worker := Worker.new()
	check(worker.start(session, &"guard", []), "callback graph starts audit without reading it synchronously")
	var completed := await _take(worker)
	check(completed.get("session") == session and completed.get("sync_fallback", false)
		and completed.get("prepared") == null and completed.get("method") == &"guard"
		and completed.get("args", []) == [], "audit refusal returns original owner and sync fallback marker")
	check(not worker.is_started() and worker.take_finished().is_empty(), "audit refusal transfers owner exactly once")
	session.board.board_changed.disconnect(_callback)
	session.close()

func _launch_failure() -> void:
	var session := PlayerTurnFixture.create()
	var worker := FailedStartWorker.new()
	check(worker.start(session, &"move", [Vector2i(1, 2)]), "thread failure scenario starts audit")
	var completed := await _take(worker)
	check(completed.get("session") == session and completed.get("sync_fallback", false)
		and completed.get("prepared") == null, "thread start failure returns the owner without invoking preparation")
	check(not worker.is_started(), "thread failure clears worker ownership after transfer")
	session.close()

func _request_validation() -> void:
	var session := PlayerTurnFixture.create()
	var worker := Worker.new()
	for request: Array in [
		[&"arbitrary_callback", []], [&"move", [Vector2i(0, 0), Vector2i(1, 0)]],
		[&"attack", ["4"]], [&"guard", [1, "bad"]], [&"turn", [1]],
		[&"mage_card", [1, 2]], [&"item", [ItemUseAction.Kind.HEAL_SELF, Vector2i(1, 1), 3]],
	]:
		check(not worker.start(session, request[0], request[1]) and not worker.is_started(),
			"malformed request refused before ownership: " + str(request[0]))
	session.close()

func _callback() -> void:
	pass

func run() -> void:
	await _prepared_parity(&"move", [Vector2i(1, 2)], _build_move)
	await _prepared_parity(&"attack", [0], _build_attack)
	await _audit_refusal()
	await _launch_failure()
	_request_validation()
	var session := PlayerTurnFixture.create()
	var turn_worker := Worker.new()
	check(turn_worker.start(session, &"turn", []), "turn special request accepted")
	var turn_result := await _take(turn_worker)
	check(turn_result.get("prepared") is TurnForecast.Prepared and turn_result.get("session") == session
		and not turn_result.get("sync_fallback", true), "turn dispatches only TurnForecast.prepare")
	session.close()
	print("BATTLE FORECAST PREPARATION WORKER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
