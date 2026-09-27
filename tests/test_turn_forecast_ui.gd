extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL TURN FORECAST UI: " + label)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	viewport.push_input(event, true)
	await process_frame
	await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		demo._process_turn_forecast()
		if not demo._turn_forecast_pending and not demo._turn_forecast_worker.is_started(): return
		await create_timer(0.002).timeout
	check(false, "worker deadline")

func capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func button_center() -> Vector2:
	return demo._end_turn_button.global_position + demo._end_turn_button.size * 0.5

func enter_player_turn(target: BattleDemo) -> void:
	var session := target.session as BattleCoreReactionsSession
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	target._refresh()

func snapshot() -> Dictionary:
	return ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	demo.set_process(false)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	await motion(button_center())
	check(not demo._turn_forecast_pending and demo._turn_forecast == null, "deployment hover never simulates combat")
	await click(button_center())
	check((demo.session as BattleCoreReactionsSession).phase == BattleTacticalSession.Phase.ENEMY_TURN, "real button starts enemy-first battle")
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "start clears deployment hover without player forecast")
	var opening := demo.session as BattleCoreReactionsSession
	opening._enemy_index = opening._enemy_ids.size()
	demo._execute_live(&"step_enemy")
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	check(opening.can_player_act() and opening.round_number == 1, "opening enemy boundary reaches first player turn")
	await motion(Vector2(5, 5))
	await motion(button_center())
	var s := demo.session as BattleCoreReactionsSession
	var before := snapshot()
	var counters := s.context.simulation_counters()
	var allocator := UnitId.get_counter()
	check(demo._turn_forecast_pending and not demo._turn_forecast_worker.is_started(), "hover only records request")
	check(demo._forecast_panel.text.contains("Рассчитываем") and demo._forecast_heading.text.contains("КОНЕЦ ХОДА"), "pending title and boundary visible")
	await capture("turn-pending")
	await settle()
	check(demo._turn_forecast != null and demo._turn_forecast.status == ActionReceipt.APPLIED, "real hover returns complete forecast")
	check(snapshot() == before and s.context.simulation_counters() == counters and UnitId.get_counter() == allocator, "hover preserves live state and IDs")
	check(demo._forecast_panel.text.contains("Оглушение, ходов: 1 → 0") and demo._forecast_panel.text.contains("До первого действия противника") and demo._forecast_panel.text.contains("Окружение 1:"), "panel explains expiry, scope, and environment phase")
	await capture("turn-ready")
	var result := demo._turn_forecast
	await motion(demo._forecast_panel.global_position + Vector2(20, 25))
	check(demo._turn_forecast == result, "panel reading retains completed result")
	var wheel := InputEventMouseButton.new()
	wheel.position = demo._forecast_panel.global_position + Vector2(25, 30)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	viewport.push_input(wheel, true)
	await process_frame
	check(demo._turn_forecast == result, "scroll does not recalculate")
	await motion(Vector2(5, 5))
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "leave clears result")
	await motion(button_center())
	demo._process_turn_forecast()
	var generation := demo._turn_forecast_job_generation
	var enemy := s.units[1]
	enemy.action_resources.try_spend_main(1)
	demo._refresh()
	check(demo._turn_forecast_generation != generation and demo._turn_forecast_pending, "refresh replaces pending capture without revision")
	await settle()
	check(demo._turn_forecast != null and demo._turn_forecast.snapshot_after == TurnForecast.build(s).snapshot_after, "latest refresh wins")
	check(demo._forecast_panel.text.contains("Основные: 0 → 1"), "incoming refill displayed")
	await key(KEY_ESCAPE)
	await settle()
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "escape discards end-turn result")
	await motion(Vector2(5, 5))
	await motion(button_center())
	demo._process_turn_forecast()
	await click(demo._roster.get_child(1).global_position + Vector2(10, 10))
	await settle()
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "selection invalidates pending turn result")
	await motion(button_center())
	await settle()
	result = demo._turn_forecast
	# Клик должен считать свежий переход, даже если мир изменили без revision.
	enemy.vitals.set_hp(enemy.vitals.get_hp() - 1.0)
	var fresh := TurnForecast.build(s)
	check(result != null and fresh.snapshot_after != result.snapshot_after, "fixture changes world after displayed forecast")
	await click(button_center())
	await settle()
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "execution clears forecast")
	check(snapshot() == fresh.snapshot_after and s.phase == BattleTacticalSession.Phase.ENEMY_TURN and s._enemy_actions == 0, "fresh click executes only transition, before AI")
	await motion(Vector2(5, 5))
	await motion(button_center())
	check(not demo._turn_forecast_pending, "enemy phase cannot preview player boundary")
	await key(KEY_R)
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "reset clears completed and pending state")
	enter_player_turn(demo)
	s = demo.session as BattleCoreReactionsSession
	var dying := s.units[5]
	for unit: UnitState in s.units:
		if unit.faction == Faction.Type.ENEMY and unit != dying:
			var death := s._queue.submit(DeathCommand.new(unit.id, DamageSource.new(&"test", 0, unit.cell)), s.context)
			check(death.status == ActionReceipt.APPLIED and not unit.is_alive(), "victory fixture removes other enemy through command")
	dying.vitals.set_hp(1.0)
	dying.bleeding.ticks_left = 1
	dying.bleeding.stacks = 1
	dying.bleeding.source = DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
	dying.bleeding.hit_id = "1:%d" % dying.id
	demo._refresh()
	await motion(Vector2(5, 5))
	await motion(button_center())
	await settle()
	check(demo._turn_forecast != null and demo._turn_forecast.phase_after == BattleTacticalSession.Phase.VICTORY and demo._forecast_panel.text.contains("Победа до действий"), "lethal tick explains early victory")
	await capture("turn-victory")
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.VICTORY and demo._turn_forecast == null, "Enter stops at predicted victory")
	await key(KEY_R)
	enter_player_turn(demo)
	await motion(Vector2(5, 5))
	await motion(button_center())
	s = demo.session as BattleCoreReactionsSession
	s.context._unsupported_runtime_ids.append(&"unknown_turn_effect")
	demo._refresh()
	await settle()
	check(demo._turn_forecast != null and demo._turn_forecast.status == ActionReceipt.REJECTED and demo._forecast_panel.text.contains("Прогноз недоступен"), "unsupported runtime is explicit refusal")
	s.context._unsupported_runtime_ids.clear()
	demo._refresh()
	demo._process_turn_forecast()
	await key(KEY_R)
	await settle()
	check(demo._turn_forecast == null and not demo._turn_forecast_pending, "reset discards running generation")
	enter_player_turn(demo)
	await motion(Vector2(5, 5))
	await motion(button_center())
	demo._process_turn_forecast()
	var worker := demo._turn_forecast_worker
	demo.queue_free()
	await process_frame
	check(not worker.is_started(), "exit joins worker")
	viewport.queue_free()
	await process_frame
	print("TURN FORECAST UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
