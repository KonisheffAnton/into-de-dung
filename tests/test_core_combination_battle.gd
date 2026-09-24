extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var board: BattleDemoBoard
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/tactical_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	var entry := find_button(demo, "Сочетания ядра")
	check(entry != null, "tactical toolbar exposes combination entry")
	if entry != null: await click(entry.global_position + entry.size * 0.5)
	check(demo.core_combination_mode and demo.control_mode and demo.environment_mode and demo.session is BattleCoreCombinationSession, "real click opens combined session with display flags")
	if not demo.session is BattleCoreCombinationSession:
		await finish()
		return
	var session := demo.session as BattleCoreCombinationSession
	board = demo.board_view
	check(demo._heading.text.contains("Сочетания ядра"), "combined heading is visible")
	check_rear_markers(session, "toolbar entry")
	var rules := session.context.get_attack_rules()
	var strike := rules.get_definition(&"demo_strike")
	var rune := rules.get_definition(&"blood_rune")
	check(strike.backstab_bonus_percent == 50 and strike.critical_on_control and rune.backstab_bonus_percent == 50 and rune.critical_on_control, "D3 attack definitions retain their critical policy and add C1 modifiers")
	check(session.units.size() >= 6 and session.units[0].cell == Vector2i(0, 2) and session.units[3].cell == Vector2i(3, 3), "live roster starts in the planned positions: %s" % str(session.units.map(func(unit: UnitState) -> Vector2i: return unit.cell)))
	check(session.units[1].control.stunned_turns == 1 and session.units[3].control.entangled_turns == 1 and session.units[3].bleeding.immune, "initial control and bleeding immunity capabilities")
	var all_living_controlled := true
	var live_count: int = 0
	for unit: UnitState in session.units:
		if unit.is_alive():
			live_count += 1
			all_living_controlled = all_living_controlled and unit.control != null
	check(live_count == 6 and all_living_controlled, "six living combatants have control state")
	check(session.units.size() == 7 and not session.units[6].is_alive() and session.units[6].control == null, "pre-existing body has no control state")
	await capture("core-start")
	var actor := session.units[2]
	var target := session.units[3]
	await click(at(actor))
	check(demo._stats.text.contains("Пробивание 50%") and demo._stats.text.contains("Оружие: 4.0"), "Bor inspection exposes equipped piercing with unchanged weapon damage")
	await capture("core-piercing-inspection")
	await key(KEY_A)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var counters_before := session.context.simulation_counters()
	var receipt_before := session.last_receipt
	await motion(at(target))
	var forecast := demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "rear attack forecast is available")
	check(demo._forecast_panel.text.contains("Удар в спину +50%") and demo._forecast_panel.text.contains("Крит ×2"), "forecast combines backstab and control critical")
	check(demo._forecast_panel.text.contains("Физический · в обход брони"), "combined forecast displays the actual piercing damage row")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before and session.context.simulation_counters() == counters_before and session.last_receipt == receipt_before, "hover leaves live state, events, and steps unchanged")
	await capture("core-forecast")
	var expected: Dictionary = forecast.snapshot_after.duplicate(true) if forecast != null else {}
	await click(at(target))
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == expected, "real attack matches forecast state")
	check(session.last_receipt.get_events() == forecast.events and session.last_receipt.get_steps() == forecast.steps, "real attack matches forecast events and steps")
	check(target.vitals.get_hp() == 17.0 and target.bleeding.ticks_left == 0 and target.cell == Vector2i(2, 3), "piercing rear critical deals 15 HP, preserves immunity and pushes onto spikes")
	await capture("core-result")
	check(not demo.attack_mode and not session.rune_selected and demo._forecast == null and demo._move_button.button_pressed, "combined attack returns to movement and clears forecast")
	await test_piercing_bleeding_input()
	await test_action_input()
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	board = demo.board_view
	check(demo.core_combination_mode and session.units[0].cell == Vector2i(0, 2), "reset restores the combined scenario")
	# Поднятие проверяет D5-путь в той же production-сессии.
	actor = session.units[0]
	await click(at(actor)); await key(KEY_6); await click(at_cell(Vector2i(0, 3)))
	var helper := session.state.active_summon(actor.id)
	check(helper != null and helper.control == null and session.state.is_summon_pending(helper.id), "raised helper has no control state and waits for its turn")
	board.refresh()
	check_rear_markers(session, "nullable-control helper")
	check(demo._log.text.contains("поднял тело"), "raising body is reported")
	await key(KEY_ENTER)
	for _step in 12:
		if session.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		await create_timer(0.8).timeout
	check(session.phase != BattleTacticalSession.Phase.ENEMY_TURN and session.phase != BattleTacticalSession.Phase.FAULTED, "real AI steps finish without fault: %s / %s" % [session.phase_text(), demo._status.text])
	check(not session.state.is_summon_pending(helper.id), "helper joins after the team boundary: %s" % str(session.state.is_summon_pending(helper.id)))
	# Новый бой возвращает цель и статусы, чтобы проверить отказ без оплаты.
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	board = demo.board_view
	var stunned := session.units[4]
	await click(at(stunned)); await key(KEY_A); await click(at(session.units[5]))
	check(stunned.action_resources.get_main_left() == 1 and demo._status.text.contains("отклонено") and demo._status.text.contains("оглушён"), "stunned ally is rejected without spending main action: %d / %s" % [stunned.action_resources.get_main_left(), demo._status.text])
	# Начинаем ИИ и сразу сбрасываем; кадровая пауза ловит запоздалый шаг прежнего боя.
	await key(KEY_ENTER)
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	var reset_snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	for _frame in 8: await process_frame
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == reset_snapshot, "reset during AI prevents stale actions")
	check(demo.core_combination_mode and demo._forecast == null and not demo.attack_mode and not demo.raising_mode and not demo.summoning_mode, "reset preserves scenario and clears UI modes")
	await click(demo._mode_button.global_position + demo._mode_button.size * 0.5)
	check(not demo.core_combination_mode and not demo.control_mode and not demo.environment_mode, "switching to another scenario clears combined flags")
	check_no_rear_markers("other scenario")
	if find_button(demo, "Сочетания ядра") != null:
		await click(find_button(demo, "Сочетания ядра").global_position + find_button(demo, "Сочетания ядра").size * 0.5)
	check(demo.core_combination_mode and demo.session is BattleCoreCombinationSession and demo._forecast == null and not demo.raising_mode and not demo.attack_mode, "return opens a clean combined scenario")
	demo.queue_free()
	await process_frame
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	check(main_scene == "res://scenes/demo/core_combination_battle.tscn", "F5 starts the combined scenario")
	demo = (load(main_scene) as PackedScene).instantiate()
	viewport.add_child(demo)
	await process_frame; await process_frame
	board = demo.board_view
	check(demo.core_combination_mode and demo.session is BattleCoreCombinationSession, "direct scene entry creates combined session")
	check(demo.session.units[2].get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50.0, "F5 scene equips Bor with piercing")
	check_rear_markers(demo.session as BattleCoreCombinationSession, "direct scene entry")
	for obsolete: String in ["Броня", "Кровотечение", "Среда / трупы", "Крит / спина"]:
		check(find_button(demo, obsolete) == null, "obsolete scenario removed from navigation: " + obsolete)
	await finish()

func test_piercing_bleeding_input() -> void:
	await key(KEY_R)
	var session := demo.session as BattleCoreCombinationSession
	var actor := session.units[2]
	var target := session.units[5]
	await click(at(actor)); await click(at_cell(Vector2i(4, 4)))
	check(actor.cell == Vector2i(4, 4) and actor.action_resources.get_main_left() == 1, "Bor moves to E5 without spending attack main")
	await key(KEY_A)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await motion(at(target))
	var forecast := demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED and demo._forecast_panel.text.contains("Физический · в обход брони"), "ordinary piercing against nonimmune Watcher is forecast")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before and target.bleeding.ticks_left == 0, "piercing hover does not apply bleeding or spend resources")
	await capture("core-piercing-bleeding")
	if forecast == null: return
	await click(at(target))
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after and session.last_receipt.get_events() == forecast.events and session.last_receipt.get_steps() == forecast.steps, "ordinary piercing click matches full forecast")
	check(target.vitals.get_hp() == 27.0 and target.bleeding.ticks_left == 2 and actor.action_resources.get_main_left() == 0, "ordinary piercing opens bleeding gate through armor for one main")
	check(not demo.attack_mode and not session.rune_selected and demo._move_button.button_pressed, "piercing strike returns to movement")

func test_action_input() -> void:
	await key(KEY_R)
	var session := demo.session as BattleCoreCombinationSession
	var actor := session.units[2]
	await click(at(actor)); await key(KEY_5)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await click(at_cell(Vector2i(4, 2)))
	check(not demo.attack_mode and not session.rune_selected and demo._status.text.contains("недопустимая цель"), "rune invalid target returns movement and clears selected ability")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "rune refusal does not spend or move")
	await key(KEY_5); await click(at(session.units[3]))
	check(session.last_receipt.status == ActionReceipt.APPLIED and actor.action_resources.get_main_left() == 0 and not demo.attack_mode and not session.rune_selected, "successful rune spends main then returns movement")
	await key(KEY_R)
	actor = session.units[0]
	await click(at(actor)); await key(KEY_6)
	before = ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await click(at_cell(Vector2i(1, 2)))
	check(not demo.raising_mode and demo._status.text.contains("недопустимая цель") and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "invalid body target returns movement without spending")
	await key(KEY_6); await click(at_cell(Vector2i(0, 3)))
	check(session.last_receipt.status == ActionReceipt.APPLIED and actor.action_resources.get_main_left() == 0 and not demo.raising_mode and demo._move_button.button_pressed, "successful raising returns movement")
	await key(KEY_R)
	actor = session.units[0]
	await click(at(actor)); await key(KEY_5); await key(KEY_2)
	check(actor.guard_stance and actor.action_resources.get_main_left() == 0 and not demo.attack_mode and not session.rune_selected, "instant guard clears rune selection and returns movement")
	await key(KEY_R)
	actor = session.units[0]
	actor.vitals.apply_damage(10.0)
	demo._refresh()
	await click(at(actor)); await key(KEY_5); await key(KEY_3)
	check(session.last_receipt.status == ActionReceipt.APPLIED and actor.action_resources.get_main_left() == 0 and not demo.attack_mode and not session.rune_selected, "instant healing clears rune selection and returns movement")
	await key(KEY_R)
	actor = session.units[0]
	await click(at(actor)); await key(KEY_5); await key(KEY_4)
	check(session.last_receipt.status == ActionReceipt.APPLIED and actor.action_resources.get_main_left() == 0 and not demo.attack_mode and not session.rune_selected, "instant armor restoration clears rune selection and returns movement")

func finish() -> void:
	if demo != null: demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("CORE COMBINATION UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CORE COMBINATION UI: " + label)

func check_rear_markers(session: BattleCoreCombinationSession, label: String) -> void:
	var player_marked := false
	var enemy_marked := false
	var helper_marked := false
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.unit == null: continue
		if visual.unit.faction == Faction.Type.PLAYER and visual.unit.is_alive(): player_marked = visual.show_rear
		if visual.unit.faction == Faction.Type.ENEMY and visual.unit.is_alive(): enemy_marked = visual.show_rear
		if session.state.active_summon(session.units[0].id) == visual.unit: helper_marked = visual.show_rear
	check(player_marked and enemy_marked, label + ": both factions show rear markers")
	if session.state.active_summon(session.units[0].id) != null:
		check(helper_marked, label + ": nullable-control helper shows rear marker")

func check_no_rear_markers(label: String) -> void:
	var no_markers := true
	for visual: BattleDemoIsoVisual in board._entity_visuals:
		if visual.unit != null: no_markers = no_markers and not visual.show_rear
	check(no_markers, label + ": unrelated scenario hides rear markers")

func find_button(node: Node, label: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.begins_with(label): return child as Button
		var nested := find_button(child, label)
		if nested != null: return nested
	return null

func at(unit: UnitState) -> Vector2:
	return board.global_position + board.cell_center(unit.cell)

func at_cell(cell: Vector2i) -> Vector2:
	return board.global_position + board.cell_center(cell)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	# В headless SceneTree frame_post_draw может не прийти для отключённого оконного рендера.
	await process_frame; await process_frame
	var texture := viewport.get_texture()
	if texture == null:
		check(false, "PNG " + label + ": viewport texture unavailable in dummy renderer")
		return
	var picture := texture.get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
