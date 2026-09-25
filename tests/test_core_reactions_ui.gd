extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: Variant
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CORE REACTIONS UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	check(main_scene == "res://scenes/demo/core_reactions_battle.tscn", "F5 starts current combined reaction battle")
	var scene := load(main_scene) as PackedScene
	demo = scene.instantiate()
	demo.set("deployment_enabled", false)
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	check(session != null and demo.core_reactions_mode, "new scene selects core reaction session")
	check(session.units[0].combat_perks.definition.tank_reactions and session.units[1].combat_perks.definition.tank_reactions, "only Astra and Strazh own tank perk")
	check(session.units[2].combat_perks.definition.sneak_attack and session.units[5].combat_perks.definition.sneak_attack, "Bor and Dozorny own sneak perk")
	check(session.units[3].combat_perks == null and session.units[4].combat_perks == null, "other units have no perk runtime")
	check(demo._inspection_text(session.units[0]).contains("реакции") and demo._inspection_text(session.units[2]).contains("Скрытая атака"), "inspection describes perks and charge")
	check(demo._inspection_text(session.units[0]).contains("Печать: помощник") and not demo._inspection_text(session.units[0]).contains("призыв недоступен"), "inspection describes available summon seal in combined battle")
	check(_dynamic_descriptors_prefix_intact(), "the eight original actions stay ahead of the perk page")
	var action_bar: BattleActionBar = demo.get("_action_bar")
	check(action_bar._buttons[0].get_meta("action_id") == &"attack" and action_bar._buttons[1].get_meta("action_id") == &"guard", "fixed attack and guard slots remain")
	await click(action_bar._down_button.global_position + action_bar._down_button.size * 0.5)
	check(action_bar._page == 1 and action_bar._buttons[2].get_meta("action_id") == &"opportunity_guard" and action_bar._buttons[3].get_meta("action_id") == &"cover_guard", "tank reaction controls occupy second page")
	demo._refresh()
	check(action_bar._page == 1, "same actor refresh preserves dynamic action page")
	var opportunity_button: Button = action_bar._buttons[2]
	await motion(opportunity_button.global_position + opportunity_button.size * 0.5)
	check(demo._guard_forecast != null and demo._guard_forecast.status == ActionReceipt.APPLIED and demo._forecast_panel.text.contains("Оппортунист"), "opportunity hover shows real guard forecast")
	check(not demo._hint.text.contains("тыл"), "new battle never advertises old rear bonus")
	await capture("reactions-opportunity-forecast")
	demo._action_bar_hovered(&"guard")
	var ordinary_forecast: GuardForecast = demo._guard_forecast
	demo._action_bar_hovered(&"guard")
	check(demo._guard_forecast_mode == CombatPerksState.Mode.NONE and demo._guard_forecast == ordinary_forecast and demo._forecast_panel.text.contains("Охранная стойка"), "ordinary guard has a distinct reusable preview after opportunity")
	var cover_targets := session.cover_targets()
	if cover_targets.is_empty():
		var adjacent := session.units[0].cell + Vector2i(1, 0)
		if session.board.is_in_bounds(adjacent) and not session.board.is_occupied(adjacent): session.board.move_unit(session.units[2], adjacent)
		demo._refresh()
		cover_targets = session.cover_targets()
	check(not cover_targets.is_empty(), "fixture has a geometrically valid cover ally")
	await click(action_bar._buttons[3].global_position + action_bar._buttons[3].size * 0.5)
	check(demo._cover_guard_mode, "cover enters ally-target mode")
	var cover_target := session.board.get_unit_by_id(cover_targets[0])
	await motion(at(cover_target.cell))
	check(demo._guard_forecast != null and demo._guard_forecast_mode == CombatPerksState.Mode.COVER and demo._guard_forecast_target == cover_target.id, "cover hover previews chosen ally")
	var cover_forecast: GuardForecast = demo._guard_forecast
	demo._hover(cover_target.cell)
	check(demo._guard_forecast == cover_forecast, "same cover target reuses forecast")
	await capture("reactions-cover-forecast")
	await key(KEY_ESCAPE)
	check(not demo._cover_guard_mode and session.selected_unit().action_resources.get_main_left() == 1, "escape cancels cover target selection without spending")
	await click(action_bar._buttons[3].global_position + action_bar._buttons[3].size * 0.5)
	var main_before: int = session.selected_unit().action_resources.get_main_left()
	await click(at(cover_target.cell))
	check(not demo._cover_guard_mode and session.selected_unit().guard_stance, "ally click installs cover guard")
	check(session.selected_unit().combat_perks.mode == CombatPerksState.Mode.COVER and session.selected_unit().combat_perks.cover_target_id == cover_target.id, "cover mode stores chosen ally")
	check(session.selected_unit().combat_perks.reaction_left == 1 and session.selected_unit().action_resources.get_main_left() == main_before - 1, "cover install spends one main and preserves shared reaction charge")
	await key(KEY_ESCAPE)
	check(not demo._cover_guard_mode, "escape cancels cover targeting")
	demo.reset_demo()
	session = demo.session as BattleCoreReactionsSession
	action_bar = demo.get("_action_bar")
	await click(action_bar._down_button.global_position + action_bar._down_button.size * 0.5)
	var opportunity_actor := session.selected_unit()
	var opportunity_main_before: int = opportunity_actor.action_resources.get_main_left()
	await click(action_bar._buttons[2].global_position + action_bar._buttons[2].size * 0.5)
	check(opportunity_actor.guard_stance and opportunity_actor.combat_perks.mode == CombatPerksState.Mode.OPPORTUNIST, "opportunity click installs the selected mode")
	check(opportunity_actor.action_resources.get_main_left() == opportunity_main_before - 1 and opportunity_actor.combat_perks.reaction_left == 1, "opportunity install spends one main and leaves the shared charge ready")
	opportunity_actor.combat_perks.reaction_left = 0
	opportunity_actor.action_resources._set_for_refill(1, 1)
	demo._refresh()
	await key(KEY_2)
	check(opportunity_actor.combat_perks.mode == CombatPerksState.Mode.NONE and opportunity_actor.combat_perks.reaction_left == 0 and opportunity_actor.guard_stance, "ordinary guard can disable spent mode through UI")

	# Расставляем тестовые угрозы board API, чтобы прогноз явно включал участников скрытой атаки.
	demo.reset_demo()
	session = demo.session as BattleCoreReactionsSession
	var attacker := session.units[2]
	var target := session.units[5]
	var second_threat := session.units[0]
	check(session.board.move_unit(target, Vector2i(4, 4)), "fixture positions hostile target")
	check(session.board.move_unit(second_threat, Vector2i(3, 4)), "fixture positions second threat")
	demo._refresh()
	await click(at(attacker.cell))
	check(session.selected_id == attacker.id, "roster selection changes attacker")
	await key(KEY_1)
	check(demo.attack_mode, "attack hotkey enters attack mode")
	await motion(at(target.cell))
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED, "sneak target forecast applies: " + (String(demo._forecast.reason) if demo._forecast != null else "missing"))
	var attack_event := _attacked_event(demo._forecast.events)
	var modifiers: Dictionary = attack_event.get("modifiers", {})
	check(modifiers.get("sneak_percent", 0) == 50 and modifiers.get("threat_ids", []).size() >= 2, "forecast's actual modifiers grant sneak with two threats: " + str(modifiers))
	check(demo.board_view.sneak_threat_ids.size() >= 2 and demo._forecast_panel.text.contains("Скрытая атака +50%"), "forecast highlights actual threat participants and explains bonus: " + str(demo.board_view.sneak_threat_ids) + " / " + demo._forecast_panel.text)
	await capture("reactions-sneak-forecast")
	await motion(Vector2(2, 2))
	check(demo._forecast == null and demo.board_view.sneak_threat_ids.is_empty(), "leaving preview clears threat participants")
	await motion(at(target.cell))
	await click(at(target.cell))
	check(_journal_text().contains("Скрытая атака +50%"), "journal explains the applied sneak attack")
	await _opportunity_movement()
	demo.toggle_scenario()
	check(not demo.session is BattleCoreReactionsSession, "sandbox transition leaves reaction session")
	demo._open_core_combination_scenario()
	check(demo.session is BattleCoreReactionsSession and demo.core_reactions_mode, "core entry returns to the current reaction battle")
	demo.deployment_enabled = true
	demo._open_core_combination_scenario()
	check(demo._instructions.text.contains("Расстав") or demo._instructions.text.contains("Перестановки"), "deployment instructions survive reaction mode")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("CORE REACTIONS UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _opportunity_movement() -> void:
	demo.reset_demo()
	var session := demo.session as BattleCoreReactionsSession
	for index: int in 6:
		var unit := session.units[index]
		session.board.move_unit(unit, Vector2i(index, 0))
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
	var tank := session.units[1]
	var mover := session.units[2]
	session.board.move_unit(tank, Vector2i(2, 2))
	session.board.move_unit(mover, Vector2i(3, 2))
	check(session._queue.submit(GuardCommand.new(tank.id, session.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), session.context).status == ActionReceipt.APPLIED, "arm enemy opportunity for UI movement")
	demo.select_character(mover.id)
	var destination := Vector2i(4, 2)
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	await motion(at(destination))
	check(demo._move_forecast_pending and demo.board_view.pending_move_path.size() > 1, "reaction path appears before exact worker forecast")
	for iteration: int in 400:
		demo._process_move_forecast()
		if not demo._move_forecast_pending: break
		await create_timer(0.01).timeout
	var forecast: MoveForecast = demo._move_forecast
	check(forecast != null and forecast.status == ActionReceipt.INTERRUPTED and forecast.reason == &"perks/opportunist_stopped", "movement hover predicts actual opportunity interruption")
	check(demo._forecast_panel.text.contains("Оппортунист остановит") and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "stop panel explains result without live mutation")
	check(not demo._forecast_panel.text.contains("не поддерживается") and not demo._forecast_panel.text.contains("perks/opportunist_stopped"), "expected reaction interruption is localized without unsupported warning")
	await capture("reactions-movement-stop")
	await click(at(destination))
	check(forecast != null and session.last_receipt.get_events() == forecast.events and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after, "fresh movement click matches complete reaction forecast")
	check(mover.combat_perks.movement_stopped and tank.combat_perks.reaction_left == 0 and demo._inspection_text(mover).contains("остановлено"), "UI describes spent charge and stopped mover")

func _roster_button(id: int) -> Button:
	for button: Button in demo._roster.get_children():
		if button.text.begins_with(demo.session.board.get_unit_by_id(id).debug_name): return button
	return null

func _attacked_event(events: Array[Dictionary]) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == &"attacked": return event
	return {}

func _dynamic_descriptors_prefix_intact() -> bool:
	var ids: Array[StringName] = []
	for descriptor: Dictionary in demo._action_bar._dynamic_descriptors: ids.append(descriptor.get("action_id", &""))
	return ids.size() == 8 and ids.slice(0, 6) == [&"healing_item", &"restore_armor", &"blood_rune", &"raise_corpse", &"entangling_strike", &"summoning_item"]

func _journal_text() -> String:
	return "\n".join(demo._journal)

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

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
	await process_frame; await process_frame
	var texture := viewport.get_texture()
	var picture := texture.get_image() if texture != null else null
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
