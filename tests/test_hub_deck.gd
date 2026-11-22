extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var page: HubDeckPage
var path: String
var captures: String = ""
var baseline: Dictionary

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB DECK: " + label)

func _run() -> void:
	path = "user://hub-deck-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := HeroHubState.create(73191, 2)
	initial.enable_mage_deck()
	baseline = initial.to_dict()
	check(HeroHubStore.write_run(path, initial).is_empty(), "fixture saved")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	await _load_hub()
	await _press_name("TabDeck")
	check(page.is_visible_in_tree() and not hub.deck_editing, "separate tab opens read-only deck")
	check(not _button("edit").disabled and _button("save").disabled and _button("plus").disabled, "overview cannot mutate deck")
	var bytes := FileAccess.get_file_as_bytes(path)
	for card: MageCardDefinition in MageCardCatalog.all():
		await _select(card.id)
		check(_text("deck_selected_title") == card.name and _text("deck_selected_description") == card.description, "catalog definition shown: " + card.id)
		check(_text("deck_selected_mana").contains(str(card.mana_cost)), "mana shown: " + card.id)
	await _select("card.poison")
	await _check_sizes("overview")
	for cycle: int in 3: hub._render()
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == bytes, "selection pagination refresh preserve complete profile RNG file")
	check(_button("edit").pressed.get_connections().size() == 1 and page.action_requested.get_connections().size() == 1, "no duplicate handlers")
	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	check(hub.deck_draft.size() == 9 and _button("save").disabled, "underfilled draft cannot save")
	_button("save").pressed.emit()
	check(hub.run.to_dict() == baseline, "forced invalid save inert")
	await _select("card.bleeding")
	await _press("plus")
	check(hub.deck_draft.size() == 10 and not _button("save").disabled, "valid replacement can save")
	await _select("card.poison")
	await _press("plus")
	check(hub.deck_draft.size() == 11 and _button("save").disabled, "temporary overfilled draft remains editable")
	hub._base_deck_action("save", "", &"deck")
	check(hub.run.to_dict() == baseline, "overfilled host request rejected")
	await _press("minus")
	await _check_sizes("draft")
	var draft := hub.deck_draft.duplicate()
	await _press("close")
	check(not page.is_visible_in_tree() and hub.deck_editing and hub.deck_draft == draft, "close navigates without losing draft")
	var start := hub._dashboard.find_child("StartJourney", true, false) as Button
	check(start.disabled, "shared draft blocks launch")
	start.pressed.emit()
	check(hub.run.to_dict() == baseline, "forced launch cannot bypass draft")
	await _press_name("ManageParty")
	check(hub.deck_draft == draft, "old management sees same draft")
	await _press_name("deck_less_card_fire")
	check(hub.deck_draft.size() == 9, "old editor changes shared draft")
	await _press_name("DashboardBack")
	await _press_name("TabDeck")
	check(_text("deck_count").contains("9"), "new panel sees old editor change")
	await _press("cancel")
	check(not hub.deck_editing and hub.deck_draft.is_empty() and hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == bytes, "cancel from new panel discards shared draft without write")
	await _replace("card.fire", "card.burning")
	var expected := HeroHubState.from_dict(baseline)
	check(expected.set_mage_base(hub.deck_draft), "existing set_mage_base expectation")
	await _press("save")
	check(not hub.deck_editing and hub.deck_draft.is_empty() and hub.run.to_dict() == expected.to_dict(), "save publishes exact existing rule and clears both views")
	_check_saved("new deck save")
	bytes = FileAccess.get_file_as_bytes(path)
	page.action_requested.emit("save", "")
	hub._base_deck_action("save", "", &"deck")
	check(hub.run.to_dict() == expected.to_dict() and FileAccess.get_file_as_bytes(path) == bytes, "duplicate save has no active draft")
	await _check_sizes("saved")
	await _test_failure_retry()
	await _test_limits_and_guards()
	await _test_shared_and_stale()
	await _test_reload_legacy_launch()
	await _test_authoring()
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB DECK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_failure_retry() -> void:
	await _replace("card.fire", "card.poison")
	var draft := hub.deck_draft.duplicate()
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	hub.save_path = path + "/blocked"
	await _press("save")
	check(hub._pending_save != null and hub.run.to_dict() == before, "failed write keeps published state")
	check(hub.deck_editing and hub.deck_draft == draft and hub._page("ErrorPage").is_visible_in_tree(), "write failure retains draft behind error page")
	var pending := hub._pending_save.to_dict()
	for action: String in ["edit", "plus", "minus", "save", "cancel", "close"]:
		page.action_requested.emit(action, "card.poison")
		hub._base_deck_action(action, "card.poison", &"deck")
		hub._base_deck_action(action, "card.poison", &"management")
	check(hub._pending_save.to_dict() == pending and hub.deck_draft == draft and FileAccess.get_file_as_bytes(path) == bytes, "failed candidate draft and old file remain unchanged")
	hub.save_path = path
	await _press_name("retry_save")
	check(hub._pending_save == null and hub.run.to_dict() == pending and not hub.deck_editing and hub.deck_draft.is_empty(), "retry publishes same candidate and clears draft")
	check(page.is_visible_in_tree(), "retry returns to separate deck page")
	_check_saved("retry")

func _test_limits_and_guards() -> void:
	await _press("edit")
	for card: MageCardDefinition in MageCardCatalog.all():
		await _select(card.id)
		while hub.deck_draft.count(card.id) < 2: await _press("plus")
		_button("plus").pressed.emit()
		check(hub.deck_draft.count(card.id) == 2, "copy limit at two: " + card.id)
	check(hub.deck_draft.size() == 30 and _button("save").disabled, "15 card types at two copies do not bypass exact ten")
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		_check_layout(page, resolution)
	viewport.size = Vector2i(1280, 850)
	for card: MageCardDefinition in MageCardCatalog.all():
		await _select(card.id)
		while hub.deck_draft.has(card.id): await _press("minus")
		_button("minus").pressed.emit()
		check(not hub.deck_draft.has(card.id), "no negative copies: " + card.id)
	check(hub.deck_draft.is_empty() and _button("save").disabled, "empty draft rejected")
	hub._base_deck_action("plus", "card.unknown", &"deck")
	check(hub.deck_draft.is_empty(), "unknown type rejected")
	await _press("cancel")
	await _press("edit")
	var draft := hub.deck_draft.duplicate()
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	await _press_name("TabMercenaries")
	page.action_requested.emit("plus", "card.bleeding")
	hub._base_deck_action("cancel", "", &"deck")
	check(hub.deck_editing and hub.deck_draft == draft, "inactive tab blocks stale actions")
	await _press_name("TabDeck")
	for phase: String in ["battle", "expedition"]:
		hub.run.phase = phase
		hub._base_deck_action("cancel", "", &"deck")
	hub.run.phase = "hub"
	hub.run.battle_report = {"open":true}
	hub._base_deck_action("cancel", "", &"deck")
	hub.run.battle_report = before.battle_report.duplicate(true)
	hub._storage_error = "barrier"
	hub._base_deck_action("cancel", "", &"deck")
	hub._storage_error = ""
	hub.hide()
	hub._base_deck_action("cancel", "", &"deck")
	hub.show()
	hub._base_deck_action("cancel", "", &"management")
	hub._base_deck_action("cancel", "", &"unknown")
	check(hub.deck_editing and hub.deck_draft == draft and hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "phase report storage hidden host and wrong surface guards")
	await _press("cancel")

func _test_shared_and_stale() -> void:
	await _press("close")
	await _press_name("ManageParty")
	await _press_name("deck_edit")
	await _press_name("deck_less_card_heal")
	var draft := hub.deck_draft.duplicate()
	await _press_name("DashboardBack")
	await _press_name("TabDeck")
	check(hub.deck_editing and hub.deck_draft == draft, "old draft resumes in new page")
	await _select("card.bleeding")
	await _press("plus")
	await _press("close")
	await _press_name("ManageParty")
	await _press_name("deck_save")
	check(not hub.deck_editing and hub.run.mage_deck.base_types.has("card.bleeding"), "old save publishes shared new edits")
	await _press_name("DashboardBack")
	await _press_name("TabDeck")
	await _press("edit")
	# Внешняя публикация другого состава должна аннулировать устаревший draft обоих UI.
	var alternate := hub._copy_run()
	check(alternate.set_mage_base(MageCardCatalog.default_base_types()), "alternate base valid")
	hub._commit(alternate)
	check(not hub.deck_editing and hub.deck_draft.is_empty(), "changed published deck invalidates stale draft")
	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	draft = hub.deck_draft.duplicate()
	var unrelated := hub._copy_run()
	unrelated.gold += 1
	hub._commit(unrelated)
	check(hub.deck_editing and hub.deck_draft == draft, "unrelated profile write preserves draft")
	await _press("cancel")

func _test_reload_legacy_launch() -> void:
	var expected := hub.run.to_dict()
	hub.queue_free()
	await _settle()
	await _load_hub()
	check(hub.run.to_dict() == expected and not hub.deck_editing, "reload restores published deck without draft")
	await _press_name("TabDeck")
	for catalog: int in [1, 2]:
		var fixture := HeroHubState.create(73191, catalog)
		hub._commit(fixture)
		check(_button("edit").disabled and _button("plus").disabled and _text("deck_legacy_hint").contains("не используется"), "legacy profile never creates deck")
		var before := hub.run.to_dict()
		hub._base_deck_action("edit", "", &"deck")
		check(not hub.deck_editing and hub.run.to_dict() == before, "forced legacy edit inert")
		fixture.enable_mage_deck()
		check(fixture.select_mage_host(fixture.party[0]), "choose carrier before returning to expedition launch")
		hub._commit(fixture)
		await _replace("card.fire", "card.poison")
		await _press("save")
		_check_saved("catalog %d" % catalog)
	var types: Array = hub.run.mage_deck.base_types.duplicate()
	await _press("close")
	await _press_name("StartJourney")
	check(hub.run.phase == "expedition" and not page.is_visible_in_tree(), "saved base starts existing expedition route")
	var started: Array[String] = []
	for card: Dictionary in hub.run.expedition.cards:
		if card.origin == "base": started.append(card.type_id)
	started.sort()
	check(started == types, "expedition receives exact saved ten cards")
	_check_saved("launch")
	hub._commit(HeroHubState.from_dict(baseline))
	await _press_name("TabDeck")

func _test_authoring() -> void:
	await _press("edit")
	await _select("card.bleeding")
	var plus := _button("plus")
	var title := _slot("deck_selected_title") as Label
	var sibling := _slot("deck_summary") as Control
	var sibling_rect := sibling.get_global_rect()
	_reparent_control(plus, page)
	plus.name = "RelocatedAdd"
	plus.position += Vector2(2, 1)
	var position := plus.position
	_reparent_control(title, page)
	title.name = "RelocatedName"
	title.add_theme_color_override("font_color", Color.REBECCA_PURPLE)
	for cycle: int in 3: hub._render()
	check(plus.position == position and sibling.get_global_rect() == sibling_rect and title.get_theme_color("font_color") == Color.REBECCA_PURPLE, "render preserves authored position theme and neighbor")
	await _click(plus)
	check(hub.deck_draft.count("card.bleeding") == 1, "reparented renamed action remains bound")
	plus.hide()
	hub._render()
	plus.pressed.emit()
	check(not plus.visible and hub.deck_draft.count("card.bleeding") == 1, "hidden action remains hidden and inert")
	plus.show()
	_button("save").free()
	title.free()
	await _click(plus)
	check(hub.deck_draft.count("card.bleeding") == 2 and _slot("deck_selected_title") == null and _button("save") == null, "removed fields and save never recreated")
	var card := _slot("deck_card_1") as Button
	_reparent_control(card, page)
	card.name = "RelocatedCard"
	var field := card.find_child("*", false, false)
	for child: Node in card.find_children("*", "Label", true, false):
		if child.has_meta(&"hub_field"): field = child; break
	field.name = "RelocatedField"
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.reparent(holder, true)
	card.hide()
	hub._render()
	var selected := _text("deck_selected_description")
	card.pressed.emit()
	check(not card.visible and _text("deck_selected_description") == selected, "hidden card cannot change selection")
	card.free()
	hub._render()
	check(_slot("deck_card_1") == null, "deleted card never recreated")
	var cancel := _button("cancel")
	_reparent_control(cancel, hub)
	cancel.pressed.emit()
	check(hub.deck_editing, "control moved outside page cannot invoke retained callback")
	cancel.free()
	var draft := hub.deck_draft.duplicate()
	page.hide()
	plus.pressed.emit()
	page.action_requested.emit("cancel", "")
	check(hub.deck_draft == draft and hub.deck_editing, "hidden page rejects forwarded actions")
	page.free()
	hub._render()
	hub._base_deck_action("cancel", "", &"deck")
	check(hub.deck_draft == draft and not hub._dashboard.deck_page_visible(), "deleted page stays absent and blocks host requests")
	check(hub.run.to_dict() == baseline, "authoring and draft preserve published profile")

func _replace(remove_type: String, add_type: String) -> void:
	await _press("edit")
	await _select(remove_type)
	await _press("minus")
	await _select(add_type)
	await _press("plus")

func _reparent_control(control: Control, parent: Control) -> void:
	# При новом родителе anchors относятся к другому прямоугольнику; автор задаёт перенос явно.
	var rectangle := control.get_global_rect()
	control.reparent(parent, true)
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.global_position = rectangle.position
	control.size = rectangle.size

func _select(type_id: String) -> void:
	while not _button("deck_page_prev").disabled: await _press("deck_page_prev")
	for index: int in 3:
		for node: Node in page.find_children("*", "Button", true, false):
			if String(node.get_meta(&"hub_type_id", "")) == type_id:
				await _click(node as Button)
				return
		if not _button("deck_page_next").disabled: await _press("deck_page_next")
	check(false, "type can be selected: " + type_id)

func _check_sizes(label: String) -> void:
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		_check_layout(page, resolution)
		var tabs: Array[Control] = []
		for node: Node in hub._dashboard.find_children("*", "Button", true, false):
			if node.has_meta(&"hub_tab") and (node as Control).is_visible_in_tree(): tabs.append(node as Control)
		for index: int in tabs.size():
			check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(tabs[index].get_global_rect()), "tab fits viewport")
			for other: int in range(index + 1, tabs.size()): check(not tabs[index].get_global_rect().intersects(tabs[other].get_global_rect()), "tabs do not overlap")
		await _capture("%s-%dx%d" % [label, resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()

func _check_layout(parent: Control, resolution: Vector2i) -> void:
	var controls: Array[Control] = []
	for node: Node in parent.get_children():
		if node is Control and (node as Control).is_visible_in_tree(): controls.append(node as Control)
	for child: Control in controls:
		check(parent.get_global_rect().grow(1).encloses(child.get_global_rect()), "%s fits %s" % [child.name, resolution])
		_check_layout(child, resolution)
	for index: int in controls.size():
		for other: int in range(index + 1, controls.size()): check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s/%s separate %s" % [controls[index].name, controls[other].name, resolution])

func _load_hub() -> void:
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await _settle()
	page = hub.get_node("ExpeditionDashboard/SectionPages/DeckPage") as HubDeckPage
	check(hub.run != null, "profile loads")

func _check_saved(label: String) -> void:
	var restored := HeroHubStore.read_run(path).get("run") as HeroHubState
	check(restored != null and restored.to_dict() == hub.run.to_dict(), label + " persists full profile")

func _slot(key: String) -> Node:
	for node: Node in page.find_children("*", "", true, false):
		if String(node.get_meta(&"hub_slot", "")) == key: return node
	return null

func _button(key: String) -> Button:
	for node: Node in page.find_children("*", "Button", true, false):
		if String(node.get_meta(&"hub_action", "")) == key: return node as Button
	return null

func _text(key: String) -> String:
	return (_slot(key) as Label).text

func _press(key: String) -> void:
	await _click(_button(key))

func _press_name(key: String) -> void:
	for node: Node in hub.find_children(key, "Button", true, false):
		if (node as Button).is_visible_in_tree():
			await _click(node as Button)
			return
	check(false, "visible button " + key)

func _click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "clickable control " + (String(button.name) if button != null else "null"))
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	await _settle()
	var parent: Node = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await _settle()
	var position := button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(position), "click inside viewport: %s %s" % [button.name, position])
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
