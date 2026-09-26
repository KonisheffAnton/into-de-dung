extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ATTACK ASYNC UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	# Останавливаем только автоматический tick: ввод идёт через настоящий SubViewport.
	demo.set_process(false)
	setup_attack()
	var s := demo.session as BattleCoreReactionsSession
	var target := s.units[3]
	var other := s.units[5]
	var before := snapshot()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var receipt := s.last_receipt
	push_motion(at(target.cell))
	check(demo._attack_forecast_pending and demo._forecast == null and not demo._attack_forecast_worker.is_started(), "input queues target without running capture or simulation")
	check(demo._forecast_panel.text.contains("Рассчитываем") and demo._forecast_panel.text.contains(target.debug_name), "pending panel immediately identifies target")
	check(demo.board_view.forecast == null and demo.board_view._forecast_entry(target.id).is_empty() and demo.board_view.sneak_threat_ids.is_empty(), "pending request invents no health or sneak result")
	await capture("attack-pending")
	push_motion(at(other.cell))
	push_motion(at(target.cell))
	check(demo._forecast_target_id == target.id and not demo._attack_forecast_worker.is_started(), "several input events coalesce before capture")
	demo._process_attack_forecast()
	check(demo._attack_forecast_worker.is_started() and demo._forecast == null, "frame starts detached work without publishing prematurely")
	var obsolete_generation := demo._attack_forecast_job_generation
	push_motion(at(other.cell))
	check(demo._attack_forecast_generation != obsolete_generation and demo._forecast_target_id == other.id, "new input replaces active job target without waiting")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(other.id)), "obsolete result cannot overwrite latest target")
	check(snapshot() == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and s.last_receipt == receipt, "asynchronous hover preserves all live state")
	push_motion(at(target.cell))
	await settle()
	var forecast := demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "ordinary attack gets exact ready forecast")
	check(demo.board_view.forecast == forecast and not demo.board_view._forecast_entry(target.id).is_empty(), "ready result updates existing health overlay")
	push_motion(at(target.cell))
	demo._process_attack_forecast()
	check(demo._forecast == forecast and not demo._attack_forecast_worker.is_started(), "unchanged hover reuses completed result")
	await capture("attack-ready")
	push_motion(Vector2(2, 2))
	await process_frame
	check(demo._forecast == null and not demo._attack_forecast_pending and demo.board_view.forecast == null, "leaving clears completed result")

	# Результат разрешено дочитать на панели даже при переходе туда до завершения.
	push_motion(at(target.cell))
	demo._process_attack_forecast()
	push_motion(demo._forecast_panel.global_position + Vector2(20, 20))
	await process_frame
	check(demo._attack_forecast_pending, "pending target survives move into reading panel")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(target.id)), "worker publishes while pointer reads panel")
	push_motion(Vector2(2, 2)); await process_frame
	push_motion(at(target.cell)); demo._process_attack_forecast()
	push_motion(Vector2(2, 2)); await process_frame
	await drain()
	check(demo._forecast == null and not demo._attack_forecast_pending, "leaving pending request discards its eventual result")

	# Смена определения не обязана менять revision, но меняет смысл прогноза.
	push_motion(at(target.cell)); demo._process_attack_forecast()
	var revision := s.context.get_revision()
	push_key(KEY_7)
	check(demo._attack_forecast_variant == &"entangle" and s.context.get_revision() == revision, "K8 key replaces pending ordinary request at same revision")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(target.id)), "K8 worker matches selected synchronous command")
	push_key(KEY_5)
	await settle()
	check(demo._attack_forecast_variant == &"rune" and same_forecast(demo._forecast, s.preview_attack(target.id)), "rune replaces K8 with exact selected command")
	push_key(KEY_1)
	await settle()
	check(demo._attack_forecast_variant == &"ordinary", "ordinary mode restores distinct request")

	# Refresh должен инвалидировать копию и при прямом изменении без revision.
	demo._refresh(); demo._process_attack_forecast()
	target.vitals.set_hp(1)
	demo._refresh()
	await settle()
	check(s.context.get_revision() == revision and same_forecast(demo._forecast, s.preview_attack(target.id)), "refresh replaces in-flight state despite unchanged revision")
	check(demo._forecast.units[target.id]["before"]["hp"] == 1, "published result uses refreshed target health")
	demo._refresh(); demo._process_attack_forecast()
	demo.select_character(s.units[0].id)
	await drain()
	check(demo._forecast == null and not demo._attack_forecast_pending, "actor selection discards outstanding attack")

	setup_attack()
	s = demo.session as BattleCoreReactionsSession
	target = s.units[3]
	push_motion(at(target.cell)); demo._process_attack_forecast()
	s.phase = BattleTacticalSession.Phase.ENEMY_TURN
	await settle()
	check(demo._forecast == null and not demo._attack_forecast_pending, "phase gate rejects stale completion before next UI refresh")
	setup_attack()
	s = demo.session as BattleCoreReactionsSession
	target = s.units[3]
	push_motion(at(target.cell)); demo._process_attack_forecast()
	s.board.remove_unit(target)
	await settle()
	check(demo._forecast == null, "removed target cannot receive stale forecast")

	setup_attack()
	s = demo.session as BattleCoreReactionsSession
	target = s.units[3]
	var expected := s.preview_attack(target.id)
	push_motion(at(target.cell)); demo._process_attack_forecast()
	push_click(at(target.cell))
	check(s.last_receipt.get_events() == expected.events and snapshot() == expected.snapshot_after, "click while pending executes fresh matching live command")
	await settle()
	check(demo._forecast == null or demo._forecast.status == ActionReceipt.REJECTED, "old successful result cannot reappear after spent action")
	setup_attack()
	push_motion(at(demo.session.units[3].cell)); demo._process_attack_forecast()
	demo.reset_demo()
	await drain()
	check(demo._forecast == null, "reset invalidates job belonging to old session")
	setup_attack()
	push_motion(at(demo.session.units[3].cell)); demo._process_attack_forecast()
	demo.toggle_scenario()
	await drain()
	check(demo._forecast == null, "scenario transition cannot inherit pending result")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("ATTACK ASYNC UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func setup_attack() -> void:
	push_motion(Vector2(2, 2))
	demo.reset_demo()
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)

func snapshot() -> Dictionary:
	return ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()

func same_forecast(a: AttackForecast, b: AttackForecast) -> bool:
	return a != null and b != null and a.status == b.status and a.reason == b.reason and a.events == b.events and a.steps == b.steps and a.snapshot_before == b.snapshot_before and a.snapshot_after == b.snapshot_after and a.rng_after == b.rng_after and a.counters_after == b.counters_after

func settle() -> void:
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func drain() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while demo._attack_forecast_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._process_attack_forecast()
		await create_timer(0.001).timeout
	check(not demo._attack_forecast_worker.is_started(), "discarded worker finishes and joins")

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func push_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)

func push_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)

func push_click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
