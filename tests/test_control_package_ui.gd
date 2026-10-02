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
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CONTROL PACKAGE UI: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene_path: String = "res://scenes/demo/core_reactions_battle.tscn"
	var scene := load(scene_path) as PackedScene
	demo = scene.instantiate() as BattleDemo
	demo.set("deployment_enabled", false)
	viewport.add_child(demo)
	# Подробный прогноз/реестр проверяется в явно открытой диагностике.
	demo.set_diagnostics_visible(true)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	check(session != null and demo.core_reactions_mode, "standalone scene opens reaction session")
	if session == null:
		quit(1)
		return
	session.action_slot_overrides[session.selected_id] = [&"opportunity_guard", &"stunning_strike"]
	demo._refresh()
	check(demo.size.x <= viewport.size.x and demo._action_bar.global_position.x + demo._action_bar.size.x <= viewport.size.x, "long perk and control labels preserve viewport width")
	check(session.units[0].combat_perks.definition.stunning_strike and session.units[1].combat_perks.definition.stunning_strike, "Astra and Strazh own stunning strike")
	check(session.units[3].combat_perks.definition.stun_immune and not session.units[3].combat_perks.definition.entangle_immune, "Shield owns stun immunity only")
	check(session.units[4].combat_perks.definition.entangle_immune and not session.units[4].combat_perks.definition.stun_immune and not session.units[4].combat_perks.definition.tank_reactions, "Rei owns entangle immunity without tank reactions")
	check(demo._inspection_text(session.units[3]).to_lower().contains("иммунитет к оглушению") and demo._inspection_text(session.units[4]).to_lower().contains("иммунитет к путам"), "inspection explains each immunity")
	var action_bar := demo.get("_action_bar") as BattleActionBar
	var stun_button := _button_for(&"stunning_strike")
	check(action_bar._buttons.size() == 4 and action_bar._page == 0 and action_bar._buttons[2].get_meta("action_id") == &"opportunity_guard" and stun_button != null and _button_for(&"cover_guard") == null, "explicit tank loadout assigns opportunity and stun to the four-slot bar")
	if stun_button == null:
		quit(1)
		return
	var actor := session.units[0]
	var main_before: int = actor.action_resources.get_main_left()
	await click(stun_button.global_position + stun_button.size * 0.5)
	check(session.stun_selected and demo.attack_mode and actor.action_resources.get_main_left() == main_before, "ability enters target mode without spending")
	await key(KEY_ESCAPE)
	check(not session.stun_selected and not demo.attack_mode and actor.action_resources.get_main_left() == main_before, "escape cancels without charge")
	await click(_roster_button(2).global_position + _roster_button(2).size * 0.5)
	check(session.selected_id == session.units[2].id and _button_for(&"stunning_strike") == null, "nonowner does not receive stun action")
	await click(_roster_button(0).global_position + _roster_button(0).size * 0.5)
	_setup_pair(session, 0, 5)
	session.action_slot_overrides[session.selected_id] = [&"opportunity_guard", &"stunning_strike"]
	demo._refresh()
	# Начать обычный прогноз, затем переключить вариант до завершения worker на том же revision.
	await key(KEY_1)
	var target := session.units[5]
	await motion(at(target.cell))
	demo._process_attack_forecast()
	var original_revision := session.context.get_revision()
	stun_button = _button_for(&"stunning_strike")
	await click(stun_button.global_position + stun_button.size * 0.5)
	check(session.context.get_revision() == original_revision and session.stun_selected and demo._attack_variant() == &"stun", "ordinary forecast variant switches to stun at same revision")
	await motion(demo.board_view.global_position + demo.board_view.cell_center(target.cell))
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED and demo._forecast.steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"stun_apply" and step.get("status") == &"APPLIED"), "stun forecast includes control command")
	check(demo._forecast_panel.text.contains("Оглушение") and demo._forecast_panel.text.to_lower().contains("физический"), "forecast explains stun and physical HP gate")
	await capture("control-stun-forecast")
	await click(demo.board_view.global_position + demo.board_view.cell_center(target.cell))
	check(target.control.stunned_turns == 1 and _journal_text().contains("оглушён"), "fresh target click applies stun and journal describes it")
	check(demo._perk_status_text(target).contains("ОГЛУШЁН") or demo._inspection_text(target).contains("Оглушён"), "roster or inspection shows applied status")
	await capture("control-stun-applied")
	# Иммунитет оставляет обычный урон цели и пропускает только наложение.
	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	session = demo.session as BattleCoreReactionsSession
	_setup_pair(session, 0, 3)
	session.action_slot_overrides[session.selected_id] = [&"opportunity_guard", &"stunning_strike"]
	demo._refresh()
	action_bar = demo.get("_action_bar") as BattleActionBar
	stun_button = _button_for(&"stunning_strike")
	await click(stun_button.global_position + stun_button.size * 0.5)
	actor = session.units[0]
	target = session.units[3]
	main_before = actor.action_resources.get_main_left()
	var hp_before: float = target.vitals.get_hp()
	await motion(demo.board_view.global_position + demo.board_view.cell_center(target.cell))
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)
	check(demo._forecast != null and demo._forecast.steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"stun_apply" and step.get("reason") == &"control/stun_immune"), "immune forecast shows skipped stun")
	check(demo._forecast_panel.text.contains("иммунитет к оглушению"), "forecast localizes stun immunity")
	await click(demo.board_view.global_position + demo.board_view.cell_center(target.cell))
	check(target.control.stunned_turns == 0 and target.vitals.get_hp() < hp_before and actor.action_resources.get_main_left() == main_before - 1, "immunity skips control while normal attack spends action and deals damage")
	check(_journal_text().contains("иммунитет к оглушению"), "journal explains immunity skip after attack")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("CONTROL PACKAGE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _setup_pair(session: BattleCoreReactionsSession, actor_index: int, target_index: int) -> void:
	session.state.environment.fires.clear()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in 6:
		var unit := session.units[index]
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		session.board.move_unit(unit, Vector2i(index, 0))
	var actor := session.units[actor_index]
	var target := session.units[target_index]
	session.board.move_unit(actor, Vector2i(2, 2))
	session.board.move_unit(target, Vector2i(3, 2))
	# Делаем выбранную иммунную цель вражеской, чтобы плейтест проверял удар через настоящий UI.
	if target_index == 3: target.faction = Faction.Type.ENEMY
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
	target.vitals.set_hp(256.0)
	target.armor.natural["physical"] = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	session.select_unit(actor.id)

func _button_for(action_id: StringName) -> Button:
	var action_bar := demo.get("_action_bar") as BattleActionBar
	for button: Button in action_bar._buttons:
		if button.visible and StringName(button.get_meta("action_id", &"")) == action_id: return button
	return null

func _roster_button(unit_index: int) -> Button:
	var unit := demo.session.units[unit_index] as UnitState
	for button: Button in demo._roster.get_children():
		if button.text.begins_with(unit.debug_name): return button
	return null

func _journal_text() -> String:
	return "\n".join(demo._journal)

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

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
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
