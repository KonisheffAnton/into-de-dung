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
		printerr("FAIL GUARD FORECAST UI: " + label)

func _snapshot() -> Dictionary:
	return ItemSimulationSnapshot.capture(_demo.session.state, []).snapshot.to_dict()

func _run() -> void:
	var packed := load("res://scenes/demo/core_combination_battle.tscn") as PackedScene
	_demo = packed.instantiate() as BattleDemo
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 850)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.add_child(_demo)
	_viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	var battle := _demo.session as BattleTacticalSession
	var actor := battle.selected_unit()
	var before := _snapshot()
	var last := battle.last_receipt
	var counters := battle.context.simulation_counters()
	var rng := battle.context.get_rng().to_dict().duplicate(true)
	var next_id := UnitId.get_counter()
	await _guard_hover()
	_check(_demo._guard_forecast != null and _demo._guard_forecast.status == ActionReceipt.APPLIED, "slot 2 hover builds ready guard forecast")
	_check(_demo._forecast_panel.is_visible_in_tree() and _demo._forecast_panel.text.contains("Основные: 1 → 0 (расход 1)") and _demo._forecast_panel.text.contains("Стойка: выключена → включена"), "panel shows cost and stance from DTO")
	_check(_demo._forecast_panel.text.contains("Бонусные:") and _demo._forecast_panel.text.contains("Движение:") and _demo._forecast_panel.text.contains("До следующего хода команды"), "panel explains remaining resources and duration")
	_check(_snapshot() == before and battle.last_receipt == last and battle.context.simulation_counters() == counters and battle.context.get_rng().to_dict() == rng and UnitId.get_counter() == next_id, "hover preserves live state receipt RNG counters allocator")
	_check(not actor.guard_stance and not _demo.attack_mode and not _demo.raising_mode and _demo.inspected_id == UnitId.NONE and _demo._forecast == null and _demo._item_forecast == null and _demo._move_forecast == null and not _demo._move_forecast_pending and _demo._raise_forecast == null and _demo.board_view.forecast == null, "hover changes neither stance nor input mode and clears other previews")
	var cached := _demo._guard_forecast
	await _mouse(_button_center(1) + Vector2(1, 0))
	_check(_demo._guard_forecast == cached, "same actor revision and button reuse cached forecast")
	_check(_demo._action_bar.get_global_rect().end.y <= _viewport.size.y, "action bar remains visible")
	await _capture("guard-forecast-ready")
	# Уменьшаем только выделенную высоту, чтобы проверить прокрутку настоящего текста.
	_demo._forecast_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	await process_frame
	await process_frame
	await _mouse(_demo._forecast_panel.global_position + Vector2(25, 25))
	_check(_demo._guard_forecast == cached, "transition from button to panel retains forecast")
	await _wheel(_demo._forecast_panel.global_position + Vector2(25, 25))
	_check(_demo._forecast_panel.get_v_scroll_bar().value > 0.0 and _demo._guard_forecast == cached and _snapshot() == before and battle.last_receipt == last, "panel wheel scrolls without recalculation or execution")
	await _capture("guard-forecast-scrolled")
	_demo._forecast_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	await _mouse(Vector2(4, 4))
	_check(_demo._guard_forecast == null and not _demo._forecast_panel.visible, "leaving panel clears result")
	await _guard_hover()
	await _mouse(_button_center(2))
	_check(_demo._guard_forecast == null and _demo._item_forecast != null and _demo._item_forecast_kind == &"healing", "healing hover replaces guard forecast")
	await _guard_hover()
	await _mouse(_button_center(0))
	_check(_demo._guard_forecast == null, "other action button clears guard forecast")
	await _guard_hover()
	var revision := battle.context.get_revision()
	actor.guard_stance = true
	_demo._refresh()
	_check(battle.context.get_revision() == revision and _demo._guard_forecast != null and _demo._guard_forecast != cached and _demo._guard_forecast.reason == &"guard/already_active" and _demo._action_bar._buttons[1].disabled, "refresh invalidates direct state change without revision")
	_check(_demo._forecast_panel.text.contains("Прогноз недоступен") and not _demo._forecast_panel.text.contains("Стойка: выключена → включена"), "refusal has no ready stance result")
	await _capture("guard-forecast-rejected")
	actor.guard_stance = false
	_demo._refresh()
	_check(_demo._guard_forecast != null and _demo._guard_forecast.status == ActionReceipt.APPLIED and not _demo._action_bar._buttons[1].disabled, "refresh restores ready forecast")
	var before_revision_change := _demo._guard_forecast
	var other_actor: UnitState = battle.units[2]
	var other_guard := battle._queue.submit(GuardCommand.new(other_actor.id, battle.context.get_revision()), battle.context)
	await _mouse(_button_center(1) + Vector2(2, 0))
	_check(other_guard.status == ActionReceipt.APPLIED and _demo._guard_forecast != before_revision_change and _demo._guard_forecast.snapshot_before == _snapshot() and not actor.guard_stance, "revision change refreshes same-button hover without executing selected actor")
	# После hover команда должна заново проверить состояние, даже без revision.
	actor.action_resources.try_spend_main(1)
	await _click(_button_center(1))
	_check(battle.last_receipt.status == ActionReceipt.REJECTED and battle.last_receipt.reason == &"guard/insufficient_main" and not actor.guard_stance and actor.action_resources.get_main_left() == 0 and _demo._guard_forecast == null, "click validates fresh state and clears cached success")
	await _key(KEY_R)
	battle = _demo.session as BattleTacticalSession
	actor = battle.selected_unit()
	await _guard_hover()
	var expected := _demo._guard_forecast
	await _click(_button_center(1))
	_check(actor.guard_stance and actor.action_resources.get_main_left() == 0 and _demo._guard_forecast == null, "click enables guard and spends one main then clears forecast")
	_check(_snapshot() == expected.snapshot_after and battle.last_receipt.get_events() == expected.events and battle.last_receipt.get_steps() == expected.steps and battle.context.simulation_counters() == expected.counters_after, "live click matches complete preview state and receipt")
	_check(_demo._stats.text.contains("Охранная стойка") and _demo._action_bar._buttons[1].disabled, "live stance and unavailable action displayed")
	await _capture("guard-forecast-applied")
	await _guard_hover()
	_check(_demo._guard_forecast != null and _demo._guard_forecast.reason == &"guard/already_active", "disabled button still explains refusal on hover")
	var guarded := _snapshot()
	await _key(KEY_2)
	_check(_snapshot() == guarded and battle.last_receipt.status == ActionReceipt.REJECTED and _demo._guard_forecast == null, "repeat keyboard guard refuses without additional cost")
	await _key(KEY_R)
	await _guard_hover()
	expected = _demo._guard_forecast
	await _key(KEY_2)
	_check(_snapshot() == expected.snapshot_after and _demo._guard_forecast == null, "key 2 still executes fresh guard directly")
	await _key(KEY_R)
	actor = battle.selected_unit()
	for enemy: UnitState in battle.board.get_all_units():
		if enemy.faction == Faction.Type.ENEMY and enemy.is_alive():
			var death := battle._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test", 0, enemy.cell)), battle.context)
			_check(death.status == ActionReceipt.APPLIED, "terminal UI setup death")
	# Восстанавливаем допустимый снимок с ещё не выполненным завершением брони.
	actor.armor.in_battle = true
	battle._queue = ActionQueue.new(1, 512, 32)
	var fault_before := _snapshot()
	await _guard_hover()
	_check(_demo._guard_forecast != null and _demo._guard_forecast.status == ActionReceipt.FAULTED and _demo._guard_forecast.units.is_empty(), "terminal limit yields diagnostic forecast only")
	_check(_demo._forecast_panel.text.contains("Прогноз недоступен") and not _demo._forecast_panel.text.contains("Стойка: выключена → включена") and _snapshot() == fault_before and not actor.guard_stance, "FAULTED prefix never displays ready stance or changes live")
	await _key(KEY_R)
	await _guard_hover()
	await _key(KEY_ESCAPE)
	_check(_demo._guard_forecast == null, "escape clears guard preview")
	await _guard_hover()
	await _key(KEY_A)
	_check(_demo._guard_forecast == null and _demo.attack_mode, "attack mode clears guard preview")
	await _guard_hover()
	_check(_demo.attack_mode, "guard hover does not change active attack mode")
	await _mouse(_demo.board_view.global_position + _demo.board_view.cell_center(battle.units[1].cell))
	_check(_demo._guard_forecast == null and _demo._forecast != null, "board attack hover replaces guard without stale panel")
	await _key(KEY_6)
	await _guard_hover()
	_check(_demo.raising_mode, "guard hover preserves active raise mode")
	await _key(KEY_ESCAPE)
	await _guard_hover()
	_demo.select_character(battle.units[2].id)
	_check(_demo._guard_forecast == null, "selection clears previous actor forecast")
	await _guard_hover()
	_check(_demo._guard_forecast != null and _demo._guard_forecast.actor_id == battle.selected_id, "new hover uses newly selected actor")
	_demo.inspect_enemy(battle.units[1].id)
	_check(_demo._guard_forecast == null and _demo.inspected_id == battle.units[1].id, "inspection clears guard forecast")
	await _guard_hover()
	_check(_demo.inspected_id == battle.units[1].id and _demo._guard_forecast.actor_id == battle.selected_id, "guard hover during inspection retains inspection and targets ally")
	await _key(KEY_R)
	_check(_demo._guard_forecast == null, "reset clears guard forecast")
	await _guard_hover()
	await _key(KEY_ENTER)
	_demo._ai_delay = 1000.0
	_check(_demo._guard_forecast == null and battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "phase transition clears guard forecast")
	await _guard_hover()
	_check(_demo._guard_forecast == null, "locked phase does not show a ready guard")
	await _key(KEY_R)
	await _guard_hover()
	var old_battle := battle
	await _click(_demo._mode_button.global_position + _demo._mode_button.size * 0.5)
	_check(_demo._guard_forecast == null and _demo.session != old_battle and old_battle.context == null, "scenario change releases old guard preview and session")
	_demo._open_core_combination_scenario()
	await _guard_hover()
	_demo.set_process(false)
	_demo._exit_tree()
	_check(_demo._guard_forecast == null and _demo.session == null, "shutdown releases guard forecast")
	print("GUARD FORECAST UI RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _button_center(index: int) -> Vector2:
	var button: Button = _demo._action_bar._buttons[index]
	return button.global_position + button.size * 0.5

func _guard_hover() -> void:
	await _mouse(Vector2(4, 4))
	await _mouse(_button_center(1))

func _mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	_viewport.push_input(event, true)
	await process_frame
	await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
	await process_frame

func _click(position: Vector2) -> void:
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
