extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var merc: HubSectionPage
var path: String
var captures: String = ""
var baseline: Dictionary
var hero_id: int

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB DEVELOPMENT: " + label)

func _run() -> void:
	path = "user://hub-development-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := HeroHubState.create(73191, 2)
	initial.enable_mage_deck()
	hero_id = initial.party[0]
	var hero: HeroProgression = initial.heroes[hero_id]
	hero.base_attributes = [10, 14, 9, 7, 10]
	hero.perk = &"force"
	hero.xp_tenths = 6035
	hero.hp_current = 21.5
	baseline = initial.to_dict()
	check(HeroHubStore.write_run(path, initial).is_empty(), "threshold fixture saved")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	await _load_hub()
	await _press_name("TabMercenaries")
	await _click(merc._action_button("mercenaries_hire"))
	var bytes := FileAccess.get_file_as_bytes(path)
	check(_button("open").disabled and not _panel().visible, "candidate cannot open development")
	_button("open").pressed.emit()
	check(not _panel().visible, "forced candidate open is inert")
	await _open_party()
	check(_text("progress").contains("603.5") and _text("progress").contains("4"), "fractional total XP and level displayed")
	check(_button("apply").disabled and merc._development.delta == [0, 0, 0, 0, 0], "empty draft cannot apply")
	check(_text("preview").replace(" ", "").contains("4→4") and _text("preview").replace(" ", "").contains("5→5"), "unchanged threshold pairs remain visible")
	await _check_sizes("overview")
	await _press("plus_1")
	await _press("plus_2")
	var preview := _text("preview").replace(" ", "")
	check(preview.contains("4→5") and preview.contains("5→5") and preview.contains("21.5→22.5"), "preview includes movement and fractional HP growth with unchanged base balance")
	await _press("plus_0")
	check(merc._development.delta == [1, 1, 1, 0, 0], "five-attribute draft uses exact indices")
	for index: int in 5: check(_button("plus_%d" % index).disabled, "budget disables all plus controls")
	_button("plus_4").pressed.emit()
	_button("minus_4").pressed.emit()
	check(merc._development.delta == [1, 1, 1, 0, 0], "forced plus and minus cannot exceed budget or go negative")
	await _check_sizes("preview")
	await _press_name("TabSmith")
	await _press_name("TabMercenaries")
	for cycle: int in 3: hub._render()
	check(_panel().is_visible_in_tree() and merc._development.delta == [1, 1, 1, 0, 0], "tab and refresh preserve local draft")
	check(_button("apply").pressed.get_connections().size() == 1 and merc.allocation_requested.get_connections().size() == 1, "refresh does not duplicate callbacks")
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == bytes, "preview navigation and render preserve complete profile RNG file")
	await _press("minus_0")
	check(merc._development.delta[0] == 0, "minus removes only planned point")
	await _press("cancel")
	check(_panel().visible and merc._development.delta == [0, 0, 0, 0, 0], "cancel clears preview and keeps panel open")
	await _press("plus_2")
	await _press("close")
	check(not _panel().visible and merc._development.delta == [0, 0, 0, 0, 0], "close cancels draft")
	await _press("open")
	await _press("plus_2")
	var expected_hero: Dictionary = (hub.run.heroes[hero_id] as HeroProgression).to_dict()
	var expected := HeroHubState.from_dict(baseline)
	var endurance: Array[int] = [0, 0, 1, 0, 0]
	check(expected.allocate(hero_id, endurance), "existing allocation expectation")
	hub.selected_hero_id = hero_id
	hub.pending_delta = [1, 0, 0, 0, 0]
	await _press("apply")
	check(hub.run.to_dict() == expected.to_dict(), "confirmation uses existing allocation exactly")
	check(hub.pending_delta == [0, 0, 0, 0, 0] and merc._development.delta == [0, 0, 0, 0, 0], "successful publication clears obsolete drafts in both views")
	check((hub.run.heroes[hero_id] as HeroProgression).available_points() == 2, "points remain to expose duplicate requests")
	bytes = FileAccess.get_file_as_bytes(path)
	merc.allocation_requested.emit(hero_id, expected_hero, endurance)
	hub._on_mercenary_allocation_requested(hero_id, expected_hero, endurance)
	check(hub.run.to_dict() == expected.to_dict() and FileAccess.get_file_as_bytes(path) == bytes, "stale repeated confirmation cannot spend another point")
	_check_saved("allocation")
	await _test_failure_retry()
	await _press("plus_0")
	await _press("apply")
	check((hub.run.heroes[hero_id] as HeroProgression).available_points() == 0, "all earned points can be spent")
	await _check_sizes("spent")
	await _test_guards()
	await _test_management_and_selection()
	await _test_reload_and_catalogs()
	await _test_large_budget()
	await _test_authoring()
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB DEVELOPMENT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_failure_retry() -> void:
	await _press("plus_1")
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var delta := merc._development.delta.duplicate()
	var source := merc._development.expected.duplicate(true)
	hub.pending_delta = [1, 0, 0, 0, 0]
	hub.save_path = path + "/blocked"
	await _press("apply")
	check(hub._pending_save != null and hub.run.to_dict() == before, "failed write keeps old published profile")
	check(hub._page("ErrorPage").is_visible_in_tree() and not merc.is_visible_in_tree(), "storage error has priority")
	check(merc._development.delta == delta and hub.pending_delta == [1, 0, 0, 0, 0], "failed write preserves both drafts until publish")
	var pending := hub._pending_save.to_dict()
	merc.allocation_requested.emit(hero_id, source, delta)
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	check(hub._pending_save.to_dict() == pending and FileAccess.get_file_as_bytes(path) == bytes, "failed request cannot replace candidate or old file")
	hub.save_path = path
	await _press_name("retry_save")
	check(hub.run.to_dict() == pending and hub._pending_save == null, "retry publishes same candidate once")
	check(_panel().is_visible_in_tree() and merc._development.target_hero_id == hero_id and merc._development.delta == [0, 0, 0, 0, 0], "retry returns to same hero and clears applied preview")
	check(hub.pending_delta == [0, 0, 0, 0, 0], "retry clears obsolete old-management draft")
	_check_saved("retry")

func _test_guards() -> void:
	_reset()
	await _open_party()
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	var source: Dictionary = (hub.run.heroes[hero_id] as HeroProgression).to_dict()
	var delta: Array[int] = [1, 0, 0, 0, 0]
	await _press_name("TabSmith")
	merc._on_action("development_plus_0")
	merc.allocation_requested.emit(hero_id, source, delta)
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	check(hub.run.to_dict() == before and merc._development.delta == [0, 0, 0, 0, 0], "inactive tab rejects page dashboard and host requests")
	await _press_name("TabMercenaries")
	await _press("close")
	await _press_name("TabExpedition")
	await _press_name("ManageParty")
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	check(hub.run.to_dict() == before, "old management blocks new development signal")
	await _press_name("DashboardBack")
	await _press_name("TabMercenaries")
	hub.run.phase = "battle"
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	hub.run.phase = "hub"
	hub.run.battle_report = {"open":true}
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	hub.run.battle_report = before.battle_report.duplicate(true)
	hub._storage_error = "test barrier"
	hub._on_mercenary_allocation_requested(hero_id, source, delta)
	hub._storage_error = ""
	hub._on_mercenary_allocation_requested(-1, source, delta)
	hub._on_mercenary_allocation_requested(hub.run.candidates[0].id, hub.run.candidates[0].to_dict(), delta)
	for invalid: Array in [[-1, 0, 0, 0, 0], [4, 0, 0, 0, 0], [0, 0, 0, 0, 0], [1]]:
		var typed_delta: Array[int] = []
		typed_delta.assign(invalid)
		hub._on_mercenary_allocation_requested(hero_id, source, typed_delta)
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "phase report storage IDs malformed and over-budget deltas do not save")
	await _open_party()
	(hub.run.heroes[hero_id] as HeroProgression).hp_current = 0.0
	hub._render()
	check(_button("apply").disabled and _button("plus_0").disabled, "dead target disables development")
	var dead: Dictionary = (hub.run.heroes[hero_id] as HeroProgression).to_dict()
	hub._on_mercenary_allocation_requested(hero_id, dead, delta)
	check(FileAccess.get_file_as_bytes(path) == bytes, "dead target never saved")
	_reset()
	await _open_party()
	var fixture := HeroHubState.from_dict(baseline)
	fixture.heroes.erase(hero_id)
	fixture.party.erase(hero_id)
	for item: Dictionary in fixture.items.values():
		if int(item.hero_id) == hero_id: item.hero_id = 0
	hub._commit(fixture)
	check(merc._development.target_hero_id == 0 and _button("apply").disabled, "removed target invalidates preview")
	_reset()

func _test_management_and_selection() -> void:
	await _open_party()
	await _press("plus_0")
	merc._on_selected("hero:%d" % hub.run.party[1])
	check(not _panel().visible and merc._development.delta == [0, 0, 0, 0, 0], "changing selected hero cancels bound draft")
	await _press("open")
	check(_button("plus_0").disabled and _button("apply").disabled, "level-one hero can inspect but cannot spend")
	await _press("close")
	await _open_party()
	await _press("plus_2")
	await _press_name("TabSmith")
	hub._open_hub_management()
	await _settle()
	await _press_name("deck_edit")
	var deck := hub.deck_draft.duplicate()
	hub._select_hero(hero_id)
	await _press_name("alloc_plus_1")
	check(hub.pending_delta == [0, 1, 0, 0, 0], "real old-management plus changes its draft")
	await _press_name("apply_allocation")
	await _press_name("DashboardBack")
	await _press_name("TabMercenaries")
	check(merc._development.delta == [0, 0, 0, 0, 0] and _panel().visible, "old-management allocation invalidates stale new preview")
	await _press("plus_0")
	await _press("apply")
	check(hub.deck_editing and hub.deck_draft == deck, "new allocation preserves mage deck draft")
	await _press("close")
	await _press_name("TabExpedition")
	await _press_name("ManageParty")
	await _press_name("deck_cancel")
	await _press_name("DashboardBack")
	await _press_name("TabMercenaries")
	_reset()

func _test_reload_and_catalogs() -> void:
	await _open_party()
	await _press("plus_2")
	await _press("apply")
	var before := hub.run.to_dict()
	viewport.remove_child(hub)
	hub.queue_free()
	await process_frame
	await _load_hub()
	check(hub.run.to_dict() == before, "reload preserves XP allocation and fractional HP")
	await _press_name("TabMercenaries")
	for catalog: int in [1, 2]:
		var fixture := HeroHubState.create(847, catalog)
		for hero: HeroProgression in fixture.heroes.values(): hero.xp_tenths = 1000
		hub._commit(fixture)
		var ids: Array = fixture.heroes.keys()
		ids.sort()
		for id: int in ids:
			merc._on_selected("hero:%d" % id)
			await _press("open")
			await _press("plus_4")
			var expected := HeroHubState.from_dict(hub.run.to_dict())
			var delta: Array[int] = [0, 0, 0, 0, 1]
			check(expected.allocate(id, delta), "catalog allocation expectation")
			if (hub.run.heroes[id] as HeroProgression).class_id == &"mage": check(_text("preview").to_lower().contains("огнен"), "mage preview identifies fire base")
			await _press("apply")
			check(hub.run.to_dict() == expected.to_dict(), "all classes both catalogs use existing rules")
			await _press("close")
		_check_saved("catalog")
	_reset()

func _test_large_budget() -> void:
	var fixture := HeroHubState.from_dict(baseline)
	(fixture.heroes[hero_id] as HeroProgression).xp_tenths = 21000
	hub._commit(fixture)
	await _open_party()
	for point: int in 6: await _press("plus_0")
	check(merc._development.delta[0] == 6 and _button("plus_0").disabled, "single attribute accepts more than five earned points")
	var expected := HeroHubState.from_dict(hub.run.to_dict())
	var delta: Array[int] = [6, 0, 0, 0, 0]
	check(expected.allocate(hero_id, delta), "large allocation expectation")
	await _press("apply")
	check(hub.run.to_dict() == expected.to_dict(), "large allocation follows existing uncapped progression")
	_reset()

func _test_authoring() -> void:
	await _open_party()
	var panel := _panel()
	var plus := _button("plus_0")
	var value := merc._slot("development_value_0") as Label
	var preview := merc._slot("development_preview") as Label
	var neighbor := merc.get_node("Roster") as Control
	var neighbor_rect := neighbor.get_global_rect()
	plus.name = "RenamedPlus"
	plus.reparent(merc, true)
	plus.position += Vector2(0, 2)
	plus.add_theme_font_size_override("font_size", 17)
	value.name = "RenamedValue"
	value.reparent(merc, true)
	var rect := plus.get_global_rect()
	for cycle: int in 3: hub._render()
	check(plus.get_global_rect() == rect and neighbor.get_global_rect() == neighbor_rect and plus.get_theme_font_size("font_size") == 17, "reparent position theme and neighbors survive refresh")
	check(plus.pressed.get_connections().size() == 1, "relocated plus retains one callback")
	await _click(plus)
	check(merc._development.delta[0] == 1 and value.text.contains("1"), "relocated field and button stay bound")
	plus.hide()
	hub._render()
	plus.pressed.emit()
	check(not plus.visible and merc._development.delta[0] == 1, "hidden plus stays hidden and inert")
	plus.show()
	_button("apply").free()
	var text_before := preview.text
	await _press("plus_2")
	check(preview.text != text_before, "preview updates without confirm button")
	value.free()
	await _click(plus)
	check(merc._development.delta[0] == 2, "editing survives removed value field")
	await _press("minus_2")
	check(not plus.disabled, "hidden-panel guard tested with remaining budget")
	panel.hide()
	hub._render()
	plus.pressed.emit()
	check(not panel.visible and merc._development.delta[0] == 2, "hidden panel is not restored and relocated action is inert")
	panel.free()
	hub._render()
	plus.pressed.emit()
	check(_panel() == null and _button("apply") == null and merc._slot("development_value_0") == null and _button("open").disabled, "removed module and fields are not recreated")
	check(hub.run.to_dict() == baseline, "authoring and draft changes do not mutate profile")

func _check_sizes(label: String) -> void:
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		var panel := _panel()
		var controls: Array[Control] = []
		for node: Node in panel.get_children():
			if node is Control and (node as Control).is_visible_in_tree(): controls.append(node as Control)
		for control: Control in controls: check(panel.get_global_rect().grow(1).encloses(control.get_global_rect()), "%s fits %s" % [control.name, resolution])
		for index: int in controls.size():
			for other: int in range(index + 1, controls.size()): check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s/%s do not overlap at %s" % [controls[index].name, controls[other].name, resolution])
		await _capture("%s-%dx%d" % [label, resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()

func _reset() -> void:
	hub._commit(HeroHubState.from_dict(baseline))
	check(hub._pending_save == null, "fixture publishes")

func _check_saved(label: String) -> void:
	var restored := HeroHubStore.read_run(path).get("run") as HeroHubState
	check(restored != null and restored.to_dict() == hub.run.to_dict(), label + " persists full profile")

func _load_hub() -> void:
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await _settle()
	merc = hub.get_node("ExpeditionDashboard/SectionPages/MercenariesPage") as HubSectionPage
	check(hub.run != null, "profile loads")

func _panel() -> Control:
	return merc._slot("development_panel") as Control

func _button(key: String) -> Button:
	return merc._action_button("development_" + key)

func _text(key: String) -> String:
	return (merc._slot("development_" + key) as Label).text

func _press(key: String) -> void:
	await _click(_button(key))

func _open_party() -> void:
	if _panel().visible: await _press("close")
	var owned_tab := merc._action_button("mercenaries_owned")
	if not owned_tab.button_pressed: await _click(owned_tab)
	var card := _card("hero:%d" % hero_id)
	await _click(card)
	await _press("open")
	check(_panel().is_visible_in_tree(), "development opens for owned hero")

func _card(selection_key: String) -> HubSkeletonCard:
	var grid := merc._slot("mercenary_grid") as GridContainer
	if grid == null: return null
	for child: Node in grid.get_children():
		if child is HubSkeletonCard and (child as HubSkeletonCard).selection_key == selection_key:
			return child as HubSkeletonCard
	return null

func _press_name(key: String) -> void:
	for node: Node in hub.find_children(key, "Button", true, false):
		if (node as Button).is_visible_in_tree():
			await _click(node as Button)
			return
	check(false, "visible button " + key)

func _click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "clickable control: " + (String(button.name) if button != null else "null"))
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	# После синхронного render контейнеры сначала должны получить размеры для прокрутки.
	await _settle()
	var parent: Node = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await _settle()
	var position := button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(position), "click center inside viewport: " + String(button.name))
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
