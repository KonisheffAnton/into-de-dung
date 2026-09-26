extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _demo: BattleDemo
var _viewport: SubViewport
var _captures: String = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): _captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		printerr("FAIL RAISE FORECAST UI: " + label)

func _run() -> void:
	var packed := load("res://scenes/demo/core_combination_battle.tscn") as PackedScene
	_demo = packed.instantiate() as BattleDemo
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 850)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	# Адресная регрессия начинается после расстановки; полный вход проверяет core_batch.
	_demo.deployment_enabled = false
	_viewport.add_child(_demo)
	_viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	var battle := _demo.session as BattleEnvironmentSession
	var actor := battle.selected_unit()
	var target := Vector2i(0, 3)
	var before := ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict()
	var counters := battle.context.simulation_counters()
	var next_id := UnitId.get_counter()
	var last := battle.last_receipt
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	await _settle_action()
	_check(_demo.raising_mode and _demo._raise_forecast != null and _demo._raise_forecast.status == ActionReceipt.APPLIED, "slot6 hover builds ready raise forecast")
	_check(_demo._forecast_panel.is_visible_in_tree() and _demo._forecast_panel.text.contains("Тело #") and _demo._forecast_panel.text.contains("будет использовано") and _demo._forecast_panel.text.contains("основные 1 → 0 (расход 1)"), "visible body consumption and actual cost")
	_check(_demo._forecast_panel.text.contains("HP: 16.0 / 16.0") and _demo._forecast_panel.text.contains("0 основных, 0 бонусных, 0.0 движения") and _demo._forecast_panel.text.contains("ожидает следующего хода") and _demo._forecast_panel.text.contains("владелец"), "new helper details and pending resources")
	_check(ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == before and battle.context.simulation_counters() == counters and UnitId.get_counter() == next_id and battle.last_receipt == last, "hover isolates live state counters allocator receipt")
	_check(_demo._forecast == null and _demo._item_forecast == null and _demo._move_forecast == null and not _demo._move_forecast_pending and _demo.board_view.forecast == null, "raise result stays separate from HP/path forecast")
	var cached := _demo._raise_forecast
	await _mouse_motion(_demo.board_view.cell_center(target) + Vector2(1.0, 0.0))
	await process_frame
	_check(_demo._raise_forecast == cached, "unchanged hover reuses forecast")
	_check(_demo._action_bar.get_global_rect().end.y <= _viewport.size.y, "action bar remains inside viewport")
	await _capture("raise-forecast-ready")
	# Проверяем прокрутку при минимальной выделенной высоте, сохраняя настоящий текст.
	_demo._forecast_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	await process_frame
	await process_frame
	var scroll := _demo._forecast_panel.get_v_scroll_bar()
	await _wheel(_demo.board_view.global_position + _demo.board_view.cell_center(target))
	_check(scroll.value > 0.0 and _demo._raise_forecast == cached and battle.last_receipt == last, "wheel on target scrolls without execution or recalculation")
	await _mouse_motion_global(_demo._forecast_panel.global_position + Vector2(25.0, 25.0))
	_check(_demo._raise_forecast == cached and _demo._forecast_panel.is_visible_in_tree(), "pointer can enter panel with forecast retained")
	await _wheel(_demo._forecast_panel.global_position + Vector2(25.0, 25.0))
	_check(_demo._raise_forecast == cached and battle.state.active_summon(actor.id) == null, "panel wheel does not execute")
	await _capture("raise-forecast-scrolled")
	_demo._forecast_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	await process_frame
	await process_frame
	await _mouse_motion_global(Vector2(4.0, 4.0))
	_check(_demo._raise_forecast == null and not _demo._forecast_panel.visible, "leaving board and panel clears preview")
	await _mouse_motion(_demo.board_view.cell_center(Vector2i(1, 3)))
	await _settle_action()
	_check(_demo._raise_forecast != null and _demo._raise_forecast.status == ActionReceipt.REJECTED and _demo._forecast_panel.text.contains("Прогноз недоступен") and not _demo._forecast_panel.text.contains("HP: 16"), "empty target explains refusal without ready helper")
	await _capture("raise-forecast-rejected")
	await _click_cell(Vector2i(1, 3))
	_check(not _demo.raising_mode and _demo._raise_forecast == null and actor.action_resources.get_main_left() == 1, "rejected click returns to movement without cost")
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	var revision := battle.context.get_revision()
	battle.state.environment.ignite(target)
	_demo._refresh()
	await _settle_action()
	_check(battle.context.get_revision() == revision and _demo._raise_forecast != null and _demo._raise_forecast.status == ActionReceipt.REJECTED and _demo._raise_forecast != cached, "refresh invalidates direct change without revision")
	battle.state.environment.fires.clear()
	_demo._refresh()
	await _settle_action()
	_check(_demo._raise_forecast != null and _demo._raise_forecast.status == ActionReceipt.APPLIED, "refresh restores valid target forecast")
	# Между hover и кликом цель может измениться даже без revision.
	battle.state.environment.ignite(target)
	await _click_cell(target)
	_check(battle.last_receipt.status == ActionReceipt.REJECTED and battle.state.active_summon(actor.id) == null and battle.state.environment.corpses_at(target).size() == 1 and actor.action_resources.get_main_left() == 1, "click validates fresh state rather than applying cached snapshot")
	_check(_demo._raise_forecast == null and not _demo.raising_mode, "fresh rejection clears cached success")
	await _key(KEY_R)
	battle = _demo.session as BattleEnvironmentSession
	actor = battle.selected_unit()
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	await _key(KEY_ESCAPE)
	_check(_demo._raise_forecast == null and not _demo.raising_mode, "escape cancels raise preview")
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	await _key(KEY_A)
	_check(_demo._raise_forecast == null and _demo.attack_mode, "attack mode replaces raise preview")
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	_demo.select_character(battle.units[2].id)
	_check(_demo._raise_forecast == null and not _demo.raising_mode, "selection clears previous actor preview")
	_demo.select_character(actor.id)
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	_demo.inspect_enemy(battle.units[1].id)
	_check(_demo._raise_forecast == null and not _demo.raising_mode and _demo.inspected_id != UnitId.NONE, "enemy inspection clears raise preview")
	await _key(KEY_ESCAPE)
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	await _settle_action()
	var expected := _demo._raise_forecast
	await _click_cell(target)
	var helper := battle.state.active_summon(actor.id)
	_check(helper != null and _demo._raise_forecast == null and not _demo.raising_mode, "live click creates helper and clears preview")
	_check(battle.last_receipt.get_events() == expected.events and battle.last_receipt.get_steps() == expected.steps and ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == expected.snapshot_after, "UI click matches complete forecast state and receipt")
	_check(battle.state.environment.corpses_at(target).is_empty() and actor.action_resources.get_main_left() == 0 and helper != null and battle.state.is_summon_pending(helper.id), "body consumed and helper pending only after click")
	await _capture("raise-forecast-applied")
	await _key(KEY_R)
	battle = _demo.session as BattleEnvironmentSession
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	await _key(KEY_ENTER)
	_check(_demo._raise_forecast == null and not _demo.raising_mode, "end turn clears forecast")
	await _key(KEY_R)
	_check(_demo._raise_forecast == null and not _demo.raising_mode, "reset clears forecast")
	await _key(KEY_6)
	await _mouse_motion(_demo.board_view.cell_center(target))
	var old_battle := battle
	await _click_control(_demo._mode_button)
	_check(_demo._raise_forecast == null and _demo.session != old_battle and old_battle.context == null, "scenario switch closes previous session and clears forecast")
	_demo.set_process(false)
	_demo._exit_tree()
	_check(_demo._raise_forecast == null and _demo.session == null, "shutdown releases forecast and session")
	print("RAISE FORECAST UI RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, _demo)

func _mouse_motion(position: Vector2) -> void:
	await _mouse_motion_global(_demo.board_view.global_position + position)
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, _demo)

func _mouse_motion_global(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	_viewport.push_input(event, true)
	await process_frame
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, _demo)

func _settle_action() -> void:
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self, _demo)

func _click_cell(cell: Vector2i) -> void:
	await _click_at(_demo.board_view.global_position + _demo.board_view.cell_center(cell))

func _click_control(control: Control) -> void:
	await _click_at(control.global_position + control.size * 0.5)

func _click_at(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		_viewport.push_input(event, true)
	await process_frame

func _wheel(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = position
	event.global_position = position
	_viewport.push_input(event, true)
	await process_frame

func _capture(label: String) -> void:
	if _captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := _viewport.get_texture().get_image()
	_check(picture != null and picture.save_png(_captures.path_join(label + ".png")) == OK, "capture " + label)
