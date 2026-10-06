extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var save_path: String = ""
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
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
	check(menu.get_node_or_null(^"CenterContainer/VBoxContainer/TestProfileHint") is Label, "main menu authors its temporary profile explanation")
	menu.free()
	await _check_menu_profiles(menu_scene)

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

func _check_menu_profiles(scene: PackedScene) -> void:
	var legacy_path := "user://menu-profile-fixture-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var legacy := HeroHubState.create(4280)
	legacy.enable_mage_deck()
	legacy.gold = 432
	check(HeroHubStore.write_run(legacy_path, legacy).is_empty(), "persistent fixture is saved")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	for suffix: String in [".bak", ".tmp"]:
		_write_fixture(legacy_path + suffix, legacy_bytes)
	var menu_viewport := SubViewport.new()
	menu_viewport.size = Vector2i(1280, 850)
	menu_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(menu_viewport)
	menu_viewport.notify_mouse_entered()
	var first := scene.instantiate() as Control
	first.set("save_path", legacy_path)
	menu_viewport.add_child(first)
	await process_frame
	await process_frame
	var first_path := String(first.get("save_path"))
	check(bool(first.get("temporary_profile")) and first_path != legacy_path, "default menu isolates the existing save")
	check(not FileAccess.file_exists(first_path), "opening the menu alone does not create a profile")
	await _capture_menu(menu_viewport, "temporary-menu")
	var button := first.get_node(^"CenterContainer/VBoxContainer/continue_game") as Button
	var click := InputEventMouseButton.new()
	click.position = button.global_position + button.size * 0.5
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu_viewport.push_input(click, true)
	await process_frame
	click.pressed = false
	menu_viewport.push_input(click, true)
	await process_frame
	await process_frame
	var first_hub := first.get_node_or_null("ExpeditionHub") as HeroHubScreen
	check(first_hub != null and first_hub.run != null, "real menu click opens the temporary hub")
	if first_hub != null and first_hub.run != null:
		check(first_hub.run.phase == "hub" and not first_hub.run.mage_deck.is_empty() and first_hub.run.expedition == null, "temporary profile begins in the new deck hub")
		check(first_hub.run.gold != legacy.gold, "temporary hub does not continue persistent progress")
		first.call("_open_hub")
		check(first.get_child_count() == 1 and first.get_child(0) == first_hub, "duplicate activation preserves the same hub")
	check(FileAccess.file_exists(first_path), "temporary hub uses normal save transactions")
	await _capture_menu(menu_viewport, "temporary-hub")
	var second := scene.instantiate() as Control
	menu_viewport.add_child(second)
	var second_path := String(second.get("save_path"))
	check(second_path != first_path and second_path != legacy_path, "another launch gets a separate path even before exit")
	second.call("_open_hub")
	check(FileAccess.file_exists(second_path), "second temporary profile is independent")
	for suffix: String in [".bak", ".tmp"]:
		_write_fixture(first_path + suffix, legacy_bytes)
	first.free()
	for suffix: String in ["", ".bak", ".tmp"]:
		check(not FileAccess.file_exists(first_path + suffix), "exit removes owned temporary file " + suffix)
		check(FileAccess.get_file_as_bytes(legacy_path + suffix) == legacy_bytes, "exit preserves original profile file " + suffix)
	check(FileAccess.file_exists(second_path), "exit cannot delete another active test profile")
	second.free()
	check(not FileAccess.file_exists(second_path), "second profile cleans up on exit")
	# Остаток после принудительной остановки не должен стать продолжением следующего теста.
	_write_fixture(first_path, legacy_bytes)
	var restarted := scene.instantiate() as Control
	menu_viewport.add_child(restarted)
	check(String(restarted.get("save_path")) != first_path, "next launch ignores an abandoned temporary save")
	restarted.free()
	check(FileAccess.get_file_as_bytes(first_path) == legacy_bytes, "cleanup is limited to the owned launch")
	_remove_save(first_path)
	var persistent := scene.instantiate() as Control
	persistent.set("temporary_profile", false)
	persistent.set("save_path", legacy_path)
	menu_viewport.add_child(persistent)
	check(String(persistent.get("save_path")) == legacy_path, "opt-out honors the persistent save override")
	var persistent_button := persistent.get_node(^"CenterContainer/VBoxContainer/continue_game") as Button
	check(persistent_button.text.begins_with("Продолжить"), "persistent mode describes continuation")
	persistent.call("_open_hub")
	var loaded_hub := persistent.get_node_or_null("ExpeditionHub") as HeroHubScreen
	check(loaded_hub != null and loaded_hub.run != null and loaded_hub.run.gold == legacy.gold, "persistent mode restores the saved progress")
	persistent.free()
	for suffix: String in ["", ".bak", ".tmp"]:
		check(FileAccess.get_file_as_bytes(legacy_path + suffix) == legacy_bytes, "persistent mode leaves save bytes untouched " + suffix)
		_remove_save(legacy_path + suffix)
	menu_viewport.queue_free()
	await process_frame
	await process_frame

func _write_fixture(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture file opens")
	if file != null:
		file.store_buffer(bytes)
		file.close()

func _capture_menu(target: SubViewport, label: String) -> void:
	if captures.is_empty(): return
	for unused: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(target.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)

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
