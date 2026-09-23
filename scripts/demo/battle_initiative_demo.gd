extends BattleDemo
class_name BattleInitiativeDemo

var _team_button: Button
var _individual_button: Button
var _order_label: RichTextLabel

func _create_session() -> void:
	tactical_mode = true
	session = BattleInitiativeSession.new()
	_battle = session as BattleTacticalSession
	_ai_delay = 0.0
	_flow_cursor = 0

func _build_ui() -> void:
	super._build_ui()
	# Строка очереди занимает место сверху; поле и прокрутки оставляют низ экрана видимым.
	board_view.custom_minimum_size.y = 410
	(_roster.get_parent() as ScrollContainer).custom_minimum_size.y = 144
	(_stats.get_parent() as ScrollContainer).custom_minimum_size.y = 120
	_log.custom_minimum_size.y = 110
	_forecast_panel.custom_minimum_size.y = 110
	# В эксперименте переключение меняет только порядок ходов одной и той же сцены.
	var title := _heading.get_parent()
	for child: Node in title.get_children():
		if child is Button and not (child as Button).text.begins_with("Сбросить"):
			(child as Button).hide()
	_team_button = _button("Командой")
	_team_button.toggle_mode = true
	_team_button.focus_mode = Control.FOCUS_NONE
	_team_button.pressed.connect(_switch_turns.bind(false))
	title.add_child(_team_button)
	_individual_button = _button("По инициативе")
	_individual_button.toggle_mode = true
	_individual_button.focus_mode = Control.FOCUS_NONE
	_individual_button.pressed.connect(_switch_turns.bind(true))
	title.add_child(_individual_button)
	var back := _button("К основному бою")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/demo/core_combination_battle.tscn"))
	title.add_child(back)
	var entry := find_child("CompareTurnsButton", true, false) as Button
	if entry != null: entry.hide()
	_order_label = RichTextLabel.new()
	_order_label.bbcode_enabled = true
	_order_label.fit_content = true
	_order_label.scroll_active = false
	_order_label.custom_minimum_size.y = 25
	_order_label.add_theme_font_size_override("normal_font_size", 16)
	var column := _phase_label.get_parent()
	column.add_child(_order_label)
	column.move_child(_order_label, _phase_label.get_index() + 1)
	# Enter всегда завершает ход, в том числе после клика по любой кнопке.
	_disable_button_focus(self)

func _disable_button_focus(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button: (child as Button).focus_mode = Control.FOCUS_NONE
		_disable_button_focus(child)

func _switch_turns(individual: bool) -> void:
	var battle := session as BattleInitiativeSession
	if battle.individual_turns == individual: return
	battle.individual_turns = individual
	reset_demo()
	_note("Новый бой по инициативе." if individual else "Новый бой командой: свободный порядок своих персонажей.")

func _refresh() -> void:
	super._refresh()
	var battle := session as BattleInitiativeSession
	if battle == null or _team_button == null: return
	var individual := battle.individual_turns
	_heading.text = "intoDeDung / Сравнение ходов"
	_subtitle.visible = true
	_subtitle.text = "Одинаковые карта, бойцы, вещи и ИИ. Смена режима начинает бой заново. Числа в очереди — инициатива."
	_team_button.set_pressed_no_signal(not individual)
	_individual_button.set_pressed_no_signal(individual)
	_team_button.tooltip_text = "Начать тот же бой командой. Сначала все свои, затем все враги."
	_individual_button.tooltip_text = "Начать тот же бой по инициативе: выше число — раньше ход. Один ход каждого за раунд."
	_order_label.text = _order_text(battle)
	_end_turn_button.text = "Завершить ход бойца · Enter" if individual else "Завершить ход команды · Enter"
	_instructions.text = "1 / A: атака · 2: защита · 3: лечение · 4: призыв · M: движение · Enter: конец хода · R: заново"
	if individual:
		var actor := battle.current_actor()
		for index: int in mini(_roster.get_child_count(), session.units.size()):
			var unit := session.units[index]
			var button := _roster.get_child(index) as Button
			button.text = ("▶ " if unit.id == battle.current_actor_id else "") + button.text
			if unit.faction == Faction.Type.PLAYER and unit.id != battle.current_actor_id:
				button.disabled = true
				button.tooltip_text = "Дождитесь очереди этого персонажа."
		if actor != null and battle.phase == BattleTacticalSession.Phase.ENEMY_TURN:
			_stats.text = _inspection_text(actor)
		elif battle.can_player_act() and not attack_mode and not summoning_mode and inspected_id == UnitId.NONE:
			_status.text = "Ходит %s. Выполните действия и нажмите Enter; остальные ждут своей очереди." % actor.debug_name
		for button: Button in _action_bar._buttons:
			button.tooltip_text = _individual_wording(button.tooltip_text)
	_disable_button_focus(_roster)

func _order_text(battle: BattleInitiativeSession) -> String:
	if not battle.individual_turns:
		return "[color=#65dfcc]Команда игрока[/color]  →  [color=#f29b9b]Команда противника[/color]  →  следующий раунд"
	var entries: Array[String] = []
	for index: int in battle.turn_order_ids.size():
		var unit := battle.board.get_unit_by_id(battle.turn_order_ids[index])
		if unit == null or not unit.is_alive(): continue
		var color := "65dfcc" if unit.faction == Faction.Type.PLAYER else "f29b9b"
		if index < battle.turn_index: color = "758293"
		var entry := "%s %d" % [unit.debug_name, int(unit.get_stat(StatTypes.StatType.INITIATIVE))]
		if unit.id == battle.current_actor_id: entry = "[b]▶ " + entry + "[/b]"
		entries.append("[color=#%s]%s[/color]" % [color, entry])
	return "  →  ".join(entries)

func _inspection_text(unit: UnitState) -> String:
	var result := super._inspection_text(unit)
	result += "\nИнициатива: %d" % int(unit.get_stat(StatTypes.StatType.INITIATIVE))
	return _individual_wording(result)

func _individual_wording(value: String) -> String:
	var battle := session as BattleInitiativeSession
	if battle == null or not battle.individual_turns: return value
	return value.replace("со следующего хода своей команды", "со следующего раунда, в свою очередь").replace("со следующего хода команды", "со следующего раунда, в свою очередь").replace("до следующего хода команды", "до следующего собственного хода")

func _event_text(event: Dictionary) -> String:
	return _individual_wording(super._event_text(event))

func _hover(cell: Vector2i) -> void:
	super._hover(cell)
	_hint.text = _individual_wording(_hint.text)

func _reason_text(reason: StringName) -> String:
	if reason == &"attack/insufficient_main" and session is BattleInitiativeSession and (session as BattleInitiativeSession).individual_turns:
		return "основные действия закончились; завершите ход этого персонажа."
	return super._reason_text(reason)
