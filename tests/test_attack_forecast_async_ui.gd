extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

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
	# Подробный прогноз/реестр проверяется в явно открытой диагностике.
	demo.set_diagnostics_visible(true)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	# Останавливаем только автоматический tick: ввод идёт через настоящий SubViewport.
	demo.set_process(false)
	await test_ally_selection_during_attack()
	await test_balance_reserve_text()
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
	check(demo.board_view.compact_forecast.label.text.contains("Расчёт") and demo.board_view.compact_forecast.model.affected_ids.is_empty(), "compact pending has no predicted values")
	check_header(s.units[2], target, "pending identifies attacker and target")
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
	check_header(s.units[2], other, "pending header replaces old target immediately")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(other.id)), "obsolete result cannot overwrite latest target")
	check_header(s.units[2], other, "ready refusal keeps latest attacker and target")
	check(demo.board_view.compact_forecast.label.text.contains("Недоступно") and demo.board_view.compact_forecast.model.affected_ids.is_empty(), "refusal stays visible beside target without partial numbers")
	check(snapshot() == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and s.last_receipt == receipt, "asynchronous hover preserves all live state")
	push_motion(at(target.cell))
	await settle()
	var forecast := demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "ordinary attack gets exact ready forecast")
	check_header(s.units[2], target, "ready attack keeps attacker and target")
	check(demo.board_view.forecast == forecast and not demo.board_view._forecast_entry(target.id).is_empty(), "ready result updates existing health overlay")
	await compact_layout_and_focus(s, target)
	push_motion(at(target.cell))
	demo._process_attack_forecast()
	check(demo._forecast == forecast and not demo._attack_forecast_worker.is_started(), "unchanged hover reuses completed result")
	await capture("attack-ready")
	push_motion(Vector2(2, 2))
	await process_frame
	check(demo._forecast == null and not demo._attack_forecast_pending and demo.board_view.forecast == null, "leaving clears completed result")
	check_no_header("leaving clears ready names")

	# Результат разрешено дочитать на панели даже при переходе туда до завершения.
	push_motion(at(target.cell))
	demo._process_attack_forecast()
	push_motion(demo._forecast_panel.global_position + Vector2(20, 20))
	await process_frame
	check(demo._attack_forecast_pending, "pending target survives move into reading panel")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(target.id)), "worker publishes while pointer reads panel")
	check_header(s.units[2], target, "reading panel keeps current names")
	push_motion(Vector2(2, 2)); await process_frame
	push_motion(at(target.cell)); demo._process_attack_forecast()
	push_motion(Vector2(2, 2)); await process_frame
	await drain()
	check(demo._forecast == null and not demo._attack_forecast_pending, "leaving pending request discards its eventual result")
	check_no_header("leaving pending clears names after obsolete completion")
	push_motion(at(target.cell)); demo._process_attack_forecast()
	push_key(KEY_ESCAPE)
	check_no_header("escape clears names immediately")
	await drain()
	check_no_header("escape prevents obsolete names returning")
	demo.set_attack_mode(true)
	push_motion(at(target.cell))

	# Смена определения не обязана менять revision, но меняет смысл прогноза.
	s.action_slot_overrides[s.selected_id] = [&"entangling_strike", &"blood_rune"]
	demo._refresh()
	push_motion(at(target.cell)); demo._process_attack_forecast()
	var revision := s.context.get_revision()
	push_key(KEY_3)
	check(demo._attack_forecast_variant == &"entangle" and s.context.get_revision() == revision, "K8 key replaces pending ordinary request at same revision")
	await settle()
	check(same_forecast(demo._forecast, s.preview_attack(target.id)), "K8 worker matches selected synchronous command")
	push_key(KEY_4)
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
	check_no_header("actor selection clears names")

	setup_attack()
	s = demo.session as BattleCoreReactionsSession
	target = s.units[3]
	push_motion(at(target.cell)); demo._process_attack_forecast()
	s.phase = BattleTacticalSession.Phase.ENEMY_TURN
	await settle()
	check(demo._forecast == null and not demo._attack_forecast_pending, "phase gate rejects stale completion before next UI refresh")
	check_no_header("phase gate clears names")
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
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
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

func test_ally_selection_during_attack() -> void:
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	var s := demo.session as BattleCoreReactionsSession
	var astra := s.units[0]
	var target := s.units[5]
	var ray := s.units[4]
	# Плоская пустая арена оставляет единственной переменной направление атаки.
	for y in s.board.height:
		for x in s.board.width:
			var cell := Vector2i(x, y)
			s.board.set_terrain(cell, TerrainType.Type.FLOOR)
			s.board.set_height_steps(cell, 0)
	check(s.board.move_unit(astra, Vector2i(3, 2)), "fixture places Astra north of target")
	check(s.board.move_unit(s.units[1], Vector2i(0, 7)), "fixture stages enemy one")
	check(s.board.move_unit(s.units[2], Vector2i(1, 7)), "fixture stages ally two")
	check(s.board.move_unit(s.units[3], Vector2i(2, 7)), "fixture stages ally three")
	check(s.board.move_unit(ray, Vector2i(2, 3)), "fixture places Ray west of target")
	check(s.board.move_unit(target, Vector2i(3, 3)), "fixture places Dozorny between attackers")
	for attacker: UnitState in [astra, ray]:
		attacker.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	ray.control.stunned_turns = 0
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
	target.vitals.set_hp(256.0)
	demo._refresh()
	check(astra.debug_name == "Астра" and ray.debug_name == "Рей" and target.debug_name == "Дозорный", "fixture unit indices match named actors and target")

	await click_cell(ray.cell)
	check(s.selected_id == ray.id, "field click selects Ray through viewport")
	push_key(KEY_A)
	push_motion(at(target.cell))
	check(demo._attack_forecast_pending, "Ray hover queues attack forecast")
	check_header(ray, target, "Ray pending header")
	demo._process_attack_forecast()
	check(demo._attack_forecast_worker.is_started(), "Ray forecast is running before ally click")
	var before_snapshot := snapshot()
	var before_rng := s.context.get_rng().to_dict().duplicate(true)
	var before_counters := s.context.simulation_counters()
	var before_receipt := s.last_receipt
	var before_journal := demo._journal.size()
	await click_cell(astra.cell)
	var pending_execution_after_click := demo.is_execution_pending()
	check(not pending_execution_after_click, "ally click does not start a live attack worker")
	if pending_execution_after_click:
		await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	var switched_during_pending := s.selected_id == astra.id and not demo.attack_mode and not demo.is_execution_pending()
	check(switched_during_pending, "clicking Astra during attack immediately selects her and returns to move mode")
	if not switched_during_pending:
		await drain()
		return
	check(s.last_receipt == before_receipt and demo._journal.size() == before_journal, "ally selection creates no receipt or journal entry")
	check(snapshot() == before_snapshot and s.context.get_rng().to_dict() == before_rng and s.context.simulation_counters() == before_counters, "pending forecast and ally selection preserve battle state")
	await drain()
	check(demo._forecast == null and not demo._attack_forecast_pending, "Ray forecast cannot publish after switching to Astra")
	check_no_header("ally selection clears pending Ray names")

	# Повторяем выбор с уже готовым прогнозом, чтобы проверить обе стадии worker.
	await click_cell(ray.cell)
	push_key(KEY_A)
	push_motion(at(target.cell))
	await settle()
	var ray_forecast := demo._forecast
	check(ray_forecast != null and ray_forecast.status == ActionReceipt.APPLIED and ray_forecast.units.has(target.id) and ray_forecast.units[target.id]["after"]["cell"] == Vector2i(4, 3), "ready Ray forecast pushes east")
	await click_cell(astra.cell)
	pending_execution_after_click = demo.is_execution_pending()
	check(not pending_execution_after_click, "ally click with ready forecast does not start a live worker")
	if pending_execution_after_click:
		await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	var switched_during_ready := s.selected_id == astra.id and not demo.attack_mode and demo._forecast == null
	check(switched_during_ready, "ally click also clears a ready Ray forecast")
	if not switched_during_ready: return
	check_no_header("ally selection clears ready Ray names")
	check(s.last_receipt == before_receipt and demo._journal.size() == before_journal, "ready-forecast selection still executes no command")

	push_key(KEY_A)
	push_motion(at(target.cell))
	check_header(astra, target, "Astra pending header replaces Ray")
	await settle()
	var astra_forecast := demo._forecast
	check_header(astra, target, "Astra ready header replaces Ray")
	check(demo._attack_forecast_actor == astra.id and astra_forecast != null, "fresh hover belongs to Astra")
	var valid_astra_forecast := astra_forecast != null and astra_forecast.status == ActionReceipt.APPLIED and astra_forecast.units.has(target.id)
	check(valid_astra_forecast and astra_forecast.units[target.id]["after"]["cell"] == Vector2i(3, 4), "Astra forecast pushes south")
	if not valid_astra_forecast: return
	var expected_snapshot := astra_forecast.snapshot_after
	var expected_rng: Dictionary = astra_forecast.rng_after.duplicate(true)
	var expected_counters: Dictionary = astra_forecast.counters_after.duplicate(true)
	push_click(at(target.cell))
	check_no_header("live execution clears attack names before join")
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	var receipt := s.last_receipt
	check_no_header("completed action leaves no old names")
	var attacked_by_astra := false
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"attacked" and event.get("actor_unit_id") == astra.id and event.get("target_unit_id") == target.id:
			attacked_by_astra = true
	check(attacked_by_astra, "live attack is executed by selected Astra")
	check(receipt.get_events() == astra_forecast.events and snapshot() == expected_snapshot, "live receipt and full snapshot match Astra forecast")
	check(s.context.get_rng().to_dict() == expected_rng and s.context.simulation_counters() == expected_counters, "live RNG and counters match Astra forecast")
func check_header(actor: UnitState, target: UnitState, label: String) -> void:
	check(demo._forecast_panel.get_parsed_text().get_slice("\n", 0) == "%s → %s" % [actor.debug_name, target.debug_name], label)
	check(demo.board_view.compact_forecast.visible and demo.board_view.compact_forecast.label.text.get_slice("\n", 0).contains("%s → %s" % [actor.debug_name, target.debug_name]), "compact " + label)

func check_no_header(label: String) -> void:
	# После удара под курсором может уже начаться прогноз движения на пустую клетку.
	check(not demo._forecast_panel.get_parsed_text().get_slice("\n", 0).contains(" → "), label)
	check(not demo.board_view.compact_forecast.visible or not demo.board_view.compact_forecast.label.text.get_slice("\n", 0).contains(" → "), "compact " + label)

func test_balance_reserve_text() -> void:
	setup_attack()
	var target := demo.session.units[3]
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 12.0)
	# Отдельно от теста снятия пут: здесь нужен неизменный максимум до и после удара.
	target.control.entangled_turns = 0
	target.vitals.set_balance(11.0)
	demo.board_view.refresh()
	var before := snapshot()
	check(demo._inspection_text(target).contains("Равновесие: 1/12"), "diagnostic inspection shows remaining reserve instead of disruption")
	check(demo._event_text({"kind": &"balance_changed", "target_unit_id": target.id, "balance_after": 4.0, "balance_max": 12.0}).contains("равновесие 8/12"), "event log uses the same reserve convention")
	push_motion(at(target.cell))
	await settle()
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED, "reserve fixture gets a real worker attack forecast")
	check(demo._forecast_panel.get_parsed_text().contains("равновесие 1/12 → 12/12"), "diagnostic forecast shows full final reserve after break")
	check(demo.board_view.compact_forecast.label.text.contains("1/12→12/12") and demo.board_view.compact_forecast.label.text.contains("Потеря равновесия"), "compact forecast distinguishes break from recovery despite full final reserve")
	check(snapshot() == before, "reserve text and real worker preview leave live state unchanged")

func compact_layout_and_focus(s: BattleCoreReactionsSession, target: UnitState) -> void:
	var board := demo.board_view
	var card := board.compact_forecast
	var selected := s.selected_id
	var before := snapshot()
	demo.set_diagnostics_visible(false)
	await process_frame; await process_frame
	check(card.visible and card.label.text.contains("ОЗ") and card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "compact ready forecast needs no diagnostic panel and cannot steal target click")
	await capture("compact-ready")
	for zoom: float in [0.75, 1.0, 2.5]:
		board.zoom_camera(zoom, board.size * 0.5)
		await process_frame; await process_frame
		check(Rect2(Vector2.ZERO, board.size).encloses(card.get_rect()), "compact forecast stays inside viewport at %s zoom" % zoom)
	board.reset_camera()
	board.set_acting_unit(s.units[1].id)
	demo._displayed_unit_hovered(target.id)
	check(board.displayed_selected_id == selected and s.selected_id == selected, "hover and acting indicators never change selected actor")
	check(board._presentation_visual(selected).selected and board._presentation_visual(target.id).hovered and board._presentation_visual(s.units[1].id).acting, "selected hovered and acting have separate visual flags")
	var copied := ActionPresentationState.capture(s.state)
	board.execution_pending = true
	board.session = null
	board.show_presentation_state(copied)
	demo._displayed_unit_hovered(target.id)
	check(board._presentation_visual(selected).selected and board._presentation_visual(target.id).hovered and board._presentation_visual(s.units[1].id).acting, "published frame preserves three indicators without runtime owner")
	check(snapshot() == before, "compact forecast and indicators preserve live snapshot")
	board.session = s
	board.execution_pending = false
	board.set_acting_unit(UnitId.NONE)
	demo.set_diagnostics_visible(true)
	board.refresh()
	await process_frame; await process_frame

func click_cell(cell: Vector2i) -> void:
	push_motion(at(cell))
	await process_frame
	push_click(at(cell))
	await process_frame

func setup_attack() -> void:
	push_motion(Vector2(2, 2))
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
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
