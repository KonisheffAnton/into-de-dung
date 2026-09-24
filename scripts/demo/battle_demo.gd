extends Control
class_name BattleDemo

@export var tactical_mode: bool = false
@export var armor_mode: bool = false
@export var bleeding_mode: bool = false
@export var environment_mode: bool = false
@export var control_mode: bool = false
@export var core_combination_mode: bool = false
var session: BattleDemoSession
var board_view: BattleDemoBoard
var attack_mode: bool = false
var summoning_mode: bool = false
var raising_mode: bool = false
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
var _end_turn_button: Button
var _mode_button: Button
var _heading: Label
var _subtitle: Label
var _instructions: Label
var _ai_delay: float = 0.0
var _flow_cursor: int = 0
var _forecast_panel: RichTextLabel
var _forecast: AttackForecast
var _move_forecast: MoveForecast
var _move_forecast_cell := Vector2i(-1, -1)
var _move_forecast_actor: int = UnitId.NONE
var _move_forecast_revision: int = -1
const MOVE_HOVER_SETTLE_MS: int = 60
var _move_forecast_pending: bool = false
var _move_forecast_due: int = 0
var _move_forecast_generation: int = 0
var _move_forecast_job_generation: int = -1
var _move_forecast_worker := MoveForecastWorker.new()
var _item_forecast: ItemUseForecast
var _item_forecast_kind: StringName = &""
var _item_forecast_cell := Vector2i(-1, -1)
var _item_forecast_revision: int = -1
var _raise_forecast: RaiseCorpseForecast
var _raise_forecast_cell := Vector2i(-1, -1)
var _raise_forecast_actor: int = UnitId.NONE
var _raise_forecast_revision: int = -1
var _guard_forecast: GuardForecast
var _guard_forecast_actor: int = UnitId.NONE
var _guard_forecast_revision: int = -1
var _forecast_cell := Vector2i(-1, -1)
var _forecast_target_id: int = UnitId.NONE
var _forecast_revision: int = -1
var _log_heading: Label
var _forecast_heading: Label
var _pointer_position := Vector2(-1, -1)
var _shown_inspection_id: int = UnitId.NONE
var _hovered_bar_action: StringName = &""

func _ready() -> void:
	_create_session()
	_build_ui()
	_note("Победите противников. Берегите своих персонажей у края." if tactical_mode else "Полигон готов. Все шесть персонажей управляются вручную.")
	_refresh()

func _create_session() -> void:
	# Составной сценарий проверяется первым, чтобы его флаги отображения не подменили сессию.
	if core_combination_mode:
		session = BattleCoreCombinationSession.new()
	elif control_mode:
		session = BattleControlSession.new()
	else:
		session = BattleEnvironmentSession.new() if environment_mode else (BattleBleedingSession.new() if bleeding_mode else (BattleArmorSession.new() if armor_mode else (BattleTacticalSession.new() if tactical_mode else BattleDemoSession.new())))
	_battle = session as BattleTacticalSession
	_ai_delay = 0.0
	_flow_cursor = 0

func _process(delta: float) -> void:
	_process_move_forecast()
	if _battle == null or _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: return
	_ai_delay -= delta
	if _ai_delay > 0.0: return
	# Один шаг за кадр; reset/смена режима не оставляют отложенных команд старого боя.
	_ai_delay = 0.7
	var receipt := _battle.step_enemy()
	if receipt != null: _show_receipt(receipt)
	else: _refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Координата самого viewport-события одинакова для мыши и replay/test input.
		_pointer_position = (event as InputEventMouseMotion).position
		_update_action_bar_hover()
		if (_forecast != null or _move_forecast != null or _move_forecast_pending or _raise_forecast != null or (_item_forecast != null and _item_forecast_kind == &"summon")) and board_view.hover_cell.x < 0 and not _forecast_reading_region().has_point(_pointer_position) and not board_view.get_global_rect().has_point(_pointer_position):
			_clear_forecast()
			_refresh_inspection()

func _exit_tree() -> void:
	_move_forecast_worker.close()
	_move_forecast_pending = false
	_forecast = null
	_move_forecast = null
	_item_forecast = null
	_item_forecast_kind = &""
	_raise_forecast = null
	_guard_forecast = null
	if board_view != null:
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
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
	root.add_child(_phase_label)
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
	board_view = BattleDemoBoard.new()
	board_view.session = session
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.cell_clicked.connect(handle_cell)
	board_view.cell_hovered.connect(_hover)
	board_view.gui_input.connect(_board_forecast_wheel_input)
	board_view.cancel_requested.connect(set_attack_mode.bind(false))
	left.add_child(board_view)
	_action_bar = BattleActionBar.new()
	_action_bar.name = "BattleActionBar"
	_action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_bar.action_requested.connect(_action_bar_requested)
	_action_bar.action_hovered.connect(_action_bar_hovered)
	_action_bar.action_hover_left.connect(_action_bar_hover_left)
	_action_bar.visible = tactical_mode
	root.add_child(_action_bar)
	_hint = _label("", 14, Color("a5b3c5"))
	_hint.custom_minimum_size.y = 40
	left.add_child(_hint)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 10)
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
	_status = _label("", 14, Color("f7c97d"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 46
	root.add_child(_status)
	_instructions = _label("", 14, Color("a5b3c5"))
	root.add_child(_instructions)

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
	if _battle != null and not _battle.can_player_act(): return
	_clear_action_mode()
	attack_mode = enabled
	_refresh()

func _clear_action_mode() -> void:
	# Только состояние ввода: остатки действий и результат команды принадлежат сессии.
	if session is BattleBleedingSession: (session as BattleBleedingSession).rune_selected = false
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	_clear_forecast()
	# Режим действия закрывает осмотр, чтобы подсветка не смешивалась с целью атаки.
	inspected_id = UnitId.NONE

func _action_bar_requested(action_id: StringName) -> void:
	if not tactical_mode: return
	match action_id:
		&"blood_rune":
			set_attack_mode(true)
			if session is BattleBleedingSession:
				(session as BattleBleedingSession).rune_selected = true
				_refresh()
		&"attack": set_attack_mode(true)
		&"guard": _use_guard()
		&"healing_item": _use_healing_item()
		&"summoning_item": _choose_summoning()
		&"raise_corpse": _choose_raise()
		&"restore_armor":
			if session is BattleArmorSession:
				_clear_action_mode()
				_show_receipt((session as BattleArmorSession).restore_selected_armor())

func _use_healing_item() -> void:
	if _battle == null: return
	_clear_action_mode()
	_show_receipt(_battle.use_healing_item())

func _use_guard() -> void:
	if _battle == null: return
	_clear_action_mode()
	_show_receipt(_battle.guard_selected())

func select_character(id: int) -> void:
	if session.select_unit(id):
		inspected_id = UnitId.NONE
		set_attack_mode(false)

func inspect_enemy(id: int) -> void:
	if _battle == null or _battle.phase != BattleTacticalSession.Phase.PLAYER_TURN or not _battle.can_player_act(): return
	var unit := session.board.get_unit_by_id(id)
	if unit == null or not unit.is_alive() or unit.faction != Faction.Type.ENEMY: return
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	_clear_forecast()
	inspected_id = UnitId.NONE if inspected_id == id else id
	_refresh()

func handle_cell(cell: Vector2i) -> void:
	if _battle != null and not _battle.can_player_act(): return
	var occupant := session.board.occupant_at(cell)
	if summoning_mode:
		var receipt := _battle.use_summoning_item(cell)
		_show_receipt(receipt, true)
	elif raising_mode and session is BattleEnvironmentSession:
		var raise_receipt := (session as BattleEnvironmentSession).raise_corpse(cell)
		_show_receipt(raise_receipt, true)
	elif attack_mode:
		if occupant == null:
			var rejected := ActionReceipt.new()
			rejected.reason = &"attack/invalid_target"
			_show_receipt(rejected, true)
			return
		_show_receipt(session.attack_unit(occupant.id), true)
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
		_show_receipt(session.move_to(cell))

func reset_demo() -> void:
	_clear_forecast()
	session.reset()
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_flow_cursor = 0
	_ai_delay = 0.0
	_note("Бой сброшен: здоровье, действия и предметы восстановлены.")
	_refresh()

func toggle_scenario() -> void:
	control_mode = false
	core_combination_mode = false
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
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_note("Начат бой против компьютера." if tactical_mode else "Полигон: все персонажи управляются вручную.")
	_refresh()

func _open_core_combination_scenario() -> void:
	_clear_forecast()
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
	_note("Сочетания ядра: контроль, тыл и крит, кровотечение, шипы и поднятие тела.")
	_refresh()

func end_turn() -> void:
	if _battle == null: return
	if not _battle.end_player_turn():
		_refresh()
		return
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	_clear_forecast()
	inspected_id = UnitId.NONE
	_ai_delay = 0.5
	_refresh()

func _refresh() -> void:
	# Любой refresh перечитывает состояние, включая изменения вне command revision.
	var refresh_guard := _guard_forecast != null and _hovered_bar_action == &"guard"
	_clear_forecast()
	if inspected_id != UnitId.NONE:
		var inspected := session.board.get_unit_by_id(inspected_id) if session != null and session.board != null else null
		if _battle == null or not _battle.can_player_act() or inspected == null or not inspected.is_alive() or inspected.faction != Faction.Type.ENEMY:
			inspected_id = UnitId.NONE
	_heading.text = "intoDeDung   /   Бой у обрыва" if tactical_mode else "intoDeDung   /   Полигон"
	if armor_mode: _heading.text = "intoDeDung   /   Броня и огонь"
	if bleeding_mode: _heading.text = "intoDeDung   /   Кровотечение"
	if environment_mode: _heading.text = "intoDeDung   /   Среда и трупы"
	if control_mode: _heading.text = "intoDeDung   /   Крит и спина"
	if core_combination_mode: _heading.text = "intoDeDung   /   Сочетания ядра"
	_subtitle.text = "Трое против троих. Победите всех врагов; потеря команды означает поражение." if tactical_mode else "Поднимитесь по ступеням. Ударьте сверху. Столкните стража с уступа."
	_subtitle.visible = not tactical_mode
	_status.custom_minimum_size.y = 26 if tactical_mode else 46
	_mode_button.text = "Полигон" if tactical_mode else "Бой против ИИ"
	_phase_label.visible = tactical_mode
	_end_turn_button.visible = tactical_mode
	# В тактическом режиме атака должна иметь единственную точку входа в action bar;
	# старая кнопка остаётся частью sandbox-полигона для совместимости.
	_attack_button.visible = not tactical_mode
	_instructions.text = "1 / A: атака · 2: защита · 3: лечение · 4: призыв · M: движение · Клик по врагу: осмотр · Enter: конец хода · R: заново" if tactical_mode else "Ступени: Астра → D3 → A → Страж. Стена: Бор → A → Щит. Пропасть: Рей → A → Мишень на G7."
	if armor_mode: _instructions.text = _instructions.text.replace("4: призыв", "4: броня +20")
	if environment_mode: _instructions.text = "1 / A: атака · 2: защита · 3: лечение · 6: поднять тело · M: движение · Enter: конец хода · R: заново"
	if session is BattleBleedingSession and (session as BattleBleedingSession).rune_selected:
		_instructions.text = "Кровавая руна (перк): выберите цель · 1 основное · Обходит требование HP-урона; иммунитет сохраняется · A: обычная атака"
	var locked := _battle != null and not _battle.can_player_act()
	_move_button.disabled = locked
	if session.selected_unit() != null and ControlRules.action_reason(session.selected_unit(), true) != &"": _move_button.disabled = true
	_attack_button.disabled = locked
	_end_turn_button.disabled = locked
	_action_bar.visible = tactical_mode
	if tactical_mode and _action_bar != null:
		var item := _battle.healing_item() if _battle != null else null
		var healing_reason := _battle.healing_reason() if _battle != null else &"battle/input_locked"
		var descriptors: Array[Dictionary] = []
		descriptors.append(_item_action_descriptor(item, &"healing_item", healing_reason))
		var seal := _battle.summoning_item() if _battle != null else null
		if session is BattleArmorSession:
			var reason := (session as BattleArmorSession).restore_armor_reason()
			descriptors.append({"action_id": &"restore_armor", "label": "Броня +20", "cost": "1 основное", "disabled": reason != &"", "tooltip": "Восстановить 20 брони по недостаче вещей. Избыток становится временной бронёй до конца боя.\n" + (_reason_text(reason) if reason != &"" else "Стойка сохраняется.")})
		elif seal != null:
			var reason := _battle.summoning_reason()
			descriptors.append(_item_action_descriptor(seal, &"summoning_item", reason))
		if session is BattleBleedingSession:
			descriptors.append({"action_id": &"blood_rune", "label": "Кровавая руна", "cost": "Перк · 1 основное", "disabled": locked or session.selected_unit() == null or not session.selected_unit().can_attack(), "tooltip": "Перк персонажа «Кровавая руна»: эта атака накладывает кровотечение даже без физического урона HP. Иммунитет сохраняется. Каждое успешное наложение добавляет 2 тика по 4 с учётом естественной защиты."})
		if environment_mode and session is BattleEnvironmentSession:
			var raise_reason := (session as BattleEnvironmentSession).raise_reason()
			descriptors.append({"action_id": &"raise_corpse", "label": "Поднять тело", "cost": "1 основное", "disabled": locked or raise_reason != &"", "tooltip": "Выберите соседнюю свободную клетку без шипов той же высоты. Помощник: 16 HP, действует со следующего хода команды.\n" + (_reason_text(raise_reason) if raise_reason != &"" else "Тело расходуется после успешного поднятия.")})
		_action_bar.set_dynamic_descriptors(descriptors)
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
	_forecast_panel.visible = attack_mode or _item_forecast != null or _move_forecast != null
	_forecast_heading.visible = attack_mode or _item_forecast != null or _move_forecast != null
	if locked:
		summoning_mode = false
		raising_mode = false
	board_view.summoning_mode = summoning_mode
	board_view.raising_mode = raising_mode
	board_view.environment_mode = environment_mode
	board_view.attack_mode = attack_mode
	board_view.inspected_id = inspected_id
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
		var text := "%s%s  ·  %s" % [unit.debug_name, stance + waiting, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб"]
		var button := _button(text)
		button.custom_minimum_size.y = 30
		button.toggle_mode = true
		button.set_pressed_no_signal(unit.id == session.selected_id and alive)
		if _battle != null and unit.faction == Faction.Type.ENEMY:
			button.set_pressed_no_signal(unit.id == inspected_id and alive)
			button.disabled = not alive or locked or _battle == null or _battle.phase != BattleTacticalSession.Phase.PLAYER_TURN
			button.pressed.connect(inspect_enemy.bind(unit.id))
		else:
			button.disabled = not alive or locked
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
	if inspected_id != UnitId.NONE:
		var enemy := session.board.get_unit_by_id(inspected_id)
		_status.text = "Осмотр: %s · движение на следующий ход: %.1f ОД\nТекущая расстановка; зона движения. Esc или клик по пустой клетке — закрыть." % [enemy.debug_name, enemy.get_stat(StatTypes.StatType.MOVE_RANGE)]
		if ControlRules.action_reason(enemy, true) != &"": _status.text = "Осмотр: %s · движение в ближайший ход недоступно из-за состояния.\nEsc или клик по пустой клетке — закрыть." % enemy.debug_name
	if summoning_mode: _status.text = "Призыв: выберите подсвеченную соседнюю клетку. 1 основное + 1 заряд. Esc — отмена."
	if raising_mode: _status.text = "Поднять тело: выберите подсвеченную соседнюю свободную клетку без шипов. 1 основное. Esc — отмена."
	if session.context.is_faulted(): _status.text = "Исполнение остановлено из-за ошибки. Выполненные последствия сохранены; сбросьте бой."
	if locked: _status.text = _battle.phase_text() + (" · Можно начать заново: R." if _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN else " · Противник выполняет действия.")
	_hover(board_view.hover_cell)
	_log.text = "\n".join(_journal)
	if refresh_guard and _battle != null and _battle.can_player_act(): _action_bar_hovered(&"guard")
	_render_forecast_panel()

func _inspection_text(unit: UnitState) -> String:
	var text := "%s · %s · высота %+.1f\nHP: %.1f / %.1f\nПотеря равновесия: %.1f / %.1f\nДвижение: %.1f / %.1f · Основное: %d · Бонус: %d\nБроня: %.1f · Оружие: %.1f урона\nСила: %.1f · Воздействие: %.1f\nАтака: 1 основное · Дальность: %.1f" % [unit.debug_name, _cell_name(unit.cell), float(session.board.get_height_steps(unit.cell)) / 2.0, unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX), unit.vitals.get_balance(), ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX)), unit.move_points_left, unit.get_stat(StatTypes.StatType.MOVE_RANGE), unit.action_resources.get_main_left(), unit.action_resources.get_bonus_left(), unit.get_stat(StatTypes.StatType.ARMOR), unit.get_stat(StatTypes.StatType.WEAPON_DAMAGE), unit.get_stat(StatTypes.StatType.STRENGTH), unit.get_stat(StatTypes.StatType.IMPACT_POWER), unit.get_stat(StatTypes.StatType.ATTACK_RANGE)]
	var control_text := ""
	var piercing := unit.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT)
	if piercing > 0.0:
		text += "\nПробивание %.0f%% физической базы: броня обходится, естественная защита действует." % piercing
	if control_mode:
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
		if unit.bleeding.immune: condition += "\nИммунитет к кровотечению и руне"
		var first_line := text.find("\n")
		text = text.insert(first_line + 1, condition + "\n")
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
					if armor_mode:
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
	var id := _forecast_target_id if _forecast != null else inspected_id
	var unit := session.board.get_unit_by_id(id) if id != UnitId.NONE else session.selected_unit()
	if unit != null:
		if _shown_inspection_id != unit.id:
			(_stats.get_parent() as ScrollContainer).scroll_vertical = 0
		_shown_inspection_id = unit.id
		_stats.text = _inspection_text(unit)

func _hover(cell: Vector2i) -> void:
	if session == null or session.board == null: return
	if _guard_forecast != null and cell.x >= 0: _clear_forecast()
	# Позволяем перейти к прокрутке длинной цепи, сохранив текущий прогноз.
	if (_forecast != null or _item_forecast != null or _move_forecast != null or _raise_forecast != null or _guard_forecast != null) and cell.x < 0:
		# mouse_exited может прийти раньше _input того же движения мыши.
		_resolve_hover_exit.call_deferred()
		return
	if raising_mode and session is BattleEnvironmentSession and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if _raise_forecast == null or _raise_forecast_cell != cell or _raise_forecast_actor != session.selected_id or _raise_forecast_revision != revision:
			_clear_forecast()
			_raise_forecast = (session as BattleEnvironmentSession).preview_raise_corpse(cell)
			_raise_forecast_cell = cell
			_raise_forecast_actor = session.selected_id
			_raise_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_render_raise_forecast_panel()
	elif summoning_mode and _battle != null and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if _item_forecast_kind != &"summon" or _item_forecast_cell != cell or _item_forecast_revision != revision:
			_item_forecast = _battle.preview_summoning_item(cell)
			_item_forecast_kind = &"summon"
			_item_forecast_cell = cell
			_item_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_render_item_forecast_panel()
	elif not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act()) and session.board.is_in_bounds(cell) and session.board.occupant_at(cell) == null:
		var revision := session.context.get_revision()
		if (_move_forecast == null and not _move_forecast_pending) or _move_forecast_cell != cell or _move_forecast_actor != session.selected_id or _move_forecast_revision != revision:
			_clear_forecast()
			_move_forecast_pending = true
			_move_forecast_due = Time.get_ticks_msec() + MOVE_HOVER_SETTLE_MS
			_move_forecast_cell = cell
			_move_forecast_actor = session.selected_id
			_move_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			board_view.move_forecast_pending = true
			board_view.refresh_forecast()
	elif not attack_mode or (_battle != null and not _battle.can_player_act()) or not session.board.is_in_bounds(cell):
		_clear_forecast()
	else:
		var target := session.board.occupant_at(cell)
		if target == null:
			_clear_forecast()
		else:
			var revision := session.context.get_revision()
			if _forecast_cell != cell or _forecast_target_id != target.id or _forecast_revision != revision:
				_forecast = session.preview_attack(target.id)
				# Новый прогноз всегда читается с начала, даже после прокрутки предыдущей цели.
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_forecast_cell = cell
				_forecast_target_id = target.id
				_forecast_revision = revision
				board_view.forecast = _forecast
				board_view.refresh_forecast()
	_refresh_inspection()

	if environment_mode and session is BattleEnvironmentSession and session.board.is_in_bounds(cell):
		var environment := (session as BattleEnvironmentSession).state.environment
		var details: Array[String] = []
		for corpse: Dictionary in environment.corpses_at(cell):
			var faction: String = {Faction.Type.PLAYER: "союзник", Faction.Type.ENEMY: "противник", Faction.Type.NEUTRAL: "нейтральный"}[corpse["faction"]]
			var kind := "гуманоид" if corpse["creature_kind"] == "humanoid" else String(corpse["creature_kind"])
			details.append("%s · %s" % [faction, kind])
		var fire := "Шипы: 8 урона при входе." if not environment.fire_at(cell).is_empty() else "Шипов нет."
		_hint.text = fire + ("\nТела ×%d: %s" % [details.size(), ", ".join(details)] if not details.is_empty() else "\nТрупов нет.")
		if raising_mode: _hint.text += "\nПоднятие: выберите соседнюю клетку той же высоты."
		_render_forecast_panel()
		return

	if summoning_mode:
		var item := _battle.summoning_item()
		_hint.text = "Бирюзовые точки — клетки призыва. Клик — %s.\nПомощник с %s HP действует со следующего хода своей команды. Esc — отмена." % [_item_cost_text(item.get_use_action() if item != null else null), _summon_hp_text(item)]
		return
	if not session.board.is_in_bounds(cell):
		_hint.text = "Золотые клетки — движение врага на следующий ход; зона атаки не показана.\nВыбранный союзник сохранён. Осмотр не расходует действия." if inspected_id != UnitId.NONE else "Числа на клетках — высота. Бирюзовые точки — доступное движение.\nПолоски: здоровье / накопленная потеря равновесия. ПКМ или Esc — движение."
		if control_mode and inspected_id == UnitId.NONE: _hint.text = "Розовая стрелка у ног — тыл: атака с соседней клетки даёт +50% базы.\nОглушение или путы на цели дают крит ×2; два состояния не складывают крит."
		return
	var reachable: Dictionary = board_view.reachable_cells()
	var cost := " · путь: %.1f ОД" % float(reachable[cell]) if reachable.has(cell) else ""
	_hint.text = "%s · высота %+.1f%s\n%s" % [_cell_name(cell), float(session.board.get_height_steps(cell)) / 2.0, cost, "Осмотр: зона движения на следующий ход, не атаки." if inspected_id != UnitId.NONE else "Прогноз показывает итог движения. Клик — выполнить; кольцо — конечная клетка."]
	if attack_mode: _hint.text = "Наведите на цель: прогноз одной атаки. Клик — выполнить.\nКрасный сегмент HP — потеря, зелёный — лечение; белая метка — итог."
	_render_forecast_panel()

func _process_move_forecast() -> void:
	var result := _move_forecast_worker.take_finished()
	if result != null and _move_forecast_pending and _move_forecast_job_generation == _move_forecast_generation:
		if not _move_forecast_request_current():
			_clear_forecast()
			return
		_move_forecast = result
		_move_forecast_pending = false
		board_view.move_forecast_pending = false
		board_view.move_forecast = result
		board_view.refresh_forecast()
		_render_forecast_panel()
	if not _move_forecast_pending or _move_forecast_worker.is_started() or Time.get_ticks_msec() < _move_forecast_due: return
	if not _move_forecast_request_current():
		_clear_forecast()
		return
	_move_forecast_job_generation = _move_forecast_generation
	# Только этот короткий capture читает live; исполнение и восстановление идут на копии.
	_move_forecast_worker.start(session.prepare_move_forecast(_move_forecast_cell))

func _move_forecast_request_current() -> bool:
	return session != null and session.context != null and board_view != null and board_view.hover_cell == _move_forecast_cell and session.selected_id == _move_forecast_actor and session.context.get_revision() == _move_forecast_revision and not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act())

func _board_forecast_wheel_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	var wheel := event as InputEventMouseButton
	if not wheel.pressed or (wheel.button_index != MOUSE_BUTTON_WHEEL_UP and wheel.button_index != MOUSE_BUTTON_WHEEL_DOWN): return
	if not _forecast_panel.is_visible_in_tree() or (_battle != null and not _battle.can_player_act()): return
	var target_cell := _forecast_cell if _forecast != null and attack_mode else _move_forecast_cell
	if _raise_forecast != null and raising_mode: target_cell = _raise_forecast_cell
	if (_forecast == null or not attack_mode) and _move_forecast == null and _raise_forecast == null: return
	if board_view.cell_at(wheel.position) != target_cell: return
	var amount := 48.0 * (wheel.factor if wheel.factor > 0.0 else 1.0)
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP: amount = -amount
	var scroll_bar := _forecast_panel.get_v_scroll_bar()
	var last_value := maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	scroll_bar.value = clampf(scroll_bar.value + amount, scroll_bar.min_value, last_value)
	accept_event()

func _leave_forecast_panel() -> void:
	_resolve_hover_exit.call_deferred()

func _resolve_hover_exit() -> void:
	if session == null or board_view.hover_cell.x >= 0 or (_forecast == null and _item_forecast == null and _move_forecast == null and _raise_forecast == null and _guard_forecast == null): return
	if _item_forecast_kind == &"healing" and _hovered_bar_action == &"healing_item": return
	if _guard_forecast != null and _hovered_bar_action == &"guard": return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _forecast_reading_region() -> Rect2:
	var panel := _forecast_panel.get_global_rect()
	# Узкий зазор между полем и панелью не должен прерывать переход курсора.
	var left := minf(board_view.get_global_rect().end.x, panel.position.x)
	return Rect2(Vector2(left, panel.position.y), Vector2(panel.end.x - left, panel.size.y))

func _clear_forecast() -> void:
	var had_forecast := _forecast != null or _move_forecast != null or _move_forecast_pending
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
	_guard_forecast = null
	_guard_forecast_actor = UnitId.NONE
	_guard_forecast_revision = -1
	_forecast_cell = Vector2i(-1, -1)
	_forecast_target_id = UnitId.NONE
	_forecast_revision = -1
	if board_view != null:
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
		if had_forecast and board_view.session != null: board_view.refresh_forecast()
	if _forecast_panel != null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		_forecast_panel.visible = attack_mode
		_forecast_heading.visible = attack_mode
		_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	if _log != null: _log.visible = not attack_mode
	if _log_heading != null: _log_heading.visible = not attack_mode

func _render_forecast_panel() -> void:
	if _forecast_panel == null: return
	if _guard_forecast != null:
		_render_guard_forecast_panel()
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
	if _forecast == null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		return
	var status: StringName = _forecast.status
	var reason: StringName = _forecast.reason
	var text := "[font_size=16][color=#f7c97d]Цель: %s[/color][/font_size]\n" % _name_for(_forecast_target_id)
	if status != &"APPLIED":
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(reason)
		return
	var units: Dictionary = _forecast.units
	var target_after: Dictionary = units.get(_forecast_target_id, {}).get("after", {})
	if target_after.has("bleeding"):
		text += "Кровотечение: %d тика после атаки\n" % target_after["bleeding"]["ticks_left"]
		for step: Dictionary in _forecast.steps:
			if step["kind"] == &"bleeding_apply" and step["status"] == &"SKIPPED":
				text += "Не наложено: " + ("иммунитет" if step["reason"] == &"bleeding/immune" else ("цель погибла" if step["reason"] == &"bleeding/dead_target" else "нет физического HP-урона")) + ".\n"
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
			text += "%s: кровотечение %d → %d тика\n" % [_name_for(id), before["bleeding"]["ticks_left"], after["bleeding"]["ticks_left"]]
		if before.has("control") and before["control"] != after["control"]:
			if before["control"]["entangled_turns"] > after["control"]["entangled_turns"]: text += "%s: путы будут сняты.\n" % _name_for(id)
		if before["main"] != after["main"]:
			text += "%s: основные действия %d → %d\n" % [_name_for(id), before["main"], after["main"]]
	var events: Array[Dictionary] = _forecast.events
	for event: Dictionary in events:
		if event.get("kind") == &"attacked" and event.has("modifiers"):
			var modifiers: Dictionary = event["modifiers"]
			if modifiers["backstab_percent"] > 0: text += "\n[color=#f7c97d]Удар в спину +%d%% базы[/color]\n" % modifiers["backstab_percent"]
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
		text += "Кровотечение не наложено: " + ("иммунитет" if step["reason"] == &"bleeding/immune" else ("цель погибла" if step["reason"] == &"bleeding/dead_target" else "нет физического HP-урона")) + ".\n"
	if events.is_empty(): text += "Событий последствий нет.\n"
	else:
		text += "\n[color=#a5b3c5]Последствия:[/color]\n"
		for event_variant in events:
			text += "• " + _event_text(event_variant as Dictionary) + "\n"
	_forecast_panel.text = text

func _render_move_forecast_panel() -> void:
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var text := "[font_size=16][color=#f7c97d]Движение к %s[/color][/font_size]\n" % _cell_name(_move_forecast_cell)
	if _move_forecast_pending:
		_forecast_panel.text = text + "Расчёт прогноза…"
		return
	if _move_forecast.status not in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		_forecast_panel.text = text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + _reason_text(_move_forecast.reason)
		return
	if _move_forecast.status == ActionReceipt.INTERRUPTED:
		text += "[color=#f29b9b]Маршрут прервётся: %s[/color]\n" % _reason_text(_move_forecast.reason)
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
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	if previous == &"healing_item" and action_id != &"healing_item": _resolve_item_hover_exit.call_deferred()
	if previous == &"guard" and action_id != &"guard": _resolve_guard_hover_exit.call_deferred()
	if action_id == &"guard":
		if _battle == null or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if _guard_forecast != null and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision: return
		_clear_forecast()
		_guard_forecast = _battle.preview_guard()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_forecast_panel.get_v_scroll_bar().value = 0.0
		_render_guard_forecast_panel()
		_refresh_inspection()
		return
	if action_id != &"healing_item" or _battle == null: return
	var revision := session.context.get_revision()
	if _item_forecast_kind == &"healing" and _item_forecast_revision == revision: return
	_clear_forecast()
	_item_forecast = _battle.preview_healing_item()
	_item_forecast_kind = &"healing"
	_item_forecast_revision = revision
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_render_item_forecast_panel()

func _action_bar_hover_left(action_id: StringName) -> void:
	if _hovered_bar_action == action_id: _hovered_bar_action = &""
	if action_id == &"guard": _resolve_guard_hover_exit.call_deferred()
	if action_id != &"healing_item" or _item_forecast_kind != &"healing": return
	_resolve_item_hover_exit.call_deferred()

func _update_action_bar_hover() -> void:
	if _action_bar == null or not _action_bar.visible: return
	var action_id: StringName = &""
	if _action_bar.get_global_rect().has_point(_pointer_position):
		for button in _action_bar._buttons:
			if button.visible and button.get_global_rect().has_point(_pointer_position):
				action_id = StringName(button.get_meta("action_id", &""))
				break
	if action_id == _hovered_bar_action:
		if action_id == &"guard" and _guard_forecast != null: _action_bar_hovered(action_id)
		return
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	if previous in [&"healing_item", &"guard"]: _action_bar_hover_left(previous)
	if action_id in [&"healing_item", &"guard"]: _action_bar_hovered(action_id)

func _resolve_guard_hover_exit() -> void:
	if session == null or _guard_forecast == null: return
	if _hovered_bar_action == &"guard" or _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _render_guard_forecast_panel() -> void:
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

func _resolve_item_hover_exit() -> void:
	if _item_forecast == null or _item_forecast_kind != &"healing": return
	if _hovered_bar_action == &"healing_item": return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_forecast_panel.visible = attack_mode
	_forecast_heading.visible = attack_mode

func _render_item_forecast_panel() -> void:
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
	# Завершённое применение и отказ по выбранной цели возвращают движение.
	# UI не зависит от того, основное или дополнительное действие оплатила команда.
	if target_attempt or receipt.status != ActionReceipt.REJECTED:
		_clear_action_mode()
	_clear_forecast()
	for event in receipt.get_events(): _note(_event_text(event))
	_refresh()
	# Смерть уже исполнена ядром; временная фигура лишь показывает падение в провал.
	for event in receipt.get_events():
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
			if event["reason"] == &"tick": return "%s: тик кровотечения; %s." % [target, "срок истёк" if ticks == 0 else "осталось тиков: %d" % ticks]
			return "%s: кровотечение %s — тиков: %d." % [target, "наложено" if event["reason"] == &"applied" else "продлено", ticks]
		&"attacked":
			var suffix := ""
			var modifiers: Dictionary = event.get("modifiers", {})
			if int(modifiers.get("backstab_percent", 0)) > 0: suffix += " Удар в спину +%d%%." % modifiers["backstab_percent"]
			if modifiers.get("critical", false): suffix += " Крит ×2."
			return "%s атакует %s.%s" % [actor, target, suffix]
		&"control_changed":
			return "%s: путы сняты толчком." % target if event["reason"] == &"push" else "%s: срок состояния контроля истёк." % target
		&"guarded": return "%s занимает охранную стойку (1 основное действие)." % actor
		&"item_used":
			var owner := session.state.get_owner(int(event["actor_unit_id"]))
			var item: ItemInstance = owner._items.get(int(event["item_instance_id"])) if owner != null else null
			var action := item.get_use_action() if item != null else null
			var name := "печать" if action != null and action.get_kind() == ItemUseAction.Kind.SUMMON_ADJACENT else "флакон"
			return "%s использует %s (%d основное; зарядов осталось: %d)." % [actor, name, int(event["main_cost"]), int(event["charges_after"])]
		&"summoned": return "%s призывает: %s. Действия со следующего хода команды." % [actor, target]
		&"corpse_created": return "Тело: %s, гуманоид." % _cell_name(event["corpse"]["cell"])
		&"corpse_raised": return "%s поднял тело: %s (16 HP), ожидает следующего хода." % [actor, target]
		&"damaged":
			var source: Dictionary = event.get("source", {})
			var cause := " от падения" if source.get("kind", &"") == &"fall" else (" от кровотечения" if bleeding_mode and source.get("kind", &"") == &"status" else (" от шипов (8)" if source.get("kind", &"") == &"cell" else ""))
			return "%s: −%.1f HP%s." % [target, float(event.get("amount", 0)), cause]
		&"healed":
			var heal_source: StringName = event.get("source", {}).get("kind", &"")
			var heal_cause := " от сопротивления урону шипов" if heal_source == &"cell" else (" от сопротивления" if heal_source in [&"attack", &"collision", &"fall"] or (bleeding_mode and heal_source == &"status") else " от предмета")
			return "%s: +%.1f HP%s." % [target, float(event.get("amount", 0)), heal_cause]
		&"armor_changed": return "%s: запас брони изменился." % target
		&"hit_resolved": return "%s: попадание завершено, HP %d → %d." % [target, event["hit"]["hp_before"], event["hit"]["hp_after"]]
		&"balance_changed": return "%s: равновесие %.1f / %.1f." % [target, float(event.get("balance_after", 0)), float(event.get("balance_max", 0))]
		&"balance_broken": return "%s теряет равновесие → толчок." % target
		&"moved":
			var pushed: bool = event.get("movement_kind", &"") == &"push"
			return "%s %s %s → %s." % [target if pushed else actor, "отброшен:" if pushed else "идёт:", _cell_name(event["from_cell"]), _cell_name(event["to_cell"])]
		&"push_blocked": return "%s врезается в препятствие." % target
		&"collision": return "%s сталкивается с %s." % [target, _name_for(int(event.get("blocker_unit_id", 0)))]
		&"fell": return "%s падает с уступа." % target
		&"died": return "%s погиб. Клетка свободна." % target
	return "%s: %s" % [target, String(event.get("kind", "событие"))]

func _name_for(id: int) -> String:
	var unit := session.board.get_unit_by_id(id)
	return unit.debug_name if unit != null else "Окружение"

func _cell_name(cell: Vector2i) -> String:
	return String.chr(65 + cell.x) + str(cell.y + 1)

func _reason_text(reason: StringName) -> String:
	match reason:
		&"control/stunned": return "персонаж оглушён и не может выполнять добровольные действия."
		&"control/entangled": return "персонаж опутан и не может двигаться; остальные действия доступны."
		&"armor/summon_unsupported": return "призыв недоступен в сценарии брони."
		&"armor/zero_restore": return "нечего восстанавливать."
		&"armor/full": return "обычная броня уже восстановлена."
		&"attack/insufficient_main": return "основные действия закончились; выберите другого персонажа или завершите ход." if tactical_mode else "основные действия закончились; выберите другого персонажа или сбросьте бой."
		&"battle/input_locked": return "сейчас нельзя действовать."
		&"battle/friendly_target": return "выберите противника."
		&"move/insufficient_move": return "не хватает очков движения."
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
		&"preview/rng_not_cloneable", &"preview/rng_state_mismatch", &"preview/unsupported_worker_rng": return "случайный эффект пока не поддерживает точный прогноз."
		&"preview/worker_unavailable": return "расчёт временно недоступен; наведите курсор ещё раз."
		&"command_limit", &"event_limit", &"depth_limit", &"sequence_exhausted": return "цепь последствий не завершилась; точный итог недоступен."
	return "Эта комбинация пока не поддерживается: " + String(reason)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				if tactical_mode and _action_bar != null:
					var slot := int(event.keycode - KEY_0)
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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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
	if _battle == null: return
	var reason := _battle.summoning_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	summoning_mode = true
	_refresh()

func _choose_raise() -> void:
	if not environment_mode or not session is BattleEnvironmentSession: return
	var environment := session as BattleEnvironmentSession
	var reason := environment.raise_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	raising_mode = true
	_refresh()
