extends RefCounted
class_name BattleLegacyHud

var heading: Label
var mode_button: Button
var subtitle: Label
var phase_row: HBoxContainer
var phase_label: Label
var skip_presentation_button: Button
var speed_presentation_button: Button
var environment_button: Button
var mage_label: Label
var mage_row: HBoxContainer
var mage_buttons: Dictionary[StringName, Button] = {}
var mage_fire: Button
var mage_heal: Button
var move_button: Button
var attack_button: Button
var end_turn_button: Button
var board_view: BattleDemoBoard
var action_bar: BattleActionBar
var hint: Label
var roster: VBoxContainer
var stats: Label
var log_heading: Label
var log: RichTextLabel
var forecast_heading: Label
var forecast_panel: RichTextLabel
var status: Label
var instructions: Label

static func build(host: Control, board: BattleDemoBoard, handlers: Dictionary[StringName, Callable], tactical_mode: bool) -> BattleLegacyHud:
	var hud := BattleLegacyHud.new()
	var background := ColorRect.new()
	background.color = Color("111a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	host.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	var title := HBoxContainer.new()
	root.add_child(title)
	hud.heading = make_label("", 28, Color("e6ecf4"))
	hud.heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(hud.heading)
	hud.mode_button = make_button("")
	hud.mode_button.pressed.connect(handlers[&"toggle_scenario"])
	title.add_child(hud.mode_button)
	var expedition_button := make_button("Забег")
	expedition_button.pressed.connect(handlers[&"open_expedition"])
	title.add_child(expedition_button)
	var reset_button := make_button("Сбросить бой  ·  R")
	reset_button.pressed.connect(handlers[&"reset_demo"])
	title.add_child(reset_button)
	hud.subtitle = make_label("", 16, Color("a5b3c5"))
	root.add_child(hud.subtitle)
	hud.phase_label = make_label("", 20, Color("f7c97d"))
	hud.phase_row = HBoxContainer.new()
	root.add_child(hud.phase_row)
	hud.phase_row.add_child(hud.phase_label)
	hud.skip_presentation_button = make_button("Пропустить · Пробел")
	hud.skip_presentation_button.name = "SkipPresentationButton"
	hud.skip_presentation_button.pressed.connect(handlers[&"skip_presentation"])
	hud.phase_row.add_child(hud.skip_presentation_button)
	hud.skip_presentation_button.hide()
	hud.skip_presentation_button.disabled = true
	hud.speed_presentation_button = make_button("Скорость ×1")
	hud.speed_presentation_button.pressed.connect(handlers[&"toggle_presentation_speed"])
	hud.phase_row.add_child(hud.speed_presentation_button)
	hud.speed_presentation_button.hide()
	hud.environment_button = make_button("Окружение · прогноз фазы")
	hud.environment_button.focus_mode = Control.FOCUS_NONE
	hud.environment_button.pressed.connect(handlers[&"request_environment_forecast"])
	hud.phase_row.add_child(hud.environment_button)
	hud.mage_row = HBoxContainer.new()
	hud.mage_label = make_label("", 14, Color("65dfcc"))
	hud.phase_row.add_child(hud.mage_label)
	hud.mage_fire = make_button("Маг · Огонь 4 / 2 маны")
	hud.mage_fire.name = "MageFireButton"
	hud.mage_fire.pressed.connect(handlers[&"choose_elemental"].bind(&"mage.fire"))
	hud.mage_row.add_child(hud.mage_fire)
	hud.mage_heal = make_button("Маг · Лечение 4 / 3 маны")
	hud.mage_heal.name = "MageHealButton"
	hud.mage_heal.pressed.connect(handlers[&"choose_elemental"].bind(&"mage.heal"))
	hud.mage_row.add_child(hud.mage_heal)
	hud.mage_buttons = {&"mage.fire": hud.mage_fire, &"mage.heal": hud.mage_heal}
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	root.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(left)
	var toolbar := HBoxContainer.new()
	left.add_child(toolbar)
	hud.move_button = make_button("Выбор / движение  ·  M")
	hud.move_button.toggle_mode = true
	hud.move_button.pressed.connect(handlers[&"set_move_mode"])
	toolbar.add_child(hud.move_button)
	hud.attack_button = make_button("Атака  ·  A")
	hud.attack_button.toggle_mode = true
	hud.attack_button.pressed.connect(handlers[&"set_attack_mode"])
	toolbar.add_child(hud.attack_button)
	hud.end_turn_button = make_button("Завершить ход · Enter")
	# Enter имеет один обработчик: фокус кнопки иначе повторяет старт на отпускании.
	hud.end_turn_button.focus_mode = Control.FOCUS_NONE
	hud.end_turn_button.pressed.connect(handlers[&"end_turn"])
	toolbar.add_child(hud.end_turn_button)
	var combination_button := make_button("Сочетания ядра")
	combination_button.focus_mode = Control.FOCUS_NONE
	combination_button.pressed.connect(handlers[&"open_core_combination"])
	toolbar.add_child(combination_button)
	left.add_child(hud.mage_row)
	hud.board_view = board
	hud.board_view.forecast_wheel_handler = handlers[&"forecast_wheel"]
	hud.board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.board_view.cell_clicked.connect(handlers[&"handle_cell"])
	hud.board_view.cell_hovered.connect(handlers[&"hover"])
	hud.board_view.displayed_unit_hovered.connect(handlers[&"displayed_unit_hovered"])
	hud.board_view.cancel_requested.connect(handlers[&"set_move_mode"])
	hud.board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(hud.board_view)
	hud.action_bar = BattleActionBar.new()
	hud.action_bar.name = "BattleActionBar"
	hud.action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.action_bar.action_requested.connect(handlers[&"action_bar_requested"])
	hud.action_bar.action_hovered.connect(handlers[&"action_bar_hovered"])
	hud.action_bar.action_hover_left.connect(handlers[&"action_bar_hover_left"])
	hud.action_bar.visible = tactical_mode
	root.add_child(hud.action_bar)
	hud.hint = make_label("", 14, Color("a5b3c5"))
	hud.hint.custom_minimum_size.y = 40
	left.add_child(hud.hint)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 10)
	content.add_child(side)
	side.add_child(make_label("ПЕРСОНАЖИ", 13, Color("65dfcc")))
	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size.y = 192
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(roster_scroll)
	hud.roster = VBoxContainer.new()
	hud.roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(hud.roster)
	hud.stats = make_label("", 15, Color("e6ecf4"))
	hud.stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inspection_scroll := ScrollContainer.new()
	inspection_scroll.custom_minimum_size = Vector2(340, 144)
	inspection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspection_scroll.add_child(hud.stats)
	side.add_child(inspection_scroll)
	hud.log_heading = make_label("ЖУРНАЛ ПОСЛЕДСТВИЙ", 13, Color("65dfcc"))
	side.add_child(hud.log_heading)
	hud.log = RichTextLabel.new()
	hud.log.custom_minimum_size = Vector2(340, 130)
	hud.log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.log.scroll_following = true
	hud.log.add_theme_font_size_override("normal_font_size", 14)
	hud.log.add_theme_color_override("default_color", Color("c8d3e1"))
	side.add_child(hud.log)
	hud.forecast_heading = make_label("ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ", 13, Color("65dfcc"))
	side.add_child(hud.forecast_heading)
	hud.forecast_panel = RichTextLabel.new()
	hud.forecast_panel.custom_minimum_size = Vector2(340, 130)
	hud.forecast_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.forecast_panel.bbcode_enabled = true
	hud.forecast_panel.fit_content = false
	hud.forecast_panel.scroll_active = true
	hud.forecast_panel.add_theme_font_size_override("normal_font_size", 14)
	hud.forecast_panel.add_theme_color_override("default_color", Color("e6ecf4"))
	hud.forecast_panel.mouse_exited.connect(handlers[&"leave_forecast_panel"])
	side.add_child(hud.forecast_panel)
	hud.status = make_label("", 14, Color("f7c97d"))
	hud.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.status.custom_minimum_size.y = 46
	root.add_child(hud.status)
	hud.instructions = make_label("", 14, Color("a5b3c5"))
	root.add_child(hud.instructions)
	return hud

static func make_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func make_button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	for state_name: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("304a56") if state_name == "pressed" else (Color("344559") if state_name == "hover" else Color("243345"))
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state_name, style)
	return button
