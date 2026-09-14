extends Control
class_name BattleDemo

@export var tactical_mode: bool = false
var session: BattleDemoSession
var board_view: BattleDemoBoard
var attack_mode: bool = false
var _roster: VBoxContainer
var _stats: Label
var _hint: Label
var _log: RichTextLabel
var _move_button: Button
var _attack_button: Button
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

func _ready() -> void:
	_create_session()
	_build_ui()
	_note("Победите противников. Берегите своих персонажей у края." if tactical_mode else "Полигон готов. Все шесть персонажей управляются вручную.")
	_refresh()

func _create_session() -> void:
	session = BattleTacticalSession.new() if tactical_mode else BattleDemoSession.new()
	_battle = session as BattleTacticalSession
	_ai_delay = 0.0
	_flow_cursor = 0

func _process(delta: float) -> void:
	if _battle == null or _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: return
	_ai_delay -= delta
	if _ai_delay > 0.0: return
	# Один шаг за кадр; reset/смена режима не оставляют отложенных команд старого боя.
	_ai_delay = 0.7
	var receipt := _battle.step_enemy()
	if receipt != null: _show_receipt(receipt)
	else: _refresh()

func _exit_tree() -> void:
	if board_view != null: board_view.session = null
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
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title := HBoxContainer.new()
	root.add_child(title)
	_heading = _label("", 28, Color("e6ecf4"))
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_heading)
	_mode_button = _button("")
	_mode_button.pressed.connect(toggle_scenario)
	title.add_child(_mode_button)
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
	board_view = BattleDemoBoard.new()
	board_view.session = session
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.cell_clicked.connect(handle_cell)
	board_view.cell_hovered.connect(_hover)
	board_view.cancel_requested.connect(set_attack_mode.bind(false))
	left.add_child(board_view)
	_hint = _label("", 14, Color("a5b3c5"))
	_hint.custom_minimum_size.y = 40
	left.add_child(_hint)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 10)
	content.add_child(side)
	side.add_child(_label("ПЕРСОНАЖИ", 13, Color("65dfcc")))
	_roster = VBoxContainer.new()
	side.add_child(_roster)
	_stats = _label("", 15, Color("e6ecf4"))
	_stats.custom_minimum_size.y = 108
	side.add_child(_stats)
	side.add_child(_label("ЖУРНАЛ ПОСЛЕДСТВИЙ", 13, Color("65dfcc")))
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(340, 130)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color("c8d3e1"))
	side.add_child(_log)
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
	attack_mode = enabled
	_refresh()

func select_character(id: int) -> void:
	if session.select_unit(id):
		set_attack_mode(false)

func handle_cell(cell: Vector2i) -> void:
	if _battle != null and not _battle.can_player_act(): return
	var occupant := session.board.occupant_at(cell)
	if attack_mode:
		if occupant == null:
			_status.text = "Для атаки выберите персонажа на поле."
			return
		_show_receipt(session.attack_unit(occupant.id))
	elif occupant != null:
		select_character(occupant.id)
	else:
		_show_receipt(session.move_to(cell))

func reset_demo() -> void:
	session.reset()
	attack_mode = false
	_journal.clear()
	_flow_cursor = 0
	_ai_delay = 0.0
	_note("Бой сброшен: здоровье, действия и предметы восстановлены.")
	_refresh()

func toggle_scenario() -> void:
	session.close()
	tactical_mode = not tactical_mode
	_create_session()
	board_view.session = session
	attack_mode = false
	_journal.clear()
	_note("Начат бой против компьютера." if tactical_mode else "Полигон: все персонажи управляются вручную.")
	_refresh()

func end_turn() -> void:
	if _battle == null or not _battle.end_player_turn(): return
	attack_mode = false
	_ai_delay = 0.5
	_refresh()

func _refresh() -> void:
	_heading.text = "intoDeDung   /   Бой у обрыва" if tactical_mode else "intoDeDung   /   Полигон"
	_subtitle.text = "Трое против троих. Победите всех врагов; потеря команды означает поражение." if tactical_mode else "Поднимитесь по ступеням. Ударьте сверху. Столкните стража с уступа."
	_mode_button.text = "Полигон" if tactical_mode else "Бой против ИИ"
	_phase_label.visible = tactical_mode
	_end_turn_button.visible = tactical_mode
	_instructions.text = "Бирюзовые — ваша команда; золотые — противник. Атака: A · Движение: M · Конец хода: Enter · Заново: R" if tactical_mode else "Ступени: Астра → D3 → A → Страж. Стена: Бор → A → Щит. Пропасть: Рей → A → Мишень на G7."
	var locked := _battle != null and not _battle.can_player_act()
	_move_button.disabled = locked
	_attack_button.disabled = locked
	_end_turn_button.disabled = locked
	if _battle != null:
		_phase_label.text = _battle.phase_text()
		while _flow_cursor < _battle.flow_log.size():
			_note(_battle.flow_log[_flow_cursor])
			_flow_cursor += 1
	_move_button.set_pressed_no_signal(not attack_mode)
	_attack_button.set_pressed_no_signal(attack_mode)
	board_view.attack_mode = attack_mode
	board_view.refresh()
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	for unit in session.units:
		var alive := unit.is_alive()
		var text := "%s  ·  %s" % [unit.debug_name, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб"]
		var button := _button(text)
		button.toggle_mode = true
		button.set_pressed_no_signal(unit.id == session.selected_id and alive)
		button.disabled = not alive or locked or (_battle != null and unit.faction != Faction.Type.PLAYER)
		button.pressed.connect(select_character.bind(unit.id))
		_roster.add_child(button)
	var selected := session.selected_unit()
	if selected == null:
		_stats.text = "Выберите живого персонажа в списке."
		if locked:
			_stats.text = "Дождитесь завершения хода противника." if _battle.phase == BattleTacticalSession.Phase.ENEMY_TURN else "Бой окончен. Нажмите R, чтобы сыграть снова."
	else:
		_stats.text = "%s  ·  %s  ·  высота %+.1f\nРавновесие: %.1f / %.1f до толчка\nДвижение: %.1f / %.1f   ·   Атаки: %d   ·   Бонус: %d\nБроня: %.1f   ·   Удар: %.1f   ·   Импакт: %.1f" % [selected.debug_name, _cell_name(selected.cell), float(session.board.get_height_steps(selected.cell)) / 2.0, selected.vitals.get_balance(), selected.get_stat(StatTypes.StatType.BALANCE_MAX), selected.move_points_left, selected.get_stat(StatTypes.StatType.MOVE_RANGE), selected.action_resources.get_main_left(), selected.action_resources.get_bonus_left(), selected.get_stat(StatTypes.StatType.ARMOR), selected.get_stat(StatTypes.StatType.STRENGTH) + selected.get_stat(StatTypes.StatType.WEAPON_DAMAGE), selected.get_stat(StatTypes.StatType.IMPACT_POWER)]
		if selected == session.units[1]: _stats.text += "\nАмулет: +2 HP после каждого полученного урона."
	_status.text = "Атака: щёлкните по цели. Расход — 1 основное действие." if attack_mode else "Движение: щёлкните по свободной клетке. Персонаж на поле или в списке — выбор."
	if session.context.is_faulted(): _status.text = "Исполнение остановлено из-за ошибки. Выполненные последствия сохранены; сбросьте бой."
	if locked: _status.text = _battle.phase_text() + (" · Можно начать заново: R." if _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN else " · Противник выполняет действия.")
	_hover(board_view.hover_cell)
	_log.text = "\n".join(_journal)

func _hover(cell: Vector2i) -> void:
	if not session.board.is_in_bounds(cell):
		_hint.text = "Числа на клетках — высота. Бирюзовые точки — доступное движение.\nПолоски: здоровье / накопленная потеря равновесия. ПКМ или Esc — движение."
		return
	var reachable := session.reachable_cells()
	var cost := " · путь: %.1f ОД" % float(reachable[cell]) if reachable.has(cell) else ""
	_hint.text = "%s · высота %+.1f%s\nЛиния показывает маршрут; последствия падений не предсказываются." % [_cell_name(cell), float(session.board.get_height_steps(cell)) / 2.0, cost]

func _show_receipt(receipt: ActionReceipt) -> void:
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
		message += ": " + _reason_text(receipt.reason)
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
		&"attacked": return "%s атакует %s." % [actor, target]
		&"damaged":
			var source: Dictionary = event.get("source", {})
			var cause := " от падения" if source.get("kind", &"") == &"fall" else ""
			return "%s: −%.1f HP%s." % [target, float(event.get("amount", 0)), cause]
		&"healed": return "%s: +%.1f HP от предмета." % [target, float(event.get("amount", 0))]
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
		&"attack/insufficient_main": return "основные действия закончились; выберите другого персонажа или завершите ход." if tactical_mode else "основные действия закончились; выберите другого персонажа или сбросьте бой."
		&"battle/input_locked": return "сейчас нельзя действовать."
		&"battle/friendly_target": return "выберите противника."
		&"move/insufficient_move": return "не хватает очков движения."
		&"attack/out_of_reach", &"attack/not_aligned": return "цель вне досягаемости прямого удара."
		&"move/unreachable": return "нет проходимого маршрута к этой клетке."
		&"move/no_selected_unit", &"attack/no_selected_unit": return "выберите живого персонажа."
		&"attack/self_target": return "нельзя атаковать самого себя."
	return String(reason)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A: set_attack_mode(true)
			KEY_M, KEY_ESCAPE: set_attack_mode(false)
			KEY_R: reset_demo()
			KEY_ENTER, KEY_KP_ENTER: end_turn()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		set_attack_mode(false)
