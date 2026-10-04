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
		profile = ExpeditionTransitions.apply(profile, "choose", {"node": profile.expedition.available_nodes()[0]}).profile
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
	for repeat: int in 3:
		demo._build_ui()
		action._build()
		mage._build()
		demo._refresh()
		demo._render_presentation_hud(ActionPresentationState.capture(demo.session.state))
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
	check(action._buttons[0].pressed.get_connections().size() == 1 and mage._next_button.pressed.get_connections().size() == 1, "one handler after repeated component binding")
	check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before and demo.session.context.get_rng().to_dict() == rng, "layout binding and refresh preserve runtime and RNG")
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
