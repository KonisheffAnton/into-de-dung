extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var save_path: String = ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL HUB SCENE AUTHORING: " + label)

func _run() -> void:
	var menu_scene := load("res://scenes/demo/main_menu.tscn") as PackedScene
	var hub_scene := load("res://scenes/demo/hero_hub.tscn") as PackedScene
	check(menu_scene != null, "main menu scene loads")
	check(hub_scene != null, "hero hub scene loads")
	if menu_scene == null or hub_scene == null:
		await _finish()
		return

	var menu := menu_scene.instantiate() as Control
	var menu_button := menu.get_node_or_null(^"CenterContainer/VBoxContainer/continue_game") as Button
	check(menu_button != null, "main menu keeps its authored continue button")
	check(menu.get_node_or_null(^"CenterContainer/VBoxContainer/Title") is Label, "main menu keeps its authored title")
	menu.free()

	hub = hub_scene.instantiate() as HeroHubScreen
	check(hub != null, "hero hub scene instantiates")
	if hub == null:
		await _finish()
		return
	var panel := hub.get_node_or_null(^"Panel") as PanelContainer
	var header := hub.get_node_or_null(^"Panel/Column/Header") as HBoxContainer
	var hub_title := hub.get_node_or_null(^"Panel/Column/Header/HubTitle") as Label
	var base_page := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage") as VBoxContainer
	var base_deck := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage/Deck/BaseDeck") as VBoxContainer
	var deck_title := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage/Deck/BaseDeck/Title") as Label
	var footer_button := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage/Footer/Start") as Button
	var report_continue := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/ReportPage/continue_battle_report") as Button
	var service_heal := hub.get_node_or_null(^"Panel/Column/HeroHubScroll/Content/Pages/ExpeditionPage/Service/service_heal") as Button
	check(panel != null and header != null and hub_title != null, "authored Panel/Column/Header/HubTitle hierarchy exists")
	check(base_page != null and base_deck != null and deck_title != null, "authored BasePage/Deck/BaseDeck hierarchy exists")
	check(footer_button != null, "authored Footer/Start exists")
	check(report_continue != null, "authored ReportPage/continue_battle_report exists")
	check(service_heal != null, "authored ExpeditionPage/Service/service_heal exists")
	if panel == null or header == null or hub_title == null or base_page == null or base_deck == null or deck_title == null or footer_button == null or report_continue == null or service_heal == null:
		hub.free()
		await _finish()
		return

	# Проверяем, что overrides экземпляра проходят через _ready и последующие рендеры.
	header.add_theme_constant_override("separation", 37)
	base_page.add_theme_constant_override("separation", 29)
	deck_title.add_theme_font_size_override("font_size", 31)
	footer_button.custom_minimum_size.y = 63
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	save_path = "user://hub-scene-authoring-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	hub.save_path = save_path

	var authored_ids: Dictionary = {
		"Panel": panel.get_instance_id(),
		"Header": header.get_instance_id(),
		"HubTitle": hub_title.get_instance_id(),
		"BasePage": base_page.get_instance_id(),
		"BaseDeck": base_deck.get_instance_id(),
		"DeckTitle": deck_title.get_instance_id(),
		"FooterStart": footer_button.get_instance_id(),
		"ReportContinue": report_continue.get_instance_id(),
		"ServiceHeal": service_heal.get_instance_id()
	}
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(hub)
	await process_frame
	await process_frame
	check(hub.run != null and hub.run.phase == "hub", "runtime initializes an isolated hub profile")
	if hub.run == null:
		await _close_viewport()
		await _finish()
		return
	var baseline_run := JSON.stringify(hub.run.to_dict())
	check_authored(hub, authored_ids, false)
	check(hub.run.mage_deck.is_empty() == false, "deck mode enables the authored base deck")

	for cycle: int in 3:
		for render_index: int in 3:
			hub._render()
		check_authored(hub, authored_ids, false)
		check(hub.run != null and JSON.stringify(hub.run.to_dict()) == baseline_run, "render cycle %d leaves profile data unchanged" % cycle)
		var deck_edit := base_deck.get_node("deck_edit") as Button
		check(deck_edit.get_signal_connection_list(&"pressed").size() == 1, "deck edit has one handler before cycle %d" % cycle)
		deck_edit.pressed.emit()
		check(hub.deck_editing, "deck edit enters editor once in cycle %d" % cycle)
		check_authored(hub, authored_ids, true)
		check(base_deck.get_node("Editor/Cards").get_child_count() == 12, "edit cycle %d creates 12 card rows" % cycle)
		check(JSON.stringify(hub.run.to_dict()) == baseline_run, "editing leaves profile data unchanged in cycle %d" % cycle)
		for render_index: int in 3:
			hub._render()
			check_authored(hub, authored_ids, true)
			check(base_deck.get_node("Editor/Cards").get_child_count() == 12, "editing rerender %d:%d has no duplicate rows" % [cycle, render_index])
		var deck_cancel := base_deck.get_node("Editor/deck_cancel") as Button
		check(deck_cancel.get_signal_connection_list(&"pressed").size() == 1, "deck cancel has one handler before cycle %d" % cycle)
		deck_cancel.pressed.emit()
		check(not hub.deck_editing, "deck cancel exits editor once in cycle %d" % cycle)
		check_authored(hub, authored_ids, false)
		check(JSON.stringify(hub.run.to_dict()) == baseline_run, "cancel leaves profile data unchanged in cycle %d" % cycle)

	check(footer_button.name == "start_expedition", "footer action keeps its expedition identity")
	check(footer_button.get_signal_connection_list(&"pressed").size() == 1, "persistent expedition button has exactly one handler")
	hub._storage_error = "fixture"
	hub._render()
	var pages := hub.get_node(^"Panel/Column/HeroHubScroll/Content/Pages") as VBoxContainer
	var error_page := hub._page("ErrorPage")
	check(error_page.get_parent() == pages and base_page.get_parent() == null, "storage error attaches only its authored page")
	hub._storage_error = ""
	hub._render()
	check(base_page.get_parent() == pages and hub._page("ErrorPage").get_parent() == null, "clearing error reattaches the original base page")
	check_authored(hub, authored_ids, false)
	hub._render()
	(base_deck.get_node("deck_edit") as Button).pressed.emit()
	check_authored(hub, authored_ids, true)
	check(base_deck.get_node("Editor/Cards").get_child_count() == 12, "error-page detach preserves 12 unique rows after edit")
	check(JSON.stringify(hub.run.to_dict()) == baseline_run, "error detach and deck edit leave profile data unchanged")
	(base_deck.get_node("Editor/deck_cancel") as Button).pressed.emit()
	check_authored(hub, authored_ids, false)
	check(JSON.stringify(hub.run.to_dict()) == baseline_run, "final cancel leaves profile data unchanged")

	await _close_viewport()
	await _finish()

func check_authored(screen: HeroHubScreen, ids: Dictionary, editing: bool) -> void:
	var header := screen.get_node(^"Panel/Column/Header") as HBoxContainer
	var title := screen.get_node(^"Panel/Column/Header/HubTitle") as Label
	var base_page := screen._page("BasePage")
	var base_deck := screen.get_node(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage/Deck/BaseDeck") as VBoxContainer
	var deck_title := base_deck.get_node("Title") as Label
	var summary := base_deck.get_node("Summary") as Control
	var edit := base_deck.get_node("deck_edit") as Control
	var editor := base_deck.get_node("Editor") as Control
	var footer_button := screen.get_node(^"Panel/Column/HeroHubScroll/Content/Pages/BasePage/Footer").get_child(0) as Button
	check(header.get_instance_id() == int(ids["Header"]) and title.get_instance_id() == int(ids["HubTitle"]), "header nodes retain authored identity")
	check(base_page.get_instance_id() == int(ids["BasePage"]) and base_deck.get_instance_id() == int(ids["BaseDeck"]), "base page and deck retain authored identity")
	check(deck_title.get_instance_id() == int(ids["DeckTitle"]) and footer_button.get_instance_id() == int(ids["FooterStart"]), "deck title and footer retain authored identity")
	check(screen._page("ReportPage").get_node("continue_battle_report").get_instance_id() == int(ids["ReportContinue"]), "report control retains authored identity")
	check(screen._page("ExpeditionPage").get_node("Service/service_heal").get_instance_id() == int(ids["ServiceHeal"]), "expedition service retains authored identity")
	check(header.get_theme_constant("separation") == 37, "instance header separation survives rendering")
	check(base_page.get_theme_constant("separation") == 29, "instance page separation survives rendering")
	check(deck_title.get_theme_font_size("font_size") == 31, "instance deck title size survives rendering")
	check(footer_button.custom_minimum_size.y == 63, "instance footer button size survives rendering")
	check(base_deck.visible and summary.visible == (not editing) and edit.visible == (not editing) and editor.visible == editing, "deck authored visibility matches editor state")

func _close_viewport() -> void:
	if viewport != null:
		if hub != null and hub.get_parent() == viewport:
			viewport.remove_child(hub)
			hub.queue_free()
		viewport.queue_free()
		await process_frame
		await process_frame
	if not save_path.is_empty():
		_remove_save(save_path)
		_remove_save(save_path + ".bak")
		_remove_save(save_path + ".tmp")

func _remove_save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)

func _finish() -> void:
	print("HUB SCENE AUTHORING RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
