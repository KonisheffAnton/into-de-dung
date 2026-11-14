extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var dashboard: ExpeditionDashboard
var squad: HubSquadList
var captures: String = ""
var path: String

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB APPROVED UI: " + label)

func _run() -> void:
	path = "user://hub-approved-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := HeroHubState.create(7414, 4)
	initial.enable_mage_deck()
	check(initial.hire(0), "reserve fixture uses real hire")
	check(HeroHubStore.write_run(path, initial).is_empty(), "initial profile saved")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await settle()
	dashboard = hub.get_node("ExpeditionDashboard") as ExpeditionDashboard
	squad = dashboard._hero_cards
	check(dashboard._section_pages[&"mercenaries"]._mercenary_mode == &"owned", "mercenaries initially shows own heroes")
	await test_reorder_picker()
	await test_save_barriers()
	await test_scaling_preparation()
	await test_features()
	await test_lifecycle()
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB APPROVED UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func test_reorder_picker() -> void:
	var before := hub.run.to_dict()
	var first := hub.run.party[0]
	var expected := hub.run.party.duplicate()
	var card := squad._cards.get_child(0) as HubSquadCard
	await drag(card, (squad._cards.get_child(2) as Control).get_global_rect().end - Vector2(20, 4))
	check(hub.run.party == [expected[1], expected[2], first], "native drag reorders first to last")
	check(not dashboard._picker.visible, "drag does not also open picker")
	var after := hub.run.to_dict()
	after["party"] = before["party"]
	check(after == before, "drag changes only party order")
	check_saved("drag")
	card = squad._cards.get_child(2) as HubSquadCard
	card.grab_focus()
	key(KEY_UP, true)
	await settle()
	check(hub.run.party[1] == first and viewport.gui_get_focus_owner() == squad._cards.get_child(1), "Alt Up reorders and follows moved card")
	check_saved("keyboard order")
	var unchanged := hub.run.to_dict()
	await click(squad._cards.get_child(0) as Button)
	check(dashboard._picker.is_visible_in_tree(), "card click opens own hero picker")
	await capture("party-picker")
	check(dashboard._picker._hero_cards.size() == hub.run.heroes.size(), "picker includes all living owned heroes")
	for candidate: HeroProgression in hub.run.candidates:
		check(not dashboard._picker._hero_cards.has(candidate.id), "picker excludes unowned candidate")
	key(KEY_TAB)
	await settle()
	check(dashboard._picker.is_ancestor_of(viewport.gui_get_focus_owner()), "picker traps keyboard focus")
	key(KEY_ESCAPE)
	await settle()
	check(not dashboard._picker.visible and hub.run.to_dict() == unchanged, "Escape cancels without mutation")
	check(viewport.gui_get_focus_owner() == squad._cards.get_child(0), "cancel restores squad focus")
	var reserve := 0
	for id: int in hub.run.heroes:
		if not hub.run.party.has(id): reserve = id; break
	await click(squad._cards.get_child(0) as Button)
	await click(dashboard._picker._hero_cards[reserve])
	check(hub.run.party[0] == reserve and not dashboard._picker.visible, "reserve choice replaces selected position")
	check_saved("picker replacement")
	expected = hub.run.party.duplicate()
	await click(squad._cards.get_child(0) as Button)
	await click(dashboard._picker._hero_cards[expected[2]])
	check(hub.run.party == [expected[2], expected[1], expected[0]], "choosing existing party member swaps positions")
	check_saved("picker swap")
	unchanged = hub.run.to_dict()
	await begin_drag(squad._cards.get_child(0) as HubSquadCard)
	key(KEY_ESCAPE)
	await settle()
	mouse_button(Vector2(400, 200), false)
	check(not viewport.gui_is_dragging() and hub.run.to_dict() == unchanged, "Escape cancels drag without save")
	await begin_drag(squad._cards.get_child(0) as HubSquadCard)
	motion(Vector2(600, 200), true)
	mouse_button(Vector2(600, 200), false)
	await settle()
	check(hub.run.to_dict() == unchanged and not dashboard._picker.visible, "drop outside list cancels without click")

func test_save_barriers() -> void:
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var expected := hub.run.party.duplicate()
	hub.save_path = path + "/blocked"
	hub._on_dashboard_party_move(expected[0], 2, expected)
	await settle()
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "failed order save leaves live profile and file unchanged")
	check(hub._pending_save != null and hub._page("ErrorPage").is_visible_in_tree(), "failed order save has retry barrier")
	var pending := hub._pending_save.to_dict()
	hub._on_dashboard_party_select(0, expected[1], expected)
	check(hub._pending_save.to_dict() == pending, "stale picker callback cannot replace pending transaction")
	hub.save_path = path
	hub._retry_save()
	await settle()
	check(hub._pending_save == null and hub.run.party == [expected[1], expected[2], expected[0]], "retry publishes exact pending order")
	check_saved("retry")
	before = hub.run.to_dict()
	hub._on_dashboard_party_move(expected[0], 0, expected)
	hub._on_dashboard_party_select(0, expected[1], expected)
	check(hub.run.to_dict() == before, "stale expected order rejects both actions")
	hub._on_hub_tab_requested(&"mercenaries")
	hub._on_dashboard_party_move(hub.run.party[0], 2, hub.run.party.duplicate())
	check(hub.run.to_dict() == before, "hidden squad callback rejected")
	hub._on_hub_tab_requested(&"expedition")
	await settle()

func test_scaling_preparation() -> void:
	var live := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var fixture := HeroHubState.from_dict(live)
	var sample: HeroProgression = fixture.heroes[fixture.party[0]]
	while fixture.party.size() < 6:
		var copy := HeroProgression.from_dict(sample.to_dict())
		copy.id = 800 + fixture.party.size()
		copy.name = "Герой %d" % copy.id
		fixture.heroes[copy.id] = copy
		fixture.party.append(copy.id)
	var six := fixture.party.duplicate()
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		for count: int in [3, 5, 6]:
			fixture.party.assign(six.slice(0, count))
			dashboard.render_profile(fixture, true, &"expedition", true, "Готово")
			await settle()
			check(squad._cards.get_child_count() == count, "%d cards at %s" % [count, resolution])
			var height := (squad._cards.get_child(0) as Control).size.y
			for child: Control in squad._cards.get_children(): check(is_equal_approx(child.size.y, height), "equal fixed card heights")
			var left := (dashboard.find_child("LeftColumn", true, false) as Control).get_global_rect()
			var center := dashboard._diorama.get_global_rect()
			var right := (dashboard.find_child("PreparationPanel", true, false) as Control).get_global_rect()
			check(left.end.x <= center.position.x and center.end.x <= right.position.x, "three columns do not overlap")
			check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(right), "preparation fits viewport")
			await capture("expedition-%d-%dx%d" % [count, resolution.x, resolution.y])
	viewport.size = Vector2i(1024, 720)
	dashboard.render_profile(fixture, true, &"expedition", true, "Готово")
	await settle()
	check(squad.get_v_scroll_bar().max_value > squad.size.y, "six cards scroll at minimum window")
	squad.scroll_vertical = 0
	await begin_drag(squad._cards.get_child(0) as HubSquadCard)
	var edge := squad.get_global_rect().end - Vector2(35, 5)
	motion(edge, true)
	await create_timer(0.7).timeout
	check(squad.scroll_vertical > 0 and squad._indicator_y >= 0.0, "native drag auto-scrolls at bottom edge with insertion marker")
	check(squad._insertion.visible, "insertion overlay is visible above cards")
	await capture("drag-edge-six")
	var scrolled := squad.scroll_vertical
	motion(squad.get_global_rect().position + Vector2(35, 5), true)
	await create_timer(0.45).timeout
	check(squad.scroll_vertical < scrolled, "native drag auto-scrolls back at top edge")
	key(KEY_ESCAPE)
	mouse_button(edge, false)
	await settle()
	fixture = HeroHubState.from_dict(live)
	dashboard.render_profile(fixture, true, &"expedition", true, "Готово")
	await settle()
	var button_rect := dashboard._start_button.get_global_rect()
	await capture("preparation-ready")
	var hero: HeroProgression = fixture.heroes[fixture.party[0]]
	hero.award_experience_tenths(6000)
	for id: int in fixture.items:
		var item: Dictionary = fixture.items[id]
		if int(item.hero_id) == hero.id and String(item.definition).begins_with("armor:"): item.remaining = 1.0
	dashboard.render_profile(fixture, true, &"expedition", true, "Готово")
	await settle()
	var state := (squad._cards.get_child(0).get_node("State") as Label).text
	check(state.contains("Броня") and state.contains("очк."), "armor and points coexist on one reserved card line")
	check(not dashboard._start_button.disabled and dashboard._warnings.get_child_count() >= 2, "warnings do not block departure")
	check(dashboard._start_button.get_global_rect() == button_rect, "warnings leave departure button fixed")
	await capture("preparation-warnings")
	dashboard.render_profile(fixture, true, &"expedition", false, "", true, [])
	await settle()
	check(dashboard._start_button.disabled and dashboard._fix_button.visible and dashboard._fix_button.text == "К колоде", "unfinished deck provides blocker and correction")
	check(dashboard._start_button.get_global_rect() == button_rect, "blocker leaves departure button fixed")
	check(dashboard._fix_button.get_global_rect().end.y <= button_rect.position.y, "fix appears above launch")
	await capture("preparation-blocked")
	check(hub.run.to_dict() == live and FileAccess.get_file_as_bytes(path) == bytes, "scaling and presentation fixtures never change profile or save")
	hub._render()
	await settle()
	await test_warning_routes()
	await test_empty_roster_route()

func test_empty_roster_route() -> void:
	var original := hub.run.to_dict()
	var fixture := HeroHubState.from_dict(original)
	fixture.party.clear()
	fixture.heroes.clear()
	for id: int in fixture.items: fixture.items[id].hero_id = 0
	hub._commit(fixture)
	await settle()
	check(dashboard._fix_button.text == "Нанять героя" and dashboard._start_button.disabled, "no owned heroes has actionable hire blocker")
	await click(dashboard._fix_button)
	await settle()
	var page := dashboard._section_pages[&"mercenaries"]
	check(hub._hub_tab == &"mercenaries" and page._mercenary_mode == &"hire" and (page._slot("mercenary_grid") as GridContainer).get_child_count() == fixture.candidates.size(), "empty-roster correction opens actual hire candidates")
	check(not dashboard._picker.visible, "empty roster never opens dead-end picker")
	hub._on_hub_tab_requested(&"expedition")
	hub._commit(HeroHubState.from_dict(original))
	await settle()

func test_warning_routes() -> void:
	var original := hub.run.to_dict()
	var fixture := HeroHubState.from_dict(original)
	var hero: HeroProgression = fixture.heroes[fixture.party[0]]
	hero.award_experience_tenths(6000)
	for id: int in fixture.items:
		var item: Dictionary = fixture.items[id]
		if int(item.hero_id) == hero.id and String(item.definition).begins_with("armor:"): item.remaining = 1.0
	hub._commit(fixture)
	await settle()
	var warning := dashboard._warnings.get_child(0) as Button
	await click(warning)
	var merc := dashboard._section_pages[&"mercenaries"]
	check(hub._hub_tab == &"mercenaries" and merc._selected_hero_id == hero.id and (merc._slot("development_panel") as Control).is_visible_in_tree(), "development warning opens correct owned hero development")
	merc._on_action("development_close")
	hub._on_hub_tab_requested(&"expedition")
	await settle()
	for child: Button in dashboard._warnings.get_children():
		if child.text.contains("броня"):
			await click(child)
			break
	check(hub._hub_tab == &"smith" and dashboard._section_pages[&"smith"]._selected_hero_id == hero.id, "armor warning selects correct hero at smith")
	hub._on_hub_tab_requested(&"expedition")
	hub._commit(HeroHubState.from_dict(original))
	await settle()

func test_features() -> void:
	hub._on_hub_tab_requested(&"mercenaries")
	await settle()
	var page := dashboard._section_pages[&"mercenaries"]
	await click(page._action_button("mercenaries_owned"))
	var live := hub.run.to_dict()
	var fixture := HeroHubState.from_dict(live)
	var hero: HeroProgression = fixture.heroes[fixture.party[0]]
	for class_id: StringName in [&"fighter", &"shieldbearer", &"rogue", &"archer", &"warrior", &"mage"]:
		hero.class_id = class_id
		hero.name = HeroCatalog.class_definition(class_id).display_name + " · осмотр"
		page._selected_hero_id = hero.id
		page.render_profile(fixture)
		await settle()
		var passive_row := page._slot("passive_icons") as Container
		var ability_row := page._slot("ability_icons") as Container
		check((page._slot("ability_group") as Control).visible == (ability_row.get_child_count() > 0), "empty ability group collapses")
		if class_id == &"warrior":
			check(ability_row.get_child_count() == 2, "legacy warrior lists only available stun and opportunity stance")
		check(passive_row.get_child_count() > 0, "innate perk icon for " + String(class_id))
		for row: Container in [passive_row, ability_row]:
			for node: HubFeatureIcon in row.get_children():
				check(node.icon != null and not node.accessibility_name.is_empty() and not node.accessibility_description.is_empty(), "feature has icon and accessible description")
				check(node.text.is_empty() and node.tooltip_text.is_empty(), "no permanent prose or duplicate native tooltip")
				check(node._passive == (row == passive_row), "passive and ability shapes distinguished")
				motion(node.get_global_rect().get_center())
				await settle()
				check(node._tooltip.visible and node._title_label.text == node.accessibility_name, "hover exposes feature title")
				check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(node._tooltip.get_global_rect()), "tooltip stays inside viewport")
				if class_id == &"mage" and node.accessibility_name == "Заморозить": await capture("mercenary-tooltip")
				key(KEY_ESCAPE)
				await settle()
				check(not node._tooltip.visible, "Escape dismisses feature")
		await capture("mercenary-" + String(class_id))
	var icon := (page._slot("passive_icons") as Container).get_child(0) as HubFeatureIcon
	motion(Vector2(10, 10))
	icon.grab_focus()
	await settle()
	check(icon._tooltip.visible, "keyboard focus opens feature description")
	await click(icon)
	check(icon._pinned, "tap pins description")
	await click(icon)
	check(not icon._tooltip.visible, "second tap dismisses description despite focus")
	await click(icon)
	mouse_button(Vector2(10, 10), true)
	mouse_button(Vector2(10, 10), false)
	await settle()
	check(not icon._tooltip.visible, "outside tap dismisses description")
	hub._on_hub_tab_requested(&"expedition")
	await settle()
	check(not icon._tooltip.visible and hub.run.to_dict() == live, "hidden page closes overlays and never alters profile")

func test_lifecycle() -> void:
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var diorama := dashboard._diorama
	diorama._on_motion_toggled(false)
	check(not diorama.is_processing(), "static diorama has no animation processing")
	var time := diorama._clock
	await settle()
	check(diorama._clock == time, "static clock stays frozen")
	diorama._on_motion_toggled(true)
	await settle()
	check(diorama._clock > time, "visible animated diorama advances")
	hub._on_hub_tab_requested(&"mercenaries")
	await settle()
	time = diorama._clock
	await settle()
	check(not diorama.is_processing() and diorama._clock == time, "hidden diorama stops animation")
	hub._on_hub_tab_requested(&"expedition")
	await settle()
	var nodes_before := get_node_count()
	for cycle: int in 500:
		hub._on_hub_tab_requested(&"expedition" if cycle % 2 == 0 else &"mercenaries")
		if cycle % 25 == 0: await settle()
	hub._on_hub_tab_requested(&"expedition")
	await settle()
	check(diorama._figures.get_child_count() == hub.run.party.size(), "500 switches keep one figure per hero")
	check(get_node_count() == nodes_before, "500 switches do not accumulate scene nodes")
	check(squad._cards.get_child(0).slot_selected.get_connections().size() == 1, "500 switches keep one card handler")
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "navigation and animation preserve RNG profile and save bytes")

func check_saved(label: String) -> void:
	var loaded := HeroHubStore.read_run(path).get("run") as HeroHubState
	check(loaded != null and loaded.to_dict() == hub.run.to_dict(), label + " survives reload")

func settle() -> void:
	for unused: int in 5: await process_frame

func key(code: Key, alt: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.alt_pressed = alt
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)

func motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = point - viewport.get_mouse_position()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	viewport.push_input(event, true)

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(event, true)

func click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "click target available")
	if button == null: return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await settle()
	var center := button.get_global_rect().get_center()
	motion(center)
	mouse_button(center, true)
	mouse_button(center, false)
	await settle()

func begin_drag(card: HubSquadCard) -> void:
	var point := card.get_global_rect().get_center()
	motion(point)
	mouse_button(point, true)
	motion(point + Vector2(0, 30), true)
	await settle()
	check(viewport.gui_is_dragging(), "native drag begins")

func drag(card: HubSquadCard, target: Vector2) -> void:
	await begin_drag(card)
	motion(target, true)
	await settle()
	mouse_button(target, false)
	await settle()

func capture(label: String) -> void:
	if captures.is_empty(): return
	await settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
