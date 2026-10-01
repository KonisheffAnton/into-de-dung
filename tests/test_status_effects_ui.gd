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

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL STATUS EFFECTS UI: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var main_scene := load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene
	_check(main_scene != null, "core reactions main scene exists")
	if main_scene == null:
		quit(1)
		return
	demo = main_scene.instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	_check(session != null, "main scene creates elemental session")
	if session == null:
		quit(1)
		return
	session.action_slot_overrides[session.selected_id] = [&"elemental_wet", &"elemental_burning"]
	demo._refresh()
	_check(demo.size.x <= viewport.size.x and demo.size.y <= viewport.size.y, "main scene fits viewport bounds")
	var action_ids: Array[StringName] = []
	for descriptor: Dictionary in demo._action_bar._dynamic_descriptors:
		action_ids.append(descriptor.get("action_id", &""))
	_check(action_ids == [&"elemental_wet", &"elemental_burning"] and demo._action_bar._buttons.size() == 4 and demo._action_bar._page == 0, "wet and burning occupy the two assigned slots in the compact bar")
	var target := session.units[1]
	var actor := session.selected_unit()
	if target.cell.distance_to(actor.cell) > 3:
		for y: int in session.board.height:
			for x: int in session.board.width:
				var candidate := Vector2i(x, y)
				if candidate.distance_to(actor.cell) <= 3 and not session.board.is_occupied(candidate):
					session.board.move_unit(target, candidate)
					break
			if target.cell.distance_to(actor.cell) <= 3: break
	_check(target.cell.distance_to(actor.cell) <= 3, "fixture target is in cast range")
	for index: int in 6:
		var unit := session.units[index]
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.action_resources._main_left = 2
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 120.0)
		unit.vitals.set_hp(120.0)
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	actor = session.units[0]
	target = session.units[1]
	# Оба вида опасной клетки видны на доске и получают отдельные подписи.
	session.state.environment.status_effects = true
	session.state.environment.fires.clear()
	var hazard_cells: Array[Vector2i] = []
	for y: int in session.board.height:
		for x: int in session.board.width:
			var candidate := Vector2i(x, y)
			if not session.board.is_occupied(candidate): hazard_cells.append(candidate)
	if hazard_cells.size() >= 2:
		_check(not session.state.environment.ignite(hazard_cells[0], "bleeding").is_empty(), "spike display fixture is created")
		_check(not session.state.environment.ignite(hazard_cells[1], "burning").is_empty(), "fire display fixture is created")
	target.elemental.wet_turns = 2
	target.bleeding.stacked = true
	target.bleeding.stacks = 2
	target.bleeding.ticks_left = 2
	target.bleeding.source = DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id).to_dict()
	target.bleeding.hit_id = "ui-fixture"
	_check(ItemSimulationSnapshot.capture(session.state, []).code == ItemSnapshotResult.Code.OK, "UI fixture keeps valid live statuses")
	demo._refresh()
	_check(demo._inspection_text(target).contains("Мокрый: 2"), "inspection card exposes wet state")
	_check(demo._inspection_text(target).contains("Кровотечение: 2 ст."), "inspection card exposes stacked bleeding")
	target.elemental.wet_turns = 0
	target.elemental.frozen_turns = 1
	demo._refresh()
	_check(demo._inspection_text(target).contains("Заморожен: 1"), "inspection card exposes frozen state")
	target.elemental.frozen_turns = 0
	target.elemental.wet_turns = 2
	demo._refresh()
	var action_bar := demo.get("_action_bar") as BattleActionBar
	var wet_button := _button_for(&"elemental_wet")
	_check(wet_button != null, "wet action occupies an assigned compact slot")
	if wet_button == null:
		quit(1)
		return
	var main_before: int = actor.action_resources.get_main_left()
	await _click(wet_button.global_position + wet_button.size * 0.5)
	_check(session.elemental_selected == &"wet" and demo.board_view.elemental_mode and actor.action_resources.get_main_left() == main_before, "mouse selects effect without spending main action")
	await _key(KEY_ESCAPE)
	_check(session.elemental_selected == &"" and not demo.board_view.elemental_mode and actor.action_resources.get_main_left() == main_before, "Escape cancels target mode without spending")
	wet_button = _button_for(&"elemental_wet")
	await _click(wet_button.global_position + wet_button.size * 0.5)
	_check(session.elemental_selected == &"wet", "mouse re-enters target mode")
	# Первый свободный fixture часто занимает (0, 0); камера должна поместить его внутрь обрезаемой доски.
	var board := demo.board_view
	board.zoom_camera(0.75, board.size * 0.5)
	var target_point := board.cell_center(target.cell)
	_check(Rect2(Vector2.ZERO, board.size).has_point(target_point), "status fixture target point is inside board bounds")
	_check(board.cell_at(target_point) == target.cell, "status fixture target point resolves to intended cell")
	await _motion(_at(target.cell))
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	if demo._elemental_forecast == null:
		_check(false, "hover produces before and after status preview")
		_check(false, "preview includes stacked bleeding state")
		demo.queue_free(); await process_frame
		viewport.queue_free(); await process_frame
		print("STATUS EFFECTS UI RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	_check(demo._forecast_panel.text.contains("мокрый"), "hover produces before and after status preview")
	_check(demo._forecast_panel.text.contains("Кровотечение"), "preview includes stacked bleeding state")
	var expected_elemental: Dictionary = demo._elemental_forecast.units_after[target.id]["elemental"].duplicate(true)
	var expected_bleeding: Dictionary = demo._elemental_forecast.units_after[target.id]["bleeding"].duplicate(true)
	await _capture("status-effects-forecast")
	await _click(_at(target.cell))
	_check(not demo.is_execution_pending() and session.elemental_selected == &"", "fresh target click completes live cast and exits mode")
	_check(actor.action_resources.get_main_left() == main_before - 1, "live cast spends one main action")
	_check(target.elemental.to_dict() == expected_elemental and target.bleeding.to_dict() == expected_bleeding, "live result matches isolated forecast with no shared preview mutation")
	_check(_journal_text().contains("Облить"), "live event appears in action journal")
	_check(session.state.environment.fires.size() == 2 and String(session.state.environment.fire_at(hazard_cells[0]).get("effect", "")) == "bleeding" and String(session.state.environment.fire_at(hazard_cells[1]).get("effect", "")) == "burning", "board fixture retains distinct spike and fire hazards")
	await _capture("status-effects-applied")
	# Переключение перка меняет допуск наложения, но не командную revision;
	# прогноз обязан замечать runtime-перки в снимке и пересчитать тот же hover.
	target.elemental = ElementalState.new()
	target.armor.natural = {"physical": 0, "fire": 0}
	var restored_armor: int = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values():
		var definition := item.get_definition()
		if definition.armor_max > 0:
			item.armor_remaining = definition.armor_max
			restored_armor += definition.armor_max
	_check(restored_armor > 4, "fire gate fixture has restored armor above the fire damage")
	actor.combat_perks.definition.burning_bypass_hp_gate = false
	demo._refresh()
	var burning_button := _button_for(&"elemental_burning")
	_check(burning_button != null, "burning action is available for the UI regression")
	if burning_button == null:
		demo.queue_free(); await process_frame
		viewport.queue_free(); await process_frame
		print("STATUS EFFECTS UI RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var fire_main_before: int = actor.action_resources.get_main_left()
	var fire_target_hp: float = target.vitals.get_hp()
	await _click(burning_button.global_position + burning_button.size * 0.5)
	_check(session.elemental_selected == &"burning" and actor.action_resources.get_main_left() == fire_main_before, "burning selection preserves charge for gate preview")
	await _motion(_at(target.cell))
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	var no_perk_revision: int = session.context.get_revision()
	var no_perk_forecast: ForecastSimulation = demo._elemental_forecast
	_check(no_perk_forecast != null and is_equal_approx(no_perk_forecast.units_after[target.id]["hp"], fire_target_hp) and no_perk_forecast.units_after[target.id]["elemental"]["burning_stacks"] == 0, "restored armor absorbs fire for zero HP damage and false perk fails gate")
	actor.combat_perks.definition.burning_bypass_hp_gate = true
	_check(session.context.get_revision() == no_perk_revision, "perk mutation does not increment combat revision")
	# Курсор остаётся на цели; обычное движение не создаст cell_hovered повторно.
	# Продвигаем ровно один UI-кадр, чтобы проверить инвалидацию готового прогноза.
	demo._process(0.0)
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	var bypass_forecast: ForecastSimulation = demo._elemental_forecast
	_check(bypass_forecast != null and bypass_forecast != no_perk_forecast and session.context.get_revision() == no_perk_revision, "same-revision perk change replaces cached forecast")
	_check(bypass_forecast != null and is_equal_approx(bypass_forecast.units_after[target.id]["hp"], fire_target_hp) and bypass_forecast.units_after[target.id]["elemental"]["burning_stacks"] > 0, "true bypass perk forecasts burn through armor-only damage")
	await _click(_at(target.cell))
	_check(is_equal_approx(target.vitals.get_hp(), fire_target_hp) and target.elemental.burning_stacks > 0 and target.bleeding.stacks == 0 and actor.action_resources.get_main_left() == fire_main_before - 1, "fresh live firecast burns through armor for zero HP damage and clears bleeding")
	_check(_journal_text().contains("Поджечь"), "bypass cast reaches live journal")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("STATUS EFFECTS UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _button_for(action_id: StringName) -> Button:
	var action_bar := demo.get("_action_bar") as BattleActionBar
	for button: Button in action_bar._buttons:
		if button.visible and StringName(button.get_meta("action_id", &"")) == action_id: return button
	return null

func _at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame

func _click(position: Vector2) -> void:
	await _motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var image := viewport.get_texture().get_image()
	_check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func _journal_text() -> String:
	return "\n".join(demo._journal)
