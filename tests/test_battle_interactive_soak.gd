extends "res://tests/test_battle_soak_performance.gd"

## Ввод проходит штатные обработчики; аппаратные события guard только считает.
## Планировщик теста не читает runtime, пока forecast-worker владеет сессией.
var pointer_cells: Array[Vector2i] = []
var pointer_mode: StringName = &""
var pointer_step: int = 0
var pointer_active: bool = false
var pointer_count: int = 0
var pointer_changes: int = 0
var previous_pointer_cell := Vector2i(-1, -1)
var input_samples: Array[float] = []
var interactive_frames: Array[float] = []
var setup_frames: Array[float] = []
var mode_samples: Dictionary = {}
var completed_forecasts: Array[Dictionary] = []
var seen_forecasts: Dictionary = {}
var input_surface: BattleHudInput
var frame_start_usec: int = 0
var pre_draw_usec: int = 0
var post_draw_usec: int = 0
var choice_samples: Array[Dictionary] = []
var fixture_setup_usec: int = 0

func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)

func _before_draw() -> void:
	pre_draw_usec = Time.get_ticks_usec()

func _after_draw() -> void:
	post_draw_usec = Time.get_ticks_usec()

func _stress_profile() -> HeroHubState:
	var profile := super._stress_profile()
	for id: int in profile.heroes:
		if (profile.heroes[id] as HeroProgression).class_id == &"mage":
			profile.party[2] = id
			break
	return profile

func _perform_player_action() -> bool:
	await _interactive_window()
	return await super._perform_player_action()

func _interactive_window() -> void:
	trace_bucket = "interactive_setup"
	trace_phase = "interactive_setup"
	if demo.session == null or demo.is_execution_pending():
		check(false, "interactive setup has exclusive runtime owner")
		return
	input_surface = demo.find_child("BattleHudInput", true, false) as BattleHudInput
	check(input_surface != null, "interactive pointer uses production HUD input surface")
	if input_surface == null: return
	var active := demo.session as BattleCoreReactionsSession
	var mage_id := UnitId.NONE
	var mage_cell := Vector2i(-1, -1)
	var enemy_cells: Array[Vector2i] = []
	for unit: UnitState in active.units:
		if not unit.is_alive(): continue
		if unit.faction == Faction.Type.ENEMY: enemy_cells.append(unit.cell)
		if unit.faction == Faction.Type.PLAYER and active.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"mage":
			mage_id = unit.id
			mage_cell = unit.cell
	check(mage_id != UnitId.NONE, "interactive roster retains production mage")
	if mage_id == UnitId.NONE: return
	var frames := _argument_int(OS.get_cmdline_user_args(), "--hover-frames", 360, 120, 3600)
	for mode: StringName in [&"elemental", &"mage_card", &"sweep"]:
		trace_bucket = "interactive_setup"
		trace_phase = "choose_" + String(mode)
		active = demo.session as BattleCoreReactionsSession
		if active == null: check(false, "mode switch has returned runtime"); return
		var setup_start := Time.get_ticks_usec()
		active.select_unit(mage_id)
		pointer_cells.clear()
		if mode == &"elemental":
			var choice_start := Time.get_ticks_usec()
			demo._choose_elemental(&"wet")
			choice_samples.append({"mode": mode, "ms": float(Time.get_ticks_usec() - choice_start) / 1000.0})
			# Self-target — настоящий допустимый ElementalCastCommand без дальнего attack/not_aligned.
			pointer_cells.append(mage_cell)
		elif mode == &"mage_card":
			var slot := -1
			for index: int in active.state.deck.hand_ids.size():
				var card_id := active.state.deck.hand_ids[index]
				var definition := MageCardCatalog.get_card(String(active.state.deck.card(card_id).get("type_id", "")))
				if definition == null or active.mage_card_reason(card_id) != &"": continue
				if definition.target_policy in ["enemy_unit", "living_unit"] and not enemy_cells.is_empty():
					slot = index
					pointer_cells.append_array(enemy_cells)
					break
				if definition.target_policy == "ally_unit":
					slot = index
					pointer_cells.append(mage_cell)
					break
			check(slot >= 0, "interactive hand contains a playable unit-target card")
			if slot < 0: continue
			var choice_start := Time.get_ticks_usec()
			demo._choose_card_slot(slot)
			choice_samples.append({"mode": mode, "ms": float(Time.get_ticks_usec() - choice_start) / 1000.0})
		else:
			var choice_start := Time.get_ticks_usec()
			demo.set_attack_mode(false)
			choice_samples.append({"mode": mode, "ms": float(Time.get_ticks_usec() - choice_start) / 1000.0})
			pointer_cells.append(mage_cell)
			pointer_cells.append_array(enemy_cells)
		fixture_setup_usec += Time.get_ticks_usec() - setup_start - int(float(choice_samples.back().ms) * 1000.0)
		pointer_mode = mode
		pointer_step = 0
		trace_bucket = "interactive"
		trace_phase = "hover_" + String(mode)
		pointer_active = true
		for _frame: int in frames: await process_frame
		pointer_active = false
		await _drain_forecast()
	# В последующем бою мышь движется над опубликованной проекцией, а не runtime worker.
	pointer_cells.assign(enemy_cells)
	pointer_cells.append(mage_cell)
	pointer_mode = &"combat_inspection"

func _drain_forecast() -> void:
	trace_bucket = "interactive_setup"
	trace_phase = "forecast_drain"
	_send_pointer(Vector2(-100.0, -100.0))
	demo.board_view._clear_hover()
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (demo.is_execution_pending() or demo._action_forecast_worker.is_started()):
		await process_frame
	check(not demo.is_execution_pending(), "interactive forecast returns owner before planner resumes")
	if demo.is_execution_pending(): return
	demo._clear_forecast()
	demo.board_view._clear_hover()

func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	super._on_process_frame()
	if soak_trace.is_empty() or demo == null: return
	var row: Dictionary = soak_trace.back()
	if fixture_setup_usec > 0:
		row["fixture_setup_ms"] = float(fixture_setup_usec) / 1000.0
		fixture_setup_usec = 0
	# Предыдущий интервал делится сигналами renderer; это не физический scanout.
	if frame_start_usec > 0 and pre_draw_usec >= frame_start_usec and post_draw_usec >= pre_draw_usec and post_draw_usec <= now:
		row["main_ms"] = float(pre_draw_usec - frame_start_usec) / 1000.0
		row["draw_wait_ms"] = float(post_draw_usec - pre_draw_usec) / 1000.0
		row["tail_ms"] = float(now - post_draw_usec) / 1000.0
	frame_start_usec = now
	if trace_bucket == "interactive": interactive_frames.append(float(row.ms))
	elif trace_bucket == "interactive_setup": setup_frames.append(float(row.ms))
	if demo._elemental_forecast != null:
		var forecast := demo._elemental_forecast
		var id := forecast.get_instance_id()
		if not seen_forecasts.has(id):
			seen_forecasts[id] = true
			completed_forecasts.append({"mode": pointer_mode, "status": forecast.status,
				"reason": forecast.reason, "frame": Engine.get_process_frames(),
				"witness": demo._action_forecast_freshness != null})
	var combat_pointer := trace_bucket == "combat" and (demo._execution_worker.is_started() or demo.is_presentation_pending())
	if not pointer_active and not combat_pointer: return
	if pointer_cells.is_empty() or input_surface == null: return
	var hold_frames := 6 if pointer_mode == &"sweep" or combat_pointer else 120
	var cell := pointer_cells[(pointer_step / hold_frames) % pointer_cells.size()]
	var point := demo.board_view.get_global_transform_with_canvas() * demo.board_view.cell_center(cell)
	point += Vector2(float(pointer_step % 5) - 2.0, 0.0)
	var start := Time.get_ticks_usec()
	_send_pointer(point)
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	input_samples.append(elapsed_ms)
	row["input_for_next_frame_ms"] = elapsed_ms
	row["pointer_mode"] = String(pointer_mode)
	pointer_count += 1
	mode_samples[pointer_mode] = int(mode_samples.get(pointer_mode, 0)) + 1
	if cell != previous_pointer_cell: pointer_changes += 1
	previous_pointer_cell = cell
	pointer_step += 1

func _send_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	demo._input(event)
	if input_surface != null: input_surface._gui_input(event)

func _write_soak_report() -> void:
	var applied: Dictionary = {}
	for row: Dictionary in completed_forecasts:
		if row.status == ActionReceipt.APPLIED: applied[row.mode] = int(applied.get(row.mode, 0)) + 1
	check(pointer_count >= 1000 and pointer_changes > 20, "long soak exercises continuous pointer movement and changing targets")
	check(int(applied.get(&"elemental", 0)) > 0 and int(applied.get(&"mage_card", 0)) > 0,
		"long soak publishes APPLIED elemental and card forecasts")
	metrics["interactive"] = {"frames": _timing_summary(interactive_frames), "setup_and_drain": _timing_summary(setup_frames),
		"choice_handlers": choice_samples,
		"input_handlers": _timing_summary(input_samples), "events": pointer_count, "target_changes": pointer_changes,
		"mode_samples": mode_samples, "forecasts": completed_forecasts,
		"route": "deterministic direct BattleDemo._input then BattleHudInput._gui_input; normal scene processing and worker/presentation; no OS cursor injection",
		"alignment": "input_for_next_frame_ms follows recorded process interval; no exact display alignment claimed"}
	metrics["fps_acceptance"] = false
	var path := "user://battle-interactive-soak.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): path = arg.trim_prefix("--probe-output=")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "interactive soak report opens")
	if file != null:
		file.store_string(JSON.stringify({"passed": passed, "failed": failed, "measurements": metrics}, "\t"))
		file.close()
