extends SceneTree

## Один и тот же сценарий для A/B: CPU обработчиков и интервалы кадров с рендером.
## Не CI-порог: частота дисплея, драйвер и машина влияют на интервалы кадров.
var demo: BattleDemo
var viewport: SubViewport
var sample: int = 0

func _initialize() -> void: call_deferred("run")

func window(label: String, action: Callable, frames: int = 12) -> void:
	var cpu: Array[float] = []
	var intervals: Array[float] = []
	await process_frame
	var frame: int = 0
	while frame < frames or (demo.has_method("is_execution_pending") and demo.call("is_execution_pending")):
		assert(frame < 600, "Live execution timeout")
		var start := Time.get_ticks_usec()
		if frame == 0: action.call()
		else:
			if demo.has_method("_poll_execution"): demo.call("_poll_execution")
			demo._process_move_forecast()
			demo._process_attack_forecast()
			# Старый commit исполняет эти прогнозы синхронно; один runner проверяет обе версии.
			if demo.has_method("_process_action_forecast"): demo.call("_process_action_forecast")
		cpu.append(float(Time.get_ticks_usec() - start) / 1000.0)
		await process_frame
		intervals.append(float(Time.get_ticks_usec() - start) / 1000.0)
		frame += 1
	print(JSON.stringify({"label": label, "sample": sample, "cpu_ms": cpu, "frame_ms": intervals}))

func reset() -> void:
	demo._hovered_bar_action = &""
	demo.reset_demo()
	demo.set_process(false)
	demo.board_view.hover_cell = Vector2i(-1, -1)
	await process_frame
	await process_frame

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	await process_frame
	demo.set_process(false)
	for i: int in 4:
		sample = i
		await reset()
		await window("idle", func() -> void: pass)
		await window("refresh", demo._refresh)
		await window("hover_guard", demo._action_bar_hovered.bind(&"guard"))
		await reset()
		demo.session.selected_unit().vitals.set_hp(10)
		demo._refresh()
		await window("hover_healing", demo._action_bar_hovered.bind(&"healing_item"))
		await reset()
		demo._choose_summoning()
		demo.board_view.hover_cell = Vector2i(0, 1)
		await window("hover_summon", demo._hover.bind(Vector2i(0, 1)))
		await reset()
		await window("live_move", demo.handle_cell.bind(Vector2i(1, 2)))
		await reset()
		demo.select_character(demo.session.units[2].id)
		demo.set_attack_mode(true)
		await window("live_attack", demo.handle_cell.bind(demo.session.units[3].cell))
		await window("end_turn", demo.end_turn)
		for step: int in 5:
			await window("enemy_step_" + str(step), demo._process.bind(1.0), 3)
		var s := demo.session
		print(JSON.stringify({"label": "state", "sample": sample, "fingerprint": ItemSimulationSnapshot.capture(s.state, []).snapshot.fingerprint(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}))
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("SMOOTHNESS PROFILE DONE")
	quit()
