extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL BATTLE HUD AUTHORING: " + message)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _exercise(false)
	await _exercise(true)
	await _fallbacks()
	viewport.queue_free()
	await process_frame
	print("BATTLE HUD AUTHORING RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _exercise(deck_mode: bool) -> void:
	var path := "res://scenes/demo/battle/hero_hub_battle.tscn" if deck_mode else "res://scenes/demo/core_reactions_battle.tscn"
	var demo := (load(path) as PackedScene).instantiate() as BattleDemo
	if deck_mode:
		var profile := HeroHubState.create(9404)
		profile.enable_mage_deck()
		profile = ExpeditionTransitions.apply(profile, "start").profile
		var bundle := HeroHubBattleFactory.create(profile)
		(demo as HeroHubBattleView).supplied_session = bundle.session
	else:
		demo.deployment_enabled = false
	var hud := demo.get_node("BattleHUD") as Control
	var column := hud.get_node("Margin/Column") as VBoxContainer
	var action := column.get_node("Content/Left/Field/BattleActionBar") as BattleActionBar
	var board := column.get_node("Content/Left/Field/Board") as BattleDemoBoard
	var mage := column.get_node("MageBar") as BattleMageBar
	var card := mage.get_node("Buttons/MageCardSlot0") as Button
	var forecast := board.get_node("CompactForecast") as BattleForecastCard
	var end_turn := column.get_node("Content/Left/Toolbar/EndTurn") as Button
	var status := column.get_node("Status") as Label
	var roster := hud.get_node("BattleDiagnostics/Scroll/Side/RosterScroll/Roster") as VBoxContainer
	var reset_button := column.get_node("Title/Reset") as Button
	reset_button.text = "Авторская подпись сброса"
	var decoration := Label.new()
	decoration.name = "AuthorDecoration"
	decoration.text = "Проверка авторского узла"
	roster.add_child(decoration)
	var decoration_id := decoration.get_instance_id()
	var identities: Dictionary = {}
	_collect(hud, hud, identities)
	check(identities.size() > 70, "full authored descendants available before ready")
	column.add_theme_constant_override("separation", 7)
	action.custom_minimum_size.x = 169
	(action.get_node("Column/Slot1") as Button).add_theme_font_size_override("font_size", 14)
	card.custom_minimum_size.y = 69
	card.add_theme_font_size_override("font_size", 16)
	end_turn.custom_minimum_size.y = 41
	status.custom_minimum_size.y = 47
	board.custom_minimum_size.y = 355
	forecast.preferred_width = 315
	(forecast.get_node("Label") as Label).add_theme_font_size_override("font_size", 16)
	var forecast_style := forecast.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	forecast_style.content_margin_left = 17
	forecast.add_theme_stylebox_override("panel", forecast_style)
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()
	var rng := demo.session.context.get_rng().to_dict()
	var original_session := demo.session
	var original_frame := ActionPresentationState.capture(demo.session.state)
	var first_unit_id: int = int(original_frame.units.keys()[0])
	var first_button := _roster_button(demo, first_unit_id)
	check(first_button != null, "roster entry exists before repeated updates")
	var first_button_instance: int = first_button.get_instance_id() if is_instance_valid(first_button) else 0
	for repeat: int in 3:
		demo._build_ui()
		action._build()
		mage._build()
		demo._refresh()
		demo._render_presentation_hud(ActionPresentationState.capture(demo.session.state))
		demo._refresh()
	var retained_button := _roster_button(demo, first_unit_id)
	check(is_instance_valid(retained_button) and retained_button.get_instance_id() == first_button_instance, "roster entry identity survives refresh and presentation")
	var changed_frame := ActionPresentationState.capture(demo.session.state)
	var changed_row: Dictionary = changed_frame.units[first_unit_id].duplicate(true)
	changed_row.hp = maxf(0.0, float(changed_row.hp) - 1.0)
	changed_frame.units[first_unit_id] = changed_row
	demo.session = null
	demo._render_presentation_hud(changed_frame)
	var after_button := _roster_button(demo, first_unit_id)
	check(is_instance_valid(after_button) and after_button.get_instance_id() == first_button_instance and after_button.text.contains("HP %.1f" % changed_row.hp), "after frame reuses entry and renders copied HP without a live session")
	var inspected_before: int = demo.inspected_id
	var selected_before: int = original_session.selected_id
	after_button.pressed.emit()
	check(after_button.disabled and demo.inspected_id == inspected_before and original_session.selected_id == selected_before, "detached frame row callback cannot select or inspect live units")
	var reordered_frame: Dictionary = changed_frame.duplicate(true)
	var ordered_ids: Array = reordered_frame.units.keys()
	ordered_ids.reverse()
	reordered_frame.units = {}
	for unit_id: int in ordered_ids:
		reordered_frame.units[unit_id] = changed_frame.units[unit_id]
	demo._render_presentation_hud(reordered_frame)
	var visible_ids: Array[int] = []
	for child: Node in roster.get_children():
		if child.has_meta("runtime_roster_unit_id"):
			visible_ids.append(int(child.get_meta("runtime_roster_unit_id")))
	check(visible_ids == ordered_ids, "detached frame roster follows published order")
	check(_roster_button(demo, first_unit_id).get_instance_id() == first_button_instance and decoration.get_index() == 0, "reordering reuses rows after author decoration")
	demo.session = original_session
	demo._refresh()
	var added_frame := ActionPresentationState.capture(demo.session.state)
	var added_id: int = int(added_frame.units.keys().max()) + 1000
	var added_row: Dictionary = added_frame.units[first_unit_id].duplicate(true)
	added_row.id = added_id; added_row.name = "Проверка нового бойца"
	added_frame.units[added_id] = added_row
	demo._render_presentation_hud(added_frame)
	check(_roster_button(demo, added_id) != null, "presentation adds a new runtime roster entry")
	added_frame.units.erase(first_unit_id)
	demo._render_presentation_hud(added_frame)
	check(demo._roster_presenter.get_button(first_unit_id) == null and roster.get_children().all(func(node: Node) -> bool: return not node.has_meta("runtime_roster_unit_id") or int(node.get_meta("runtime_roster_unit_id")) != first_unit_id), "presentation removes absent runtime entry without removing author children")
	demo._refresh()
	for node_path: NodePath in identities:
		var node := hud.get_node_or_null(node_path)
		check(node != null and node.get_instance_id() == identities[node_path], "persistent authored node " + String(node_path))
	check(decoration.get_instance_id() == decoration_id and decoration.get_parent() == roster, "refresh retains author decoration in dynamic roster")
	check(column.get_theme_constant("separation") == 7, "root spacing override survives")
	check(action.custom_minimum_size.x == 169 and action._buttons[0].get_theme_font_size("font_size") == 14, "hero overrides survive")
	check(action._buttons.size() == 4, "repeated binding keeps four slots")
	check(card.custom_minimum_size.y == 69 and card.get_theme_font_size("font_size") == 16, "hand overrides survive")
	check(end_turn.custom_minimum_size.y == 41 and status.custom_minimum_size.y == 47 and board.custom_minimum_size.y == 355, "control status and board sizes survive refresh")
	check(end_turn.pressed.get_connections().size() == 1 and card.pressed.get_connections().size() == 1, "one gameplay handler per persistent button")
	var live_roster_button := _roster_button(demo, int(demo.session.units[0].id))
	check(is_instance_valid(live_roster_button) and live_roster_button.pressed.get_connections().size() == 1, "reused roster entry keeps one bound handler")
	if demo._battle != null and (demo._battle.can_player_act() or demo._is_deploying()):
		var saved_inspected_id: int = demo.inspected_id
		var enemy_id: int = UnitId.NONE
		for unit in demo.session.units:
			if unit.faction == Faction.Type.ENEMY and unit.is_alive(): enemy_id = unit.id; break
		if enemy_id != UnitId.NONE:
			var enemy_button := _roster_button(demo, enemy_id)
			if is_instance_valid(enemy_button):
				enemy_button.pressed.emit()
				check(demo.inspected_id == enemy_id, "roster signal dispatches through the current enemy inspection guard")
		demo.inspected_id = saved_inspected_id
		demo._refresh()
	check(action._buttons[0].pressed.get_connections().size() == 1 and mage._next_button.pressed.get_connections().size() == 1, "one handler after repeated component binding")
	check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before and demo.session.context.get_rng().to_dict() == rng, "layout binding and refresh preserve runtime and RNG")
	var current_roster_id: int = int(demo.session.units[0].id)
	var current_roster_button := _roster_button(demo, current_roster_id)
	var old_roster_instance: int = current_roster_button.get_instance_id() if is_instance_valid(current_roster_button) else 0
	var original_session_mode: bool = demo.core_reactions_mode
	var original_runtime_session := demo.session
	var replacement_session := BattleCoreReactionsSession.new()
	var replacement_roster_id: int = int(replacement_session.units[0].id)
	demo.session = replacement_session
	demo._battle = replacement_session as BattleTacticalSession
	board.session = replacement_session
	demo._refresh()
	var reset_session_button := _roster_button(demo, replacement_roster_id)
	check(demo._roster_presenter.get_button(current_roster_id) == null and is_instance_valid(reset_session_button) and reset_session_button.get_instance_id() != old_roster_instance, "new session retires old rows and binds fresh IDs")
	check(is_instance_valid(reset_session_button) and reset_session_button.pressed.get_connections().size() == 1, "new session roster row has one current handler")
	var stable_after_reset := _roster_button(demo, replacement_roster_id)
	demo.core_reactions_mode = not demo.core_reactions_mode
	demo._refresh()
	var alternate_mode_entry := _roster_button(demo, replacement_roster_id)
	var stable_reset_instance: int = stable_after_reset.get_instance_id() if is_instance_valid(stable_after_reset) else 0
	check(is_instance_valid(alternate_mode_entry) and alternate_mode_entry.get_instance_id() != stable_reset_instance, "roster rows reset when authored mode changes")
	demo.core_reactions_mode = original_session_mode
	demo.session = original_runtime_session
	demo._battle = original_runtime_session as BattleTacticalSession
	board.session = original_runtime_session
	replacement_session.close()
	demo._refresh()
	check(demo.core_reactions_mode == original_session_mode, "roster fixture restores authored mode")
	forecast.publish({"text": "Прогноз\nHP 20 → 16 · щит 6 → 2"}, Vector2i(3, 3), board)
	await process_frame
	check(is_equal_approx(forecast.size.x, 315) and forecast.label.get_theme_font_size("font_size") == 16, "forecast authored width and font survive publish")
	check(forecast.get_theme_stylebox("panel") == forecast_style and forecast_style.content_margin_left == 17, "forecast style override survives")
	check(demo._instructions.get_global_rect().end.y <= viewport.size.y, "authored override fixture fits viewport")
	if deck_mode:
		check(not reset_button.visible, "hub hides scenario controls by identity after author edits caption")
		check((demo as HeroHubBattleView)._return_button.pressed.get_connections().size() == 1, "hub return has one handler")
		check(demo._mage_label == column.get_node("DeckSummary"), "deck selects authored deck summary")
	else:
		check(demo._mage_label == column.get_node("Phase/MageSummary"), "legacy mage selects phase summary")
	await _capture("deck-authored" if deck_mode else "battle-authored")
	demo.set_diagnostics_visible(true)
	await process_frame
	await process_frame
	var diagnostics_rect := demo._diagnostics.get_global_rect()
	check(demo._diagnostics.is_visible_in_tree() and viewport.get_visible_rect().encloses(diagnostics_rect), "opened diagnostics stays inside viewport")
	check(diagnostics_rect.position.y == 104 and diagnostics_rect.size.x >= 340, "diagnostics uses right-wide authored anchors")
	check(demo._diagnostics.z_index > RenderLayers.z_index_for(RenderLayers.Layer.UI_PREVIEW) + 2, "diagnostics draws above board layers and compact forecast")
	await _capture("deck-diagnostics" if deck_mode else "battle-diagnostics")
	demo.queue_free()
	await process_frame

func _collect(node: Node, root_node: Node, identities: Dictionary) -> void:
	identities[root_node.get_path_to(node)] = node.get_instance_id()
	for child: Node in node.get_children(): _collect(child, root_node, identities)

func _roster_button(demo: BattleDemo, unit_id: int) -> Button:
	return demo._roster_presenter.get_button(unit_id)

func _fallbacks() -> void:
	var bar := BattleActionBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport.add_child(bar)
	bar._build()
	check(bar._buttons.size() == 8 and bar.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "legacy new retains eight slots and caller expansion")
	bar.queue_free()
	var mage := BattleMageBar.new()
	var button := Button.new()
	mage.add_child(button)
	viewport.add_child(mage)
	mage.configure([button])
	check(button.get_parent() == mage._button_row and button.visible, "new pager accepts children before ready")
	mage.queue_free()
	var demo := HeroHubBattleView.new()
	demo.supplied_session = PlayerTurnFixture.create()
	viewport.add_child(demo)
	demo.set_process(false)
	check(demo.has_node("BattleHUD") and demo.board_view != null and demo._return_button != null, "direct hub new loads same authored HUD")
	demo.queue_free()
	await process_frame

func _capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK, "capture " + name)
