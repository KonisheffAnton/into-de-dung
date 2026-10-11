extends SceneTree

const EXPECTED_PATH := "res://tests/fixtures/battle_mage_presenter_expected.json"

class ProbeDemo:
	extends BattleDemo
	var force_pending: bool = false
	var calls: Array[String] = []
	var override_text: bool = false

	func _create_session() -> void:
		_battle = session as BattleTacticalSession

	func is_execution_pending() -> bool:
		return force_pending or super.is_execution_pending()

	func _elemental_effect_label(id: StringName) -> String:
		calls.append("effect:" + String(id))
		return ("E:" if override_text else "") + super._elemental_effect_label(id)

	func _mage_spell_help(id: StringName) -> String:
		calls.append("help:" + String(id))
		return ("H:" if override_text else "") + super._mage_spell_help(id)

	func _reason_text(reason: StringName) -> String:
		calls.append("reason:" + String(reason))
		return ("R:" if override_text else "") + super._reason_text(reason)

var passed: int = 0
var failed: int = 0
var actual: Array[Dictionary] = []
var emit_path: String = ""
var demo: ProbeDemo
var toggles: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--emit-expected="):
			emit_path = argument.trim_prefix("--emit-expected=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE MAGE PRESENTER: " + label)

func _run() -> void:
	await _spells()
	await _deck()
	if not emit_path.is_empty():
		var file := FileAccess.open(emit_path, FileAccess.WRITE)
		check(file != null, "baseline output writable")
		if file != null: file.store_string(JSON.stringify(actual, "\t") + "\n")
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		check(expected is Array and expected.size() == actual.size(), "base case count")
		if expected is Array and expected.size() == actual.size():
			for index: int in actual.size():
				check(actual[index] == expected[index], "base " + String(actual[index].label))
	print("BATTLE MAGE PRESENTER RESULTS: %d passed, %d failed; %d cases" % [passed, failed, actual.size()])
	quit(0 if failed == 0 else 1)

func _open(session: BattleCoreReactionsSession) -> void:
	demo = ProbeDemo.new()
	demo.session = session
	demo.core_reactions_mode = true
	demo.deployment_enabled = false
	root.add_child(demo)
	demo.set_process(false)
	for button: Button in demo._card_buttons:
		button.toggled.connect(func(_value: bool) -> void: toggles += 1)

func _spells() -> void:
	var session := BattleCoreReactionsSession.new()
	_open(session)
	_record("spells/initial")
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()
	_record("spells/player")
	var ability := session.state.abilities
	ability.mana = 0
	_record("spells/no-mana")
	demo.override_text = true
	_record("spells/formatter-overrides")
	ability.mana = 6
	ability.definition(&"mage.fire").cooldown_turns = 1
	_record("spells/live-duration-without-revision")
	var bar := demo._mage_row as BattleMageBar
	bar.set_page(1)
	_record("spells/page-two")
	_record("spells/page-two-repeat")
	# Неизвестная кнопка проверяет старый путь definition == null без порчи runtime.
	var missing := Button.new()
	missing.name = "UnknownSpell"
	missing.tooltip_text = "Сохранённая подсказка"
	demo.add_child(missing)
	demo._mage_buttons[&"mage.missing"] = missing
	_record("spells/unknown-button")
	var plain := HBoxContainer.new()
	demo.add_child(plain)
	demo._mage_row = plain
	demo.board_view.authored_layout = false
	_record("spells/plain-row")
	var compact := demo._compact_inspection
	demo._compact_inspection = null
	_record("spells/plain-row-no-compact")
	demo._compact_inspection = compact
	demo._mage_row = bar
	_guard("spells")
	var original_session := demo.session
	demo.session = BattleTacticalSession.new()
	_record("spells/non-mage-session")
	demo.session = original_session
	session.state.abilities = null
	_record("spells/no-abilities")
	session.state.abilities = ability
	demo.queue_free()
	await process_frame

func _deck() -> void:
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var session := HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	_open(session)
	var deck := session.state.deck
	_record("deck/deploying")
	check(session.confirm_mage_deployment(), "fixture deployment confirmed")
	_record("deck/mulligan-none")
	demo._mulligan_ids.append(deck.hand_ids[0])
	_record("deck/mulligan-one")
	demo._mulligan_ids.append(deck.hand_ids[1])
	_record("deck/mulligan-two")
	check(session.confirm_mage_mulligan([]).status == ActionReceipt.APPLIED, "fixture mulligan confirmed")
	_record("deck/mulligan-done")
	check(session.start_battle(), "fixture battle started")
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	_record("deck/player-no-selection")
	demo._card_selected_id = deck.hand_ids[0]
	_record("deck/selected")
	session.state.abilities.mana = 0
	_record("deck/no-mana-replace-allowed")
	demo.override_text = true
	session.phase = BattleTacticalSession.Phase.ENEMY_TURN
	_record("deck/enemy-formatter-override")
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	deck.replaced_serial = session.state.abilities.serials[0]
	_record("deck/replacement-used")
	deck.replaced_serial = 0
	while deck.hand_ids.size() < 6:
		deck.hand_ids.append(deck.draw_ids.pop_front())
	_record("deck/six-cards")
	deck.draw_ids.append(deck.hand_ids.pop_back())
	_record("deck/shrinking-hand")
	while not deck.draw_ids.is_empty():
		deck.spent_ids.append(deck.draw_ids.pop_front())
	deck.spent_ids.sort()
	_record("deck/draw-empty")
	while not deck.hand_ids.is_empty():
		deck.spent_ids.append(deck.hand_ids.pop_back())
	deck.spent_ids.sort()
	_record("deck/empty-hand")
	_guard("deck")
	var before := _projection()
	session.state.deck = null
	demo._refresh_deck_bar(session)
	check(_projection() == before, "direct deck refresh with absent deck preserves HUD")
	session.state.deck = deck
	var ability := session.state.abilities
	session.state.abilities = null
	demo._refresh_deck_bar(session)
	check(_projection() == before, "direct deck refresh with absent abilities preserves HUD")
	session.state.abilities = ability
	demo.queue_free()
	await process_frame

func _guard(label: String) -> void:
	var saved := demo.session
	var before := _projection()
	demo.force_pending = true
	demo.session = null
	demo._refresh_mage()
	check(_projection() == before, label + " detached pending guard preserves HUD")
	demo.session = saved
	demo.force_pending = false

func _record(label: String) -> void:
	var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot
	check(before != null, label + " snapshot captured")
	if before == null: return
	var before_data := before.to_dict()
	var rng := demo.session.context.get_rng().to_dict()
	var selected: int = demo.session.selected_id
	var selected_card: int = demo._card_selected_id
	var toggles_before: int = toggles
	var mulligan := demo._mulligan_ids.duplicate()
	var nodes: Array[int] = []
	for button: Button in demo._card_buttons: nodes.append(button.get_instance_id())
	demo.calls.clear()
	demo._refresh_mage()
	var projection := _projection()
	projection["label"] = label
	projection["calls"] = demo.calls.duplicate()
	projection["toggled_events"] = toggles - toggles_before
	actual.append(JSON.parse_string(JSON.stringify(projection)))
	var after := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot
	check(after != null and after.to_dict() == before_data, label + " preserves full snapshot")
	check(demo.session.context.get_rng().to_dict() == rng and demo.session.selected_id == selected,
		label + " preserves RNG and hero selection")
	check(demo._card_selected_id == selected_card and demo._mulligan_ids == mulligan,
		label + " preserves card selection")
	var after_nodes: Array[int] = []
	for button: Button in demo._card_buttons: after_nodes.append(button.get_instance_id())
	check(nodes == after_nodes, label + " preserves button identities")

func _projection() -> Dictionary:
	var buttons: Array[Dictionary] = []
	for key: StringName in demo._mage_buttons:
		buttons.append(_button(demo._mage_buttons[key]))
	for button: Button in demo._card_buttons: buttons.append(_button(button))
	buttons.append(_button(demo._card_confirm_button))
	buttons.append(_button(demo._card_replace_button))
	var result := {"text": demo._mage_label.text, "tooltip": demo._mage_label.tooltip_text,
		"label_visible": demo._mage_label.visible, "row_visible": demo._mage_row.visible,
		"height": demo.board_view.custom_minimum_size.y, "buttons": buttons}
	if demo._mage_row is BattleMageBar:
		var bar := demo._mage_row as BattleMageBar
		var shown: Array[String] = []
		for button: Button in bar._buttons: shown.append(String(button.name))
		result["shown"] = shown
		result["page"] = bar.get_page()
		result["page_count"] = bar.get_page_count()
		result["paging_enabled"] = bar._paging_enabled
	return result

func _button(button: Button) -> Dictionary:
	return {"name": String(button.name), "text": button.text, "tooltip": button.tooltip_text,
		"disabled": button.disabled, "visible": button.visible, "toggle": button.toggle_mode,
		"pressed": button.button_pressed}
