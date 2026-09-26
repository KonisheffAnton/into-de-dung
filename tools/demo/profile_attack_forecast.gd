extends SceneTree

## CPU и задержка UI измеряются раздельно; результаты не являются FPS или CI-порогом.
## Этот runner можно скопировать в прежний checkout для сравнения того же сценария.
var viewport: SubViewport
var demo: Variant

func _initialize() -> void: call_deferred("run")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	demo.select_character(session.units[2].id)
	demo.set_attack_mode(true)
	var target := session.units[3]
	var asynchronous: bool = session.has_method("prepare_attack_forecast")
	for sample: int in 9:
		var start := Time.get_ticks_usec()
		var forecast := session.preview_attack(target.id)
		print(JSON.stringify({"sample": sample, "kind": "sync_cpu", "ms": elapsed(start), "status": forecast.status, "events": forecast.events, "steps": forecast.steps, "snapshot": hash(forecast.snapshot_after), "rng": forecast.rng_after, "counters": forecast.counters_after}))
		motion(Vector2(2, 2))
		await process_frame
		demo._clear_forecast()
		start = Time.get_ticks_usec()
		motion(demo.board_view.global_position + demo.board_view.cell_center(target.cell))
		var row := {"sample": sample, "kind": "ui", "input_ms": elapsed(start), "async": asynchronous}
		var frames := 0
		if asynchronous:
			var preparation := Time.get_ticks_usec()
			demo.call("_process_attack_forecast")
			row["prepare_ms"] = elapsed(preparation)
			while demo.get("_attack_forecast_pending") and elapsed(start) < 5000:
				await process_frame
				frames += 1
				var poll := Time.get_ticks_usec()
				demo.call("_process_attack_forecast")
				row["max_poll_ms"] = maxf(row.get("max_poll_ms", 0.0), elapsed(poll))
		row["ready_ms"] = elapsed(start)
		row["frames_while_pending"] = frames
		row["parity"] = demo._forecast != null and demo._forecast.events == forecast.events and demo._forecast.snapshot_after == forecast.snapshot_after
		print(JSON.stringify(row))
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	quit()

func elapsed(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
