extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
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
	demo = (load("res://scenes/demo/core_combination_battle.tscn") as PackedScene).instantiate()
	# Адресная регрессия начинается после расстановки; полный вход проверяет core_batch.
	demo.deployment_enabled = false
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	var session := demo.session as BattleCoreCombinationSession
	var button := demo._action_bar._buttons[6]
	check(button.get_meta("action_id") == &"entangling_strike", "slot 7 offers new attack")
	var actor := session.units[2]
	var target := session.units[5]
	await click(at(actor.cell)); await click(at(Vector2i(4, 4)))
	check(actor.cell == Vector2i(4, 4), "real input moves Bor to E5")
	await click(button.global_position + button.size * 0.5)
	check(demo.attack_mode and session.entangle_selected and not session.rune_selected, "button chooses entangle attack")
	var before := snapshot(session)
	var counters := session.context.simulation_counters()
	await motion(at(target.cell))
	var forecast := demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "hover produces forecast")
	check(demo._forecast_panel.text.contains("Путы: до конца") and not demo._forecast_panel.text.contains("Крит ×2"), "new root is forecast and does not grant retroactive critical")
	check(snapshot(session) == before and session.context.simulation_counters() == counters, "hover keeps live snapshot and counters")
	await capture("k8-entangle-forecast")
	await key(KEY_A); await motion(at(target.cell))
	check(not session.entangle_selected and demo._forecast != null and not demo._forecast_panel.text.contains("Путы: до конца"), "ordinary attack replaces cached entangle forecast on same target")
	await key(KEY_7); await motion(at(target.cell))
	forecast = demo._forecast
	await click(at(target.cell))
	check(forecast != null and snapshot(session) == forecast.snapshot_after and session.last_receipt.get_events() == forecast.events and session.last_receipt.get_steps() == forecast.steps, "real click matches full preview")
	check(target.control.entangled_turns == 1 and target.bleeding.ticks_left == 0 and actor.action_resources.get_main_left() == 0, "one main applies root without bleeding")
	check(not demo.attack_mode and not session.entangle_selected and demo._forecast == null, "completed attack returns to movement")
	var selected_before_inspection: int = session.selected_id
	var inspection_snapshot := snapshot(session)
	var inspection_rng: Dictionary = session.context.get_rng().to_dict().duplicate(true)
	var inspection_counters: Dictionary = session.context.simulation_counters()
	var inspection_receipt: ActionReceipt = session.last_receipt
	await click_roster_enemy(target.id)
	check(demo.inspected_id == target.id and session.selected_id == selected_before_inspection, "roster click inspects root target without changing selection")
	check(snapshot(session) == inspection_snapshot and session.context.get_rng().to_dict() == inspection_rng and session.context.simulation_counters() == inspection_counters and session.last_receipt == inspection_receipt, "roster inspection does not mutate battle")
	check(demo._stats.text.contains("Опутан") and demo._stats.text.contains("Срок: до конца"), "inspection shows root and expiry")
	await capture("k8-entangle-result")
	# Свежий клик обязан учесть изменение gate после прогноза без изменения revision.
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	actor = session.units[2]; target = session.units[5]
	await click(at(actor.cell)); await click(at(Vector2i(4, 4)))
	await key(KEY_7); await motion(at(target.cell))
	check(demo._forecast != null and demo._forecast_panel.text.contains("Путы: до конца"), "initial positive gate forecast")
	actor.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, -50.0)
	await click(at(target.cell))
	check(session.last_receipt.status == ActionReceipt.APPLIED and target.control.entangled_turns == 0, "fresh click reevaluates physical HP gate")
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	actor = session.units[2]; target = session.units[5]
	actor.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, -50.0)
	await click(at(actor.cell)); await click(at(Vector2i(4, 4)))
	await key(KEY_7); await motion(at(target.cell))
	check(demo._forecast != null and demo._forecast_panel.text.contains("Путы не наложены: нет положительного физического урона HP"), "gate failure explained in forecast")
	await capture("k8-entangle-gate")
	await key(KEY_ESCAPE)
	check(not session.entangle_selected and not demo.attack_mode and demo._forecast == null, "cancel clears mode and forecast")
	await key(KEY_7); await click(at(session.units[0].cell))
	check(not session.entangle_selected and not demo.attack_mode, "ally selection clears mode")
	await key(KEY_7); await key(KEY_5)
	check(not session.entangle_selected and session.rune_selected, "rune replaces entangle mode")
	await key(KEY_7); await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	check(not session.entangle_selected and demo._forecast == null, "reset clears entangle mode")
	await click(at(session.units[4].cell))
	check(demo._action_bar._buttons[6].disabled, "stunned actor cannot select entangle")
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	await click(at(session.units[2].cell)); await key(KEY_7); await key(KEY_ENTER)
	check(not session.entangle_selected and not demo.attack_mode and demo._forecast == null, "team boundary clears entangle mode")
	await key(KEY_R)
	session = demo.session as BattleCoreCombinationSession
	await click(at(session.units[2].cell)); await key(KEY_7)
	await click(demo._mode_button.global_position + demo._mode_button.size * 0.5)
	check(not demo.core_combination_mode and not demo.attack_mode and demo._forecast == null, "scenario switch clears input and preview")
	check(not demo._action_bar.visible or demo._action_bar._buttons[6].disabled or demo._action_bar._buttons[6].get_meta("action_id", &"") != &"entangling_strike", "new ability stays in K2")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("ENTANGLE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func snapshot(session: BattleCoreCombinationSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ENTANGLE UI: " + label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame

func click_roster_enemy(unit_id: int) -> void:
	var button := demo._runtime_roster_buttons.get(unit_id) as Button
	check(button != null and is_instance_valid(button), "enemy roster button exists")
	if button == null or not is_instance_valid(button): return
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame; await process_frame
	var position := button.global_position + button.size * 0.5
	await motion(position)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT; down.position = position; down.global_position = position; down.pressed = true
	viewport.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.position = position; up.global_position = position; up.pressed = false
	viewport.push_input(up, true)
	await process_frame; await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var texture := viewport.get_texture()
	if texture == null:
		check(false, "missing viewport texture"); return
	var picture := texture.get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
