extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var demo: BattleDemo
var viewport: SubViewport
var captures: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ACTION ASYNC UI: " + label)

func settle() -> void:
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		demo._process_action_forecast()
		if not demo._action_forecast_pending and not demo._action_forecast_worker.is_started(): return
		await create_timer(0.002).timeout
	check(false, "worker deadline")

func capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK, "capture " + name)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate()
	demo.deployment_enabled = false
	viewport.add_child(demo)
	# Подробный прогноз/реестр проверяется в явно открытой диагностике.
	demo.set_diagnostics_visible(true)
	PlayerTurnFixture.enter_player_turn(demo)
	await process_frame
	await process_frame
	demo.set_process(false)
	var s := demo.session as BattleCoreReactionsSession
	s.selected_unit().vitals.set_hp(10)
	demo._refresh()
	demo._pointer_position = Vector2(-1, -1)
	demo.board_view.hover_cell = Vector2i(-1, -1)
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var counters := s.context.simulation_counters()
	var last := s.last_receipt
	demo._action_bar_hovered(&"guard")
	check(demo._action_forecast_pending and not demo._action_forecast_worker.is_started() and demo._guard_forecast == null, "hover records request without capture or simulation")
	check(demo._forecast_panel.text.contains("Рассчитываем") and demo._forecast_panel.visible, "pending feedback immediately visible")
	await capture("action-pending")
	demo._process_action_forecast()
	var generation := demo._action_forecast_job_generation
	demo._action_bar_hovered(&"healing_item")
	check(demo._action_forecast_generation != generation and demo._action_forecast_kind == &"healing", "latest action replaces running request")
	await settle()
	check(demo._guard_forecast == null and demo._item_forecast != null and demo._item_forecast.snapshot_after == s.preview_healing_item().snapshot_after, "old guard cannot replace latest healing")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.simulation_counters() == counters and s.last_receipt == last, "worker hover isolates live state")
	await capture("action-ready")
	demo._clear_forecast()
	demo._action_bar_hovered(&"healing_item")
	demo._process_action_forecast()
	s.selected_unit().vitals.set_hp(5)
	demo._refresh()
	demo._action_bar_hovered(&"healing_item")
	await settle()
	check(demo._item_forecast != null and demo._item_forecast.snapshot_after == s.preview_healing_item().snapshot_after, "refresh discards old capture even without revision change")
	demo._clear_forecast()
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	demo._hovered_bar_action = &""
	demo._pointer_position = demo._forecast_panel.global_position + Vector2(25, 25)
	demo._resolve_hover_exit()
	check(demo._action_forecast_pending, "panel transition retains pending forecast")
	await settle()
	check(demo._guard_forecast != null and demo._guard_forecast.status == ActionReceipt.APPLIED, "pending result publishes on panel")
	demo._pointer_position = Vector2(-1, -1)
	demo._clear_forecast()
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	demo._action_bar_hover_left(&"guard")
	await process_frame
	await settle()
	check(demo._guard_forecast == null and not demo._action_forecast_pending, "leaving discards pending result")
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	s.selected_unit().action_resources.try_spend_main(1)
	demo._use_guard()
	await settle()
	check(s.last_receipt.status == ActionReceipt.REJECTED and not s.selected_unit().guard_stance and demo._guard_forecast == null, "click validates fresh state without waiting for old success")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	demo.select_character(demo.session.units[2].id)
	await settle()
	check(demo._guard_forecast == null or demo._guard_forecast.actor_id == demo.session.selected_id, "selection cannot publish old actor")
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	demo.end_turn()
	await settle()
	check(demo._guard_forecast == null and not demo._action_forecast_pending, "enemy phase discards player request")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	demo._action_bar_hovered(&"guard")
	demo._process_action_forecast()
	var worker: RefCounted = demo._action_forecast_worker
	demo.queue_free()
	await process_frame
	check(not worker.is_started(), "destroy joins outstanding worker")
	viewport.queue_free()
	await process_frame
	print("ACTION ASYNC UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
