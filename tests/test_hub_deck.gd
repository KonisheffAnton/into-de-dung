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
	await _test_book_interactions()
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

func _test_book_interactions() -> void:
	var published := hub.run.to_dict()
	var saved_bytes := FileAccess.get_file_as_bytes(path)
	var target := _slot("deck_drop_target") as Control
	check(target != null, "book has a deck drop target")
	if target == null: return
	var fire := await _catalog_card("card.fire")
	check(fire != null, "full-deck catalog card is available")
	if fire == null: return
	await _click(fire)
	check(not hub.deck_editing and hub.deck_draft.is_empty() and hub.run.to_dict() == published, "catalog click on full deck only inspects")
	check(FileAccess.get_file_as_bytes(path) == saved_bytes, "full-deck click preserves save bytes")
	var full_payload := _payload_for(fire)
	check(not page._can_drop_card(target.size * 0.5, full_payload, target), "full deck rejects a forged valid source")
	fire.drag_started = false

	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	var source := await _catalog_card("card.binding_thread")
	check(source != null and hub.deck_draft.size() == 9, "underfilled draft and add source are ready")
	if source != null:
		await _click(source)
		check(hub.deck_editing and hub.deck_draft.size() == 10 and hub.deck_draft.count("card.binding_thread") == 1, "catalog click adds one card to underfilled draft")
	check(hub.run.to_dict() == published and FileAccess.get_file_as_bytes(path) == saved_bytes, "catalog add remains in shared draft before save")
	await _press("cancel")

	var fire_row := _deck_row("card.fire")
	check(fire_row != null, "published deck exposes a removable row")
	if fire_row == null: return
	await _click(fire_row)
	check(hub.deck_editing and hub.deck_draft.size() == 9 and hub.deck_draft.count("card.fire") == 1, "row click starts shared draft and removes one copy")
	var binding_source := await _catalog_card("card.binding_thread")
	check(binding_source != null, "binding thread drag source is available")
	if binding_source != null:
		var rows := _slot("deck_rows") as Control
		var drop_area := rows.get_parent() as Control
		var drop_point := drop_area.get_global_rect().get_center()
		await _native_begin_drag(binding_source)
		check(viewport.gui_is_dragging() and binding_source.drag_started, "catalog drag starts with source preview")
		_native_motion(drop_point, true)
		await _settle()
		check(viewport.gui_is_dragging() and binding_source.drag_started, "catalog drag preview remains active over deck rows")
		_native_mouse(drop_point, false)
		await _settle()
		check(not viewport.gui_is_dragging() and hub.deck_draft.size() == 10 and hub.deck_draft.count("card.binding_thread") == 1, "native drop adds exactly one card")
		check(_deck_row("card.binding_thread") != null, "valid drop refreshes shared deck rows")
	check(hub.run.to_dict() == published and FileAccess.get_file_as_bytes(path) == saved_bytes, "native drop changes draft only before save")
	await _press("cancel")

	# Фиктивные данные нужны для адресной проверки защит без обхода обработчика UI.
	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	var fire_again := await _catalog_card("card.fire")
	if fire_again != null:
		var stale_payload := _payload_for(fire_again)
		fire_again.hide()
		check(not page._can_drop_card(target.size * 0.5, stale_payload, target), "hidden catalog source cannot be dropped")
		fire_again.show()
		var old_parent := fire_again.get_parent() as Control
		var old_index := fire_again.get_index()
		var layout := _control_layout(fire_again)
		fire_again.reparent(viewport, true)
		check(not page._can_drop_card(target.size * 0.5, stale_payload, target), "source moved outside page cannot be dropped")
		fire_again.reparent(old_parent, true)
		_restore_control_layout(fire_again, layout)
		old_parent.move_child(fire_again, old_index)
		check(page._can_drop_card(target.size * 0.5, stale_payload, target), "current visible source can address the deck")
		var unknown_payload := stale_payload.duplicate(true)
		unknown_payload["type_id"] = "card.unknown"
		check(not page._can_drop_card(target.size * 0.5, unknown_payload, target), "unknown spell payload is rejected")
		hub._render()
		check(not page._can_drop_card(target.size * 0.5, stale_payload, target), "profile render invalidates old drag generation")
		var hidden_payload := _payload_for(fire_again)
		await _press_name("TabMercenaries")
		check(not page._can_drop_card(target.size * 0.5, hidden_payload, target), "tab change rejects current source")
		await _press_name("TabDeck")
		fire_again.drag_started = false

	await _press("cancel")
	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	var capped_source := await _catalog_card("card.heal")
	if capped_source != null:
		var capped_payload := _payload_for(capped_source)
		check(not page._can_drop_card(target.size * 0.5, capped_payload, target), "third copy is rejected while draft has room")
		capped_source.drag_started = false
	var fresh_source := await _catalog_card("card.binding_thread")
	if fresh_source != null:
		var fresh_payload := _payload_for(fresh_source)
		check(page._can_drop_card(target.size * 0.5, fresh_payload, target), "valid payload can target deck while draft has room")
		fresh_source.drag_started = false
		check(not page._can_drop_card(target.size * 0.5, fresh_payload, target), "completed drag source cannot be replayed")
	await _press("cancel")

	await _press("edit")
	await _select("card.fire")
	await _press("minus")
	var unchanged_draft := hub.deck_draft.duplicate()
	var outside_source := await _catalog_card("card.binding_thread")
	var outside_target := await _catalog_card("card.bleeding")
	if outside_source != null and outside_target != null:
		await _native_drag(outside_source, outside_target.get_global_rect().get_center())
		check(hub.deck_editing and hub.deck_draft == unchanged_draft and hub.run.to_dict() == published, "drop outside deck does not mutate shared draft")
	var cancel_source := await _catalog_card("card.binding_thread")
	if cancel_source != null:
		await _native_begin_drag(cancel_source)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		viewport.push_input(escape, true)
		escape.pressed = false
		viewport.push_input(escape, true)
		_native_mouse(viewport.get_mouse_position(), false)
		await _settle()
		check(not viewport.gui_is_dragging() and hub.deck_editing and hub.deck_draft == unchanged_draft and hub.run.to_dict() == published, "escape cancels drag without mutating shared draft")
	await _press("cancel")
	check(not hub.deck_editing and hub.deck_draft.is_empty() and hub.run.to_dict() == published, "cancel discards draft after rejected drags")
	check(FileAccess.get_file_as_bytes(path) == saved_bytes, "cancelled and rejected interactions preserve save bytes")

func _control_layout(control: Control) -> Dictionary:
	return {
		"anchor_left": control.anchor_left, "anchor_top": control.anchor_top,
		"anchor_right": control.anchor_right, "anchor_bottom": control.anchor_bottom,
		"offset_left": control.offset_left, "offset_top": control.offset_top,
		"offset_right": control.offset_right, "offset_bottom": control.offset_bottom,
	}

func _restore_control_layout(control: Control, layout: Dictionary) -> void:
	control.anchor_left = layout.anchor_left
	control.anchor_top = layout.anchor_top
	control.anchor_right = layout.anchor_right
	control.anchor_bottom = layout.anchor_bottom
	control.offset_left = layout.offset_left
	control.offset_top = layout.offset_top
	control.offset_right = layout.offset_right
	control.offset_bottom = layout.offset_bottom

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
	for action: String in ["edit", "plus", "minus", "add", "remove", "save", "cancel", "close"]:
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
	var card := await _catalog_card(type_id)
	check(card != null, "type can be selected: " + type_id)
	if card == null: return
	await _hover(card)
	check(_text("deck_selected_title") == MageCardCatalog.get_card(type_id).name, "hover inspects catalog card: " + type_id)

func _catalog_card(type_id: String) -> HubDeckTypeCard:
	while not _button("deck_page_prev").disabled: await _press("deck_page_prev")
	var page_count := maxi(ceili(float(MageCardCatalog.IDS.size()) / float(HubDeckPage.PAGE_SIZE)), 1)
	for index: int in page_count:
		for node: Node in page.find_children("*", "Button", true, false):
			if node is HubDeckTypeCard and String(node.get_meta(&"hub_type_id", "")) == type_id:
				return node as HubDeckTypeCard
		if not _button("deck_page_next").disabled: await _press("deck_page_next")
	return null

func _deck_row(type_id: String) -> Button:
	var rows := _slot("deck_rows") as Control
	if rows == null: return null
	for node: Node in rows.find_children("*", "Button", true, false):
		if String(node.get_meta(&"hub_type_id", "")) == type_id: return node as Button
	return null

func _payload_for(source: HubDeckTypeCard) -> Dictionary:
	source.drag_started = true
	return {
		"kind": "hub_spellbook_card",
		"type_id": source.type_id,
		"source_id": int(source.get_instance_id()),
		"page_id": int(page.get_instance_id()),
		"generation": int(page._view_generation),
	}

func _hover(control: Control) -> void:
	await _settle()
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	viewport.push_input(motion, true)
	await _settle()

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
		# Содержимое списка намеренно выше ScrollContainer и обрезается им при прокрутке.
		if not parent is ScrollContainer:
			check(parent.get_global_rect().grow(1).encloses(child.get_global_rect()), "%s fits %s" % [child.name, resolution])
		_check_layout(child, resolution)
	for index: int in controls.size():
		for other: int in range(index + 1, controls.size()):
			if controls[index] is ScrollBar or controls[other] is ScrollBar: continue
			check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s/%s separate %s" % [controls[index].name, controls[other].name, resolution])

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

func _native_motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = point - viewport.get_mouse_position()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	viewport.push_input(event, true)

func _native_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(event, true)

func _native_begin_drag(source: Control) -> void:
	var point := source.get_global_rect().get_center()
	_native_motion(point)
	_native_mouse(point, true)
	_native_motion(point + Vector2(0, 30), true)
	await _settle()
	check(viewport.gui_is_dragging(), "native drag begins")

func _native_drag(source: Control, target: Vector2) -> void:
	await _native_begin_drag(source)
	_native_motion(target, true)
	await _settle()
	_native_mouse(target, false)
	await _settle()

func _settle() -> void:
	for unused: int in 4: await process_frame

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
