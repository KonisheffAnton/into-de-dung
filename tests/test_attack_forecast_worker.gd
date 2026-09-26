extends SceneTree

const AttackWorkerScript = preload("res://scripts/demo/attack_forecast_worker.gd")

var passed: int = 0
var failed: int = 0

class UnsupportedRng extends ActionRngPort:
	func clone() -> ActionRngPort: return UnsupportedRng.new()
	func to_dict() -> Dictionary: return {"unsupported": true}

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ATTACK FORECAST WORKER: " + label)

func _fixture(session: BattleDemoSession, actor_index: int, target_index: int) -> void:
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	for i: int in session.units.size():
		if session.units[i].is_alive(): session.board.move_unit(session.units[i], Vector2i(i, 7))
	session.board.move_unit(session.units[actor_index], Vector2i(3, 3))
	session.board.move_unit(session.units[target_index], Vector2i(4, 3))
	session.select_unit(session.units[actor_index].id)
	if session.state.environment != null: session.state.environment.fires.clear()

func _snapshot(session: BattleDemoSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "fixture snapshot: " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func _same(a: AttackForecast, b: AttackForecast) -> bool:
	return a != null and b != null and a.status == b.status and a.reason == b.reason and a.units == b.units and a.events == b.events and a.steps == b.steps and a.snapshot_before == b.snapshot_before and a.snapshot_after == b.snapshot_after and a.rng_after == b.rng_after and a.counters_after == b.counters_after

func _run_worker(prepared: ForecastSimulation.Prepared) -> AttackForecast:
	var worker := AttackWorkerScript.new()
	worker.start(prepared)
	var result := await _take(worker, prepared)
	worker.close()
	check(not worker.is_started(), "close releases worker")
	check(AttackForecast.build_prepared(prepared).reason == &"preview/request_consumed", "prepared request is one-shot")
	return result

func _take(worker: Object, prepared: ForecastSimulation.Prepared) -> AttackForecast:
	var deadline := Time.get_ticks_msec() + 5000
	var result: AttackForecast
	while Time.get_ticks_msec() < deadline:
		result = worker.take_finished()
		if result != null: break
		await create_timer(0.005).timeout
	if result == null:
		worker.close()
		check(false, "worker completes within 5 seconds")
		return null
	check(worker.take_finished() == null, "worker result is single take")
	return result

func _parity(session: BattleDemoSession, actor_index: int, target_index: int, label: String) -> void:
	var actor := session.units[actor_index]
	var target := session.units[target_index]
	var expected := session.preview_attack(target.id)
	var before := _snapshot(session)
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var counters := session.context.simulation_counters()
	var prepared := session.prepare_attack_forecast(target.id)
	var forecast := await _run_worker(prepared)
	check(_same(expected, forecast), label + " exact sync parity")
	check(forecast.snapshot_before == before, label + " complete initial snapshot")
	check(_snapshot(session) == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters, label + " worker leaves live state/RNG/counters unchanged")
	var actual := session.attack_unit(target.id)
	check(forecast.status == actual.status and forecast.reason == actual.reason and forecast.events == actual.get_events() and forecast.steps == actual.get_steps(), label + " full live receipt parity")
	check(forecast.snapshot_after == _snapshot(session) and forecast.rng_after == session.context.get_rng().to_dict() and forecast.counters_after == session.context.simulation_counters(), label + " resulting snapshot/RNG/counters")
	check(actor.id != target.id, label + " fixture uses distinct units")

func _run() -> void:
	var ordinary := BattleCoreReactionsSession.new()
	_fixture(ordinary, 2, 5)
	await _parity(ordinary, 2, 5, "ordinary core reaction attack")
	ordinary.close()

	var rune := BattleBleedingSession.new()
	_fixture(rune, 0, 1)
	rune.rune_selected = true
	var rune_prepared := rune.prepare_attack_forecast(rune.units[1].id)
	check((rune_prepared.command as AttackCommand).get_attack_definition_id() == &"blood_rune", "rune session prepares selected attack definition")
	await _parity(rune, 0, 1, "rune attack")
	rune.close()

	var k8 := BattleCoreCombinationSession.new()
	_fixture(k8, 2, 5)
	k8.entangle_selected = true
	var k8_prepared := k8.prepare_attack_forecast(k8.units[5].id)
	check((k8_prepared.command as AttackCommand).get_attack_definition_id() == &"entangling_strike", "K8 inherited override survives preparation")
	await _parity(k8, 2, 5, "K8 entangling attack")
	k8.close()

	var invalid := BattleDemoSession.new()
	_fixture(invalid, 0, 1)
	check(invalid.preview_attack(invalid.units[0].id).reason == invalid.prepare_attack_forecast(invalid.units[0].id).reason, "self-target rejection matches")
	check(invalid.preview_attack(999999).reason == invalid.prepare_attack_forecast(999999).reason, "missing-target rejection matches")
	var unsupported := invalid.prepare_attack_forecast(invalid.units[1].id)
	unsupported.context._rng = UnsupportedRng.new()
	var rejected_worker := AttackWorkerScript.new()
	rejected_worker.start(unsupported)
	check(rejected_worker._thread == null and rejected_worker.take_finished().reason == &"preview/unsupported_worker_rng", "unsupported RNG rejects immediately")
	check(not rejected_worker.is_started(), "immediate rejection clears on take")
	var consumed := AttackWorkerScript.new()
	consumed.start(null)
	check(consumed.take_finished().reason == &"preview/request_consumed", "null request rejects immediately")
	consumed.close()
	var reusable := AttackWorkerScript.new()
	var first := invalid.prepare_attack_forecast(invalid.units[1].id)
	var first_result := await _take_started(reusable, first)
	var second := invalid.prepare_attack_forecast(invalid.units[1].id)
	var second_result := await _take_started(reusable, second)
	check(first_result != null and second_result != null and first_result.events == second_result.events, "worker accepts a new prepared request after result is taken")
	reusable.close()
	var closing := AttackWorkerScript.new()
	closing.start(invalid.prepare_attack_forecast(invalid.units[1].id))
	closing.close()
	check(not closing.is_started(), "close joins and discards an outstanding calculation")
	invalid.close()

	print("ATTACK FORECAST WORKER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _take_started(worker: Object, prepared: ForecastSimulation.Prepared) -> AttackForecast:
	worker.start(prepared)
	return await _take(worker, prepared)
