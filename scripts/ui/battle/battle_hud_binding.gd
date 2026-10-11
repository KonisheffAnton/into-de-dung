extends RefCounted
class_name BattleHudBinding

var heading: Label
var mode_button: Button
var subtitle: Label
var phase_row: HBoxContainer
var phase_label: Label
var skip_presentation_button: Button
var speed_presentation_button: Button
var environment_button: Button
var mage_label: Label
var mage_row: BattleMageBar
var mage_buttons: Dictionary[StringName, Button] = {}
var mage_fire: Button
var mage_heal: Button
var card_buttons: Array[Button] = []
var card_replace_button: Button
var card_confirm_button: Button
var move_button: Button
var attack_button: Button
var end_turn_button: Button
var board_view: BattleDemoBoard
var action_bar: BattleActionBar
var hint: Label
var compact_inspection: Label
var diagnostics_button: Button
var diagnostics: PanelContainer
var roster: VBoxContainer
var stats: Label
var log_heading: Label
var log: RichTextLabel
var forecast_heading: Label
var forecast_panel: RichTextLabel
var status: Label
var instructions: Label

static func bind(hud: Control, handlers: Dictionary[StringName, Callable], deck_layout: bool) -> BattleHudBinding:
	var binding := BattleHudBinding.new()
	var column := hud.get_node("Margin/Column") as VBoxContainer
	var title := column.get_node("Title") as HBoxContainer
	var left := column.get_node("Content/Left") as VBoxContainer
	var toolbar := left.get_node("Toolbar") as HBoxContainer
	var side := hud.get_node("BattleDiagnostics/Scroll/Side") as VBoxContainer
	var phase := column.get_node("Phase") as HBoxContainer
	var mage := column.get_node("MageBar") as BattleMageBar
	var deck_label := column.get_node("DeckSummary") as Label
	var legacy_label := phase.get_node("MageSummary") as Label

	binding.heading = title.get_node("Heading") as Label
	binding.mode_button = title.get_node("Mode") as Button
	binding.mode_button.pressed.connect(handlers[&"toggle_scenario"])
	(title.get_node("Expedition") as Button).pressed.connect(handlers[&"open_expedition"])
	(title.get_node("Reset") as Button).pressed.connect(handlers[&"reset_demo"])
	binding.subtitle = column.get_node("Subtitle") as Label
	binding.phase_row = phase
	binding.phase_label = phase.get_node("PhaseLabel") as Label
	binding.skip_presentation_button = phase.get_node("SkipPresentationButton") as Button
	binding.skip_presentation_button.pressed.connect(handlers[&"skip_presentation"])
	binding.speed_presentation_button = phase.get_node("Speed") as Button
	binding.speed_presentation_button.pressed.connect(handlers[&"toggle_presentation_speed"])
	binding.environment_button = phase.get_node("Environment") as Button
	binding.environment_button.pressed.connect(handlers[&"request_environment_forecast"])
	deck_label.visible = deck_layout
	legacy_label.visible = not deck_layout
	binding.mage_label = deck_label if deck_layout else legacy_label
	binding.mage_row = mage
	mage.page_changed.connect(handlers[&"mage_page_changed"])
	for child: Node in mage.get_node("Buttons").get_children():
		if child is Button and child.has_meta("spell_id"):
			var spell := StringName(child.get_meta("spell_id"))
			binding.mage_buttons[spell] = child as Button
			(child as Button).pressed.connect(handlers[&"choose_elemental"].bind(spell))
	binding.mage_fire = binding.mage_buttons[&"mage.fire"]
	binding.mage_heal = binding.mage_buttons[&"mage.heal"]
	for slot: int in 6:
		var card_button := mage.get_node("Buttons/MageCardSlot%d" % slot) as Button
		card_button.pressed.connect(handlers[&"choose_card_slot"].bind(slot))
		binding.card_buttons.append(card_button)
	binding.card_replace_button = mage.get_node("Buttons/MageCardReplaceButton") as Button
	binding.card_replace_button.pressed.connect(handlers[&"replace_selected_card"])
	binding.card_confirm_button = mage.get_node("Buttons/MageMulliganConfirmButton") as Button
	binding.card_confirm_button.pressed.connect(handlers[&"confirm_selected_mulligan"])
	binding.move_button = toolbar.get_node("Move") as Button
	binding.move_button.pressed.connect(handlers[&"set_move_mode"])
	binding.attack_button = toolbar.get_node("Attack") as Button
	binding.attack_button.pressed.connect(handlers[&"set_attack_mode"])
	binding.end_turn_button = toolbar.get_node("EndTurn") as Button
	binding.end_turn_button.pressed.connect(handlers[&"end_turn"])
	(toolbar.get_node("CompareTurnsButton") as Button).pressed.connect(handlers[&"open_initiative"])
	(toolbar.get_node("Combination") as Button).pressed.connect(handlers[&"open_core_combination"])
	binding.board_view = left.get_node("Field/Board") as BattleDemoBoard
	binding.board_view.forecast_wheel_handler = handlers[&"forecast_wheel"]
	binding.board_view.cell_clicked.connect(handlers[&"handle_cell"])
	binding.board_view.cell_hovered.connect(handlers[&"hover"])
	binding.board_view.displayed_unit_hovered.connect(handlers[&"displayed_unit_hovered"])
	binding.board_view.cancel_requested.connect(handlers[&"set_move_mode"])
	binding.action_bar = left.get_node("Field/BattleActionBar") as BattleActionBar
	binding.action_bar.action_requested.connect(handlers[&"action_bar_requested"])
	binding.action_bar.action_hovered.connect(handlers[&"action_bar_hovered"])
	binding.action_bar.action_hover_left.connect(handlers[&"action_bar_hover_left"])
	binding.hint = left.get_node("Hint") as Label
	binding.compact_inspection = left.get_node("Inspection") as Label
	binding.diagnostics_button = title.get_node("Diagnostics") as Button
	binding.diagnostics_button.toggled.connect(handlers[&"set_diagnostics_visible"])
	binding.diagnostics = hud.get_node("BattleDiagnostics") as PanelContainer
	binding.roster = side.get_node("RosterScroll/Roster") as VBoxContainer
	binding.stats = side.get_node("InspectionScroll/Stats") as Label
	binding.log_heading = side.get_node("LogHeading") as Label
	binding.log = side.get_node("Log") as RichTextLabel
	binding.forecast_heading = side.get_node("ForecastHeading") as Label
	binding.forecast_panel = side.get_node("Forecast") as RichTextLabel
	binding.forecast_panel.mouse_exited.connect(handlers[&"leave_forecast_panel"])
	binding.status = column.get_node("Status") as Label
	binding.instructions = column.get_node("Instructions") as Label
	return binding
