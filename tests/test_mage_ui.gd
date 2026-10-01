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
func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL MAGE UI: " + label)
func _run() -> void:
	viewport = SubViewport.new(); viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false; viewport.add_child(demo); demo.set_process(false)
	viewport.notify_mouse_entered()
	var session := demo.session as BattleCoreReactionsSession
	session._enemy_index = session._enemy_ids.size(); session.step_enemy()
	_check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN, "real player boundary")
	var actor := session.units[0]
	var target := session.units[1]
	for unit: UnitState in session.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0); unit.vitals.set_hp(80.0)
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	session.selected_id = 0
	demo._refresh(); await process_frame; await process_frame
	_check(demo._mage_row.visible and not demo._mage_fire.disabled and not demo._mage_heal.disabled, "mage independent of hero selection")
	_check(demo._mage_label.tooltip_text.contains("длительность: огонь 2") and demo._mage_label.tooltip_text.contains("лечение 2"), "default mage durations remain two turns")
	_check(demo._instructions.get_global_rect().end.y <= float(viewport.size.y), "instructions fit viewport")
	_check(demo.size.x <= viewport.size.x and demo.size.y <= viewport.size.y, "UI fits viewport")
	var main_before := actor.action_resources.get_main_left()
	await _click(demo._mage_fire.global_position + demo._mage_fire.size * 0.5)
	_check(session.elemental_selected == &"mage.fire", "real button selects fire")
	await _motion(_at(target.cell))
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	var first := demo._elemental_forecast
	_check(first != null and first.status == ActionReceipt.APPLIED and session.state.abilities.mana == 6, "worker preview leaves live mana")
	_check(demo._forecast_panel.text.contains("длительность 2 ходов, после действия осталось 2"), "default fire preview shows descriptor duration and simulated remaining")
	session.state.abilities.mana = 5
	demo._process(0.0)
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	_check(demo._elemental_forecast != null and demo._elemental_forecast != first and demo._elemental_forecast.snapshot_before.abilities.mana == 5, "direct mana mutation refreshes forecast")
	await _capture("mage-fire-preview")
	await _click(_at(target.cell))
	_check(session.state.abilities.mana == 3 and session.state.abilities.remaining(&"mage.fire") == 2 and actor.action_resources.get_main_left() == main_before, "fresh click pays mage only")
	await _click(demo._mage_heal.global_position + demo._mage_heal.size * 0.5)
	await _motion(_at(actor.cell)); await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, demo)
	await _capture("mage-heal-preview")
	await _click(_at(actor.cell))
	_check(session.state.abilities.mana == 0 and session.state.abilities.remaining(&"mage.heal") == 2 and actor.vitals.get_hp() == 84.0, "second spell heals with separate cooldown")
	_check(demo._mage_fire.disabled and demo._mage_heal.disabled, "both cooldown buttons disabled")
	await _test_descriptor_durations(session, actor, target)
	# Exit joins any detached preview worker before releasing session.
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("MAGE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_descriptor_durations(session: BattleCoreReactionsSession, actor: UnitState, target: UnitState) -> void:
	for spell: StringName in [&"mage.fire", &"mage.heal"]:
		for duration: int in [0, 1]:
			var definition := session.state.abilities.definition(spell)
			definition.cooldown_turns = duration
			session.state.abilities.ledger.clear()
			session.state.abilities.mana = 6
			demo._refresh_mage()
			var label_key := "огонь %d" % duration if spell == &"mage.fire" else "лечение %d" % duration
			_check(demo._mage_label.tooltip_text.contains("длительность:") and demo._mage_label.tooltip_text.contains(label_key), "%s duration %d comes from live descriptor" % [String(spell), duration])
			var target_id := target.id if spell == &"mage.fire" else actor.id
			var forecast := ForecastSimulation.run_prepared(session.prepare_mage_forecast(spell, target_id))
			_check(forecast.status == ActionReceipt.APPLIED, "%s duration %d forecast executes" % [String(spell), duration])
			demo._elemental_forecast = forecast
			demo._action_forecast_effect = spell
			demo._action_forecast_target_id = target_id
			demo._action_forecast_actor = UnitId.NONE
			demo._render_elemental_forecast_panel()
			var after := BattleAbilityState.from_dict(forecast.snapshot_after.get("abilities", {}))
			_check(after != null and after.remaining(spell) == duration, "%s duration %d preview snapshot remaining value" % [String(spell), duration])
			_check(demo._forecast_panel.text.contains("длительность %d ходов, после действия осталось %d" % [duration, duration]), "%s forecast labels duration and computed remaining distinctly" % String(spell))

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
