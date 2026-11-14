extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB DASHBOARD: " + label)

func _run() -> void:
	var path := "user://hub-dashboard-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	var dashboard := hub.get_node("ExpeditionDashboard") as ExpeditionDashboard
	var tab := dashboard.find_child("TabExpedition", true, false) as Button
	tab.add_theme_font_size_override("font_size", 23)
	viewport.add_child(hub)
	await _settle()
	check(hub.run != null, "fresh profile loads")
	if hub.run == null:
		quit(1)
		return
	var baseline := hub.run.to_dict()
	var save_bytes := FileAccess.get_file_as_bytes(path)
	var cards := dashboard.find_child("HeroCards", true, false) as HubSquadList
	var card_rows := cards.get_node("Cards") as VBoxContainer
	var start := dashboard.find_child("StartJourney", true, false) as Button
	check(dashboard.is_visible_in_tree() and not hub.get_node("Panel").is_visible_in_tree(), "dashboard owns initial hub presentation")
	check(card_rows.get_child_count() == 3, "three persistent party slots")
	check(_label("DeckSummary").text == "Колода: 10 карт", "deck count comes from profile")
	check(_label("Gold").text.ends_with(str(hub.run.gold)), "wallet comes from profile")
	var card_id := card_rows.get_child(0).get_instance_id()
	for cycle: int in 4: hub._render()
	check(card_rows.get_child_count() == 3 and card_rows.get_child(0).get_instance_id() == card_id, "refresh preserves card instances")
	check(tab.get_theme_font_size("font_size") == 23, "refresh preserves authored override")
	check(start.get_signal_connection_list(&"pressed").size() == 1, "start has one connection")
	check(dashboard.start_requested.get_connections().size() == 1, "host has one launch connection")
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		for key: String in ["TabExpedition", "TabMercenaries", "TabSmith", "TabDeck", "PartyPanel", "Resources", "PreparationPanel", "StartJourney", "ManageParty"]:
			var control := dashboard.find_child(key, true, false) as Control
			check(bounds.grow(1.0).encloses(control.get_global_rect()), "%s fits %s" % [key, resolution])
		var left := (dashboard.find_child("LeftColumn", true, false) as Control).get_global_rect()
		var right := (dashboard.find_child("PreparationPanel", true, false) as Control).get_global_rect()
		check(left.end.x < right.position.x, "side panels leave diorama visible at %s" % resolution)
		await _capture("dashboard-%dx%d" % [resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()
	for key: String in ["TabMercenaries", "TabSmith", "TabDeck"]:
		await _press(key)
		check(not start.is_visible_in_tree(), key + " has no launch action")
		check((dashboard.find_child(key, true, false) as Button).button_pressed, key + " remains selected")
		await _capture(key)
	await _press("TabMercenaries")
	await _press("TabExpedition")
	await _press("ManageParty")
	var base_page := hub._page("BasePage")
	check(base_page.is_visible_in_tree() and not dashboard.is_visible_in_tree(), "management opens existing page")
	var base_id := base_page.get_instance_id()
	await _press("deck_edit")
	check(hub.deck_editing, "management opens deck draft")
	var draft := hub.deck_draft.duplicate()
	await _press("DashboardBack")
	check(dashboard.is_visible_in_tree() and start.disabled, "unsaved draft blocks dashboard launch")
	check(hub.deck_draft == draft and hub.deck_editing, "back retains draft")
	start.pressed.emit()
	check(hub.run.to_dict() == baseline, "disabled launch leaves profile unchanged")
	await _press("ManageParty")
	check(hub._page("BasePage").get_instance_id() == base_id, "management page identity survives navigation")
	await _press("deck_cancel")
	await _press("DashboardBack")
	check(not start.disabled, "cancel enables launch")
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == save_bytes, "navigation and refresh preserve state RNG and save bytes")

	# Меняем только копию для проверки отображения неполного/изменённого состава.
	var fixture := HeroHubState.from_dict(baseline)
	fixture.gold = 237
	fixture.essence = 11
	fixture.party.resize(1)
	var hero: HeroProgression = fixture.heroes[fixture.party[0]]
	hero.class_id = &"mage"
	hero.award_experience_tenths(6000)
	dashboard.render_profile(fixture, true, &"expedition", true, "Готово")
	check(_label("Gold").text.ends_with("237") and _label("Essence").text.ends_with("11"), "changed resources render")
	check(_label("PartyCount").text == "1", "partial party count renders")
	check(_label("Reserve").text.ends_with(str(fixture.heroes.size() - 1)), "living reserve updates after party change")
	check((card_rows.get_child(0).get_node("Identity") as Label).text == "Маг · ур. %d" % hero.level(), "class and level update")
	check((card_rows.get_child(0).get_node("Portrait") as TextureRect).texture != null, "mage has fallback portrait")
	check((card_rows.get_child(1).get_node("Portrait") as TextureRect).texture == null, "empty slot clears old portrait")
	await _capture("partial-party")
	fixture.party.clear()
	dashboard.render_profile(fixture, false, &"expedition", false, "Добавьте героя")
	check(start.disabled and _label("Route").text == "1 бой", "empty H1 disables launch and has correct route")
	check(_label("PreparationTitle").text == "Подготовка к бою", "H1 heading")
	hub._render()
	await _press("StartJourney")
	check(hub.run.phase == "expedition" and not dashboard.is_visible_in_tree(), "real launch leaves dashboard for existing expedition route")
	check(HeroHubStore.read_run(path).run.to_dict() == hub.run.to_dict(), "launch persisted by host")
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB DASHBOARD RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _label(key: String) -> Label:
	return hub.get_node("ExpeditionDashboard").find_child(key, true, false) as Label

func _settle() -> void:
	for unused: int in 4: await process_frame

func _press(key: String) -> void:
	var button := hub.find_child(key, true, false) as Button
	check(button != null and button.is_visible_in_tree() and not button.disabled, "usable button " + key)
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	var parent: Node = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await _settle()
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	viewport.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await _settle()

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
