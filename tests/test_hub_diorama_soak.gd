extends SceneTree

# Отдельная длительная проба: --seconds=300 --output=<absolute JSON>.
# CPU диорамы измеряется прямым вызовом того же _process один раз за кадр;
# автоматический processing в этой пробе выключен, чтобы не считать его дважды.
var seconds: float = 300.0
var output: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = maxf(1.0, float(arg.trim_prefix("--seconds=")))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var dashboard := (load("res://scenes/demo/hub/expedition_dashboard.tscn") as PackedScene).instantiate() as ExpeditionDashboard
	viewport.add_child(dashboard)
	var profile := HeroHubState.create(714, 4)
	profile.enable_mage_deck()
	var initial := profile.to_dict()
	dashboard.render_profile(profile, true, &"expedition", true, "Готово")
	for unused: int in 120: await process_frame
	var result: Dictionary = {"seconds_per_mode": seconds, "resolution": [1280, 850], "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "method": "process-frame intervals; RenderingServer measured viewport CPU/GPU; direct diorama process once per frame; no OS present-time guarantee"}
	for animated: bool in [false, true]:
		dashboard._diorama._on_motion_toggled(animated)
		dashboard._diorama.set_process(false)
		for unused: int in 60: await process_frame
		var frames: Array[float] = []
		var cpu: Array[float] = []
		var render_cpu: Array[float] = []
		var render_gpu: Array[float] = []
		var memory_start := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var nodes_start := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var started := Time.get_ticks_usec()
		var previous := started
		while (Time.get_ticks_usec() - started) / 1000000.0 < seconds:
			await process_frame
			var now := Time.get_ticks_usec()
			var frame_ms := (now - previous) / 1000.0
			previous = now
			frames.append(frame_ms)
			var begin := Time.get_ticks_usec()
			if animated: dashboard._diorama._process(frame_ms / 1000.0)
			cpu.append((Time.get_ticks_usec() - begin) / 1000.0)
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
			render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		result["animated" if animated else "static"] = {"frames": stats(frames), "diorama_cpu_ms": stats(cpu), "render_cpu_ms": stats(render_cpu), "render_gpu_ms": stats(render_gpu), "memory_static_start": memory_start, "memory_static_end": int(Performance.get_monitor(Performance.MEMORY_STATIC)), "nodes_start": nodes_start, "nodes_end": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}
		print("HUB DIORAMA SOAK MODE: " + ("animated" if animated else "static"))
	result["profile_unchanged"] = profile.to_dict() == initial
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("FAIL HUB DIORAMA SOAK: output unavailable")
			quit(1)
			return
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("HUB DIORAMA SOAK: " + JSON.stringify(result))
	viewport.queue_free()
	await process_frame
	print("HUB DIORAMA SOAK RESULTS: %d passed, %d failed" % [1 if result.profile_unchanged else 0, 0 if result.profile_unchanged else 1])
	quit(0 if result.profile_unchanged else 1)

func stats(values: Array[float]) -> Dictionary:
	values.sort()
	return {"count": values.size(), "p50": values[floori((values.size() - 1) * 0.50)], "p95": values[floori((values.size() - 1) * 0.95)], "p99": values[floori((values.size() - 1) * 0.99)], "max": values[-1]}
