extends Control
class_name BattleDemo

@export var tactical_mode: bool = false
@export var armor_mode: bool = false
@export var bleeding_mode: bool = false
@export var environment_mode: bool = false
@export var control_mode: bool = false
@export var core_combination_mode: bool = false
@export var core_reactions_mode: bool = false
@export var deployment_enabled: bool = true
var session: BattleDemoSession
var board_view: BattleDemoBoard
var attack_mode: bool = false
var summoning_mode: bool = false
var raising_mode: bool = false
var retreat_mode: bool = false
var inspected_id: int = UnitId.NONE
var _roster: VBoxContainer
var _stats: Label
var _hint: Label
var _log: RichTextLabel
var _move_button: Button
var _attack_button: Button
var _action_bar: BattleActionBar
var _status: Label
var _journal: Array[String] = []
var _battle: BattleTacticalSession
var _phase_label: Label
var _phase_row: HBoxContainer
var _end_turn_button: Button
var _mode_button: Button
var _heading: Label
var _subtitle: Label
var _instructions: Label
var _ai_delay: float = 0.0
var _flow_cursor: int = 0
var _forecast_panel: RichTextLabel
var _forecast: AttackForecast
var _attack_forecast_pending: bool = false
var _attack_forecast_actor: int = UnitId.NONE
var _attack_forecast_variant: StringName = &""
var _attack_forecast_generation: int = 0
var _attack_forecast_job_generation: int = -1
var _attack_forecast_worker := preload("res://scripts/demo/attack_forecast_worker.gd").new()
var _move_forecast: MoveForecast
var _move_forecast_cell := Vector2i(-1, -1)
var _move_forecast_actor: int = UnitId.NONE
var _move_forecast_revision: int = -1
var _move_forecast_retreat: bool = false
const MOVE_HOVER_SETTLE_MS: int = 60
var _move_forecast_pending: bool = false
var _move_forecast_due: int = 0
var _move_forecast_generation: int = 0
var _move_forecast_job_generation: int = -1
var _move_forecast_worker := MoveForecastWorker.new()
var _action_forecast_pending: bool = false
var _action_forecast_kind: StringName = &""
var _action_forecast_actor: int = UnitId.NONE
var _action_forecast_revision: int = -1
var _action_forecast_cell := Vector2i(-1, -1)
var _action_forecast_generation: int = 0
var _action_forecast_job_generation: int = -1
var _action_forecast_corpse_id: int = 0
var _action_forecast_session_id: int = 0
var _action_forecast_target_id: int = UnitId.NONE
var _action_forecast_effect: StringName = &""
var _action_forecast_cache: Dictionary = {}
var _action_forecast_worker := preload("res://scripts/demo/action_forecast_worker.gd").new()
var _item_forecast: ItemUseForecast
var _item_forecast_kind: StringName = &""
var _item_forecast_cell := Vector2i(-1, -1)
var _item_forecast_revision: int = -1
var _raise_forecast: RaiseCorpseForecast
var _raise_forecast_cell := Vector2i(-1, -1)
var _raise_forecast_actor: int = UnitId.NONE
var _raise_forecast_revision: int = -1
var _armor_forecast: ForecastSimulation
var _mage_row: HBoxContainer
var _mage_label: Label
var _mage_fire: Button
var _mage_buttons: Dictionary = {}
var _mage_heal: Button
var _elemental_forecast: ForecastSimulation
var _armor_forecast_actor: int = UnitId.NONE
var _armor_forecast_revision: int = -1
var _guard_forecast: GuardForecast
var _guard_forecast_actor: int = UnitId.NONE
var _guard_forecast_revision: int = -1
var _guard_forecast_mode: int = 0
var _guard_forecast_target: int = 0
var _cover_guard_mode: bool = false
var _descriptors_session_id: int = 0
var _descriptors_actor: int = UnitId.NONE
var _forecast_cell := Vector2i(-1, -1)
var _forecast_target_id: int = UnitId.NONE
var _forecast_revision: int = -1
var _log_heading: Label
var _forecast_heading: Label
var _pointer_position := Vector2(-1, -1)
var _shown_inspection_id: int = UnitId.NONE
var _hovered_bar_action: StringName = &""
var _execution_worker := BattleExecutionWorker.new()
@export var presentation_enabled: bool = true
var _presentation_player: BattlePresentationPlayer
var _presentation_before: Dictionary = {}
var _presentation_roots: Array[Dictionary] = []
var _presentation_events: Array[Dictionary] = []
var _presentation_seen: Dictionary = {}
var _presentation_method: StringName
var _presentation_result: Variant
var _presentation_target: bool = false
var _receipt_already_presented: bool = false
var _skip_presentation_button: Button
var _speed_presentation_button: Button
var _diagnostics: PanelContainer
var _diagnostics_button: Button
var _compact_inspection: Label
var _display_inspection_id: int = UnitId.NONE
var _turn_forecast: TurnForecast
var _turn_forecast_pending: bool = false
var _turn_forecast_generation: int = 0
var _turn_forecast_job_generation: int = -1
var _turn_forecast_session_id: int = 0
var _turn_forecast_actor: int = UnitId.NONE
var _turn_forecast_revision: int = -1
var _turn_forecast_worker := TurnForecastWorker.new()
var _environment_button: Button
var _environment_forecast: ForecastSimulation
var _environment_forecast_pending: bool = false
var _environment_forecast_generation: int = 0
var _environment_forecast_job: int = -1
var _environment_forecast_session: int = 0
var _environment_forecast_revision: int = -1
var _environment_forecast_actor: int = 0
var _environment_forecast_worker := preload("res://scripts/demo/action_forecast_worker.gd").new()

func is_execution_pending() -> bool:
	return _execution_worker.is_started() or is_presentation_pending()

func is_presentation_pending() -> bool:
	return _presentation_player != null and _presentation_player.active

func _allows_execution_worker() -> bool:
	return get_script() == BattleDemo

func _execute_live(method: StringName, args: Array = [], target_attempt: bool = false) -> void:
	if is_execution_pending(): return
	_clear_forecast()
	# Сбор значений разрешён только для проверенного штатного runtime, включая sync fallback.
	if presentation_enabled and session != null and session.get_script() == BattleCoreReactionsSession and BattleExecutionWorker.can_transfer(session):
		_presentation_before = ActionPresentationState.capture(session.state)
		session.begin_presentation_capture()
	if _allows_execution_worker() and session != null and session.get_script() == BattleCoreReactionsSession:
		var owned := session as BattleCoreReactionsSession
		# Отрисовка уже держит значения последнего refresh. Убираем доступ UI к runtime.
		board_view.execution_pending = true
		board_view.session = null
		session = null
		_battle = null
		if _execution_worker.start(owned, method, args, target_attempt):
			_status.text = "Выполняется действие…"
			return
		session = owned
		_battle = owned
		board_view.session = owned
		board_view.execution_pending = false
	_complete_live(method, session.callv(method, args), target_attempt)

func _poll_execution() -> void:
	var completed := _execution_worker.take_finished()
	if completed.is_empty(): return
	_restore_execution_owner(completed)
	_complete_live(completed.method, completed.result, completed.target_attempt)

func _restore_execution_owner(completed: Dictionary) -> void:
	session = completed.session
	_battle = session as BattleTacticalSession
	board_view.session = session
	board_view.execution_pending = false

func _join_execution() -> void:
	if _presentation_player != null: _presentation_player.cancel()
	# Reset/выход ждут завершения prefix, но не публикуют устаревший receipt в новый бой.
	var completed := _execution_worker.take_finished(true)
	if not completed.is_empty(): _restore_execution_owner(completed)
	if not _presentation_before.is_empty() and session != null: session.take_presentation_capture()
	_presentation_before.clear()
	_presentation_roots.clear()
	_presentation_events.clear()
	_presentation_result = null
	if board_view != null: board_view.execution_pending = false
	if _skip_presentation_button != null:
		_skip_presentation_button.visible = core_reactions_mode
		_skip_presentation_button.disabled = true
	if _speed_presentation_button != null: _speed_presentation_button.visible = core_reactions_mode

func _complete_live(method: StringName, result: Variant, target_attempt: bool) -> void:
	if not _presentation_before.is_empty():
		_presentation_roots = session.take_presentation_capture()
		var frames: Array[Dictionary] = []
		for root: Dictionary in _presentation_roots: frames.append_array(root.frames)
		if not frames.is_empty():
			_presentation_method = method
			_presentation_result = result
			_presentation_target = target_attempt
			_presentation_seen.clear()
			board_view.execution_pending = true
			_skip_presentation_button.show()
			_skip_presentation_button.disabled = false
			_speed_presentation_button.show()
			# Слоты остаются на месте; до завершения показа запрещено только исполнение.
			_disable_action_buttons(_action_bar)
			_disable_action_buttons(_mage_row)
			_move_button.disabled = true
			_attack_button.disabled = true
			_end_turn_button.disabled = true
			_environment_button.disabled = true
			_phase_label.text = "Показ действия"
			_render_presentation_hud(_presentation_before)
			_presentation_player.play(board_view, _presentation_before, frames, ActionPresentationState.capture(session.state))
			return
		_presentation_before.clear()
	if method == &"end_player_turn":
		if result:
			_clear_action_mode()
			_ai_delay = 0.5
		_refresh()
	elif result is ActionReceipt:
		_show_receipt(result, target_attempt)
	else:
		_refresh()

func _presentation_frame_started(frame: Dictionary) -> void:
	_presentation_events.assign(frame.events)
	var caption := "Изменение состояния хода"
	for event: Dictionary in frame.events:
		var value := BattleDemoBoard._presentation_caption(event)
		if event.get("kind") == &"moved": value = "Движение"
		if not value.is_empty():
			caption = value
			break
	_status.text = caption + " · Пробел: пропустить · ×1 / ×3"

func _presentation_frame_finished(state: Dictionary) -> void:
	for event: Dictionary in _presentation_events: _note_presentation_event(event)
	_render_presentation_hud(state)
	_log.text = "\n".join(_journal)
	_displayed_unit_hovered(_display_inspection_id)

func _disable_action_buttons(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Button: (child as Button).disabled = true
		_disable_action_buttons(child)

func set_diagnostics_visible(value: bool) -> void:
	if _diagnostics == null: return
	_diagnostics.visible = value
	_diagnostics_button.set_pressed_no_signal(value)

func _displayed_unit_hovered(unit_id: int) -> void:
	_display_inspection_id = unit_id
	if _compact_inspection == null: return
	_compact_inspection.text = board_view.displayed_unit_summary(unit_id)
	_compact_inspection.tooltip_text = board_view.displayed_unit_details(unit_id)
	board_view.tooltip_text = _compact_inspection.tooltip_text if unit_id != UnitId.NONE else ""

func _note_presentation_event(event: Dictionary) -> void:
	var seq := int(event.get("event_seq", 0))
	if _presentation_seen.has(seq): return
	_presentation_seen[seq] = true
	_note(_event_text(event))

func _render_presentation_hud(state: Dictionary) -> void:
	for child: Node in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	var details: PackedStringArray = []
	for row: Dictionary in state.get("units", {}).values():
		var status := BattleDemoBoard.presentation_status(row)
		var text := "%s · HP %.1f / %.1f" % [row.name, row.hp, row.hp_max] if row.alive else "%s · погиб" % row.name
		if not status.is_empty(): text += " · " + status
		var button := _button(text)
		button.disabled = true
		button.clip_text = true
		button.custom_minimum_size = Vector2(0 if _diagnostics != null else 480, 30)
		button.tooltip_text = text
		_roster.add_child(button)
		if row.alive:
			details.append("%s · основное %d · движение %.1f · броня %d + %d" % [row.name, row.main, row.move, int(row.armor.get("current", 0)) - int(row.armor.get("extra", 0)), int(row.armor.get("extra", 0))])
	_stats.text = "\n".join(details)
	var abilities: Dictionary = state.get("abilities", {})
	_mage_label.text = "Маг · мана %d" % int(abilities.get("mana", 0)) if not abilities.is_empty() else ""
	for entry: Dictionary in abilities.get("ledger", []):
		if String(entry.get("ability_id", "")).begins_with("mage."):
			_mage_label.text += " · %s %d" % ["огонь" if entry.ability_id == "mage.fire" else "лечение", int(entry.remaining)]

func skip_presentation() -> void:
	if _presentation_player != null: _presentation_player.skip()

func _toggle_presentation_speed() -> void:
	_presentation_player.set_speed(3.0 if _presentation_player.speed < 2.0 else 1.0)
	_speed_presentation_button.text = "Скорость ×%d" % int(_presentation_player.speed)

func _finish_presentation() -> void:
	for root: Dictionary in _presentation_roots:
		for frame: Dictionary in root.frames:
			for event: Dictionary in frame.events: _note_presentation_event(event)
	# turn_events дублирует уже собранные roots; журнал границы не должен повторяться.
	if session is BattleBleedingSession: (session as BattleBleedingSession).turn_events.clear()
	_presentation_before.clear()
	_presentation_roots.clear()
	_presentation_events.clear()
	board_view.execution_pending = false
	_skip_presentation_button.visible = core_reactions_mode
	_skip_presentation_button.disabled = true
	_speed_presentation_button.visible = core_reactions_mode
	_receipt_already_presented = true
	_complete_live(_presentation_method, _presentation_result, _presentation_target)
	_receipt_already_presented = false
	_presentation_result = null

func _ready() -> void:
	_create_session()
	_build_ui()
	_presentation_player = BattlePresentationPlayer.new()
	add_child(_presentation_player)
	_presentation_player.frame_started.connect(_presentation_frame_started)
	_presentation_player.frame_finished.connect(_presentation_frame_finished)
	_presentation_player.finished.connect(_finish_presentation)
	_note("Победите противников. Берегите своих персонажей у края." if tactical_mode else "Полигон готов. Все шесть персонажей управляются вручную.")
	_refresh()

func _create_session() -> void:
	# Составной сценарий проверяется первым, чтобы его флаги отображения не подменили сессию.
	if core_combination_mode:
		session = BattleCoreReactionsSession.new() if core_reactions_mode else BattleCoreCombinationSession.new()
		if deployment_enabled: (session as BattleCoreCombinationSession).begin_deployment()
	elif control_mode:
		session = BattleControlSession.new()
	else:
		session = BattleEnvironmentSession.new() if environment_mode else (BattleBleedingSession.new() if bleeding_mode else (BattleArmorSession.new() if armor_mode else (BattleTacticalSession.new() if tactical_mode else BattleDemoSession.new())))
	_battle = session as BattleTacticalSession
	_ai_delay = 0.0
	_flow_cursor = 0

func _process(delta: float) -> void:
	if _execution_worker.is_started():
		_poll_execution()
		return
	if is_presentation_pending(): return
	_refresh_mage()
	_process_move_forecast()
	_process_attack_forecast()
	_process_action_forecast()
	_process_turn_forecast()
	_process_environment_forecast()
	if _battle == null or _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: return
	_ai_delay -= delta
	if _ai_delay > 0.0: return
	# Один шаг за кадр; reset/смена режима не оставляют отложенных команд старого боя.
	_ai_delay = 0.7
	_execute_live(&"step_enemy")

func _input(event: InputEvent) -> void:
	# Горячая клавиша показа должна опережать Space у кнопки, сохранившей фокус.
	if is_presentation_pending() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		skip_presentation()
		get_viewport().set_input_as_handled()
		return
	if is_execution_pending(): return
	if event is InputEventMouseMotion:
		# Координата самого viewport-события одинакова для мыши и replay/test input.
		_pointer_position = (event as InputEventMouseMotion).position
		_update_action_bar_hover()
		_update_turn_forecast_hover()
		_update_environment_forecast_hover()
		if (_forecast != null or _attack_forecast_pending or _move_forecast != null or _move_forecast_pending or _raise_forecast != null or (_item_forecast != null and _item_forecast_kind == &"summon")) and board_view.hover_cell.x < 0 and not _forecast_reading_region().has_point(_pointer_position) and not board_view.get_global_rect().has_point(_pointer_position):
			_clear_forecast()
			_refresh_inspection()

func _exit_tree() -> void:
	_join_execution()
	_move_forecast_worker.close()
	_attack_forecast_worker.close()
	_action_forecast_worker.close()
	_turn_forecast_worker.close()
	_environment_forecast_worker.close()
	_turn_forecast = null
	_turn_forecast_pending = false
	_attack_forecast_pending = false
	_move_forecast_pending = false
	_forecast = null
	_move_forecast = null
	_item_forecast = null
	_item_forecast_kind = &""
	_raise_forecast = null
	_armor_forecast = null
	_armor_forecast_actor = UnitId.NONE
	_armor_forecast_revision = -1
	_guard_forecast = null
	if board_view != null:
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.sneak_threat_ids.clear()
		board_view.session = null
	if session != null: session.close()
	session = null

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("111a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	var title := HBoxContainer.new()
	root.add_child(title)
	_heading = _label("", 28, Color("e6ecf4"))
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_heading)
	_mode_button = _button("")
	_mode_button.pressed.connect(toggle_scenario)
	title.add_child(_mode_button)
	var expedition_button := _button("Забег")
	expedition_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/demo/expedition_d4.tscn"))
	title.add_child(expedition_button)
	var reset_button := _button("Сбросить бой  ·  R")
	reset_button.pressed.connect(reset_demo)
	title.add_child(reset_button)
	_subtitle = _label("", 16, Color("a5b3c5"))
	root.add_child(_subtitle)
	_phase_label = _label("", 20, Color("f7c97d"))
	_phase_row = HBoxContainer.new()
	root.add_child(_phase_row)
	_phase_row.add_child(_phase_label)
	_skip_presentation_button = _button("Пропустить · Пробел")
	_skip_presentation_button.name = "SkipPresentationButton"
	_skip_presentation_button.pressed.connect(skip_presentation)
	_phase_row.add_child(_skip_presentation_button)
	_skip_presentation_button.visible = core_reactions_mode
	_skip_presentation_button.disabled = true
	_speed_presentation_button = _button("Скорость ×1")
	_speed_presentation_button.pressed.connect(_toggle_presentation_speed)
	_phase_row.add_child(_speed_presentation_button)
	_speed_presentation_button.visible = core_reactions_mode
	_environment_button = _button("Окружение · прогноз фазы")
	_environment_button.focus_mode = Control.FOCUS_NONE
	_environment_button.pressed.connect(_request_environment_forecast)
	_phase_row.add_child(_environment_button)
	_mage_row = HBoxContainer.new()
	_mage_label = _label("", 14, Color("65dfcc"))
	_phase_row.add_child(_mage_label)
	_mage_fire = _button("Маг · Огонь 4 / 2 маны")
	_mage_fire.name = "MageFireButton"
	_mage_fire.pressed.connect(_choose_elemental.bind(&"mage.fire"))
	_mage_row.add_child(_mage_fire)
	_mage_heal = _button("Маг · Лечение 4 / 3 маны")
	_mage_heal.name = "MageHealButton"
	_mage_heal.pressed.connect(_choose_elemental.bind(&"mage.heal"))
	_mage_row.add_child(_mage_heal)
	_mage_buttons = {&"mage.fire": _mage_fire, &"mage.heal": _mage_heal}
	if core_reactions_mode:
		_mage_fire.text = "Огонь\n2 маны"
		_mage_heal.text = "Лечение\n3 маны"
		for spell: StringName in AbilityDefinition.TEST_EFFECTS:
			var button := _button(_elemental_effect_label(spell) + "\n1 мана")
			button.pressed.connect(_choose_elemental.bind(spell))
			_mage_buttons[spell] = button
			_mage_row.add_child(button)
		for button: Button in _mage_buttons.values():
			button.clip_text = true
			button.custom_minimum_size = Vector2(96, 64)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	root.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(left)
	var toolbar := HBoxContainer.new()
	left.add_child(toolbar)
	_move_button = _button("Выбор / движение  ·  M")
	_move_button.toggle_mode = true
	_move_button.pressed.connect(set_attack_mode.bind(false))
	toolbar.add_child(_move_button)
	_attack_button = _button("Атака  ·  A")
	_attack_button.toggle_mode = true
	_attack_button.pressed.connect(set_attack_mode.bind(true))
	toolbar.add_child(_attack_button)
	_end_turn_button = _button("Завершить ход · Enter")
	# Enter имеет один обработчик: фокус кнопки иначе повторяет старт на отпускании.
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.pressed.connect(end_turn)
	toolbar.add_child(_end_turn_button)
	var compare_button := _button("Сравнить ходы")
	compare_button.name = "CompareTurnsButton"
	compare_button.focus_mode = Control.FOCUS_NONE
	compare_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/demo/initiative_battle.tscn"))
	toolbar.add_child(compare_button)
	var combination_button := _button("Сочетания ядра")
	combination_button.focus_mode = Control.FOCUS_NONE
	combination_button.pressed.connect(_open_core_combination_scenario)
	toolbar.add_child(combination_button)
	if not core_reactions_mode: left.add_child(_mage_row)
	var field_row := HBoxContainer.new()
	if core_reactions_mode:
		field_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		field_row.add_theme_constant_override("separation", 12)
		left.add_child(field_row)
	board_view = BattleDemoBoard.new()
	board_view.camera_controls_enabled = core_reactions_mode
	board_view.forecast_wheel_handler = _board_forecast_wheel_input
	board_view.session = session
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.cell_clicked.connect(handle_cell)
	board_view.cell_hovered.connect(_hover)
	board_view.displayed_unit_hovered.connect(_displayed_unit_hovered)
	board_view.cancel_requested.connect(set_attack_mode.bind(false))
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if core_reactions_mode: field_row.add_child(board_view)
	else: left.add_child(board_view)
	_action_bar = BattleActionBar.new()
	_action_bar.compact_vertical = core_reactions_mode
	_action_bar.name = "BattleActionBar"
	_action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_bar.action_requested.connect(_action_bar_requested)
	_action_bar.action_hovered.connect(_action_bar_hovered)
	_action_bar.action_hover_left.connect(_action_bar_hover_left)
	_action_bar.visible = tactical_mode
	if core_reactions_mode:
		_action_bar.size_flags_horizontal = Control.SIZE_FILL
		_action_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		field_row.add_child(_action_bar)
		field_row.move_child(_action_bar, 0)
		root.add_child(_mage_row)
	else: root.add_child(_action_bar)
	_hint = _label("", 14, Color("a5b3c5"))
	_hint.custom_minimum_size.y = 40
	left.add_child(_hint)
	if core_reactions_mode:
		_hint.clip_text = true
		_hint.max_lines_visible = 2
		_compact_inspection = _label("Наведите на фигуру для осмотра.", 14, Color("e6ecf4"))
		# Две строки этого шрифта занимают 43 px; запас предотвращает resize при появлении статусов.
		_compact_inspection.custom_minimum_size.y = 44
		_compact_inspection.clip_text = true
		_compact_inspection.max_lines_visible = 2
		left.add_child(_compact_inspection)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 10)
	if core_reactions_mode:
		# Диагностика — отдельная область поверх поля, её текст не меняет раскладку боя.
		_diagnostics_button = _button("Диагностика")
		_diagnostics_button.toggle_mode = true
		_diagnostics_button.focus_mode = Control.FOCUS_NONE
		_diagnostics_button.toggled.connect(set_diagnostics_visible)
		title.add_child(_diagnostics_button)
		_diagnostics = PanelContainer.new()
		_diagnostics.name = "BattleDiagnostics"
		_diagnostics.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_diagnostics.offset_left = -380
		_diagnostics.offset_right = -24
		_diagnostics.offset_top = 104
		_diagnostics.offset_bottom = -140
		add_child(_diagnostics)
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color("172637")
		_diagnostics.add_theme_stylebox_override("panel", panel_style)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_diagnostics.add_child(scroll)
		scroll.add_child(side)
		_diagnostics.hide()
	else:
		content.add_child(side)
	side.add_child(_label("ПЕРСОНАЖИ", 13, Color("65dfcc")))
	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size.y = 192
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(roster_scroll)
	_roster = VBoxContainer.new()
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(_roster)
	_stats = _label("", 15, Color("e6ecf4"))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inspection_scroll := ScrollContainer.new()
	inspection_scroll.custom_minimum_size = Vector2(340, 144)
	inspection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspection_scroll.add_child(_stats)
	side.add_child(inspection_scroll)
	_log_heading = _label("ЖУРНАЛ ПОСЛЕДСТВИЙ", 13, Color("65dfcc"))
	side.add_child(_log_heading)
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(340, 130)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color("c8d3e1"))
	side.add_child(_log)
	_forecast_heading = _label("ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ", 13, Color("65dfcc"))
	side.add_child(_forecast_heading)
	_forecast_panel = RichTextLabel.new()
	_forecast_panel.custom_minimum_size = Vector2(340, 130)
	_forecast_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_forecast_panel.bbcode_enabled = true
	_forecast_panel.fit_content = false
	_forecast_panel.scroll_active = true
	_forecast_panel.add_theme_font_size_override("normal_font_size", 14)
	_forecast_panel.add_theme_color_override("default_color", Color("e6ecf4"))
	_forecast_panel.mouse_exited.connect(_leave_forecast_panel)
	side.add_child(_forecast_panel)
	if core_reactions_mode:
		side.move_child(_forecast_heading, 0)
		side.move_child(_forecast_panel, 1)
	_status = _label("", 14, Color("f7c97d"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 46
	root.add_child(_status)
	_instructions = _label("", 14, Color("a5b3c5"))
	root.add_child(_instructions)
	if core_reactions_mode:
		_status.clip_text = true
		_status.max_lines_visible = 2
		_instructions.clip_text = true
		_instructions.max_lines_visible = 1
		_phase_label.clip_text = true
		_phase_label.custom_minimum_size.x = 160
		_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mage_label.clip_text = true
		_mage_label.custom_minimum_size.x = 180

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	for state_name in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("304a56") if state_name == "pressed" else (Color("344559") if state_name == "hover" else Color("243345"))
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state_name, style)
	return button

func set_attack_mode(enabled: bool) -> void:
	if is_execution_pending(): return
	if _battle != null and not _battle.can_player_act(): return
	_clear_action_mode()
	attack_mode = enabled
	_refresh()

func _clear_action_mode() -> void:
	if is_execution_pending(): return
	# Только состояние ввода: остатки действий и результат команды принадлежат сессии.
	if session is BattleBleedingSession: (session as BattleBleedingSession).rune_selected = false
	if session is BattleCoreCombinationSession: (session as BattleCoreCombinationSession).entangle_selected = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).stun_selected = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).elemental_selected = &""
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	_cover_guard_mode = false
	_clear_forecast()
	# Режим действия закрывает осмотр, чтобы подсветка не смешивалась с целью атаки.
	inspected_id = UnitId.NONE

func _choose_elemental(effect: StringName) -> void:
	if is_execution_pending() or not session is BattleCoreReactionsSession: return
	var reaction_session := session as BattleCoreReactionsSession
	var reason := reaction_session.cast_reason(effect)
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	reaction_session.elemental_selected = effect
	_refresh()

func _action_bar_requested(action_id: StringName) -> void:
	if is_execution_pending(): return
	if not tactical_mode or (_battle != null and not _battle.can_player_act()): return
	match action_id:
		&"entangling_strike":
			set_attack_mode(true)
			if session is BattleCoreCombinationSession:
				(session as BattleCoreCombinationSession).entangle_selected = true
				_refresh()
		&"stunning_strike":
			set_attack_mode(true)
			if session is BattleCoreReactionsSession:
				(session as BattleCoreReactionsSession).stun_selected = true
				_refresh()
		&"elemental_burning": _choose_elemental(&"burning")
		&"elemental_wet": _choose_elemental(&"wet")
		&"elemental_freeze": _choose_elemental(&"freeze")
		&"blood_rune":
			set_attack_mode(true)
			if session is BattleBleedingSession:
				(session as BattleBleedingSession).rune_selected = true
				_refresh()
		&"attack": set_attack_mode(true)
		&"guard": _use_guard()
		&"opportunity_guard": _choose_reaction_guard(CombatPerksState.Mode.OPPORTUNIST)
		&"cover_guard": _choose_reaction_guard(CombatPerksState.Mode.COVER)
		&"counterattack_guard": _choose_reaction_guard(CombatPerksState.Mode.COUNTERATTACK)
		&"healing_item": _use_healing_item()
		&"summoning_item": _choose_summoning()
		&"raise_corpse": _choose_raise()
		&"safe_retreat": _choose_retreat()
		&"restore_armor":
			if session is BattleArmorSession:
				_clear_action_mode()
				_execute_live(&"restore_selected_armor")

func _use_healing_item() -> void:
	if is_execution_pending(): return
	if _battle == null: return
	_clear_action_mode()
	_execute_live(&"use_healing_item")

func _use_guard() -> void:
	if is_execution_pending(): return
	if _battle == null: return
	_clear_action_mode()
	_execute_live(&"guard_selected")

func _choose_reaction_guard(mode: int) -> void:
	if is_execution_pending(): return
	if not session is BattleCoreReactionsSession or _battle == null: return
	var reaction_session := session as BattleCoreReactionsSession
	if mode == CombatPerksState.Mode.COVER:
		var eligible := reaction_session.cover_targets()
		var reason := _cover_choice_reason(reaction_session, eligible)
		if reason != &"":
			_status.text = _reason_text(reason)
			return
		_clear_action_mode()
		_cover_guard_mode = true
		_refresh()
		return
	if mode not in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COUNTERATTACK]: return
	_clear_action_mode()
	_execute_live(&"set_reaction_guard", [mode])

func _cover_choice_reason(reaction_session: BattleCoreReactionsSession, targets: Array[int]) -> StringName:
	var reason := reaction_session.reaction_reason(CombatPerksState.Mode.COVER)
	for target: int in targets:
		reason = reaction_session.reaction_reason(CombatPerksState.Mode.COVER, target)
		if reason == &"": return reason
	return reason

func select_character(id: int) -> void:
	if is_execution_pending(): return
	if session.select_unit(id):
		inspected_id = UnitId.NONE
		_clear_action_mode()
		_refresh()

func _is_deploying() -> bool:
	return session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying()

func inspect_enemy(id: int) -> void:
	if is_execution_pending(): return
	if _battle == null or (not _is_deploying() and not _battle.can_player_act()): return
	var unit := session.board.get_unit_by_id(id)
	if unit == null or not unit.is_alive() or unit.faction != Faction.Type.ENEMY: return
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).stun_selected = false
	_clear_forecast()
	inspected_id = UnitId.NONE if inspected_id == id else id
	_cover_guard_mode = false
	_refresh()

func handle_cell(cell: Vector2i) -> void:
	if is_execution_pending(): return
	if _is_deploying():
		var unit := session.board.occupant_at(cell)
		if unit != null:
			if unit.faction == Faction.Type.PLAYER: select_character(unit.id)
			else: inspect_enemy(unit.id)
		else:
			inspected_id = UnitId.NONE
			var placed := (session as BattleCoreCombinationSession).place_selected(cell)
			_refresh()
			if not placed: _status.text = "Нужна свободная безопасная клетка в подсвеченной зоне A3–F6."
		return
	if _battle != null and not _battle.can_player_act(): return
	var occupant := session.board.occupant_at(cell)
	if _cover_guard_mode and session is BattleCoreReactionsSession:
		var reaction_session := session as BattleCoreReactionsSession
		if occupant != null and reaction_session.cover_targets().has(occupant.id):
			_clear_forecast()
			_cover_guard_mode = false
			_execute_live(&"set_reaction_guard", [CombatPerksState.Mode.COVER, occupant.id])
		else:
			_status.text = "Выберите подсвеченного союзника для Прикрытия или нажмите Esc."
		return
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		if occupant == null:
			_status.text = "Выберите допустимую живую цель."
			return
		var spell := (session as BattleCoreReactionsSession).elemental_selected
		if AbilityDefinition.mage_source_id(spell) > 0: _execute_live(&"cast_mage_spell", [spell, occupant.id], true)
		else: _execute_live(&"cast_unit", [occupant.id], true)
	elif summoning_mode:
		_execute_live(&"use_summoning_item", [cell], true)
	elif raising_mode and session is BattleEnvironmentSession:
		_execute_live(&"raise_corpse", [cell], true)
	elif attack_mode:
		if occupant == null:
			var rejected := ActionReceipt.new()
			rejected.reason = &"attack/invalid_target"
			_show_receipt(rejected, true)
			return
		# В командном бою союзник под курсором означает выбор, а не дружественный удар.
		if _battle != null and occupant.is_alive() and occupant.faction == Faction.Type.PLAYER:
			select_character(occupant.id)
			return
		_execute_live(&"attack_unit", [occupant.id], true)
	elif occupant != null:
		if _battle != null and occupant.faction == Faction.Type.ENEMY:
			inspect_enemy(occupant.id)
		else:
			select_character(occupant.id)
	elif inspected_id != UnitId.NONE:
		# Первый клик по пустой клетке завершает осмотр; движение требует второго клика.
		inspected_id = UnitId.NONE
		_refresh()
	else:
		_execute_live(&"retreat_to" if retreat_mode else &"move_to", [cell], retreat_mode)

func reset_demo() -> void:
	_join_execution()
	_clear_forecast()
	session.reset()
	_cover_guard_mode = false
	_descriptors_session_id = 0
	_descriptors_actor = UnitId.NONE
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_flow_cursor = 0
	_ai_delay = 0.0
	_note("Бой сброшен: здоровье, действия и предметы восстановлены.")
	_refresh()

func toggle_scenario() -> void:
	_join_execution()
	control_mode = false
	core_combination_mode = false
	_cover_guard_mode = false
	_clear_forecast()
	session.close()
	armor_mode = false
	bleeding_mode = false
	environment_mode = false
	tactical_mode = not tactical_mode
	_create_session()
	board_view.session = session
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_note("Начат бой против компьютера." if tactical_mode else "Полигон: все персонажи управляются вручную.")
	_refresh()

func _open_core_combination_scenario() -> void:
	_join_execution()
	_clear_forecast()
	retreat_mode = false
	_cover_guard_mode = false
	if session != null: session.close()
	core_combination_mode = true
	# Эти флаги включают уже существующие подсказки и действия окружения/контроля.
	control_mode = true
	armor_mode = true
	bleeding_mode = true
	environment_mode = true
	tactical_mode = true
	_create_session()
	board_view.session = session
	board_view.environment_mode = true
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_note("Реакции и скрытая атака: полный общий бой." if session is BattleCoreReactionsSession else "Сочетания ядра: пробивающий клинок Бора, контроль, тыл и крит, кровотечение, шипы и поднятие тела.")
	_refresh()

func end_turn() -> void:
	if is_execution_pending(): return
	if _battle == null: return
	if _is_deploying():
		if (session as BattleCoreCombinationSession).start_battle(): _clear_action_mode()
		_refresh()
		return
	_execute_live(&"end_player_turn")

func _refresh_mage() -> void:
	if not is_execution_pending() and _mage_row != null:
		var mage_session := session as BattleCoreReactionsSession
		_mage_row.visible = mage_session != null and mage_session.state.abilities != null
		_mage_label.visible = _mage_row.visible
		if board_view != null:
			board_view.custom_minimum_size.y = 350.0 if _compact_inspection != null else (476.0 if _mage_row.visible else 520.0)
		if _mage_row.visible:
			var ability := mage_session.state.abilities
			_mage_label.text = "Маг · мана %d/%d" % [ability.mana, ability.maximum]
			_mage_label.tooltip_text = "Откаты: длительность: огонь %d, лечение %d · осталось: огонь %d, лечение %d" % [ability.definition(&"mage.fire").cooldown_turns, ability.definition(&"mage.heal").cooldown_turns, ability.remaining(&"mage.fire"), ability.remaining(&"mage.heal")]
			for id: StringName in _mage_buttons:
				var button: Button = _mage_buttons[id]
				var definition := ability.definition(id)
				button.visible = definition != null
				var reason := mage_session.mage_reason(id)
				button.disabled = reason != &""
				if definition == null: continue
				button.tooltip_text = "%s · %d маны · откат %d, осталось %d\n%s" % [_elemental_effect_label(id), definition.mana_cost, definition.cooldown_turns, ability.remaining(id), _mage_spell_help(id)]
				if AbilityDefinition.TEST_EFFECTS.has(id): button.tooltip_text += "\nТестовое заклинание: любая живая цель на доске, включая союзников. Без затрат действий героя."
				if reason != &"": button.tooltip_text += "\n" + _reason_text(reason)

func _mage_spell_help(id: StringName) -> String:
	match id:
		&"mage.fire": return "4 огненного урона врагу, без поджога. Вся доска."
		&"mage.heal": return "Восстановить союзнику 4 HP. Вся доска."
		&"mage.test_burning": return "Тест: +1 стак горения и 3 тика; вода гасит, лёд тает. Снимает кровотечение."
		&"mage.test_wet": return "Тест: вода на 3 хода цели, гасит горение."
		&"mage.test_freeze": return "Тест: сухую цель сначала мочит; мокрую замораживает на 2 хода при броне ниже половины. Иммунитет сохраняется."
		&"mage.test_stun": return "Тест: оглушение до конца хода цели, без удара. Иммунитет сохраняется."
		&"mage.test_roots": return "Тест: корни до конца хода цели, без удара. Иммунитет сохраняется."
		&"mage.test_bleeding": return "Тест: +1 стак, срок 3 тика. Горение и иммунитет блокируют наложение."
	return ""

func _refresh() -> void:
	_refresh_mage()
	if is_execution_pending(): return
	# Любой refresh перечитывает состояние, включая изменения вне command revision.
	var refresh_turn := (_turn_forecast != null or _turn_forecast_pending) and (_over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position))
	var refresh_environment := (_environment_forecast != null or _environment_forecast_pending) and (_over_environment_button() or _forecast_reading_region().has_point(_pointer_position))
	var refresh_armor := (_armor_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"armor")) and _hovered_bar_action == &"restore_armor"
	var refresh_guard_action := _hovered_bar_action if _guard_forecast != null or (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack"]) else &""
	var refresh_healing := (_item_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"healing")) and _hovered_bar_action == &"healing_item"
	var refresh_guard := refresh_guard_action in [&"guard", &"opportunity_guard", &"counterattack_guard"]
	var reset_dynamic_page := _descriptors_session_id != session.get_instance_id() or _descriptors_actor != session.selected_id
	_clear_forecast()
	if inspected_id != UnitId.NONE:
		var inspected := session.board.get_unit_by_id(inspected_id) if session != null and session.board != null else null
		if _battle == null or (not _battle.can_player_act() and not _is_deploying()) or inspected == null or not inspected.is_alive() or inspected.faction != Faction.Type.ENEMY:
			inspected_id = UnitId.NONE
	_heading.text = "intoDeDung   /   Бой у обрыва" if tactical_mode else "intoDeDung   /   Полигон"
	if armor_mode: _heading.text = "intoDeDung   /   Броня и огонь"
	if bleeding_mode: _heading.text = "intoDeDung   /   Кровотечение"
	if environment_mode: _heading.text = "intoDeDung   /   Среда и трупы"
	if control_mode: _heading.text = "intoDeDung   /   Крит и спина"
	if core_combination_mode: _heading.text = "intoDeDung   /   Сочетания ядра"
	if session is BattleCoreReactionsSession: _heading.text = "intoDeDung   /   Реакции и скрытая атака"
	_subtitle.text = "Трое против троих. Победите всех врагов; потеря команды означает поражение." if tactical_mode else "Поднимитесь по ступеням. Ударьте сверху. Столкните стража с уступа."
	_subtitle.visible = not tactical_mode
	_status.custom_minimum_size.y = 42 if core_reactions_mode else (26 if tactical_mode else 46)
	_mode_button.text = "Полигон" if tactical_mode else "Бой против ИИ"
	_phase_label.visible = tactical_mode
	_phase_row.visible = tactical_mode
	_end_turn_button.visible = tactical_mode
	_environment_button.visible = session is BattleCoreReactionsSession and not _is_deploying()
	_environment_button.disabled = not _can_forecast_environment()
	# В тактическом режиме атака должна иметь единственную точку входа в action bar;
	# старая кнопка остаётся частью sandbox-полигона для совместимости.
	_attack_button.visible = not tactical_mode
	_instructions.text = "1 / A: атака · 2: защита · 3: лечение · 4: призыв · M: движение · Клик по врагу: осмотр · Enter: конец хода · R: заново" if tactical_mode else "Ступени: Астра → D3 → A → Страж. Стена: Бор → A → Щит. Пропасть: Рей → A → Мишень на G7."
	if armor_mode: _instructions.text = _instructions.text.replace("4: призыв", "4: броня +20")
	if environment_mode: _instructions.text = "1 / A: атака · 2: защита · 3: лечение · 6: поднять тело · M: движение · Enter: конец хода · R: заново"
	if session is BattleBleedingSession and (session as BattleBleedingSession).rune_selected:
		_instructions.text = "Кровавая руна (перк): выберите цель · 1 основное · Обходит требование HP-урона; иммунитет сохраняется · A: обычная атака"
	if session is BattleCoreCombinationSession:
		_instructions.text += " · 7: опутывающий удар"
		if (session as BattleCoreCombinationSession).entangle_selected:
			_instructions.text = "Опутывающий удар: выберите цель · 1 основное · Путы после физического HP-урона · A: обычная атака"
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).stun_selected:
		_instructions.text = "Оглушающий удар: выберите цель · 1 основное · Оглушение после физического HP-урона · A: обычная атака"
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		_instructions.text = "%s: выберите живую цель в пределах трёх клеток · 1 основное · Esc — отмена" % _elemental_effect_label((session as BattleCoreReactionsSession).elemental_selected)
		if AbilityDefinition.mage_source_id((session as BattleCoreReactionsSession).elemental_selected) > 0: _instructions.text = "Маг: выберите цель на доске · отдельная мана · Esc — отмена"
	var locked := _battle != null and not _battle.can_player_act()
	_move_button.disabled = locked
	if session.selected_unit() != null and ControlRules.action_reason(session.selected_unit(), true) != &"": _move_button.disabled = true
	_attack_button.disabled = locked
	_end_turn_button.disabled = locked
	_end_turn_button.text = "Начать бой · Enter" if _is_deploying() else "Завершить ход · Enter"
	if _is_deploying(): _end_turn_button.disabled = false
	_action_bar.visible = tactical_mode
	if tactical_mode and _action_bar != null:
		var item := _battle.healing_item() if _battle != null else null
		var healing_reason := _battle.healing_hint_reason() if _battle != null else &"battle/input_locked"
		var descriptors: Array[Dictionary] = []
		descriptors.append(_item_action_descriptor(item, &"healing_item", healing_reason))
		var seal := _battle.summoning_item() if _battle != null else null
		if session is BattleArmorSession:
			var reason := (session as BattleArmorSession).restore_armor_reason()
			descriptors.append({"action_id": &"restore_armor", "label": "Броня +20", "cost": "1 основное", "disabled": reason != &"", "tooltip": "Восстановить 20 брони по недостаче вещей. Избыток становится временной бронёй до конца боя.\n" + (_reason_text(reason) if reason != &"" else "Стойка сохраняется.")})
		elif seal != null:
			var reason := _battle.summoning_hint_reason()
			descriptors.append(_item_action_descriptor(seal, &"summoning_item", reason))
		if session is BattleBleedingSession and (not session is BattleCoreReactionsSession or (session as BattleCoreReactionsSession).allows_loadout_action(&"blood_rune")):
			descriptors.append({"action_id": &"blood_rune", "label": "Кровавая руна", "cost": "Перк · 1 основное", "disabled": locked or session.selected_unit() == null or not session.selected_unit().can_attack(), "tooltip": "Перк персонажа «Кровавая руна»: эта атака накладывает кровотечение даже без физического урона HP. Иммунитет сохраняется. " + ("Добавляет стак урона и обновляет срок до 3 тиков; 1 за стак в начале хода, 2 за клетку, с учётом естественной защиты." if session is BattleCoreReactionsSession else "Каждое успешное наложение добавляет 2 тика по 4 с учётом естественной защиты.")})
		if environment_mode and session is BattleEnvironmentSession:
			var raise_reason := (session as BattleEnvironmentSession).raise_hint_reason()
			descriptors.append({"action_id": &"raise_corpse", "label": "Поднять тело", "cost": "1 основное", "disabled": locked or raise_reason != &"", "tooltip": "Выберите соседнюю свободную клетку без шипов той же высоты. Помощник: 16 HP, действует со следующего хода команды.\n" + (_reason_text(raise_reason) if raise_reason != &"" else "Тело расходуется после успешного поднятия.")})
		if session is BattleCoreCombinationSession and (not session is BattleCoreReactionsSession or (session as BattleCoreReactionsSession).allows_loadout_action(&"entangling_strike")):
			descriptors.append({"action_id": &"entangling_strike", "label": "Опутывающий удар", "cost": "1 основное", "disabled": locked or session.selected_unit() == null or not session.selected_unit().can_attack() or ControlRules.action_reason(session.selected_unit()) != &"", "tooltip": "Обычный урон и толчок, затем путы при физическом HP-уроне. Без кровотечения. Движение цели запрещено до конца её ближайшего хода; следующий фактический толчок снимает путы. Повтор не накапливает срок."})
			descriptors.append(_item_action_descriptor(seal, &"summoning_item", _battle.summoning_hint_reason()))
		if session is BattleCoreReactionsSession and session.selected_unit() != null and session.selected_unit().combat_perks != null and session.selected_unit().combat_perks.definition.tank_reactions:
			var reaction_session := session as BattleCoreReactionsSession
			var opportunity_reason := reaction_session.reaction_reason(CombatPerksState.Mode.OPPORTUNIST)
			var eligible_cover_targets := reaction_session.cover_targets()
			var cover_reason := _cover_choice_reason(reaction_session, eligible_cover_targets)
			descriptors.append({"action_id": &"opportunity_guard", "label": "Оппортунист", "cost": "1 основное", "disabled": locked or opportunity_reason != &"", "tooltip": "До следующего пополнения своей команды остановить первого врага, покидающего вашу угрозу. Перемещение полностью прекращается; расходуется один общий заряд реакции.\n" + (_reason_text(opportunity_reason) if opportunity_reason != &"" else "Наведение показывает прогноз. Клик ставит режим за 1 основное действие.")})
			descriptors.append({"action_id": &"cover_guard", "label": "Прикрытие", "cost": "1 основное", "disabled": locked or cover_reason != &"", "tooltip": "Выберите соседнего союзника с допустимой геометрией. Один прямой удар снижается на 30% по всем компонентам до брони. Нужны стойка и общий заряд; заряд тратится при срабатывании.\n" + (_reason_text(cover_reason) if cover_reason != &"" else "Клик — выбор союзника.")})
		if session is BattleCoreReactionsSession and session.selected_unit() != null and ControlRules.has_stunning_strike(session.selected_unit()):
			var stun_actor := session.selected_unit()
			var stun_reason := ControlRules.action_reason(stun_actor)
			if locked: stun_reason = &"battle/input_locked"
			elif not stun_actor.can_attack(): stun_reason = &"attack/insufficient_main"
			descriptors.append({"action_id": &"stunning_strike", "label": "Оглушающий удар", "cost": "Перк · 1 основное", "disabled": stun_reason != &"", "tooltip": "Обычные урон, крит и толчок; оглушение накладывается после положительного физического урона HP. Без кровотечения. Иммунитет цели пропускает только оглушение.\n" + (_reason_text(stun_reason) if stun_reason != &"" else "Клик — выбрать цель; плата происходит после проверки владения и допуска.")})
		if session is BattleCoreReactionsSession and MeleeThreat.has_counterattack(session.selected_unit()):
			var counter_reason := (session as BattleCoreReactionsSession).reaction_reason(CombatPerksState.Mode.COUNTERATTACK)
			if locked: counter_reason = &"battle/input_locked"
			descriptors.append({"action_id": &"counterattack_guard", "label": "Контратака", "cost": "Перк · 1 основное", "disabled": counter_reason != &"", "tooltip": "Охранная стойка сохраняется. После прямого ближнего удара по вам последует один ответный удар без толчка; по замороженной цели — крит. Расходуется общий заряд реакции.\n" + (_reason_text(counter_reason) if counter_reason != &"" else "Наведение показывает полный прогноз стойки. Клик включает режим за 1 основное действие.")})
		if session is BattleCoreReactionsSession:
			var retreat_reason := (session as BattleCoreReactionsSession).retreat_reason()
			descriptors.append({"action_id": &"safe_retreat", "label": "Безопасный отход", "cost": "1 основное + движение", "disabled": locked or retreat_reason != &"", "tooltip": "Один маршрут без перехвата Оппортунистом. Контроль и опасности сохраняются. Основное списывается с первым сегментом, движение — за пройденный путь.\n" + (_reason_text(retreat_reason) if retreat_reason != &"" else "Выберите клетку; наведение покажет последствия.")})
		# Новые действия дополняют список, сохраняя прежние клавиши и страницы.
		if session is BattleCoreReactionsSession and session.selected_unit() != null:
			var reaction_session := session as BattleCoreReactionsSession
			var burning_rule := "Огонь 4 урона; крит ×2 по замороженной цели. Без толчка. Требуется положительный огненный урон HP."
			if session.selected_unit().combat_perks != null and session.selected_unit().combat_perks.definition.burning_bypass_hp_gate:
				burning_rule = "Огонь 4 урона; крит ×2 по замороженной цели. Без толчка. Перк позволяет наложить горение без положительного огненного урона HP."
			for ability: Array in [[&"elemental_burning", &"burning", "Поджечь", burning_rule], [&"elemental_wet", &"wet", "Облить", "Мокрый на 3 своих хода; снимает горение и защищает от одного наложения горения. Без урона."], [&"elemental_freeze", &"freeze", "Заморозить", "Мокрую цель замораживает только при броне ниже 50% максимума; сухую сначала делает мокрой. Замороженную можно продлить при том же пороге. Без урона."]]:
				var reason := reaction_session.cast_reason(ability[1])
				descriptors.append({"action_id": ability[0], "label": ability[2], "cost": "1 основное", "disabled": locked or reason != &"", "tooltip": "Дальность: 3 клетки. " + String(ability[3]) + "\n" + (_reason_text(reason) if reason != &"" else "Клик — выбрать цель; расход после проверки цели.")})
		if _action_bar.compact_vertical and session is BattleCoreReactionsSession:
			descriptors = (session as BattleCoreReactionsSession).visible_action_descriptors(descriptors)
		_action_bar.set_dynamic_descriptors(descriptors, reset_dynamic_page)
		_descriptors_session_id = session.get_instance_id()
		_descriptors_actor = session.selected_id
		var control_reason := ControlRules.action_reason(session.selected_unit())
		_action_bar.set_slot_enabled(&"attack", not locked and control_reason == &"", "Сейчас нельзя действовать." if locked else (_reason_text(control_reason) if control_reason != &"" else "1 основное действие"))
		var guard_reason := _battle.guard_reason() if _battle != null else &"battle/input_locked"
		var guard_enabled := not locked and guard_reason == &""
		_action_bar.set_slot_enabled(&"guard", guard_enabled, "1 основное действие" if guard_enabled else _reason_text(guard_reason))
	if _battle != null:
		_phase_label.text = _battle.phase_text()
		if session is BattleBleedingSession:
			for event: Dictionary in (session as BattleBleedingSession).turn_events: _note(_event_text(event))
			(session as BattleBleedingSession).turn_events.clear()
		while _flow_cursor < _battle.flow_log.size():
			_note(_battle.flow_log[_flow_cursor])
			_flow_cursor += 1
	_move_button.set_pressed_no_signal(not attack_mode)
	_attack_button.set_pressed_no_signal(attack_mode)
	_log.visible = not attack_mode
	_log_heading.visible = not attack_mode
	_forecast_panel.visible = attack_mode or _item_forecast != null or _move_forecast != null or _guard_forecast != null or _armor_forecast != null or _raise_forecast != null
	_forecast_heading.visible = attack_mode or _item_forecast != null or _move_forecast != null or _guard_forecast != null or _armor_forecast != null or _raise_forecast != null
	var elemental_mode: bool = session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &""
	_forecast_panel.visible = _forecast_panel.visible or elemental_mode or _elemental_forecast != null
	_forecast_heading.visible = _forecast_panel.visible
	if locked:
		summoning_mode = false
		raising_mode = false
		retreat_mode = false
		_cover_guard_mode = false
		if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).elemental_selected = &""
	board_view.summoning_mode = summoning_mode
	board_view.raising_mode = raising_mode
	board_view.retreat_mode = retreat_mode
	board_view.environment_mode = environment_mode
	board_view.attack_mode = attack_mode
	board_view.elemental_mode = elemental_mode
	board_view.inspected_id = inspected_id
	board_view.reaction_zone_cells.clear()
	_update_area_preview()
	board_view.cover_target_ids.clear()
	board_view.sneak_threat_ids.clear()
	if session is BattleCoreReactionsSession and MeleeThreat.has_reactions(session.selected_unit()):
		if _cover_guard_mode: board_view.cover_target_ids.assign((session as BattleCoreReactionsSession).cover_targets())
	if _forecast != null:
		for event: Dictionary in _forecast.events:
			if event.get("kind") != &"attacked": continue
			var modifiers: Dictionary = event.get("modifiers", {})
			for threat_id: Variant in modifiers.get("threat_ids", []):
				if typeof(threat_id) == TYPE_INT and not board_view.sneak_threat_ids.has(threat_id): board_view.sneak_threat_ids.append(threat_id)
	board_view.refresh()
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	for unit in session.units:
		var alive := unit.is_alive()
		var waiting := " · ЖДЁТ ХОДА" if session.state.is_summon_pending(unit.id) and alive else ""
		var stance := " · ОХРАНА" if unit.guard_stance and alive else ""
		if alive and unit.control != null:
			if unit.control.stunned_turns > 0: stance += " · ОГЛУШЁН"
			if unit.control.entangled_turns > 0: stance += " · ОПУТАН"
		var perk_status := _perk_status_text(unit)
		var text := "%s%s%s  ·  %s" % [unit.debug_name, stance + waiting, perk_status, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб"]
		var button := _button(text)
		if session is BattleCoreReactionsSession:
			# Сочетания перков/контроля не должны расширять окно за пределы viewport.
			button.clip_text = true
			button.custom_minimum_size.x = 0 if _diagnostics != null else 480
			button.tooltip_text = text
			# HP идёт перед длинными перками, чтобы оставаться видимым при обрезке.
			button.text = "%s · %s%s%s" % [unit.debug_name, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб", stance + waiting, perk_status]
		button.custom_minimum_size.y = 30
		button.toggle_mode = true
		button.set_pressed_no_signal(unit.id == session.selected_id and alive)
		if _battle != null and unit.faction == Faction.Type.ENEMY:
			button.set_pressed_no_signal(unit.id == inspected_id and alive)
			button.disabled = not alive or (locked and not _is_deploying())
			button.pressed.connect(inspect_enemy.bind(unit.id))
		else:
			button.disabled = not alive or (locked and not _is_deploying())
			button.pressed.connect(select_character.bind(unit.id))
		_roster.add_child(button)
	var selected := session.selected_unit()
	if selected == null:
		_stats.text = "Выберите живого персонажа в списке."
		if locked:
			_stats.text = "Дождитесь завершения хода противника." if _battle.phase == BattleTacticalSession.Phase.ENEMY_TURN else "Бой окончен. Нажмите R, чтобы сыграть снова."
	else:
		_stats.text = _inspection_text(selected)
	if inspected_id != UnitId.NONE:
		var enemy := session.board.get_unit_by_id(inspected_id)
		if enemy != null:
			_stats.text = _inspection_text(enemy)
	_status.text = "Атака: щёлкните по цели. Расход — 1 основное действие." if attack_mode else "Движение: щёлкните по свободной клетке. Персонаж на поле или в списке — выбор."
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		_status.text = "%s: наведите курсор на цель для прогноза, щёлкните для применения." % _elemental_effect_label((session as BattleCoreReactionsSession).elemental_selected)
	if inspected_id != UnitId.NONE:
		var enemy := session.board.get_unit_by_id(inspected_id)
		_status.text = "Осмотр: %s · движение на следующий ход: %.1f ОД\nТекущая расстановка; зона движения. Esc или клик по пустой клетке — закрыть." % [enemy.debug_name, enemy.get_stat(StatTypes.StatType.MOVE_RANGE)]
		if ControlRules.action_reason(enemy, true) != &"": _status.text = "Осмотр: %s · движение в ближайший ход недоступно из-за состояния.\nEsc или клик по пустой клетке — закрыть." % enemy.debug_name
	if summoning_mode: _status.text = "Призыв: выберите подсвеченную соседнюю клетку. 1 основное + 1 заряд. Esc — отмена."
	if raising_mode: _status.text = "Поднять тело: выберите подсвеченную соседнюю свободную клетку без шипов. 1 основное. Esc — отмена."
	if retreat_mode: _status.text = "Безопасный отход: выберите клетку. 1 основное + пройденное движение. Оппортунист не срабатывает; опасности сохраняются. Esc — отмена."
	if session.context.is_faulted(): _status.text = "Исполнение остановлено из-за ошибки. Выполненные последствия сохранены; сбросьте бой."
	if locked: _status.text = _battle.phase_text() + (" · Можно начать заново: R." if _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN else " · Противник выполняет действия.")
	if _is_deploying():
		_instructions.text = "Выберите союзника → свободную клетку в зоне A3–F6. Перестановки бесплатны. Enter: начать бой · R: исходная расстановка"
		_status.text = "Расставьте отряд или начните с готовой позиции. Противников можно осмотреть; действия и эффекты пока не исполняются."
	elif session is BattleCoreCombinationSession:
		_instructions.text += " · 8: печать призыва"
	if session is BattleCoreReactionsSession and not _is_deploying():
		_instructions.text = "1–4: способности слева · маг: снизу · зелёная зона: союзник, красная: враг · контур: область выбранного действия"
	if _cover_guard_mode: _status.text = "Прикрытие: выберите подсвеченного союзника. 1 основное действие, заряд реакции тратится при первом срабатывании. Esc — отмена."
	_hover(board_view.hover_cell)
	_log.text = "\n".join(_journal)
	if refresh_armor and _battle != null and _battle.can_player_act(): _action_bar_hovered(&"restore_armor")
	if refresh_guard and _battle != null and _battle.can_player_act(): _action_bar_hovered(refresh_guard_action)
	if refresh_healing and _battle != null and _battle.can_player_act(): _action_bar_hovered(&"healing_item")
	if refresh_turn and _can_forecast_turn(): _request_turn_forecast()
	if refresh_environment and _can_forecast_environment(): _request_environment_forecast()
	_render_forecast_panel()
	_displayed_unit_hovered(_display_inspection_id)

func _perk_status_text(unit: UnitState) -> String:
	if not session is BattleCoreReactionsSession or unit.combat_perks == null: return ""
	var parts: PackedStringArray = []
	if unit.combat_perks.definition.sneak_attack: parts.append("Скрытая атака")
	if unit.combat_perks.definition.stunning_strike: parts.append("Оглушающий удар")
	if unit.combat_perks.definition.counterattack: parts.append("перк Контратака")
	if unit.combat_perks.definition.stun_immune: parts.append("иммунитет к оглушению")
	if unit.combat_perks.definition.entangle_immune: parts.append("иммунитет к путам")
	if MeleeThreat.has_reactions(unit):
		var mode_text := "без режима"
		if unit.combat_perks.mode == CombatPerksState.Mode.OPPORTUNIST: mode_text = "Оппортунист"
		elif unit.combat_perks.mode == CombatPerksState.Mode.COVER: mode_text = "Прикрытие → " + _name_for(unit.combat_perks.cover_target_id)
		elif unit.combat_perks.mode == CombatPerksState.Mode.COUNTERATTACK: mode_text = "Контратака"
		parts.append("%s · реакция %d/1" % [mode_text, unit.combat_perks.reaction_left])
	if unit.combat_perks.movement_stopped: parts.append("движение остановлено")
	return " · " + " · ".join(parts) if not parts.is_empty() else ""

func _inspection_text(unit: UnitState) -> String:
	var text := "%s · %s · высота %+.1f\nHP: %.1f / %.1f\nПотеря равновесия: %.1f / %.1f\nДвижение: %.1f / %.1f · Основное: %d · Бонус: %d\nБроня: %.1f · Оружие: %.1f урона\nСила: %.1f · Воздействие: %.1f\nАтака: 1 основное · Дальность: %.1f" % [unit.debug_name, _cell_name(unit.cell), float(session.board.get_height_steps(unit.cell)) / 2.0, unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX), unit.vitals.get_balance(), ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX)), unit.move_points_left, unit.get_stat(StatTypes.StatType.MOVE_RANGE), unit.action_resources.get_main_left(), unit.action_resources.get_bonus_left(), unit.get_stat(StatTypes.StatType.ARMOR), unit.get_stat(StatTypes.StatType.WEAPON_DAMAGE), unit.get_stat(StatTypes.StatType.STRENGTH), unit.get_stat(StatTypes.StatType.IMPACT_POWER), unit.get_stat(StatTypes.StatType.ATTACK_RANGE)]
	var control_text := ""
	if session is BattleCoreReactionsSession and unit.combat_perks != null:
		if unit.combat_perks.definition.sneak_attack: control_text += "Перк «Скрытая атака»: +50% физической базы, если цели угрожают минимум двое. Оружие ближнего боя любое.\n"
		if unit.combat_perks.definition.stunning_strike: control_text += "Перк «Оглушающий удар»: накладывает оглушение после положительного физического урона HP. Без кровотечения.\n"
		if unit.combat_perks.definition.burning_bypass_hp_gate: control_text += "Перк «Поджог»: горение накладывается без положительного огненного урона HP.\n"
		if unit.combat_perks.definition.counterattack: control_text += "Перк «Контратака»: стойка отвечает одним ударом на прямую ближнюю атаку; без толчка, по замороженной цели — крит. Стойка сохраняется, тратится общий заряд реакции.\n"
		if unit.combat_perks.definition.stun_immune: control_text += "Иммунитет к оглушению: полученный удар и толчок сохраняются.\n"
		if unit.combat_perks.definition.entangle_immune: control_text += "Иммунитет к путам: полученный удар и толчок сохраняются.\n"
		if MeleeThreat.has_reactions(unit):
			var mode_text := "нет"
			if unit.combat_perks.mode == CombatPerksState.Mode.OPPORTUNIST: mode_text = "Оппортунист"
			elif unit.combat_perks.mode == CombatPerksState.Mode.COVER: mode_text = "Прикрытие: " + _name_for(unit.combat_perks.cover_target_id)
			elif unit.combat_perks.mode == CombatPerksState.Mode.COUNTERATTACK: mode_text = "Контратака"
			control_text += "Режим реакции: %s · общий заряд: %d/1.\n" % [mode_text, unit.combat_perks.reaction_left]
		if unit.combat_perks.movement_stopped: control_text += "Движение остановлено Оппортунистом до следующего пополнения команды цели.\n"
	var piercing := unit.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT)
	if piercing > 0.0:
		text += "\nПробивание %.0f%% физической базы: броня обходится, естественная защита действует." % piercing
	if control_mode and not session is BattleCoreReactionsSession:
		var rear := AttackModifiers.rear_offset(unit.faction)
		if rear != Vector2i.ZERO: control_text += "Тыл: %s · соседняя клетка, +50%% базы\n" % _cell_name(unit.cell + rear)
	if unit.control != null:
		if unit.control.stunned_turns > 0: control_text += "Оглушён: добровольные действия недоступны; входящий крит ×2.\n"
		if unit.control.entangled_turns > 0: control_text += "Опутан: движение недоступно; порог равновесия ×2 = %.1f.\nФактический толчок снимает путы; входящий крит ×2.\n" % ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX))
		if unit.control.stunned_turns > 0 or unit.control.entangled_turns > 0: control_text += "Срок: до конца ближайшего хода этой команды.\n"
	if not control_text.is_empty(): text = text.insert(text.find("\n") + 1, control_text)
	if session.state.summon_owner_id(unit.id) != 0:
		text += "\nПомощник: до гибели / конца боя; владелец " + _name_for(session.state.summon_owner_id(unit.id))
		text += "\nДействия со следующего хода своей команды." if session.state.is_summon_pending(unit.id) else "\nГотов действовать."
	var descriptions: Array[String] = []
	if unit.bleeding != null:
		var condition := "Кровотечение: тиков — %d · 4 до защиты" % unit.bleeding.ticks_left
		if session is BattleBleedingSession and unit.faction == Faction.Type.PLAYER:
			condition += "\nПерк: Кровавая руна · атака клавишей 5"
		if unit.bleeding.stacked: condition = "Кровотечение: " + _bleeding_summary(unit.bleeding.to_dict())
		if unit.bleeding.immune: condition += "\nИммунитет к кровотечению"
		var first_line := text.find("\n")
		text = text.insert(first_line + 1, condition + "\n")
	if unit.elemental != null:
		var effects: PackedStringArray = []
		if unit.elemental.burning_stacks > 0: effects.append("Горение: %d ст. · %d тиков · %d огненного урона за тик" % [unit.elemental.burning_stacks, unit.elemental.burning_ticks, unit.elemental.burning_stacks])
		if unit.elemental.wet_turns > 0: effects.append("Мокрый: %d своих ходов" % unit.elemental.wet_turns)
		if unit.elemental.frozen_turns > 0: effects.append("Заморожен: %d своих ходов · входящий удар критический" % unit.elemental.frozen_turns)
		if unit.elemental.freeze_immune: effects.append("Иммунитет к заморозке")
		if effects.is_empty(): effects.append("Элементальные статусы отсутствуют")
		var first_line := text.find("\n")
		text = text.insert(first_line + 1, "\n".join(effects) + "\n")
	if unit.armor != null:
		var armor := ArmorRuntime.totals(ArmorRuntime.capture(session.state.get_owner(unit.id)))
		if not armor.is_empty():
			text = text.replace("Броня: %.1f" % unit.get_stat(StatTypes.StatType.ARMOR), "Броня: %d / %d (временная: %d)" % [armor["current"], armor["maximum"], armor["extra"]])
	if session.state != null:
		var owner := session.state.get_owner(unit.id)
		if owner != null:
			for item: ItemInstance in owner._items.values():
				if not item.is_active(): continue
				var action := item.get_use_action()
				if action != null and action.get_target_mode() == ItemUseAction.TargetMode.ADJACENT_CELL:
					if _battle != null and not _battle.supports_summoning():
						descriptions.append("Печать: призыв недоступен в сценарии брони.")
					else:
						descriptions.append("Печать: помощник с %s HP за %s; осталось %d/%d. Один на владельца, действует со следующего хода команды, до гибели / конца боя." % [_summon_hp_text(item), _item_cost_text(action), item.get_charges_left(), action.get_max_charges()])
				elif action != null:
					descriptions.append("%s: лечение себя до +%.1f HP за %s; осталось %d/%d. Стойка сохраняется." % [item.get_definition().display_name, action.get_heal_amount(), _item_cost_text(action), item.get_charges_left(), action.get_max_charges()])
				for effect in item.get_effects():
					if not effect.is_active(): continue
					if effect is HealOnDamageEffectRuntime:
						descriptions.append("Лечение +%.1f HP после урона; пока предмет активен." % (effect as HealOnDamageEffectRuntime).get_heal_amount())
					elif effect is StatModifierEffectRuntime:
						var modifier := effect as StatModifierEffectRuntime
						var amount := "%+.1f" % modifier.get_value()
						if modifier.get_stat_type() == StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: amount += " п.п."
						if modifier.get_operation() == StatModifier.Operation.ADD_PERCENT: amount = "%+.1f%%" % (modifier.get_value() * 100.0)
						elif modifier.get_operation() == StatModifier.Operation.MULTIPLY: amount = "×%.2f" % modifier.get_value()
						descriptions.append("%s %s; пока предмет активен." % [_stat_name(modifier.get_stat_type()), amount])
					else: descriptions.append("Неизвестный активный эффект; описание недоступно.")
	if unit.guard_stance:
		text += "\nОхранная стойка: прямой урон −30%, воздействие −50% до следующего хода команды; движение и атака снимают стойку."
	text += "\nЭффекты: " + ("нет активных." if descriptions.is_empty() else "\n" + "\n".join(descriptions))
	return text

func _stat_name(type: StatTypes.StatType) -> String:
	var names := ["Макс. HP", "Инициатива", "Порог равновесия", "Сила", "Воздействие", "Движение", "Броня", "Основные действия", "Бонусные действия", "Урон оружия", "Дальность атаки", "Пробивание физической базы"]
	return names[int(type)] if int(type) >= 0 and int(type) < names.size() else "Характеристика"

func _refresh_inspection() -> void:
	if is_execution_pending(): return
	var id := _forecast_target_id if _forecast != null or _attack_forecast_pending else inspected_id
	var unit := session.board.get_unit_by_id(id) if id != UnitId.NONE else session.selected_unit()
	if unit != null:
		if _shown_inspection_id != unit.id:
			(_stats.get_parent() as ScrollContainer).scroll_vertical = 0
		_shown_inspection_id = unit.id
		_stats.text = _inspection_text(unit)

func _hover(cell: Vector2i) -> void:
	if is_execution_pending(): return
	if session == null or session.board == null: return
	if _is_deploying(): return
	if _environment_forecast != null or _environment_forecast_pending:
		if cell.x < 0:
			_resolve_hover_exit.call_deferred()
			return
		_clear_forecast()
	if _turn_forecast != null or _turn_forecast_pending:
		if cell.x < 0:
			_resolve_hover_exit.call_deferred()
			return
		_clear_forecast()
	if (_guard_forecast != null and _guard_forecast_mode != CombatPerksState.Mode.COVER or _armor_forecast != null) and cell.x >= 0: _clear_forecast()
	# Позволяем перейти к прокрутке длинной цепи, сохранив текущий прогноз.
	if (_forecast != null or _attack_forecast_pending or _action_forecast_pending or _item_forecast != null or _move_forecast != null or _raise_forecast != null or _guard_forecast != null or _armor_forecast != null or _elemental_forecast != null) and cell.x < 0:
		# mouse_exited может прийти раньше _input того же движения мыши.
		_resolve_hover_exit.call_deferred()
		return
	if raising_mode and session is BattleEnvironmentSession and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if (_raise_forecast == null and not _action_forecast_pending) or _raise_forecast_cell != cell or _raise_forecast_actor != session.selected_id or _raise_forecast_revision != revision:
			_clear_forecast()
			_raise_forecast_cell = cell
			_raise_forecast_actor = session.selected_id
			_raise_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_request_action_forecast(&"raise", cell)
	elif summoning_mode and _battle != null and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if _item_forecast_kind != &"summon" or _item_forecast_cell != cell or _item_forecast_revision != revision:
			_clear_forecast()
			_item_forecast_kind = &"summon"
			_item_forecast_cell = cell
			_item_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_request_action_forecast(&"summon", cell)
	elif _cover_guard_mode and session is BattleCoreReactionsSession:
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		var reaction_session := session as BattleCoreReactionsSession
		if target != null and reaction_session.cover_targets().has(target.id):
			var revision := session.context.get_revision()
			if (_guard_forecast == null and not _action_forecast_pending) or _guard_forecast_actor != session.selected_id or _guard_forecast_revision != revision or _guard_forecast_mode != CombatPerksState.Mode.COVER or _guard_forecast_target != target.id:
				_clear_forecast()
				_guard_forecast_actor = session.selected_id
				_guard_forecast_revision = revision
				_guard_forecast_mode = CombatPerksState.Mode.COVER
				_guard_forecast_target = target.id
				_request_action_forecast(&"cover", cell)
		else:
			_clear_forecast()
	elif session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		var reaction_session := session as BattleCoreReactionsSession
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		if _battle == null or not _battle.can_player_act() or target == null:
			_clear_forecast()
		else:
			var cache := _elemental_cast_cache(reaction_session.selected_unit(), target, reaction_session.elemental_selected)
			if _action_forecast_kind != &"elemental" or _action_forecast_target_id != target.id or _action_forecast_revision != session.context.get_revision() or _action_forecast_cache != cache:
				_clear_forecast()
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_request_action_forecast(&"elemental", cell)
	elif not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act()) and session.board.is_in_bounds(cell) and session.board.occupant_at(cell) == null:
		var revision := session.context.get_revision()
		if (_move_forecast == null and not _move_forecast_pending) or _move_forecast_cell != cell or _move_forecast_actor != session.selected_id or _move_forecast_revision != revision or _move_forecast_retreat != retreat_mode:
			_clear_forecast()
			_move_forecast_pending = true
			_move_forecast_due = Time.get_ticks_msec() + MOVE_HOVER_SETTLE_MS
			_move_forecast_cell = cell
			_move_forecast_actor = session.selected_id
			_move_forecast_revision = revision
			_move_forecast_retreat = retreat_mode
			_forecast_panel.get_v_scroll_bar().value = 0.0
			board_view.move_forecast_pending = true
			# Быстрая геометрия не ждёт полного исполнения прогноза в рабочем потоке.
			if board_view.reachable_cells().has(cell): board_view.pending_move_path = session.path_to(cell)
			board_view.refresh_forecast()
	elif not attack_mode or (_battle != null and not _battle.can_player_act()) or not session.board.is_in_bounds(cell):
		_clear_forecast()
	else:
		var target := session.board.occupant_at(cell)
		if target == null:
			_clear_forecast()
		else:
			var revision := session.context.get_revision()
			if _forecast_cell != cell or _forecast_target_id != target.id or _forecast_revision != revision or _attack_forecast_actor != session.selected_id or _attack_forecast_variant != _attack_variant():
				_clear_forecast()
				_attack_forecast_pending = true
				_attack_forecast_actor = session.selected_id
				_attack_forecast_variant = _attack_variant()
				# Новый прогноз всегда читается с начала, даже после прокрутки предыдущей цели.
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_forecast_cell = cell
				_forecast_target_id = target.id
				_forecast_revision = revision
	_refresh_inspection()

	if environment_mode and session is BattleEnvironmentSession and session.board.is_in_bounds(cell):
		var environment := (session as BattleEnvironmentSession).state.environment
		var details: Array[String] = []
		for corpse: Dictionary in environment.corpses_at(cell):
			var faction: String = {Faction.Type.PLAYER: "союзник", Faction.Type.ENEMY: "противник", Faction.Type.NEUTRAL: "нейтральный"}[corpse["faction"]]
			var kind := "гуманоид" if corpse["creature_kind"] == "humanoid" else String(corpse["creature_kind"])
			details.append("%s · %s" % [faction, kind])
		var fire_record: Dictionary = environment.fire_at(cell)
		var fire := "Опасностей нет."
		if not fire_record.is_empty():
			fire = _hazard_summary(fire_record)
		_hint.text = fire + ("\nТела ×%d: %s" % [details.size(), ", ".join(details)] if not details.is_empty() else "\nТрупов нет.")
		if environment.collapse.get("marked", []).has(cell):
			_hint.text = "%s · ОБВАЛ после вашего хода. Клетка станет пропастью; оставшийся здесь погибнет.\n" % _cell_name(cell) + _hint.text
		if raising_mode: _hint.text += "\nПоднятие: выберите соседнюю клетку той же высоты."
		var area_text := board_view.area_details(cell)
		if not area_text.is_empty(): _hint.text = area_text + "\n" + _hint.text
		_hint.tooltip_text = _hint.text
		_render_forecast_panel()
		return

	if summoning_mode:
		var item := _battle.summoning_item()
		_hint.text = "Бирюзовые точки — клетки призыва. Клик — %s.\nПомощник с %s HP действует со следующего хода своей команды. Esc — отмена." % [_item_cost_text(item.get_use_action() if item != null else null), _summon_hp_text(item)]
		return
	if not session.board.is_in_bounds(cell):
		var movement_cancel_hint := "ПКМ — сдвиг карты; Esc или M — отмена." if board_view.camera_controls_enabled else "ПКМ или Esc — движение."
		_hint.text = "Золотые клетки — движение врага на следующий ход; зона атаки не показана.\nВыбранный союзник сохранён. Осмотр не расходует действия." if inspected_id != UnitId.NONE else "Числа на клетках — высота. Бирюзовые точки — доступное движение.\nПолоски: здоровье / накопленная потеря равновесия. %s" % movement_cancel_hint
		if control_mode and not session is BattleCoreReactionsSession and inspected_id == UnitId.NONE: _hint.text = "Розовая стрелка у ног — тыл: атака с соседней клетки даёт +50% базы.\nОглушение или путы на цели дают крит ×2; два состояния не складывают крит."
		return
	var reachable: Dictionary = board_view.reachable_cells()
	var cost := " · путь: %.1f ОД" % float(reachable[cell]) if reachable.has(cell) else ""
	_hint.text = "%s · высота %+.1f%s\n%s" % [_cell_name(cell), float(session.board.get_height_steps(cell)) / 2.0, cost, "Осмотр: зона движения на следующий ход, не атаки." if inspected_id != UnitId.NONE else "Прогноз показывает итог движения. Клик — выполнить; кольцо — конечная клетка."]
	if attack_mode: _hint.text = "Наведите на цель: прогноз одной атаки. Клик — выполнить.\nКрасный сегмент HP — потеря, зелёный — лечение; белая метка — итог."
	var environment_state: CombatEnvironmentState = session.state.environment if session.state != null else null
	if environment_state != null:
		var hazard: Dictionary = environment_state.fire_at(cell)
		if not hazard.is_empty():
			_hint.text += "\n" + _hazard_summary(hazard)
	_render_forecast_panel()

func _hazard_summary(hazard: Dictionary) -> String:
	if String(hazard.get("effect", "")) == "burning": return "Огонь: поджог при входе и в начале своего хода, независимо от брони."
	if hazard.has("effect"): return "Шипы: 8 физического урона при входе; кровотечение независимо от брони."
	return "Шипы: 8 урона при входе."

func _attack_variant() -> StringName:
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).stun_selected: return &"stun"
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).entangle_selected: return &"entangle"
	if session is BattleBleedingSession and (session as BattleBleedingSession).rune_selected: return &"rune"
	return &"ordinary"

func _attack_forecast_request_current() -> bool:
	if session == null or session.context == null or board_view == null: return false
	if not attack_mode or summoning_mode or raising_mode or _cover_guard_mode or (_battle != null and not _battle.can_player_act()): return false
	if session.selected_id != _attack_forecast_actor or session.context.get_revision() != _forecast_revision or _attack_variant() != _attack_forecast_variant: return false
	var target := session.board.get_unit_by_id(_forecast_target_id)
	if target == null or target.cell != _forecast_cell: return false
	# Переход к панели сохраняет ожидаемый результат так же, как уже готовый прогноз.
	return board_view.hover_cell == _forecast_cell or (board_view.hover_cell.x < 0 and _forecast_reading_region().has_point(_pointer_position))

func _request_action_forecast(kind: StringName, cell: Vector2i = Vector2i(-1, -1)) -> void:
	if is_execution_pending(): return
	_action_forecast_pending = true
	_action_forecast_kind = kind
	_action_forecast_actor = session.selected_id
	_action_forecast_revision = session.context.get_revision()
	_action_forecast_cell = cell
	_action_forecast_session_id = session.get_instance_id()
	_action_forecast_target_id = UnitId.NONE
	_action_forecast_effect = &""
	_action_forecast_cache = {}
	if kind == &"elemental" and session is BattleCoreReactionsSession:
		var reaction_session := session as BattleCoreReactionsSession
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		_action_forecast_target_id = target.id if target != null else UnitId.NONE
		_action_forecast_effect = reaction_session.elemental_selected
		_action_forecast_cache = _elemental_cast_cache(reaction_session.selected_unit(), target, _action_forecast_effect)
	_render_forecast_panel()

func _elemental_cast_cache(actor: UnitState, target: UnitState, effect: StringName) -> Dictionary:
	if target == null or (actor == null and AbilityDefinition.mage_source_id(effect) == 0): return {}
	# Равные totals/revision не означают равные вещи, перки, RNG и последствия.
	var captured := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	return {
		"session_id": session.get_instance_id(), "actor_id": actor.id if actor != null else 0, "effect": effect,
		"target_id": target.id, "world": captured.snapshot.to_dict() if captured.snapshot != null else {},
		"capture_reason": captured.reason, "rng": session.context.get_rng().to_dict().duplicate(true),
		"counters": session.context.simulation_counters(), "admission": SummonAdmission.values(session.context),
		"limits": [session._queue._max_commands, session._queue._max_events, session._queue._max_depth],
	}

func _action_forecast_request_current() -> bool:
	if _battle == null or not _battle.can_player_act() or board_view == null: return false
	if session == null or session.get_instance_id() != _action_forecast_session_id or session.selected_id != _action_forecast_actor or session.context.get_revision() != _action_forecast_revision: return false
	var over_panel := board_view.hover_cell.x < 0 and _forecast_reading_region().has_point(_pointer_position)
	match _action_forecast_kind:
		&"healing": return _hovered_bar_action == &"healing_item" or over_panel
		&"armor": return _hovered_bar_action == &"restore_armor" or over_panel
		&"guard": return _hovered_bar_action == &"guard" or over_panel
		&"opportunity": return _hovered_bar_action == &"opportunity_guard" or over_panel
		&"counterattack": return _hovered_bar_action == &"counterattack_guard" or over_panel
		&"raise": return raising_mode and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"summon": return summoning_mode and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"cover":
			var target := session.board.get_unit_by_id(_guard_forecast_target)
			return _cover_guard_mode and target != null and target.cell == _action_forecast_cell and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"elemental":
			if not session is BattleCoreReactionsSession: return false
			var reaction_session := session as BattleCoreReactionsSession
			var target := session.board.get_unit_by_id(_action_forecast_target_id)
			if target == null or target.cell != _action_forecast_cell or reaction_session.elemental_selected != _action_forecast_effect or reaction_session.cast_reason(_action_forecast_effect) != &"": return false
			if _elemental_cast_cache(reaction_session.selected_unit(), target, _action_forecast_effect) != _action_forecast_cache: return false
			return board_view.hover_cell == _action_forecast_cell or over_panel
	return false

func _process_action_forecast() -> void:
	if is_execution_pending(): return
	# Готовый прогноз тоже устаревает при изменении мира без движения мыши.
	if _elemental_forecast != null and not _action_forecast_request_current():
		_clear_forecast()
		_hover(board_view.hover_cell)
	var result: ForecastSimulation = _action_forecast_worker.take_finished()
	if result != null and _action_forecast_pending and _action_forecast_job_generation == _action_forecast_generation:
		if not _action_forecast_request_current():
			_clear_forecast()
			return
		_action_forecast_pending = false
		match _action_forecast_kind:
			&"healing", &"summon": _item_forecast = ItemUseForecast.from_simulation(result)
			&"guard", &"opportunity", &"cover", &"counterattack": _guard_forecast = GuardForecast.from_simulation(result, _action_forecast_actor)
			&"raise": _raise_forecast = RaiseCorpseForecast.from_simulation(result, _action_forecast_actor, _action_forecast_corpse_id)
			&"armor": _armor_forecast = result
			&"elemental": _elemental_forecast = result
		_render_forecast_panel()
		_refresh_inspection()
	if not _action_forecast_pending or _action_forecast_worker.is_started(): return
	if not _action_forecast_request_current():
		_clear_forecast()
		return
	var prepared: ForecastSimulation.Prepared
	match _action_forecast_kind:
		&"healing": prepared = _battle.prepare_item_forecast(ItemUseAction.Kind.HEAL_SELF)
		&"summon": prepared = _battle.prepare_item_forecast(ItemUseAction.Kind.SUMMON_ADJACENT, _action_forecast_cell)
		&"guard", &"opportunity", &"cover", &"counterattack": prepared = _battle.prepare_guard_forecast(_guard_forecast_mode, _guard_forecast_target)
		&"raise": prepared = (session as BattleEnvironmentSession).prepare_raise_corpse_forecast(_action_forecast_cell)
		&"armor": prepared = (session as BattleArmorSession).prepare_restore_armor_forecast()
		&"elemental": prepared = (session as BattleCoreReactionsSession).prepare_cast_forecast(_action_forecast_target_id)
	_action_forecast_corpse_id = (prepared.command as RaiseCorpseCommand)._corpse_id if prepared != null and prepared.command is RaiseCorpseCommand else 0
	_action_forecast_job_generation = _action_forecast_generation
	_action_forecast_worker.start(prepared)

func _process_attack_forecast() -> void:
	if is_execution_pending(): return
	var result := _attack_forecast_worker.take_finished()
	if result != null and _attack_forecast_pending and _attack_forecast_job_generation == _attack_forecast_generation:
		if not _attack_forecast_request_current():
			_clear_forecast()
			return
		_forecast = result
		_attack_forecast_pending = false
		board_view.forecast = result
		_sync_sneak_threat_highlight()
		board_view.refresh_forecast()
		_render_forecast_panel()
		_refresh_inspection()
	if not _attack_forecast_pending or _attack_forecast_worker.is_started(): return
	if not _attack_forecast_request_current():
		_clear_forecast()
		return
	_attack_forecast_job_generation = _attack_forecast_generation
	# Ввод только запоминает последнюю цель; capture выполняется один раз на кадре.
	_attack_forecast_worker.start(session.prepare_attack_forecast(_forecast_target_id))

func _process_move_forecast() -> void:
	if is_execution_pending(): return
	var result := _move_forecast_worker.take_finished()
	if result != null and _move_forecast_pending and _move_forecast_job_generation == _move_forecast_generation:
		if not _move_forecast_request_current():
			_clear_forecast()
			return
		_move_forecast = result
		_move_forecast_pending = false
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.move_forecast = result
		board_view.refresh_forecast()
		_render_forecast_panel()
	if not _move_forecast_pending or _move_forecast_worker.is_started() or Time.get_ticks_msec() < _move_forecast_due: return
	if not _move_forecast_request_current():
		_clear_forecast()
		return
	_move_forecast_job_generation = _move_forecast_generation
	# Только этот короткий capture читает live; исполнение и восстановление идут на копии.
	var prepared := (session as BattleCoreReactionsSession).prepare_retreat_forecast(_move_forecast_cell) if _move_forecast_retreat and session is BattleCoreReactionsSession else session.prepare_move_forecast(_move_forecast_cell)
	_move_forecast_worker.start(prepared)

func _move_forecast_request_current() -> bool:
	return session != null and session.context != null and board_view != null and board_view.hover_cell == _move_forecast_cell and session.selected_id == _move_forecast_actor and session.context.get_revision() == _move_forecast_revision and retreat_mode == _move_forecast_retreat and not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act())

func _board_forecast_wheel_input(event: InputEvent) -> bool:
	if is_execution_pending(): return false
	if not event is InputEventMouseButton: return false
	var wheel := event as InputEventMouseButton
	if not wheel.pressed or (wheel.button_index != MOUSE_BUTTON_WHEEL_UP and wheel.button_index != MOUSE_BUTTON_WHEEL_DOWN): return false
	if not _forecast_panel.is_visible_in_tree() or (_battle != null and not _battle.can_player_act()): return false
	var target_cell := _forecast_cell if _forecast != null and attack_mode else _move_forecast_cell
	if _raise_forecast != null and raising_mode: target_cell = _raise_forecast_cell
	if (_forecast == null or not attack_mode) and _move_forecast == null and _raise_forecast == null: return false
	if board_view.cell_at(wheel.position) != target_cell: return false
	var amount := 48.0 * (wheel.factor if wheel.factor > 0.0 else 1.0)
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP: amount = -amount
	var scroll_bar := _forecast_panel.get_v_scroll_bar()
	var last_value := maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	scroll_bar.value = clampf(scroll_bar.value + amount, scroll_bar.min_value, last_value)
	accept_event()
	return true

func _leave_forecast_panel() -> void:
	if is_execution_pending(): return
	_resolve_hover_exit.call_deferred()

func _resolve_hover_exit() -> void:
	if is_execution_pending(): return
	if _environment_forecast != null or _environment_forecast_pending:
		if _over_environment_button() or _forecast_reading_region().has_point(_pointer_position): return
		_clear_forecast()
		_refresh_inspection()
		return
	if _turn_forecast != null or _turn_forecast_pending:
		if _over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position): return
		_clear_forecast()
		_refresh_inspection()
		return
	if session == null or board_view.hover_cell.x >= 0 or (_forecast == null and not _attack_forecast_pending and not _action_forecast_pending and _item_forecast == null and _move_forecast == null and _raise_forecast == null and _guard_forecast == null and _armor_forecast == null and _elemental_forecast == null): return
	if _item_forecast_kind == &"healing" and _hovered_bar_action == &"healing_item": return
	if (_armor_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"armor")) and _hovered_bar_action == &"restore_armor": return
	if (_guard_forecast != null or (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack"])) and _hovered_bar_action in [&"guard", &"opportunity_guard", &"counterattack_guard"]: return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _forecast_reading_region() -> Rect2:
	if not _forecast_panel.is_visible_in_tree(): return Rect2()
	var panel := _forecast_panel.get_global_rect()
	# Узкий зазор между полем и панелью не должен прерывать переход курсора.
	var left := minf(board_view.get_global_rect().end.x, panel.position.x)
	return Rect2(Vector2(left, panel.position.y), Vector2(panel.end.x - left, panel.size.y))

func _clear_forecast() -> void:
	if is_execution_pending(): return
	_environment_forecast_generation += 1
	_environment_forecast_pending = false
	_environment_forecast = null
	_turn_forecast_generation += 1
	_turn_forecast_pending = false
	_turn_forecast = null
	_turn_forecast_session_id = 0
	_turn_forecast_actor = UnitId.NONE
	_turn_forecast_revision = -1
	_action_forecast_generation += 1
	_action_forecast_pending = false
	_action_forecast_kind = &""
	_action_forecast_session_id = 0
	_action_forecast_target_id = UnitId.NONE
	_action_forecast_effect = &""
	_action_forecast_cache.clear()
	var had_forecast := _forecast != null or _attack_forecast_pending or _move_forecast != null or _move_forecast_pending
	_attack_forecast_generation += 1
	_attack_forecast_pending = false
	_attack_forecast_actor = UnitId.NONE
	_attack_forecast_variant = &""
	_move_forecast_generation += 1
	_move_forecast_pending = false
	_forecast = null
	_move_forecast = null
	_move_forecast_cell = Vector2i(-1, -1)
	_move_forecast_actor = UnitId.NONE
	_move_forecast_revision = -1
	_item_forecast = null
	_item_forecast_kind = &""
	_item_forecast_cell = Vector2i(-1, -1)
	_item_forecast_revision = -1
	_raise_forecast = null
	_raise_forecast_cell = Vector2i(-1, -1)
	_raise_forecast_actor = UnitId.NONE
	_raise_forecast_revision = -1
	_armor_forecast = null
	_elemental_forecast = null
	_armor_forecast_actor = UnitId.NONE
	_armor_forecast_revision = -1
	_guard_forecast = null
	_guard_forecast_actor = UnitId.NONE
	_guard_forecast_revision = -1
	_guard_forecast_mode = 0
	_guard_forecast_target = 0
	_forecast_cell = Vector2i(-1, -1)
	_forecast_target_id = UnitId.NONE
	_forecast_revision = -1
	if board_view != null:
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.sneak_threat_ids.clear()
		if had_forecast and board_view.session != null: board_view.refresh_forecast()
	if _forecast_panel != null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		_forecast_panel.visible = attack_mode
		_forecast_heading.visible = attack_mode
		_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	if _log != null: _log.visible = not attack_mode
	if _log_heading != null: _log_heading.visible = not attack_mode

func _render_forecast_panel() -> void:
	if is_execution_pending(): return
	if _forecast_panel == null: return
	if _environment_forecast_pending or _environment_forecast != null:
		_render_environment_forecast()
		return
	if _turn_forecast_pending or _turn_forecast != null:
		_render_turn_forecast()
		return
	if _action_forecast_pending:
		_forecast_panel.visible = true
		_forecast_heading.visible = true
		_forecast_heading.text = "ПРОГНОЗ ДЕЙСТВИЯ"
		_log.visible = false
		_log_heading.visible = false
		_forecast_panel.text = "Рассчитываем последствия для %s…" % _name_for(_action_forecast_target_id) if _action_forecast_kind == &"elemental" else "Рассчитываем последствия действия…"
		return
	if _armor_forecast != null:
		_render_armor_forecast_panel()
		return
	if _elemental_forecast != null:
		_render_elemental_forecast_panel()
		return
	if _guard_forecast != null:
		if _guard_forecast_mode in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]: _render_reaction_guard_forecast()
		else: _render_guard_forecast_panel()
		return
	if _raise_forecast != null:
		_render_raise_forecast_panel()
		return
	if _move_forecast != null or _move_forecast_pending:
		_render_move_forecast_panel()
		return
	if _item_forecast != null:
		_render_item_forecast_panel()
		return
	if _attack_forecast_pending:
		_forecast_panel.text = "[font_size=16][color=#f7c97d]%s → %s[/color][/font_size]\nРассчитываем последствия удара…" % [_name_for(_attack_forecast_actor), _name_for(_forecast_target_id)]
		return
	if _forecast == null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		return
	var status: StringName = _forecast.status
	var reason: StringName = _forecast.reason
	var text := "[font_size=16][color=#f7c97d]%s → %s[/color][/font_size]\n" % [_name_for(_attack_forecast_actor), _name_for(_forecast_target_id)]
	if status != &"APPLIED":
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(reason)
		return
	# Краткий итог цепи виден до подробных строк брони и HP.
	var chain_links: PackedStringArray = []
	for event: Dictionary in _forecast.events:
		if event.get("kind") == &"chain_link":
			chain_links.append("%s: %s%s" % [_name_for(int(event.target_unit_id)), str(event.impulse), "" if event.broke else " (удержал)"])
	if not chain_links.is_empty():
		text += "[color=#f7c97d]Цепь · сила: %s[/color]\n" % " → ".join(chain_links)
		text += "Пунктир — импульс; стрелка — сдвиг.\n"
	var units: Dictionary = _forecast.units
	var target_after: Dictionary = units.get(_forecast_target_id, {}).get("after", {})
	for step: Dictionary in _forecast.steps:
		if step["kind"] == &"stun_apply":
			if step["status"] == &"APPLIED": text += "Оглушение: до конца ближайшего хода команды цели.\n"
			elif step["status"] == &"SKIPPED": text += "Оглушение пропущено: " + _control_skip_text(step["reason"]) + ".\n"
			continue
		if step["kind"] != &"entangle_apply": continue
		if step["status"] == &"APPLIED":
			text += "Путы: до конца ближайшего хода команды цели. Движение запрещено; следующий толчок снимает путы.\n"
		elif step["status"] == &"SKIPPED": text += "Путы не наложены: " + _control_skip_text(step["reason"]) + ".\n"
	if target_after.has("bleeding"):
		text += "Кровотечение после атаки: %s\n" % _bleeding_summary(target_after["bleeding"]) if target_after["bleeding"].has("stacks") else "Кровотечение: %d тика после атаки\n" % target_after["bleeding"]["ticks_left"]
		for step: Dictionary in _forecast.steps:
			if step["kind"] == &"bleeding_apply" and step["status"] == &"SKIPPED":
				text += "Не наложено: " + _bleeding_skip_text(step["reason"]) + ".\n"
	for id_variant in units:
		var id := int(id_variant)
		var entry: Dictionary = units[id]
		var before: Dictionary = entry.get("before", {})
		var after: Dictionary = entry.get("after", {})
		if before == after: continue
		var hp_before := float(before.get("hp", 0.0))
		var hp_after := float(after.get("hp", 0.0))
		var hp_color := "#f29b9b" if hp_after < hp_before else "#65dfcc"
		if hp_before != hp_after or id == _forecast_target_id:
			text += "%s: HP [color=%s]%.1f → %.1f%s[/color]\n" % [_name_for(id), hp_color, hp_before, hp_after, " · ГИБЕЛЬ" if not after["alive"] else ""]
		if before["balance"] != after["balance"]:
			text += "%s: потеря равновесия %.1f → %.1f\n" % [_name_for(id), before["balance"], after["balance"]]
		if before.has("armor_current"):
			text += "%s: броня %d → %d / %d\n" % [_name_for(id), before["armor_current"], after["armor_current"], after["armor_max"]]
		if before.has("bleeding") and (id == _forecast_target_id or before["bleeding"] != after["bleeding"]):
			if before["bleeding"].has("stacks"):
				text += "%s: кровотечение %s → %s\n" % [_name_for(id), _bleeding_summary(before["bleeding"]), _bleeding_summary(after["bleeding"])]
			else:
				text += "%s: кровотечение %d → %d тика\n" % [_name_for(id), before["bleeding"]["ticks_left"], after["bleeding"]["ticks_left"]]
		if before.get("elemental", {}) != after.get("elemental", {}):
			text += "%s: %s → %s\n" % [_name_for(id), _elemental_summary(before.get("elemental", {})), _elemental_summary(after.get("elemental", {}))]
		if before.has("control") and before["control"] != after["control"]:
			if before["control"]["entangled_turns"] > after["control"]["entangled_turns"]: text += "%s: путы будут сняты.\n" % _name_for(id)
			if after["control"]["stunned_turns"] > before["control"]["stunned_turns"]: text += "%s: оглушение будет наложено.\n" % _name_for(id)
		if before["main"] != after["main"]:
			text += "%s: основные действия %d → %d\n" % [_name_for(id), before["main"], after["main"]]
	var events: Array[Dictionary] = _forecast.events
	for event: Dictionary in events:
		if event.get("kind") == &"attacked" and event.has("modifiers"):
			var modifiers: Dictionary = event["modifiers"]
			if modifiers.has("sneak_percent") and modifiers["sneak_percent"] == 50:
				var names: PackedStringArray = []
				for threat_id: int in modifiers.get("threat_ids", []): names.append(_name_for(threat_id))
				text += "\n[color=#f7c97d]Скрытая атака +50%% физической базы[/color] · угрожают: %s\n" % ", ".join(names)
			if modifiers["backstab_percent"] > 0 and not session is BattleCoreReactionsSession: text += "\n[color=#f7c97d]Удар в спину +%d%% базы[/color]\n" % modifiers["backstab_percent"]
			if modifiers["critical"]: text += "[color=#f29b9b]Крит ×2: прямой урон и воздействие[/color]\n"
	for event: Dictionary in events:
		if event.get("kind") != &"hit_resolved": continue
		var hit: Dictionary = event["hit"]
		var hit_source: Dictionary = event.get("source", {})
		if hit_source.get("kind", &"") == &"cell":
			text += "[color=#f29b9b]Шипы на %s: 8 урона при входе[/color]\n" % _cell_name(hit_source.get("origin_cell", Vector2i.ZERO))
		text += "\n[color=#f7c97d]%s · броня −%d[/color]\n" % [_name_for(event["target_unit_id"]), hit["armor_spent"]]
		text += "В HP до защиты: %d/%d · урон %d · лечение %d\n" % [hit["p_num"], hit["p_den"], hit["total_damage"], hit["total_healing"]]
		for row: Dictionary in hit["rows"]:
			var damage_label := "Физический" if row["type"] == &"physical" else "Огонь"
			if row["policy"] == &"hp_only_natural": damage_label += " · в обход брони"
			elif row["policy"] == &"hp_only_unresisted": damage_label += " · без защит"
			text += "%s: вход %d → броня %d / HP %d / лечение %d\n" % [damage_label, row["D"], row["armor_spent"], row["hp_damage"], row["healing"]]
		if hit.has("bleeding"):
			var gate: Dictionary = hit["bleeding"]
			text += "Кровотечение: " + ("Перк «Кровавая руна» обходит требование физического HP-урона" if gate["policy"] == &"bypass_hp_gate" else ("есть физический HP-урон до лечения" if gate["eligible"] else "нет физического HP-урона")) + ".\n"
	for step: Dictionary in _forecast.steps:
		if step["kind"] != &"bleeding_apply" or step["status"] != &"SKIPPED": continue
		text += "Кровотечение не наложено: " + _bleeding_skip_text(step["reason"]) + ".\n"
	if events.is_empty(): text += "Событий последствий нет.\n"
	else:
		text += "\n[color=#a5b3c5]Последствия:[/color]\n"
		for event_variant in events:
			text += "• " + _event_text(event_variant as Dictionary) + "\n"
	_forecast_panel.text = text

func _sync_sneak_threat_highlight() -> void:
	if is_execution_pending(): return
	if board_view == null: return
	board_view.sneak_threat_ids.clear()
	if _forecast == null: return
	for event: Dictionary in _forecast.events:
		if event.get("kind") != &"attacked": continue
		var modifiers: Dictionary = event.get("modifiers", {})
		for raw_id: Variant in modifiers.get("threat_ids", []):
			if typeof(raw_id) == TYPE_INT and not board_view.sneak_threat_ids.has(raw_id): board_view.sneak_threat_ids.append(raw_id)

func _control_skip_text(reason: StringName) -> String:
	match reason:
		&"control/dead_target": return "цель погибла"
		&"control/stun_immune": return "иммунитет к оглушению"
		&"control/entangle_immune": return "иммунитет к путам"
		_: return "нет положительного физического урона HP"

func _render_move_forecast_panel() -> void:
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]%s к %s[/color][/font_size]\n" % ["Безопасный отход" if _move_forecast_retreat else "Движение", _cell_name(_move_forecast_cell)]
	if _move_forecast_retreat: text += "Оппортунист не перехватывает этот маршрут. Опасности сохраняются.\n"
	if _move_forecast_pending:
		_forecast_panel.text = text + ("Пунктир — выбранный маршрут.\nРассчитываем последствия…" if not board_view.pending_move_path.is_empty() else "Расчёт прогноза…")
		return
	if _move_forecast.status not in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_move_forecast.reason)
		return
	if _move_forecast.status == ActionReceipt.INTERRUPTED:
		text += "[color=#f29b9b]Маршрут прервётся: %s[/color]\n" % _reason_text(_move_forecast.reason)
		if _move_forecast.reason == &"perks/opportunist_stopped": text += "Оппортунист остановит движение до выхода на следующую клетку; заряд реакции будет потрачен.\n"
	for id: int in _move_forecast.units:
		var row: Dictionary = _move_forecast.units[id]
		var before: Dictionary = row["before"]
		var after: Dictionary = row["after"]
		if id != _move_forecast.actor_id and before == after: continue
		text += "%s: %s → %s\n" % [_name_for(id), _cell_name(before["cell"]), _cell_name(after["cell"])]
		text += "HP %.1f → %.1f%s\n" % [before["hp"], after["hp"], " · ГИБЕЛЬ" if not after["alive"] else ""]
		if id == _move_forecast.actor_id:
			text += "Движение %.1f → %.1f · расход %.1f ОД\n" % [before["move"], after["move"], float(before["move"]) - float(after["move"])]
			text += "Основные %d → %d · бонусные %d → %d\n" % [before["main"], after["main"], before["bonus"], after["bonus"]]
		if before.has("armor_current") and before["armor_current"] != after["armor_current"]:
			text += "Броня %d → %d / %d\n" % [before["armor_current"], after["armor_current"], after["armor_max"]]
		if before["guard_stance"] and not after["guard_stance"]: text += "Стойка будет снята.\n"
	text += "\n[color=#a5b3c5]Последствия:[/color]\n"
	for event: Dictionary in _move_forecast.events:
		text += "• " + _event_text(event) + "\n"
	_forecast_panel.text = text

func _action_bar_hovered(action_id: StringName) -> void:
	if is_execution_pending(): return
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	_update_area_preview()
	if previous == &"healing_item" and action_id != &"healing_item": _resolve_item_hover_exit.call_deferred()
	if previous == &"guard" and action_id != &"guard": _resolve_guard_hover_exit.call_deferred()
	if previous in [&"opportunity_guard", &"counterattack_guard"] and action_id != previous: _resolve_guard_hover_exit.call_deferred()
	if previous == &"restore_armor" and action_id != &"restore_armor": _resolve_armor_hover_exit.call_deferred()
	if action_id == &"opportunity_guard":
		if not session is BattleCoreReactionsSession or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision and _guard_forecast_mode == CombatPerksState.Mode.OPPORTUNIST: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_guard_forecast_mode = CombatPerksState.Mode.OPPORTUNIST
		_guard_forecast_target = 0
		_request_action_forecast(&"opportunity")
		return
	if action_id == &"counterattack_guard":
		if not session is BattleCoreReactionsSession or not _battle.can_player_act(): return
		var counter_revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == counter_revision and _guard_forecast_mode == CombatPerksState.Mode.COUNTERATTACK: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = counter_revision
		_guard_forecast_mode = CombatPerksState.Mode.COUNTERATTACK
		_guard_forecast_target = 0
		_request_action_forecast(&"counterattack")
		return
	if action_id == &"restore_armor":
		if not session is BattleArmorSession or not _battle.can_player_act(): return
		var current_revision := session.context.get_revision()
		if (_armor_forecast != null or _action_forecast_pending) and _armor_forecast_actor == session.selected_id and _armor_forecast_revision == current_revision: return
		_clear_forecast()
		_armor_forecast_actor = session.selected_id
		_armor_forecast_revision = current_revision
		_forecast_panel.get_v_scroll_bar().value = 0.0
		_request_action_forecast(&"armor")
		return
	if action_id == &"guard":
		if _battle == null or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision and _guard_forecast_mode == CombatPerksState.Mode.NONE: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_forecast_panel.get_v_scroll_bar().value = 0.0
		_request_action_forecast(&"guard")
		_refresh_inspection()
		return
	if action_id != &"healing_item" or _battle == null: return
	var revision := session.context.get_revision()
	if _item_forecast_kind == &"healing" and _item_forecast_revision == revision: return
	_clear_forecast()
	_item_forecast_kind = &"healing"
	_item_forecast_revision = revision
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_request_action_forecast(&"healing")

func _action_bar_hover_left(action_id: StringName) -> void:
	if is_execution_pending(): return
	if _hovered_bar_action == action_id: _hovered_bar_action = &""
	_update_area_preview()
	if action_id == &"restore_armor": _resolve_armor_hover_exit.call_deferred()
	if action_id in [&"guard", &"opportunity_guard", &"counterattack_guard"]: _resolve_guard_hover_exit.call_deferred()
	if action_id != &"healing_item" or _item_forecast_kind != &"healing": return
	_resolve_item_hover_exit.call_deferred()

func _update_area_preview() -> void:
	if board_view == null or is_execution_pending(): return
	board_view.area_preview_owner = UnitId.NONE
	if not session is BattleCoreReactionsSession: return
	var show_area := attack_mode
	for button: Button in _action_bar._buttons:
		if button.get_meta("action_id", &"") == _hovered_bar_action and not button.disabled and _hovered_bar_action in [&"attack", &"opportunity_guard", &"counterattack_guard", &"stunning_strike", &"entangling_strike", &"blood_rune"]: show_area = true
	if show_area: board_view.area_preview_owner = session.selected_id
	if board_view._overlay != null: board_view._overlay.queue_redraw()

func _update_action_bar_hover() -> void:
	if is_execution_pending(): return
	if _action_bar == null or not _action_bar.visible: return
	var action_id: StringName = &""
	if _action_bar.get_global_rect().has_point(_pointer_position):
		for button in _action_bar._buttons:
			if button.visible and button.get_global_rect().has_point(_pointer_position):
				action_id = StringName(button.get_meta("action_id", &""))
				break
	if action_id == _hovered_bar_action:
		if (action_id in [&"guard", &"opportunity_guard", &"counterattack_guard"] and (_guard_forecast != null or _action_forecast_pending)) or (action_id == &"restore_armor" and (_armor_forecast != null or _action_forecast_pending)) or (action_id == &"healing_item" and (_item_forecast != null or _action_forecast_pending)): _action_bar_hovered(action_id)
		return
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	_update_area_preview()
	if previous in [&"healing_item", &"guard", &"opportunity_guard", &"counterattack_guard", &"restore_armor"]: _action_bar_hover_left(previous)
	if action_id in [&"healing_item", &"guard", &"opportunity_guard", &"counterattack_guard", &"restore_armor"]: _action_bar_hovered(action_id)

func _resolve_guard_hover_exit() -> void:
	if is_execution_pending(): return
	if session == null or (_guard_forecast == null and not (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack"])): return
	if _hovered_bar_action in [&"guard", &"opportunity_guard", &"counterattack_guard"] or _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _render_guard_forecast_panel() -> void:
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Охранная стойка · %s[/color][/font_size]\n" % _name_for(_guard_forecast_actor)
	if _guard_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_guard_forecast.reason)
		return
	var row: Dictionary = _guard_forecast.units[_guard_forecast.actor_id]
	var before: Dictionary = row["before"]
	var after: Dictionary = row["after"]
	text += "Основные: %d → %d (расход %d)\nБонусные: %d → %d\nДвижение: %.1f → %.1f\n" % [before["main"], after["main"], int(before["main"]) - int(after["main"]), before["bonus"], after["bonus"], before["move"], after["move"]]
	text += "Стойка: %s → %s\n" % ["включена" if before["guard_stance"] else "выключена", "включена" if after["guard_stance"] else "выключена"]
	text += "До следующего хода команды; добровольные движение и атака снимают стойку.\nКлик или клавиша 2 — занять стойку."
	_forecast_panel.text = text

func _render_reaction_guard_forecast() -> void:
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · РЕАКЦИЯ"
	_log.visible = false
	_log_heading.visible = false
	var mode_name := "Оппортунист" if _guard_forecast_mode == CombatPerksState.Mode.OPPORTUNIST else ("Контратака" if _guard_forecast_mode == CombatPerksState.Mode.COUNTERATTACK else "Прикрытие")
	var text := "[font_size=16][color=#f7c97d]%s · %s[/color][/font_size]\n" % [mode_name, _name_for(_guard_forecast_actor)]
	if _guard_forecast_mode == CombatPerksState.Mode.COVER: text += "Союзник: %s\n" % _name_for(_guard_forecast_target)
	if _guard_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_guard_forecast.reason)
		return
	var row: Dictionary = _guard_forecast.units.get(_guard_forecast_actor, {})
	var before: Dictionary = row.get("before", {})
	var after: Dictionary = row.get("after", {})
	text += "Основные: %d → %d (расход 1)\n" % [before.get("main", 0), after.get("main", 0)]
	var perks: Dictionary = after.get("combat_perks", {})
	text += "Общий заряд реакции: %d → %d\n" % [before.get("combat_perks", {}).get("reaction_left", 0), perks.get("reaction_left", 0)]
	text += "Клик — занять стойку за 1 основное действие. Реакция сработает при подходящем событии, если останется общий заряд."
	_forecast_panel.text = text

func _resolve_item_hover_exit() -> void:
	if is_execution_pending(): return
	if (_item_forecast == null and not _action_forecast_pending) or _item_forecast_kind != &"healing": return
	if _hovered_bar_action == &"healing_item": return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_forecast_panel.visible = attack_mode
	_forecast_heading.visible = attack_mode

func _render_item_forecast_panel() -> void:
	if is_execution_pending(): return
	if _forecast_panel == null or _item_forecast == null: return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]"
	if _item_forecast_kind == &"healing": text += "Прогноз лечения"
	else: text += "Прогноз призыва · %s" % _cell_name(_item_forecast_cell)
	text += "[/color][/font_size]\n"
	var item_action: ItemUseAction = _item_action_for_forecast()
	if _item_forecast.status != &"APPLIED":
		text += "Цена: %s.\n[color=#f29b9b]Прогноз недоступен[/color]\n" % _item_cost_text(item_action) + _reason_text(_item_forecast.reason)
		_forecast_panel.text = text
		return
	var item_actor_id: int = -1
	for item_id_variant in _item_forecast.items:
		var owner_row: Dictionary = _item_forecast.items[item_id_variant]
		item_actor_id = int(owner_row.get("actor_id", -1))
	for id_variant in _item_forecast.units:
		var id := int(id_variant)
		var entry: Dictionary = _item_forecast.units[id]
		var before_value: Variant = entry.get("before")
		var after: Dictionary = entry.get("after", {})
		if _item_forecast_kind == &"healing" and id != item_actor_id: continue
		if _item_forecast_kind == &"summon" and before_value != null: continue
		var label := String(after.get("name", "Участник %d" % id))
		if before_value == null:
			# Призванный помощник не имеет состояния до появления и не считается погибшим.
			var after_cell: Vector2i = after.get("cell", Vector2i.ZERO)
			text += "%s · ID %d · помощник\nКлетка: %s · владелец: %d\nСтатус: %s\nHP: %.1f / %.1f\nДействия: %d основных, %d бонусных, %.1f движения\n" % [label, int(after.get("id", id)), _cell_name(after_cell), int(after.get("owner_unit_id", 0)), "ожидает следующего хода" if bool(after.get("pending", false)) else "готов", float(after.get("hp", 0.0)), float(after.get("hp_max", 0.0)), int(after.get("main", 0)), int(after.get("bonus", 0)), float(after.get("move", 0.0))]
		else:
			var before: Dictionary = before_value
			text += "%s: HP %.1f → %.1f / %.1f\n" % [label, float(before.get("hp", 0.0)), float(after.get("hp", 0.0)), float(after.get("hp_max", 0.0))]
			text += "Действия: основные %d → %d\n" % [int(before.get("main", 0)), int(after.get("main", 0))]
	for item_id_variant in _item_forecast.items:
		var item_row: Dictionary = _item_forecast.items[item_id_variant]
		var item_before: Dictionary = item_row.get("before", {})
		var item_after: Dictionary = item_row.get("after", {})
		text += "Заряды: %d → %d\n" % [int(item_before.get("charges", 0)), int(item_after.get("charges", 0))]
	text += "Цена: %s.\n" % _item_cost_text(item_action)
	if _item_forecast_kind == &"summon": text += "Помощник не действует до следующего хода своей команды."
	_forecast_panel.text = text

func _render_raise_forecast_panel() -> void:
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Поднятие тела · %s[/color][/font_size]\n" % _cell_name(_raise_forecast_cell)
	if _raise_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_raise_forecast.reason)
		return
	for id: int in _raise_forecast.corpses:
		var row: Dictionary = _raise_forecast.corpses[id]
		if row["after"] == null:
			var corpse: Dictionary = row["before"]
			text += "Тело #%d на %s будет использовано.\n" % [id, _cell_name(corpse["cell"])]
	for id: int in _raise_forecast.units:
		var row: Dictionary = _raise_forecast.units[id]
		var after: Dictionary = row["after"]
		if row["before"] == null:
			# Новый ID отличает помощника от погибшего, чьё тело расходуется.
			text += "%s · ID %d · помощник\nКлетка: %s · владелец: %d\nHP: %.1f / %.1f\nДействия: %d основных, %d бонусных, %.1f движения\nСтатус: %s\n" % [after["name"], id, _cell_name(after["cell"]), after["owner_unit_id"], after["hp"], after["hp_max"], after["main"], after["bonus"], after["move"], "ожидает следующего хода" if after["pending"] else "готов"]
		elif id == _raise_forecast.actor_id:
			var before: Dictionary = row["before"]
			text += "%s: основные %d → %d (расход %d)\nБонус: %d → %d · Движение: %.1f → %.1f\n" % [after["name"], before["main"], after["main"], before["main"] - after["main"], before["bonus"], after["bonus"], before["move"], after["move"]]
	_forecast_panel.text = text

func _item_action_for_forecast() -> ItemUseAction:
	if _battle == null: return null
	var item := _battle.healing_item() if _item_forecast_kind == &"healing" else _battle.summoning_item()
	return item.get_use_action() if item != null else null

func _show_receipt(receipt: ActionReceipt, target_attempt: bool = false) -> void:
	if is_execution_pending(): return
	# Завершённое применение и отказ по выбранной цели возвращают движение.
	# UI не зависит от того, основное или дополнительное действие оплатила команда.
	if target_attempt or receipt.status != ActionReceipt.REJECTED:
		_clear_action_mode()
	_clear_forecast()
	if not _receipt_already_presented:
		for event in receipt.get_events(): _note(_event_text(event))
	for step: Dictionary in receipt.get_steps():
		if step["status"] == &"SKIPPED" and step["kind"] in [&"stun_apply", &"entangle_apply"]:
			_note(("Оглушение" if step["kind"] == &"stun_apply" else "Путы") + ": наложение пропущено — " + _control_skip_text(step["reason"]) + ".")
	_refresh()
	# Смерть уже исполнена ядром; временная фигура лишь показывает падение в провал.
	for event in receipt.get_events():
		if _receipt_already_presented: break
		if event.get("kind", &"") != &"died": continue
		var source: Dictionary = event.get("source", {})
		if source.get("kind", &"") != &"fall": continue
		var unit := session.board.get_unit_by_id(int(event.get("target_unit_id", 0)))
		if unit == null: continue
		var destination: Vector2i = source.get("origin_cell", unit.cell)
		if session.board.is_in_bounds(destination) and session.board.get_terrain(destination) != TerrainType.Type.VOID: continue
		var origin := unit.cell
		for movement in receipt.get_events():
			if movement.get("kind", &"") == &"moved" and int(movement.get("target_unit_id", 0)) == unit.id:
				origin = movement["from_cell"]
		board_view.animate_fall(unit, origin, destination)
	if receipt.status != ActionReceipt.APPLIED:
		var message := "Действие отклонено" if receipt.status == ActionReceipt.REJECTED else "Исполнение остановлено"
		message += ": "
		if target_attempt and receipt.status == ActionReceipt.REJECTED: message += "недопустимая цель. "
		message += _reason_text(receipt.reason)
		_note(message)
		_log.text = "\n".join(_journal)
		_status.text = message

func _note(message: String) -> void:
	_journal.append(message)
	while _journal.size() > 80: _journal.pop_front()

func _event_text(event: Dictionary) -> String:
	var actor := _name_for(int(event.get("actor_unit_id", 0)))
	var target := _name_for(int(event.get("target_unit_id", 0)))
	match StringName(event.get("kind", &"")):
		&"bleeding_changed":
			var ticks: int = event["after"]["ticks_left"]
			if event["reason"] == &"burned": return "%s: кровотечение снято горением." % target
			if event["reason"] == &"tick" and event["after"].has("stacks"): return "%s: тик кровотечения; %s." % [target, "срок истёк" if ticks == 0 else _bleeding_summary(event["after"])]
			if event["reason"] == &"tick": return "%s: тик кровотечения; %s." % [target, "срок истёк" if ticks == 0 else "осталось тиков: %d" % ticks]
			if not event["after"].has("stacks"): return "%s: кровотечение %s — тиков: %d." % [target, "наложено" if event["reason"] == &"applied" else "продлено", ticks]
			return "%s: кровотечение %s — %s." % [target, "наложено" if event["reason"] == &"applied" else "продлено", _bleeding_summary(event["after"])]
		&"elemental_changed":
			var after: Dictionary = event.get("after", {})
			var reason: StringName = event.get("reason", &"")
			var label := "Тик горения" if reason == &"burn_tick" else ("Истечение статусов" if reason == &"turn_end" else _elemental_effect_label(reason))
			return "%s: %s — %s." % [target, label, _elemental_summary(after)]
		&"mage_cast":
			return "Маг: %s → %s; мана %d → %d; откат %d." % [_elemental_effect_label(StringName(event.spell_id)), target, event.mana_before, event.mana_after, event.cooldown_after]
		&"elemental_cast":
			return "%s применяет «%s» к %s; основные действия %d → %d." % [actor, _elemental_effect_label(event.get("effect", &"")), target, int(event.get("main_before", 0)), int(event.get("main_after", 0))]
		&"attacked":
			var suffix := ""
			var modifiers: Dictionary = event.get("modifiers", {})
			if int(modifiers.get("sneak_percent", 0)) == 50: suffix += " Скрытая атака +50%% физической базы (угроза: %s)." % ", ".join(_names_for_ids(modifiers.get("threat_ids", [])))
			if int(modifiers.get("backstab_percent", 0)) > 0 and not session is BattleCoreReactionsSession: suffix += " Удар в спину +%d%%." % modifiers["backstab_percent"]
			if modifiers.get("critical", false): suffix += " Крит ×2."
			return "%s атакует %s.%s" % [actor, target, suffix]
		&"reaction_used":
			var used_mode: int = int(event.get("mode", 0))
			var mode_name := "Оппортунист" if used_mode == CombatPerksState.Mode.OPPORTUNIST else ("Контратака" if used_mode == CombatPerksState.Mode.COUNTERATTACK else "Прикрытие")
			return "%s: режим «%s» срабатывает на %s; общий заряд реакции %d → %d." % [actor, mode_name, target, int(event.get("charge_before", 1)), int(event.get("charge_after", 0))]
		&"opportunity_attacked": return "%s прерывает движение %s атакой Оппортуниста без основного действия; общий заряд реакции потрачен." % [actor, target]
		&"counterattacked": return "%s контратакует %s без толчка; расходуется общий заряд реакции." % [actor, target]
		&"control_changed":
			if event["reason"] == &"entangled": return "%s: наложены путы до конца ближайшего хода команды цели." % target
			if event["reason"] == &"refreshed": return "%s: путы сохранены; срок не накапливается." % target
			if event["reason"] == &"stunned": return "%s: оглушён до конца ближайшего хода команды цели." % target
			if event["reason"] == &"stun_refreshed": return "%s: оглушение сохранено; срок не накапливается." % target
			return "%s: путы сняты толчком." % target if event["reason"] == &"push" else "%s: срок состояния контроля истёк." % target
		&"guarded":
			if event.has("reaction_mode") and int(event["reaction_mode"]) in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]:
				var reaction_mode: int = int(event["reaction_mode"])
				var mode_name := "Оппортунист" if reaction_mode == CombatPerksState.Mode.OPPORTUNIST else ("Контратака" if reaction_mode == CombatPerksState.Mode.COUNTERATTACK else "Прикрытие → " + _name_for(int(event.get("cover_target_id", 0))))
				return "%s включает режим «%s» за 1 основное действие; заряд реакции не пополняется." % [actor, mode_name]
			return "%s занимает охранную стойку (1 основное действие)." % actor
		&"item_used":
			var owner := session.state.get_owner(int(event["actor_unit_id"]))
			var item: ItemInstance = owner._items.get(int(event["item_instance_id"])) if owner != null else null
			var action := item.get_use_action() if item != null else null
			var name := "печать" if action != null and action.get_kind() == ItemUseAction.Kind.SUMMON_ADJACENT else "флакон"
			return "%s использует %s (%d основное; зарядов осталось: %d)." % [actor, name, int(event["main_cost"]), int(event["charges_after"])]
		&"summoned": return "%s призывает: %s. Действия со следующего хода команды." % [actor, target]
		&"corpse_created": return "Тело: %s, гуманоид." % _cell_name(event["corpse"]["cell"])
		&"support_collapsed": return "Обвал: %s стала пропастью." % _cell_name(event["cell"])
		&"environment_turn": return "Окружение %d: %s" % [event["turn"], "новых угроз нет." if event["marked"].is_empty() else ("%s обрушится в следующую фазу окружения." % _cell_name(event["marked"][0]))]
		&"corpse_raised": return "%s поднял тело: %s (16 HP), ожидает следующего хода." % [actor, target]
		&"damaged":
			var source: Dictionary = event.get("source", {})
			var cause := " от падения" if source.get("kind", &"") == &"fall" else (" от эффекта" if bleeding_mode and source.get("kind", &"") == &"status" else (" от шипов (8)" if source.get("kind", &"") == &"cell" else ""))
			return "%s: −%.1f HP%s." % [target, float(event.get("amount", 0)), cause]
		&"healed":
			var heal_source: StringName = event.get("source", {}).get("kind", &"")
			var heal_cause := " от сопротивления урону шипов" if heal_source == &"cell" else (" от сопротивления" if heal_source in [&"attack", &"collision", &"fall"] or (bleeding_mode and heal_source == &"status") else " от мага" if heal_source == &"mage" else " от предмета")
			return "%s: +%.1f HP%s." % [target, float(event.get("amount", 0)), heal_cause]
		&"armor_changed": return "%s: запас брони изменился." % target
		&"hit_resolved": return "%s: попадание завершено, HP %d → %d%s." % [target, event["hit"]["hp_before"], event["hit"]["hp_after"], " · добивание замороженной цели" if event["hit"].get("shattered", false) else ""]
		&"balance_changed": return "%s: равновесие %.1f / %.1f." % [target, float(event.get("balance_after", 0)), float(event.get("balance_max", 0))]
		&"balance_broken": return "%s теряет равновесие → толчок." % target
		&"moved":
			var pushed: bool = event.get("movement_kind", &"") == &"push"
			if event.get("movement_kind", &"") == &"safe_retreat": return "%s отходит: %s → %s · %d основное, %.1f движения." % [actor, _cell_name(event["from_cell"]), _cell_name(event["to_cell"]), int(event.get("main_cost", 0)), float(event["move_cost"])]
			return "%s %s %s → %s." % [target if pushed else actor, "отброшен:" if pushed else "идёт:", _cell_name(event["from_cell"]), _cell_name(event["to_cell"])]
		&"push_blocked": return "%s врезается в препятствие." % target
		&"chain_link": return "Цепь: %s → %s, сила %s — %s." % [_name_for(int(event.get("from_unit_id", 0))), target, str(event.get("impulse", 0.0)), "равновесие потеряно" if event.get("broke", false) else "цепь остановлена"]
		&"collision": return "%s сталкивается с %s." % [target, _name_for(int(event.get("blocker_unit_id", 0)))]
		&"fell": return "%s падает с уступа." % target
		&"died": return "%s погиб. Клетка свободна." % target
	return "%s: %s" % [target, String(event.get("kind", "событие"))]

func _name_for(id: int) -> String:
	var unit := session.board.get_unit_by_id(id)
	return unit.debug_name if unit != null else "Окружение"

func _names_for_ids(ids: Array) -> PackedStringArray:
	var names: PackedStringArray = []
	for id: Variant in ids:
		if typeof(id) == TYPE_INT: names.append(_name_for(id))
	return names

func _cell_name(cell: Vector2i) -> String:
	return String.chr(65 + cell.x) + str(cell.y + 1)

func _reason_text(reason: StringName) -> String:
	match reason:
		&"mage/cooldown": return "Заклинание восстанавливается до конца следующих своих ходов."
		&"mage/insufficient_mana": return "Недостаточно маны мага."
		&"mage/full_hp": return "Для лечения нужен раненый живой союзник."
		&"mage/invalid_target": return "Огонь — по живому противнику; лечение — по живому союзнику."
		&"mage/window_closed", &"mage/terminal": return "Маг действует между завершёнными действиями вашего хода."
	match reason:
		&"perks/stunning_strike_required": return "этот персонаж не владеет Оглушающим ударом."
		&"perks/not_owned": return "этот персонаж не владеет выбранным режимом реакции."
		&"guard/already_active": return "эта охранная стойка уже активна."
		&"guard/insufficient_main": return "не хватает основного действия, чтобы включить режим реакции."
		&"control/stun_immune": return "цель невосприимчива к оглушению; урон и толчок сохраняются."
		&"control/entangle_immune": return "цель невосприимчива к путам; урон и толчок сохраняются."
		&"control/stunned": return "персонаж оглушён и не может выполнять добровольные действия."
		&"control/frozen": return "персонаж заморожен и не может выполнять добровольные действия."
		&"status/insufficient_main": return "для этого действия нужно 1 основное действие."
		&"status/dead_target": return "живой цели больше нет на поле."
		&"status/not_admitted": return "сейчас этот персонаж не может действовать."
		&"status/stale_revision": return "состояние боя изменилось; наведите курсор заново."
		&"status/capability_required": return "эти эффекты доступны в основном бою."
		&"control/entangled": return "персонаж опутан и не может двигаться; остальные действия доступны."
		&"control/capability_required": return "эта цель не поддерживает состояния контроля."
		&"armor/summon_unsupported": return "призыв недоступен в сценарии брони."
		&"armor/zero_restore": return "нечего восстанавливать."
		&"armor/full": return "обычная броня уже восстановлена."
		&"attack/insufficient_main": return "основные действия закончились; выберите другого персонажа или завершите ход." if tactical_mode else "основные действия закончились; выберите другого персонажа или сбросьте бой."
		&"battle/input_locked": return "сейчас нельзя действовать."
		&"battle/friendly_target": return "выберите противника."
		&"move/insufficient_move": return "не хватает очков движения."
		&"move/insufficient_main": return "для безопасного отхода нужно 1 основное действие."
		&"move/actor_dead": return "персонаж погибнет на пути."
		&"move/actor_displaced": return "персонаж будет смещён с маршрута."
		&"move/path_blocked": return "продолжение пути будет перекрыто."
		&"move/budget_exhausted": return "очки движения закончатся на пути."
		&"attack/out_of_reach", &"attack/not_aligned": return "цель вне досягаемости прямого удара."
		&"move/unreachable": return "нет проходимого маршрута к этой клетке."
		&"move/no_selected_unit", &"attack/no_selected_unit": return "выберите живого персонажа."
		&"attack/self_target": return "нельзя атаковать самого себя."
		&"attack/line_blocked": return "линию атаки перекрывает стена или противник."
		&"attack/terrain_shape_unsupported": return "рельеф не допускает прямой удар."
		&"attack/stale_revision": return "состояние боя изменилось; наведите курсор заново."
		&"attack/missing_target", &"attack/invalid_target", &"attack/dead_target": return "живой цели больше нет на поле."
		&"BUSY": return "дождитесь завершения действия."
		&"CONTEXT_FAULTED": return "бой остановлен; выполните сброс."
		&"guard/already_active": return "охранная стойка уже активна."
		&"summon/active_helper": return "у этого владельца уже есть живой помощник."
		&"summon/invalid_cell": return "нужна соседняя свободная безопасная клетка той же высоты."
		&"environment/no_corpse": return "нет доступного гуманоида на соседней свободной клетке."
		&"environment/invalid_raise_cell": return "тело нельзя поднять на клетке с шипами, занятой или другой высоты."
		&"summon/helper_cannot_summon": return "помощник не может поднимать другие тела."
		&"item/full_hp": return "здоровье уже полное."
		&"item/no_charges": return "заряды предмета закончились."
		&"item/insufficient_main": return "недостаточно основных действий."
		&"item/not_owned": return "нет доступного предмета."
		&"item/inactive": return "предмет не активен."
		&"item/not_usable": return "этот предмет нельзя использовать."
		&"item/no_selected_unit": return "выберите живого персонажа."
		&"item/not_admitted": return "персонаж не может использовать предмет."
		&"item/stale_revision": return "состояние боя изменилось; повторите попытку."
		&"item/invalid_runtime", &"item/invalid_mutation": return "состояние боя повреждено; начните заново."
		&"guard/insufficient_main": return "недостаточно основных действий."
		&"guard/no_selected_unit": return "выберите живого персонажа."
		&"guard/not_admitted": return "персонаж не может занять стойку."
		&"guard/stale_revision": return "состояние боя изменилось; повторите попытку."
		&"guard/invalid_runtime": return "состояние персонажа повреждено; сбросьте бой."
		&"perks/not_owned": return "этот персонаж не владеет преимуществом."
		&"perks/invalid_cover_target": return "выберите допустимого соседнего союзника."
		&"perks/movement_stopped": return "движение уже остановлено Оппортунистом до пополнения команды."
		&"perks/opportunist_stopped": return "Оппортунист прервёт выход из зоны угрозы."
		&"perks/invalid_mode": return "режим реакции недоступен."
		&"preview/rng_not_cloneable", &"preview/rng_state_mismatch", &"preview/unsupported_worker_rng", &"preview/unsupported_rng": return "случайный эффект пока не поддерживает точный прогноз."
		&"turn/unsupported_session", &"turn/unsupported_runtime": return "этот вариант боя пока не поддерживает точный прогноз перехода."
		&"turn/unsupported_phase", &"turn/not_transitioned": return "завершение хода сейчас недоступно."
		&"turn/faulted": return "переход хода не завершится; точный итог недоступен."
		&"preview/worker_unavailable": return "расчёт временно недоступен; наведите курсор ещё раз."
		&"command_limit", &"event_limit", &"depth_limit", &"sequence_exhausted": return "цепь последствий не завершилась; точный итог недоступен."
	return "Эта комбинация пока не поддерживается: " + String(reason)

func _unhandled_input(event: InputEvent) -> void:
	if is_execution_pending():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R: reset_demo()
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE: skip_presentation()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				if tactical_mode and _action_bar != null:
					var slot := int(event.keycode - KEY_0)
					if slot > _action_bar._buttons.size(): return
					if slot == 1: set_attack_mode(true)
					elif slot == 2: _use_guard()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"summoning_item": _choose_summoning()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"healing_item": _use_healing_item()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"raise_corpse": _choose_raise()
					else: _action_bar.activate_slot(slot)
			KEY_A: set_attack_mode(true)
			KEY_M, KEY_ESCAPE: set_attack_mode(false)
			KEY_R: reset_demo()
			KEY_ENTER, KEY_KP_ENTER: end_turn()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (board_view == null or not board_view.camera_controls_enabled):
		set_attack_mode(false)

func _item_cost_text(action: ItemUseAction) -> String:
	return "%d основное и %d заряд" % [action.get_main_cost(), action.get_charge_cost()] if action != null else "применение недоступно"

func _item_action_descriptor(item: ItemInstance, action_id: StringName, reason: StringName) -> Dictionary:
	if item == null: return {"label": "—", "disabled": true}
	var action := item.get_use_action()
	if action == null: return {"action_id": action_id, "label": item.get_definition().display_name, "disabled": true, "tooltip": _reason_text(&"item/not_usable")}
	var detail := ""
	var ready := ""
	match action.get_target_mode():
		ItemUseAction.TargetMode.SELF:
			detail = "Лечение себя до +%s HP; %s.\n" % [String.num(action.get_heal_amount()).trim_suffix(".0"), _item_cost_text(action)]
			ready = "Стойка сохраняется."
		ItemUseAction.TargetMode.ADJACENT_CELL:
			detail = "Помощник: %s HP, действует со следующего хода команды. Один на владельца, до гибели или конца боя. %s.\n" % [_summon_hp_text(item), _item_cost_text(action)]
			ready = "Выберите соседнюю свободную безопасную клетку той же высоты."
	return {"action_id": action_id, "label": "%s %d/%d" % [item.get_definition().display_name, item.get_charges_left(), action.get_max_charges()], "cost": "%d основное" % action.get_main_cost(), "disabled": reason != &"", "tooltip": detail + (_reason_text(reason) if reason != &"" else ready)}

func _summon_hp_text(item: ItemInstance) -> String:
	# Подсказка читает тот же зафиксированный шаблон, что и команда призыва.
	var action := item.get_use_action() if item != null else null
	var definition := action.get_summon_definition() if action != null else null
	var hp := definition.hp_max if definition != null else SummonDefinition.DEFAULT_HP_MAX
	return String.num(hp).trim_suffix(".0")

func _choose_summoning() -> void:
	if is_execution_pending(): return
	if _battle == null: return
	var reason := _battle.summoning_hint_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	summoning_mode = true
	_refresh()

func _choose_raise() -> void:
	if is_execution_pending(): return
	if not environment_mode or not session is BattleEnvironmentSession: return
	var environment := session as BattleEnvironmentSession
	var reason := environment.raise_hint_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	raising_mode = true
	_refresh()

func _choose_retreat() -> void:
	if is_execution_pending() or not session is BattleCoreReactionsSession: return
	var reason := (session as BattleCoreReactionsSession).retreat_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	retreat_mode = true
	_refresh()

func _resolve_armor_hover_exit() -> void:
	if is_execution_pending(): return
	if (_armor_forecast == null and not (_action_forecast_pending and _action_forecast_kind == &"armor")) or _hovered_bar_action == &"restore_armor" or _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _render_armor_forecast_panel() -> void:
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Восстановление брони · %s[/color][/font_size]\n" % _name_for(_armor_forecast_actor)
	if _armor_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "Прогноз недоступен: " + _reason_text(_armor_forecast.reason)
		return
	var before: Dictionary = _armor_forecast.units_before[_armor_forecast_actor]
	var after: Dictionary = _armor_forecast.units_after[_armor_forecast_actor]
	text += "Броня: %d → %d\nОсновные: %d → %d (расход 1)\n" % [before["armor_current"], after["armor_current"], before["main"], after["main"]]
	for event: Dictionary in _armor_forecast.events:
		if event["kind"] != &"armor_changed": continue
		for item: Dictionary in event["items"]: text += "Вещь #%d: %d → %d\n" % [item["id"], item["before"], item["after"]]
		for grant: Dictionary in event["grants"]: text += "Временная броня: +%d до конца боя\n" % [int(grant["after"]) - int(grant["before"])]
	text += "Стойка сохраняется. Клик или клавиша 4 — восстановить броню."
	_forecast_panel.text = text

func _render_elemental_forecast_panel() -> void:
	if is_execution_pending() or _elemental_forecast == null: return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · ЭЛЕМЕНТАЛЬНЫЙ ЭФФЕКТ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]%s → %s · дальность 3[/color][/font_size]\n" % [_elemental_effect_label(_action_forecast_effect), _name_for(_action_forecast_target_id)]
	if _elemental_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "Прогноз недоступен: " + _reason_text(_elemental_forecast.reason)
		return
	if AbilityDefinition.mage_source_id(_action_forecast_effect) > 0:
		text = "[font_size=16]%s → %s · вся доска[/font_size]\n" % [_elemental_effect_label(_action_forecast_effect), _name_for(_action_forecast_target_id)]
		var before_abilities := BattleAbilityState.from_dict(_elemental_forecast.snapshot_before.get("abilities", {}))
		var after_abilities := BattleAbilityState.from_dict(_elemental_forecast.snapshot_after.get("abilities", {}))
		var spell_definition: AbilityDefinition = before_abilities.definition(_action_forecast_effect) if before_abilities != null else null
		if before_abilities == null or after_abilities == null or spell_definition == null:
			_forecast_panel.text = text + "Прогноз недоступен: данные отката повреждены."
			return
		text += "Мана %d → %d · откат: длительность %d ходов, после действия осталось %d\n" % [before_abilities.mana, after_abilities.mana, spell_definition.cooldown_turns, after_abilities.remaining(_action_forecast_effect)]
	var actor_before: Dictionary = _elemental_forecast.units_before.get(_action_forecast_actor, {})
	var actor_after: Dictionary = _elemental_forecast.units_after.get(_action_forecast_actor, {})
	if not actor_before.is_empty() and not actor_after.is_empty():
		text += "Основные действия: %d → %d\n" % [actor_before.get("main", 0), actor_after.get("main", 0)]
	var before: Dictionary = _elemental_forecast.units_before.get(_action_forecast_target_id, {})
	var after: Dictionary = _elemental_forecast.units_after.get(_action_forecast_target_id, {})
	if not before.is_empty() and not after.is_empty():
		text += "%s: HP %.1f → %.1f\n" % [_name_for(_action_forecast_target_id), before.get("hp", 0.0), after.get("hp", 0.0)]
		text += "Элементальные статусы: %s → %s\n" % [_elemental_summary(before.get("elemental", {})), _elemental_summary(after.get("elemental", {}))]
		text += "Кровотечение: %s → %s\n" % [_bleeding_summary(before.get("bleeding", {})), _bleeding_summary(after.get("bleeding", {}))]
	if _elemental_forecast.events.is_empty():
		text += "Событий последствий нет.\n"
	else:
		text += "\n[color=#a5b3c5]Последствия:[/color]\n"
		for event: Dictionary in _elemental_forecast.events: text += "• " + _event_text(event) + "\n"
	_forecast_panel.text = text

func _elemental_effect_label(effect: StringName) -> String:
	match effect:
		&"mage.test_burning": return "Поджог"
		&"mage.test_wet": return "Вода"
		&"mage.test_freeze": return "Заморозка"
		&"mage.test_stun": return "Оглушение"
		&"mage.test_roots": return "Корни"
		&"mage.test_bleeding": return "Кровотечение"
	if effect == &"mage.fire": return "Огненный импульс"
	if effect == &"mage.heal": return "Лечение мага"
	match effect:
		&"burning": return "Поджечь"
		&"wet": return "Облить"
		&"freeze": return "Заморозить"
	return "Элементальное действие"

func _elemental_summary(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY: return "нет"
	var data: Dictionary = value
	var parts: PackedStringArray = []
	if int(data.get("burning_stacks", 0)) > 0: parts.append("горение %d ст. / %d т." % [data["burning_stacks"], data["burning_ticks"]])
	if int(data.get("wet_turns", 0)) > 0: parts.append("мокрый %d х." % data["wet_turns"])
	if int(data.get("frozen_turns", 0)) > 0: parts.append("заморозка %d х." % data["frozen_turns"])
	if parts.is_empty(): return "нет"
	return ", ".join(parts)

func _bleeding_skip_text(reason: StringName) -> String:
	match reason:
		&"bleeding/immune": return "иммунитет"
		&"bleeding/dead_target": return "цель погибла"
		&"bleeding/burning": return "горение блокирует кровотечение"
	return "нет физического HP-урона"

func _bleeding_summary(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY: return "нет"
	var data: Dictionary = value
	var ticks: int = int(data.get("ticks_left", 0))
	if ticks <= 0: return "нет"
	if bool(data.get("stacked", false)) or data.has("stacks"):
		var stacks: int = int(data.get("stacks", 0))
		var movement_damage := str(stacks * BleedingState.MOVE_DAMAGE) if stacks <= 4611686018427387903 else "за пределом расчёта"
		return "%d ст. · %d т. · %d/тик · %s/клетку" % [stacks, ticks, stacks, movement_damage]
	return "%d т. · 4/тик" % ticks

func _can_forecast_turn() -> bool:
	return not is_execution_pending() and session != null and session.get_script() == BattleCoreReactionsSession and _battle != null and _battle.can_player_act() and not _is_deploying()

func _can_forecast_environment() -> bool:
	return _can_forecast_turn() and not session.state.environment.collapse.is_empty()

func _over_environment_button() -> bool:
	return _environment_button != null and _environment_button.is_visible_in_tree() and _environment_button.get_global_rect().has_point(_pointer_position)

func _update_environment_forecast_hover() -> void:
	if _over_environment_button() and _can_forecast_environment():
		if _environment_forecast == null and not _environment_forecast_pending: _request_environment_forecast()
	elif (_environment_forecast != null or _environment_forecast_pending) and not _forecast_reading_region().has_point(_pointer_position):
		_clear_forecast()

func _request_environment_forecast() -> void:
	if not _can_forecast_environment(): return
	_clear_forecast()
	_environment_forecast_pending = true
	_environment_forecast_session = session.get_instance_id()
	_environment_forecast_revision = session.context.get_revision()
	_environment_forecast_actor = session.selected_id
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_render_forecast_panel()

func _environment_request_current() -> bool:
	return _can_forecast_environment() and session.get_instance_id() == _environment_forecast_session and session.context.get_revision() == _environment_forecast_revision and session.selected_id == _environment_forecast_actor and (_over_environment_button() or _forecast_reading_region().has_point(_pointer_position))

func _process_environment_forecast() -> void:
	if is_execution_pending(): return
	var result := _environment_forecast_worker.take_finished()
	if (_environment_forecast_pending or _environment_forecast != null) and not _environment_request_current():
		_clear_forecast()
		return
	if result != null and _environment_forecast_pending and _environment_forecast_job == _environment_forecast_generation:
		_environment_forecast = result
		_environment_forecast_pending = false
		_render_forecast_panel()
	if not _environment_forecast_pending or _environment_forecast_worker.is_started(): return
	_environment_forecast_job = _environment_forecast_generation
	_environment_forecast_worker.start((session as BattleCoreReactionsSession).prepare_environment_forecast())

func _render_environment_forecast() -> void:
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · ОКРУЖЕНИЕ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Фаза окружения[/color][/font_size]\nЕсли она начнётся при нынешней расстановке. Будущие действия могут изменить результат.\n\n"
	if _environment_forecast_pending:
		_forecast_panel.text = text + "Рассчитываем последствия…"
		return
	if _environment_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "Прогноз недоступен: " + _reason_text(_environment_forecast.reason)
		return
	for event: Dictionary in _environment_forecast.events: text += _event_text(event) + "\n"
	for id: int in _environment_forecast.units_after:
		if _environment_forecast.units_before[id].alive and not _environment_forecast.units_after[id].alive:
			text += "[color=#f29b9b]%s: погибнет в пропасти.[/color]\n" % _name_for(id)
	_forecast_panel.text = text

func _over_end_turn_button() -> bool:
	return _end_turn_button != null and _end_turn_button.is_visible_in_tree() and _end_turn_button.get_global_rect().has_point(_pointer_position)

func _update_turn_forecast_hover() -> void:
	if _over_end_turn_button() and _can_forecast_turn():
		if _turn_forecast == null and not _turn_forecast_pending: _request_turn_forecast()
	elif (_turn_forecast != null or _turn_forecast_pending) and not _forecast_reading_region().has_point(_pointer_position):
		_clear_forecast()

func _request_turn_forecast() -> void:
	if not _can_forecast_turn(): return
	_clear_forecast()
	_turn_forecast_pending = true
	_turn_forecast_session_id = session.get_instance_id()
	_turn_forecast_actor = session.selected_id
	_turn_forecast_revision = session.context.get_revision()
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_render_forecast_panel()

func _turn_forecast_request_current() -> bool:
	if not _can_forecast_turn(): return false
	if session.get_instance_id() != _turn_forecast_session_id or session.selected_id != _turn_forecast_actor or session.context.get_revision() != _turn_forecast_revision: return false
	return _over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position)

func _process_turn_forecast() -> void:
	if is_execution_pending(): return
	var result := _turn_forecast_worker.take_finished()
	if (_turn_forecast_pending or _turn_forecast != null) and not _turn_forecast_request_current():
		_clear_forecast()
		return
	if result != null and _turn_forecast_pending and _turn_forecast_job_generation == _turn_forecast_generation:
		_turn_forecast = result
		_turn_forecast_pending = false
		_render_forecast_panel()
	if not _turn_forecast_pending or _turn_forecast_worker.is_started(): return
	# Подготовка отделяет runtime на кадре; обработчик мыши только записывает запрос.
	_turn_forecast_job_generation = _turn_forecast_generation
	_turn_forecast_worker.start(TurnForecast.prepare(session as BattleCoreReactionsSession))

func _render_turn_forecast() -> void:
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОНЕЦ ХОДА"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Завершение командного хода[/color][/font_size]\nДо первого действия противника.\n"
	if _turn_forecast_pending:
		_forecast_panel.text = text + "Рассчитываем последствия перехода…"
		return
	if _turn_forecast.status != ActionReceipt.APPLIED:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_turn_forecast.reason)
		return
	var phases := {BattleTacticalSession.Phase.ENEMY_TURN: "Начнётся ход противника.", BattleTacticalSession.Phase.VICTORY: "Победа до действий противника.", BattleTacticalSession.Phase.DEFEAT: "Поражение до действий противника.", BattleTacticalSession.Phase.MUTUAL_DESTRUCTION: "Обе команды погибнут. Бой завершится."}
	text += "[color=#f7c97d]%s[/color]\n" % phases.get(_turn_forecast.phase_after, "Переход завершён.")
	for event: Dictionary in _turn_forecast.events:
		if event.get("kind", &"") in [&"environment_turn", &"support_collapsed"]:
			text += _event_text(event) + "\n"
	var ids: Array = _turn_forecast.units_before.keys()
	ids.sort()
	for id: int in ids:
		var before: Dictionary = _turn_forecast.units_before[id]
		var after: Dictionary = _turn_forecast.units_after.get(id, {})
		if after.is_empty(): continue
		var changes: PackedStringArray = []
		for pair: Array in [["hp", "HP"], ["armor_current", "Броня"], ["main", "Основные"], ["bonus", "Бонусные"], ["move", "Движение"]]:
			var key: String = pair[0]
			if before.has(key) and after.has(key) and before[key] != after[key]: changes.append("%s: %s → %s" % [pair[1], str(before[key]), str(after[key])])
		if before.get("alive", true) and not after.get("alive", true): changes.append("Погибнет")
		if before.get("guard_stance", false) != after.get("guard_stance", false): changes.append("Охранная стойка снята" if not after.guard_stance else "Охранная стойка включена")
		if before.get("pending", false) and not after.get("pending", false): changes.append("Помощник готов действовать")
		if before.get("bleeding", {}) != after.get("bleeding", {}): changes.append("Кровотечение: %s → %s" % [_bleeding_summary(before.get("bleeding", {})), _bleeding_summary(after.get("bleeding", {}))])
		if before.get("elemental", {}) != after.get("elemental", {}): changes.append("Статусы: %s → %s" % [_elemental_summary(before.get("elemental", {})), _elemental_summary(after.get("elemental", {}))])
		for entry: Array in [["control", "stunned_turns", "Оглушение, ходов"], ["control", "entangled_turns", "Путы, ходов"], ["combat_perks", "reaction_left", "Общий заряд реакции"]]:
			var old_value: int = before.get(entry[0], {}).get(entry[1], 0)
			var new_value: int = after.get(entry[0], {}).get(entry[1], 0)
			if old_value != new_value: changes.append("%s: %d → %d" % [entry[2], old_value, new_value])
		if before.get("combat_perks", {}).get("movement_stopped", false) and not after.get("combat_perks", {}).get("movement_stopped", false): changes.append("Остановка движения снята")
		if not changes.is_empty(): text += "\n[color=#f7c97d]%s[/color]\n%s\n" % [before.get("name", _name_for(id)), "\n".join(changes)]
	_forecast_panel.text = text
