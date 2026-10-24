extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var captures: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB SECTIONS: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	var path := "user://hub-sections-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await _settle()
	var baseline := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var merc := hub.get_node("ExpeditionDashboard/SectionPages/MercenariesPage") as HubSectionPage
	var smith := hub.get_node("ExpeditionDashboard/SectionPages/SmithPage") as HubSectionPage
	var schools := hub.get_node("ExpeditionDashboard/SectionPages/SchoolsPage") as HubSectionPage
	var pages: Array[HubSectionPage] = [merc, smith, schools]
	var tabs: Array[String] = ["TabMercenaries", "TabSmith", "TabSchools"]
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		for index: int in pages.size():
			await _press_name(tabs[index])
			var page := pages[index]
			check(page.is_visible_in_tree(), tabs[index] + " opens its scene")
			for other: HubSectionPage in pages:
				if other != page: check(not other.is_visible_in_tree(), "other section hidden")
			var bounds := Rect2(Vector2.ZERO, Vector2(resolution)).grow(1.0)
			for node: Node in page.find_children("*", "Control", true, false):
				var control := node as Control
				if control.is_visible_in_tree():
					check(bounds.encloses(control.get_global_rect()), "%s/%s fits %s" % [page.name, control.name, resolution])
			check(page.find_children("*", "Container", true, false).is_empty(), "section free positioning has no layout containers")
			await _capture("%s-%dx%d" % [page.section_id, resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()
	await _press_name("TabMercenaries")
	var candidate := merc._slot("candidate_1") as HubSkeletonCard
	await _click(candidate)
	check(merc._selected_hero_id == hub.run.candidates[1].id, "candidate click updates local detail selection")
	check((merc._slot("hero_title") as Label).text == hub.run.candidates[1].name, "detail comes from selected candidate")
	await _press_name("ManageMercenaries")
	check(hub._page("BasePage").is_visible_in_tree(), "mercenaries retains management route")
	await _press_name("DashboardBack")
	await _press_name("TabSmith")
	var selected_item := smith._slot("item_1") as HubSkeletonCard
	var item_id := int(selected_item.selection_key.get_slice(":", 1))
	await _click(selected_item)
	check(smith._selected_item_id == item_id, "item click updates local detail selection")
	var definition := HeroGearCatalog.definition(hub.run.items[item_id].definition)
	check((smith._slot("item_title") as Label).text == definition.display_name, "item detail uses existing catalog")
	await _click(_action(smith, "items_next"))
	check(smith._items_page == 1, "inventory pagination reaches remaining real items")
	check((smith._slot("item_0") as HubSkeletonCard).selection_key != "", "next page has real item")
	await _click(_action(smith, "items_prev"))
	await _press_name("ManageEquipment")
	check(hub._page("BasePage").is_visible_in_tree(), "smith retains existing equipment route")
	await _press_name("DashboardBack")
	await _press_name("TabSchools")
	await _click(_action(schools, "school_2"))
	await _click(_action(schools, "skill_4"))
	check(schools._school_index == 2 and schools._skill_index == 4, "school nodes change local preview only")
	check((schools._slot("skill_title") as Label).text == "Узел 5", "selected node detail")
	for page: HubSectionPage in pages:
		for cycle: int in 3: page.render_profile(hub.run)
		for node: Node in page.find_children("*", "Button", true, false):
			var button := node as Button
			if node.has_meta(&"hub_action") or node is HubSkeletonCard:
				check(button.pressed.get_connections().size() == 1, "one action connection: " + String(node.name))
		for node: Node in page.get_children():
			if node is Control: check(not node.get_parent() is Container, "module freely positioned")
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == bytes, "navigation selection pagination preserve profile RNG and save bytes")
	await _test_profile_boundaries(merc, smith, baseline)
	await _test_independence(merc, smith, schools)
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == bytes, "authoring changes preserve game state and save bytes")
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB SECTIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_profile_boundaries(merc: HubSectionPage, smith: HubSectionPage, baseline: Dictionary) -> void:
	# Меняется только копия: проверяем повторный показ после изменения состава/склада.
	var fixture := HeroHubState.from_dict(baseline)
	await _press_name("TabMercenaries")
	fixture.party.resize(1)
	merc.render_profile(fixture)
	check((merc._slot("party_count") as Label).text == "1/3", "partial party renders")
	check((merc._slot("party_1") as HubSkeletonCard).disabled, "empty party slot clears previous hero")
	fixture.party.clear()
	merc.render_profile(fixture)
	var reserve := merc._reserve_ids()
	check(reserve.size() > HubSectionPage.RESERVE_PAGE_SIZE, "fixture has multiple reserve pages")
	await _click(_action(merc, "reserve_next"))
	check(merc._reserve_page == 1, "reserve next reaches second page")
	var last := merc._slot("reserve_0") as HubSkeletonCard
	check(last.selection_key == "hero:%d" % reserve[3], "second reserve page binds remaining hero")
	await _click(last)
	check((merc._slot("hero_title") as Label).text == fixture.heroes[reserve[3]].name, "reserve click updates details")
	fixture.party.append(reserve[0])
	merc.render_profile(fixture)
	check(merc._reserve_page == 0 and _action(merc, "reserve_next").disabled, "shrinking reserve clamps page and navigation")
	fixture.party.clear()
	fixture.heroes.clear()
	fixture.candidates.clear()
	merc.render_profile(fixture)
	check((merc._slot("party_count") as Label).text == "0/3", "empty party renders")
	check((merc._slot("hero_portrait") as TextureRect).texture == null and (merc._slot("hero_detail") as Label).text == "Нет доступных героев", "empty roster clears stale detail and portrait")
	check((merc._slot("candidate_0") as HubSkeletonCard).disabled and (merc._slot("reserve_0") as HubSkeletonCard).disabled, "empty candidates and reserve clear stale slots")
	merc.render_profile(hub.run)
	await _press_name("TabSmith")
	fixture.items.clear()
	smith.render_profile(fixture)
	check((smith._slot("item_detail") as Label).text == "Склад пуст", "empty inventory clears selected item detail")
	check((smith._slot("item_0") as HubSkeletonCard).disabled and _action(smith, "items_next").disabled, "empty inventory clears cards and navigation")
	smith.render_profile(hub.run)

func _test_independence(merc: HubSectionPage, smith: HubSectionPage, schools: HubSectionPage) -> void:
	await _press_name("TabMercenaries")
	var candidates := merc.get_node("Candidates") as Control
	var squad := merc.get_node("Squad") as Control
	var untouched_rect := squad.get_global_rect()
	var untouched_id := squad.get_instance_id()
	candidates.position += Vector2(8, 6)
	var moved := candidates.position
	candidates.name = "MovedCandidates"
	var count := merc._slot("candidate_count") as Label
	count.reparent(merc, true)
	count.name = "RelocatedHeading"
	var title_position := count.position
	count.add_theme_color_override("font_color", Color.REBECCA_PURPLE)
	var card := merc._slot("candidate_0") as HubSkeletonCard
	card.position += Vector2(5, 3)
	var card_position := card.position
	var title := card.get_node("Title") as Label
	title.position += Vector2(2, 4)
	var field_position := title.position
	for cycle: int in 3: merc.render_profile(hub.run)
	check(candidates.position == moved and card.position == card_position and title.position == field_position, "refresh preserves independent panel card and text positions")
	check(count.position == title_position and count.text.contains(str(hub.run.candidates.size())), "binding survives rename and reparent")
	check(count.get_theme_color("font_color") == Color.REBECCA_PURPLE, "custom authored style preserved")
	check(squad.get_instance_id() == untouched_id and squad.get_global_rect() == untouched_rect, "moving one module leaves sibling identity and layout unchanged")
	candidates.hide()
	merc.render_profile(hub.run)
	check(not candidates.visible and squad.visible, "hidden module remains hidden independently")
	candidates.show()
	title.free()
	merc.render_profile(hub.run)
	check(not card.has_node("Title"), "deleted card field is not recreated")
	card.free()
	merc.render_profile(hub.run)
	check(merc._slot("candidate_0") == null, "deleted card slot is not recreated")
	candidates.free()
	merc.render_profile(hub.run)
	check(not merc.has_node("MovedCandidates") and squad.get_global_rect() == untouched_rect, "deleted module does not move neighbors")
	await _press_name("TabSmith")
	var materials := smith.get_node("Materials") as Control
	materials.hide()
	var details := smith._slot("item_title") as Label
	details.name = "RenamedItemTitle"
	var item_count := smith._slot("item_count") as Label
	item_count.free()
	smith.render_profile(hub.run)
	check(not materials.visible and smith._slot("item_count") == null, "smith hidden panel and removed label survive refresh")
	check(not details.text.is_empty(), "renamed item binding still updates")
	await _press_name("TabSchools")
	var tree := schools.get_node("SchoolTree") as Control
	var skill := _action(schools, "skill_3")
	var link := tree.get_node("Link0") as Line2D
	var points_before := link.points.duplicate()
	var other := _action(schools, "skill_2")
	var other_position := other.position
	skill.position += Vector2(13, 7)
	skill.name = "MovedSkill"
	await _settle()
	check(link.points != points_before and other.position == other_position, "independent link follows moved node without moving neighbors")
	skill.reparent(schools, true)
	await _settle()
	check(link.points.size() == 2 and link.points[1].is_equal_approx(link.to_local(skill.get_global_rect().get_center())), "link binding survives endpoint reparent within page")
	skill.free()
	schools.render_profile(hub.run)
	await _settle()
	check(link.points.is_empty(), "link safely clears when endpoint is removed")
	check(_action(schools, "skill_3") == null, "removed school node is not recreated")
	await _press_name("TabMercenaries")
	check(merc._slot("candidate_0") == null and squad.get_instance_id() == untouched_id, "tab navigation preserves authored deletion and sibling instances")

func _action(page: HubSectionPage, key: String) -> Button:
	for node: Node in page.find_children("*", "Button", true, false):
		if String(node.get_meta(&"hub_action", "")) == key: return node as Button
	return null

func _press_name(key: String) -> void:
	for node: Node in hub.find_children(key, "Button", true, false):
		if (node as Button).is_visible_in_tree():
			await _click(node as Button)
			return
	check(false, "visible button " + key)

func _click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "clickable control")
	if button == null or not button.is_visible_in_tree() or button.disabled: return
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

func _settle() -> void:
	for unused: int in 4: await process_frame

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
