extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""
var callback_on_main: bool = false

class FailedLaunchWorker extends BattleExecutionWorker:
	func _start_thread(_args: Array) -> Error:
		return ERR_CANT_CREATE

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE EXECUTION UI: " + label)

func settle() -> void:
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func clicked(cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = demo.board_view.global_position + demo.board_view.cell_center(cell)
	event.global_position = event.position
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)

func hp_changed(_before: float, _after: float) -> void:
	callback_on_main = OS.get_thread_caller_id() == OS.get_main_thread_id()

func _assign_slots(actions: Array[StringName]) -> void:
	var session := demo.session as BattleCoreReactionsSession
	session.action_slot_overrides[session.selected_id] = actions.duplicate()
	demo._refresh()

func _assigned_slots_match(unit_id: int, expected: Array[StringName]) -> bool:
	var session := demo.session as BattleCoreReactionsSession
	return session.action_slot_overrides.get(unit_id, []) == expected

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	demo.set_process(false)
	var old_status := demo._stats.text
	var first_view: BattleUnitView = demo.board_view._view_units[0].unit
	var old_cell: Vector2i = demo.board_view._view_units[0].cell
	clicked(Vector2i(1, 2))
	check(demo.is_execution_pending(), "real click dispatches background live move")
	check(demo.session == null and demo._battle == null and demo.board_view.session == null, "UI has no session access before join")
	check(demo.board_view.execution_pending and demo._stats.text == old_status and demo.board_view._view_units[0].cell == old_cell, "last completed view remains consistent")
	# Даже если поток уже завершился, только публикация возвращает UI владение.
	demo.handle_cell(Vector2i(2, 2))
	demo.select_character(first_view.id)
	demo.inspect_enemy(999)
	demo.set_attack_mode(true)
	demo._action_bar_requested(&"guard")
	demo._use_guard()
	demo._use_healing_item()
	demo._choose_summoning()
	demo._choose_raise()
	demo._choose_reaction_guard(CombatPerksState.Mode.COVER)
	demo.end_turn()
	demo._hover(Vector2i(2, 2))
	demo._action_bar_hovered(&"healing_item")
	demo._refresh()
	demo._refresh_inspection()
	demo._process_attack_forecast()
	demo._process_move_forecast()
	demo._process_action_forecast()
	demo.board_view.refresh()
	demo.board_view.refresh_forecast()
	demo.board_view.size += Vector2(12, 8)
	demo.board_view._rescale_layout()
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals: visual.queue_redraw()
	await capture("execution-pending")
	check(demo.session == null and demo.board_view._view_units[0].cell == old_cell and demo.board_view._view_units[0].unit == first_view, "resize redraw and all input preserve detached view")
	await settle()
	check(demo.session.selected_unit().cell == Vector2i(1, 2) and demo.board_view._view_units[0].cell == Vector2i(1, 2), "join publishes one completed move")
	check(first_view != demo.board_view._view_units[0].unit and first_view.hp == demo.session.units[0].vitals.get_hp(), "new projection replaces values")
	await capture("execution-completed")
	# Выбор не пополняет остатки, а reset не принимает receipt в новую сессию.
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)
	clicked(demo.session.units[3].cell)
	check(demo.is_execution_pending(), "attack async")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	check(not demo.is_execution_pending() and demo.session.units[3].is_alive() and demo.session.selected_unit().action_resources.get_main_left() == 1, "reset joins before rebuilding runtime")
	check(not demo._journal.any(func(line: String) -> bool: return line.contains("атакует")), "old receipt not published after reset")
	var count_before := demo.session.units.size()
	var summon_session := demo.session as BattleCoreReactionsSession
	var summoner_id := summon_session.selected_id
	_assign_slots([&"summoning_item", &"safe_retreat"])
	check(_assigned_slots_match(summoner_id, [&"summoning_item", &"safe_retreat"]), "summoning fixture uses its explicit two-slot loadout")
	demo._action_bar._next_page()
	check(demo._action_bar._page == 0, "compact action bar ignores page navigation")
	demo._choose_summoning()
	clicked(Vector2i(0, 1))
	check(demo.is_execution_pending(), "summon async")
	await settle()
	check(demo._action_bar._page == 0 and _assigned_slots_match(summoner_id, [&"summoning_item", &"safe_retreat"]), "worker publication preserves actor loadout without page state")
	check(demo.session.units.size() == count_before + 1 and demo.board_view._view_units.size() == demo.session.units.size(), "summon publication includes new helper: " + str(demo.session.last_receipt.reason) + " count=" + str(demo.session.units.size()))
	demo.end_turn()
	check(demo.is_execution_pending(), "turn boundary async")
	await settle()
	var steps: int = 0
	while demo._battle.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		demo._process(1.0)
		await settle()
		steps += 1
	check(demo._battle.phase == BattleTacticalSession.Phase.PLAYER_TURN and demo._battle.round_number == 2, "AI and both boundaries publish complete round")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	_assign_slots([&"raise_corpse", &"safe_retreat"])
	count_before = demo.session.units.size()
	demo._choose_raise()
	clicked(Vector2i(0, 3))
	check(demo.is_execution_pending(), "raise async")
	await settle()
	check(demo.session.units.size() == count_before + 1, "raise completes with helper: " + str(demo.session.last_receipt.reason) + " count=" + str(demo.session.units.size()))
	# Отказ ОС возвращает владельца до sync-вызова, сохраняя прежний показ.
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	var fallback_session := demo.session
	demo._execution_worker = FailedLaunchWorker.new()
	demo.presentation_enabled = true
	demo._use_guard()
	check(demo.session == fallback_session and demo.board_view.session == fallback_session and demo._battle == fallback_session, "launch failure restores all UI owners before fallback")
	check(not demo._execution_worker.is_started() and demo.is_presentation_pending(), "launch failure synchronous result still starts presentation")
	check(demo._presentation_roots.size() == 1 and fallback_session.selected_unit().action_resources.get_main_left() == 0, "launch failure executes and captures guard once")
	await settle()
	check(not fallback_session._queue.capture_presentation and demo._presentation_before.is_empty(), "fallback presentation finishes and clears capture")
	demo._execution_worker = BattleExecutionWorker.new()
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	_assign_slots([&"restore_armor", &"healing_item"])
	demo.session.units[0].vitals.set_hp(10)
	demo.session.units[0].vitals.hp_changed.connect(hp_changed)
	demo._use_healing_item()
	check(not demo.is_execution_pending() and callback_on_main and demo.session.units[0].vitals.get_hp() > 10, "external callback executes on main via sync fallback")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	demo.session._queue._max_commands = 1
	demo.select_character(demo.session.units[2].id)
	demo.set_attack_mode(true)
	clicked(demo.session.units[3].cell)
	await settle()
	check(demo._battle.phase == BattleTacticalSession.Phase.FAULTED and demo._status.text.contains("остановлено"), "FAULTED prefix published to UI")
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	clicked(Vector2i(1, 2))
	demo.toggle_scenario()
	check(not demo.is_execution_pending() and not demo.session is BattleCoreReactionsSession, "scenario switch joins previous owner")
	demo._open_core_combination_scenario()
	PlayerTurnFixture.enter_player_turn(demo)
	clicked(Vector2i(1, 2))
	var worker := demo._execution_worker
	demo.queue_free()
	await process_frame
	check(not worker.is_started(), "exit joins before closing runtime")
	viewport.queue_free()
	await process_frame
	print("BATTLE EXECUTION UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
