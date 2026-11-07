extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL BATTLE CHARACTER CARD: " + label)

func _settle() -> void:
	for index: int in 4: await process_frame

func _snapshot(demo: BattleDemo) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict(),
		"rng": demo.session.context.get_rng().to_dict(), "counters": demo.session.context.simulation_counters()}

func _capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

func _run() -> void:
	_test_resource_edges()
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	for hub: bool in [false, true]:
		await _exercise(hub)
	viewport.queue_free()
	await process_frame
	print("BATTLE CHARACTER CARD RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _exercise(hub: bool) -> void:
	var demo: BattleDemo
	if hub:
		var profile := HeroHubState.create(9404, 4)
		profile.enable_mage_deck()
		profile = ExpeditionTransitions.apply(profile, "start").profile
		var battle := (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
		var route := HeroHubScreen.new()
		check(route._configure_first_room_art(battle, profile), "production first-room art configured")
		route.free()
		battle.supplied_session = HeroHubBattleFactory.create(profile).session
		demo = battle
	else:
		demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
		demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.set_process(false)
	if hub:
		demo.end_turn()
		demo._confirm_selected_mulligan()
		var hub_session := demo.session as BattleCoreReactionsSession
		if hub_session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
			hub_session._enemy_index = hub_session._enemy_ids.size()
			hub_session.step_enemy()
		demo._refresh()
	else:
		PlayerTurnFixture.enter_player_turn(demo)
	await _settle()
	var board := demo.board_view
	var card := demo._character_card
	var session := demo.session as BattleCoreReactionsSession
	var actor := session.selected_unit()
	var enemy: UnitState
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.ENEMY and unit.is_alive(): enemy = unit; break
	check(card != null and not card.visible, "card starts closed")
	for dimensions: Vector2i in [Vector2i(1440, 1000), Vector2i(1280, 720)]:
		viewport.size = dimensions
		demo._close_character_card()
		await _settle()
		var rect := board.get_global_rect()
		var zoom := board.camera_view.zoom
		var offset := board.camera_view.offset
		var before := _snapshot(demo)
		demo.handle_cell(enemy.cell)
		await _settle()
		check(card.visible and card.name_label.text == enemy.debug_name, "ordinary enemy click opens its card")
		check(session.selected_id == actor.id and _snapshot(demo) == before, "inspection leaves selected ally, full state, RNG and counters intact")
		check(board.get_global_rect() == rect and board.camera_view.zoom == zoom and board.camera_view.offset == offset, "open keeps exact battlefield and camera")
		check(card.size.x == 300.0 and card.get_global_rect().end.x <= viewport.size.x - 20.0, "bounded right overlay")
		check(not card.get_global_rect().intersects(demo._mage_row.get_global_rect()), "card never covers bottom hand")
		check(card.get_global_rect().end.y <= viewport.size.y and card.size.y > 200.0, "card fits supported height")
		if not card.details_label.visible: card.details_button.pressed.emit()
		await _settle()
		check(board.get_global_rect() == rect and not card.get_global_rect().intersects(demo._mage_row.get_global_rect()), "expanded details scroll without shifting board or hand")
		demo._refresh_character_card()
		check(card.details_label.visible, "same target refresh preserves expanded details")
		var clicked: Array[Vector2i] = []
		var listener := func(cell: Vector2i) -> void: clicked.append(cell)
		board.cell_clicked.connect(listener)
		_click(card.get_global_rect().position + Vector2(5, 80))
		await _settle()
		check(clicked.is_empty() and _snapshot(demo) == before, "panel background blocks field clicks")
		board.cell_clicked.disconnect(listener)
		var wheel := InputEventMouseButton.new()
		wheel.position = card.get_global_rect().position + Vector2(100, 150)
		wheel.global_position = wheel.position
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		viewport.push_input(wheel, true)
		wheel.pressed = false
		viewport.push_input(wheel, true)
		await _settle()
		check(board.camera_view.zoom == zoom, "wheel inside card never zooms field")
		card.scroll_container.scroll_vertical = 0
		await _settle()
		await _capture(("hub" if hub else "main") + "-%d" % dimensions.y)
		_click(card.close_button.get_global_rect().get_center())
		await _settle()
		check(not card.visible and demo._character_card_id == UnitId.NONE and session.selected_id == actor.id, "close button only closes card")
		check(board.get_global_rect() == rect and _snapshot(demo) == before, "close preserves field and complete runtime")
	viewport.size = Vector2i(1440, 1000)
	demo.select_character(actor.id)
	await _settle()
	check(card.visible and demo._character_card_id == actor.id and not card.details_label.visible, "ally click selects and changes card with collapsed details")
	check((card.portrait_rect.texture != null) == session.actor_loadouts.has(actor.id), "portrait uses known class, explicit fallback otherwise")
	var data := BattleCharacterCardData.live(actor, session.state, session.actor_loadouts.get(actor.id, {}), demo._inspection_options(actor))
	check(data.hp_text.contains(BattleEventText.amount_text(actor.vitals.get_hp())), "current HP comes from runtime")
	check(data.balance_text == BattleBalanceDisplay.value_text(actor.vitals.get_balance(), ControlRules.balance_maximum(actor, actor.get_stat(StatTypes.StatType.BALANCE_MAX))), "balance displays remaining reserve")
	check(data.attributes_text.contains("Мощь") and data.attributes_text.contains("Мастерство") and not data.attributes_text.contains("Инициатива"), "five attributes without initiative")
	if hub:
		var count := 0
		for unit: UnitState in session.units:
			var unit_data := BattleCharacterCardData.live(unit, session.state, session.actor_loadouts.get(unit.id, {}), demo._inspection_options(unit))
			check(unit_data.portrait != null and unit_data.class_label != "Боец", "production class has name and portrait")
			count += 1
		check(count == 5, "five-class production roster preserved")
	await _capture("ally-" + ("hub" if hub else "main"))
	# Изменённый готовый кадр не должен читать будущий runtime или прежнюю live-строку.
	var state := ActionPresentationState.capture(session.state)
	state.units[actor.id].hp = 1.25
	state.units[actor.id].main = 0
	state.units[actor.id].elemental.burning_stacks = 3
	state.units[actor.id].elemental.burning_ticks = 2
	var before_frame := _snapshot(demo)
	demo.session = null
	demo._render_presentation_hud(state)
	check(card.hp_value.text.begins_with(BattleEventText.amount_text(1.25)) and card.actions_label.text.contains("Основное  0"), "detached publication uses only shown HP and actions")
	check(card.status_label.text.contains("стаки: 3") and card.status_label.text.contains("2 тиков"), "published status includes stacks and duration")
	check(card.attributes_label.text.contains("после действия"), "unpublished attributes do not leak future runtime")
	demo._close_character_card()
	demo._render_presentation_hud(state)
	check(not card.visible, "later frame does not reopen explicitly closed card")
	demo.session = session
	check(_snapshot(demo) == before_frame, "DTO publication preserves live state")
	demo._refresh()
	demo._open_character_card(enemy.id)
	demo.set_attack_mode(true)
	demo.handle_cell(enemy.cell)
	check(demo.is_execution_pending() or session.last_receipt != null, "explicit attack still dispatches action")
	var deadline := Time.get_ticks_msec() + 15000
	while demo.is_execution_pending() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): demo.skip_presentation()
		await process_frame
	check(not demo.is_execution_pending(), "attack finishes without card delay")
	demo._open_character_card(actor.id)
	demo._character_card_session = -1
	demo._refresh_character_card()
	check(not card.visible and demo._character_card_id == UnitId.NONE, "session replacement clears old inspection")
	demo.queue_free()
	await _settle()

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)

func _test_resource_edges() -> void:
	var row := {"id": 1, "hp": 2.5, "hp_max": 10.0, "alive": true,
		"armor": {"current": 6.0, "maximum": 0.0, "extra": 6.0}, "balance": 2.0, "balance_max": 5.0}
	var data := BattleCharacterCardData.frame(row, {})
	check(data.armor_text == "6 / 6  (+6 врем.)" and is_equal_approx(data.armor_ratio, 1.0), "temporary-only armor remains visible with finite capacity")
	row.armor = {"current": 8.0, "maximum": 10.0, "extra": 3.0}
	data = BattleCharacterCardData.frame(row, {})
	check(data.armor_text == "8 / 13  (+3 врем.)" and is_equal_approx(data.armor_ratio, 8.0 / 13.0), "mixed armor includes extra once in current and capacity")
	check(data.balance_text == "3/5", "balance reserve is maximum minus disruption")
	row.armor = {"current": 0.0, "maximum": 0.0, "extra": 0.0}
	row.balance_max = 0.0
	data = BattleCharacterCardData.frame(row, {})
	check(data.armor_ratio == 0.0 and data.balance_text == "невосприимчив", "zero armor and balance immunity remain explicit")
	check(data.status_text == "Состояний нет.", "empty states have one clear placeholder")
	for extra_state: Dictionary in [{"guard": true}, {"pending": true}, {"raised_shield": {"active": true}}, {"alive": false}]:
		var variant := row.duplicate(true)
		variant.merge(extra_state, true)
		data = BattleCharacterCardData.frame(variant, {})
		check(not data.status_text.contains("Состояний нет.") and not data.status_text.is_empty(), "active auxiliary state replaces empty placeholder")
