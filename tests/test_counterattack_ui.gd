extends SceneTree

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
		printerr("FAIL COUNTERATTACK UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	check(session != null and session.selected_unit() != null, "combined reaction battle is active")
	var owner := session.units[0]
	check(MeleeThreat.has_counterattack(owner) and MeleeThreat.has_counterattack(session.units[1]), "Astra and Strazh own counterattack")
	check(_dynamic_counterattack_follows_stun(), "counterattack descriptor follows the existing stun action")
	var saved_tank: bool = owner.combat_perks.definition.tank_reactions
	owner.combat_perks.definition.tank_reactions = false
	demo._refresh()
	var counter_only_ids := _descriptor_ids()
	check(counter_only_ids.has(&"counterattack_guard") and not counter_only_ids.has(&"opportunity_guard") and not counter_only_ids.has(&"cover_guard"), "counter-only owner sees only the counterattack reaction control")
	owner.combat_perks.definition.tank_reactions = saved_tank
	demo._refresh()
	var main_before: int = owner.action_resources.get_main_left()
	var charge_before: int = owner.combat_perks.reaction_left
	var state_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var counter_button := await _button_for_action(&"counterattack_guard")
	check(counter_button != null, "counterattack action is reachable by action bar input")
	await motion(counter_button.global_position + counter_button.size * 0.5)
	await _settle_action()
	var guard_forecast: GuardForecast = demo._guard_forecast
	check(guard_forecast != null and guard_forecast.status == ActionReceipt.APPLIED and demo._guard_forecast_mode == CombatPerksState.Mode.COUNTERATTACK, "hover uses asynchronous mode-three guard forecast")
	var forecast_row: Dictionary = guard_forecast.units.get(owner.id, {}) if guard_forecast != null else {}
	var forecast_after: Dictionary = forecast_row.get("after", {})
	check(forecast_after.get("main", -1) == main_before - 1 and forecast_after.get("combat_perks", {}).get("reaction_left", -1) == charge_before, "guard preview predicts one main action and preserves the shared charge")
	check(demo._forecast_panel.text.contains("Контратака") and demo._forecast_panel.text.contains("Общий заряд реакции"), "guard preview names counterattack and shared charge")
	check(owner.action_resources.get_main_left() == main_before and owner.combat_perks.reaction_left == charge_before and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == state_before, "hover leaves live actions, charge, and board unchanged")
	await capture("counterattack-guard")
	await click(counter_button.global_position + counter_button.size * 0.5)
	check(owner.guard_stance and owner.combat_perks.mode == CombatPerksState.Mode.COUNTERATTACK, "click installs counterattack guard mode")
	check(owner.action_resources.get_main_left() == main_before - 1 and owner.combat_perks.reaction_left == charge_before, "stance costs one main and leaves the shared charge ready")
	check(demo._inspection_text(owner).contains("Контратака") and demo._inspection_text(owner).contains("общий заряд: 1/1"), "inspection reports mode and charge")
	check(_journal_contains("включает режим «Контратака»"), "guard event uses the correct reaction name")
	await _attack_forecast_and_live_result()
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("COUNTERATTACK UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _attack_forecast_and_live_result() -> void:
	demo.reset_demo()
	var session := demo.session as BattleCoreReactionsSession
	var attacker := session.units[0]
	var defender := session.units[1]
	# Страж — реальный вражеский владелец контратаки, доступный для прямого удара игрока.
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	session.state.environment.fires.clear()
	for index: int in 6:
		var unit := session.units[index]
		session.board.move_unit(unit, Vector2i(index, 0))
		if unit.control != null:
			unit.control.stunned_turns = 0
			unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.vitals.reset_balance()
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	session.board.move_unit(attacker, Vector2i(2, 3))
	session.board.move_unit(defender, Vector2i(3, 3))
	defender.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	defender.combat_perks.reaction_left = 1
	defender.guard_stance = true
	demo._refresh()
	await click(demo.board_view.global_position + demo.board_view.cell_center(attacker.cell))
	check(session.selected_id == attacker.id, "real board click selects the attack actor")
	await key(KEY_1)
	await motion(demo.board_view.global_position + demo.board_view.cell_center(defender.cell))
	var forecast: AttackForecast = demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "attack hover prepares the complete counterattack tail")
	check(forecast != null and _has_event(forecast.events, &"counterattacked") and _has_counter_mode_event(forecast.events), "forecast includes counterattacked and mode-three charge events")
	check(demo._forecast_panel.text.contains("контратакует") and demo._forecast_panel.text.contains("Контратака"), "attack forecast explains the response")
	check(defender.guard_stance and defender.combat_perks.reaction_left == 1 and not attacker.combat_perks.movement_stopped, "forecast keeps stance and shared charge live, without stopping movement")
	var forecast_events: Array[Dictionary] = forecast.events.duplicate(true) if forecast != null else []
	var forecast_after: Dictionary = forecast.snapshot_after if forecast != null else {}
	await click(demo.board_view.global_position + demo.board_view.cell_center(defender.cell))
	check(session.last_receipt.status == ActionReceipt.APPLIED and session.last_receipt.get_events() == forecast_events, "live attack events match full forecast")
	check(not forecast_after.is_empty() and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast_after, "live counterattack state matches forecast snapshot")
	check(defender.guard_stance and defender.combat_perks.reaction_left == 0 and not attacker.combat_perks.movement_stopped, "counter spends one charge, keeps guard stance, and does not stop the attacker")
	check(_journal_contains("контратакует") and _journal_contains("режим «Контратака»") and not _journal_contains("Прикрытие →"), "live journal names counterattack without cover")
	check(demo._inspection_text(defender).contains("Контратака") and demo._inspection_text(defender).contains("общий заряд: 0/1"), "post-hit inspection reports spent counterattack charge")
	await capture("counterattack-result")
	# Reset обязан дождаться worker и закрыть результат старого боя до смены состояния.
	demo.reset_demo()
	var pending_button := await _button_for_action(&"counterattack_guard")
	var pending_position := pending_button.global_position + pending_button.size * 0.5
	await motion(pending_position)
	var pending_click := InputEventMouseButton.new()
	pending_click.button_index = MOUSE_BUTTON_LEFT; pending_click.position = pending_position; pending_click.global_position = pending_position; pending_click.pressed = true
	viewport.push_input(pending_click, true)
	pending_click.pressed = false; viewport.push_input(pending_click, true)
	await process_frame
	check(demo.is_execution_pending(), "counterattack guard starts a pending live worker")
	demo.reset_demo()
	check(not demo.is_execution_pending() and demo.session is BattleCoreReactionsSession and (demo.session as BattleCoreReactionsSession).units[0].combat_perks.reaction_left == 1, "reset joins the pending live action before rebuilding")

func _button_for_action(action_id: StringName) -> Button:
	var action_bar: BattleActionBar = demo.get("_action_bar")
	for page: int in 4:
		for button: Button in action_bar._buttons:
			if button.visible and button.get_meta("action_id", &"") == action_id: return button
		if action_bar._down_button.disabled: break
		await click(action_bar._down_button.global_position + action_bar._down_button.size * 0.5)
	return null

func _descriptor_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for descriptor: Dictionary in demo._action_bar._dynamic_descriptors:
		result.append(descriptor.get("action_id", &""))
	return result

func _dynamic_counterattack_follows_stun() -> bool:
	var ids := _descriptor_ids()
	var stun_index := ids.find(&"stunning_strike")
	var counter_index := ids.find(&"counterattack_guard")
	return counter_index >= 0 and (stun_index < 0 or counter_index == stun_index + 1)

func _has_event(events: Array[Dictionary], kind: StringName) -> bool:
	for event: Dictionary in events:
		if event.get("kind", &"") == kind: return true
	return false

func _has_counter_mode_event(events: Array[Dictionary]) -> bool:
	for event: Dictionary in events:
		if event.get("kind", &"") == &"reaction_used" and event.get("mode", -1) == CombatPerksState.Mode.COUNTERATTACK: return true
	return false

func _journal_text() -> String:
	return "\n".join(demo._journal)

func _journal_contains(fragment: String) -> bool:
	for entry: String in demo._journal:
		if entry.contains(fragment): return true
	return false

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func _settle_action() -> void:
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
