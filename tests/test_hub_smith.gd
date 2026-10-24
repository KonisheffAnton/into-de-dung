extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var smith: HubSectionPage
var path: String
var baseline: Dictionary
var captures: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB SMITH: " + label)

func _run() -> void:
	path = "user://hub-smith-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := HeroHubState.create(73191, 2)
	initial.enable_mage_deck()
	var shield_id := initial.party[0]
	var archer_id := initial.party[1]
	var rogue_id := initial.party[2]
	var weapon_id: int = initial.equipped(shield_id, "weapon").id
	var armor_id: int = initial.equipped(shield_id, "armor").id
	initial.items[armor_id].remaining = 10.5
	baseline = initial.to_dict()
	check(HeroHubStore.write_run(path, initial).is_empty(), "initial profile saved")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	await _load_hub()
	await _press_name("TabSmith")
	await _item(weapon_id)
	check(smith._selected_hero_id == shield_id and _action().text == "Снять", "default hero and equipped weapon action")
	var file_before := FileAccess.get_file_as_bytes(path)
	for cycle: int in 3: hub._render()
	check(_action().pressed.get_connections().size() == 1 and smith.equipment_requested.get_connections().size() == 1, "one callback after repeated refresh")
	await _hero(archer_id)
	check(_action().disabled and not _text("smith_equipment_hint").is_empty(), "other owner must remove item first")
	_action().pressed.emit()
	hub._on_smith_equipment_requested(weapon_id, archer_id, true)
	await _hero(shield_id)
	await _press_name("TabMercenaries")
	await _press_name("TabSmith")
	check(smith._selected_hero_id == shield_id and smith._selected_item_id == weapon_id, "tab change preserves hero and item IDs")
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == file_before, "navigation selection refresh and invalid owner leave profile RNG file unchanged")
	await _check_sizes("weapon")
	var expected := HeroHubState.from_dict(baseline)
	check(expected.unequip(weapon_id), "existing unequip expectation")
	await _click(_action())
	check(hub.run.to_dict() == expected.to_dict() and _action().text == "Надеть", "unequip moves selected weapon to storage through existing rules")
	_check_saved("unequip")
	var before := hub.run.to_dict()
	file_before = FileAccess.get_file_as_bytes(path)
	smith.equipment_requested.emit(weapon_id, shield_id, false)
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == file_before, "repeated unequip is inert")
	await _hero(archer_id)
	check(_action().disabled and not _text("smith_equipment_hint").is_empty(), "wrong weapon class blocked with reason")
	_action().pressed.emit()
	hub._on_smith_equipment_requested(weapon_id, archer_id, true)
	check(hub.run.to_dict() == before, "forced incompatible equip blocked")
	await _hero(shield_id)
	check(expected.equip(weapon_id, shield_id), "existing equip expectation")
	await _click(_action())
	check(hub.run.to_dict() == expected.to_dict(), "equip uses exact selected item and hero")
	file_before = FileAccess.get_file_as_bytes(path)
	smith.equipment_requested.emit(weapon_id, shield_id, true)
	check(FileAccess.get_file_as_bytes(path) == file_before, "repeated equip does not write again")
	_check_saved("equip")

	await _hero(rogue_id)
	await _item(int(hub.run.equipped(rogue_id, "weapon").id))
	check(_text("item_detail").contains("35") and _text("item_detail").contains("+1"), "rogue inspection exposes piercing and extra attack perk")
	await _check_sizes("rogue-knives")
	await _hero(shield_id)
	await _item(armor_id)
	check(_text("item_detail").contains("10.5"), "fractional remaining armor shown")
	await _click(_action())
	await _hero(archer_id)
	var replaced_id: int = hub.run.equipped(archer_id, "armor").id
	check(not _action().disabled and _text("smith_equipment_hint").contains("склад"), "armor fits another class and replacement is explained")
	await _check_sizes("armor-replacement")
	expected = HeroHubState.from_dict(hub.run.to_dict())
	check(expected.equip(armor_id, archer_id), "existing armor replacement expectation")
	await _click(_action())
	check(hub.run.to_dict() == expected.to_dict() and int(hub.run.items[replaced_id].hero_id) == 0, "replacement preserves displaced item on storage")
	check(float(hub.run.items[armor_id].remaining) == 10.5, "transfer does not repair remaining armor")
	smith.equipment_requested.emit(armor_id, shield_id, false)
	check(hub.run.to_dict() == expected.to_dict(), "old owner request cannot strip new owner")
	_check_saved("armor transfer")
	await _test_failure_retry(armor_id, archer_id)
	await _test_roster_and_empty()
	await _test_guards(weapon_id, shield_id)
	await _test_reload_legacy()
	await _test_authoring(weapon_id, shield_id)
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB SMITH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_failure_retry(item_id: int, hero_id: int) -> void:
	# Оба направления обязаны ждать успешной записи одного и того же candidate.
	for equip_item: bool in [false, true]:
		var before := hub.run.to_dict()
		var bytes := FileAccess.get_file_as_bytes(path)
		hub.save_path = path + "/blocked"
		await _click(_action())
		check(hub._pending_save != null and hub.run.to_dict() == before, "failed equipment write keeps published profile")
		check(not smith.is_visible_in_tree() and hub._page("ErrorPage").is_visible_in_tree(), "error page takes priority")
		check(smith._selected_item_id == item_id and smith._selected_hero_id == hero_id, "failed write keeps both selections")
		var pending := hub._pending_save.to_dict()
		smith.equipment_requested.emit(item_id, hero_id, equip_item)
		hub._on_smith_equipment_requested(item_id, hero_id, equip_item)
		check(hub._pending_save.to_dict() == pending and FileAccess.get_file_as_bytes(path) == bytes, "pending candidate and old file survive repeated request")
		hub.save_path = path
		await _press_name("retry_save")
		check(hub._pending_save == null and hub.run.to_dict() == pending, "retry publishes once")
		check(smith.is_visible_in_tree() and smith._selected_item_id == item_id and smith._selected_hero_id == hero_id, "retry returns to same item and hero")
		_check_saved("equipment retry")

func _test_roster_and_empty() -> void:
	var fixture := HeroHubState.from_dict(baseline)
	while fixture.heroes.size() < HeroHubState.MAX_ROSTER: check(fixture.hire(0), "fill roster fixture")
	hub._commit(fixture)
	var hero_ids: Array = hub.run.heroes.keys()
	hero_ids.sort()
	for id: int in hero_ids: await _hero(id)
	check(_control("smith_hero_next").disabled, "all twelve heroes reachable and next disabled at end")
	var last_id: int = hero_ids.back()
	check(_text("smith_hero").contains((hub.run.heroes[last_id] as HeroProgression).name), "caption follows last hero")
	await _item(int(hub.run.items.keys().max()))
	check(smith._items_page > 0, "expanded storage pagination")
	fixture = HeroHubState.from_dict(baseline)
	fixture.items.clear()
	hub._commit(fixture)
	check(smith._items_page == 0 and smith._selected_item_id == 0 and _action().disabled, "empty storage clears selected item and clamps page")
	check(_text("item_detail") == "Склад пуст", "empty storage clears previous item stats")
	check((smith._slot("item_detail") as Label).tooltip_text.is_empty() and (smith._slot("item_0") as Button).tooltip_text.is_empty(), "empty storage clears previous descriptions")
	check(hub.run.heroes.has(smith._selected_hero_id), "removed selected hero falls back to valid hero")
	var selected_id := smith._selected_hero_id
	(hub.run.heroes[selected_id] as HeroProgression).hp_current = 0.0
	hub._render()
	check(smith._selected_hero_id != selected_id and (hub.run.heroes[smith._selected_hero_id] as HeroProgression).hp_current > 0.0, "dead selected hero falls back to living hero")
	for hero: HeroProgression in hub.run.heroes.values(): hero.hp_current = 0.0
	hub._render()
	check(smith._selected_hero_id == 0 and _control("smith_hero_prev").disabled and _control("smith_hero_next").disabled, "no living heroes clears selector")
	fixture = HeroHubState.from_dict(baseline)
	fixture.heroes.clear()
	fixture.party.clear()
	for item: Dictionary in fixture.items.values(): item.hero_id = 0
	hub._commit(fixture)
	check(smith._selected_hero_id == 0 and _action().disabled, "no heroes disables equipment")
	check(_control("smith_hero_prev").disabled and _control("smith_hero_next").disabled, "empty hero navigation disabled")
	var before := hub.run.to_dict()
	_action().pressed.emit()
	check(hub.run.to_dict() == before, "empty roster forced action inert")
	_reset()

func _test_guards(item_id: int, hero_id: int) -> void:
	await _hero(hero_id)
	await _item(item_id)
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	await _press_name("TabMercenaries")
	smith._on_action("smith_equipment")
	smith.equipment_requested.emit(item_id, hero_id, false)
	hub._on_smith_equipment_requested(item_id, hero_id, false)
	check(hub.run.to_dict() == before, "inactive section rejected at page dashboard host")
	await _press_name("TabSmith")
	await _press_name("ManageEquipment")
	hub._on_smith_equipment_requested(item_id, hero_id, false)
	check(hub.run.to_dict() == before, "old management page blocks section mutation")
	await _press_name("deck_edit")
	var draft := hub.deck_draft.duplicate()
	await _press_name("DashboardBack")
	await _press_name("TabSmith")
	await _click(_action())
	check(hub.deck_editing and hub.deck_draft == draft, "equipment preserves deck draft")
	await _press_name("ManageEquipment")
	await _press_name("deck_cancel")
	await _press_name("DashboardBack")
	await _press_name("TabSmith")
	_reset()
	before = hub.run.to_dict()
	bytes = FileAccess.get_file_as_bytes(path)
	hub.run.phase = "battle"
	hub._on_smith_equipment_requested(item_id, hero_id, false)
	hub.run.phase = "hub"
	hub.run.battle_report = {"open":true}
	hub._on_smith_equipment_requested(item_id, hero_id, false)
	hub.run.battle_report = before.battle_report.duplicate(true)
	hub._storage_error = "test barrier"
	hub._on_smith_equipment_requested(item_id, hero_id, false)
	hub._storage_error = ""
	hub._on_smith_equipment_requested(-1, hero_id, true)
	hub._on_smith_equipment_requested(item_id, -1, false)
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "phase report storage and unknown ID guards")
	check((smith.get_node("ItemDetail/Upgrade") as Button).disabled and (smith.get_node("Salvage/Salvage") as Button).disabled, "upgrade and salvage remain unavailable")

func _test_reload_legacy() -> void:
	await _click(_action())
	var before := hub.run.to_dict()
	viewport.remove_child(hub)
	hub.queue_free()
	await process_frame
	await _load_hub()
	check(hub.run.to_dict() == before, "reloaded profile preserves equipment ownership and durability")
	await _press_name("TabSmith")
	var legacy := HeroHubState.create(733, 1)
	hub._commit(legacy)
	var mage_id: int = legacy.heroes.keys().back()
	await _hero(mage_id)
	var staff_id: int = hub.run.equipped(mage_id, "weapon").id
	await _item(staff_id)
	check(_text("item_detail").to_lower().contains("огнен"), "legacy staff displays contribution to fire base")
	await _click(_action())
	check(int(hub.run.items[staff_id].hero_id) == 0, "legacy staff unequips")
	await _click(_action())
	check(int(hub.run.items[staff_id].hero_id) == mage_id, "legacy staff reequips")
	_check_saved("legacy staff")
	_reset()

func _test_authoring(item_id: int, hero_id: int) -> void:
	await _hero(hero_id)
	await _item(item_id)
	var button := _action()
	var hint := smith._slot("smith_equipment_hint") as Label
	var caption := smith._slot("smith_hero") as Label
	var next := _control("smith_hero_next")
	var neighbor := smith.get_node("Materials") as Control
	var neighbor_rect := neighbor.get_global_rect()
	button.name = "RelocatedEquipment"
	button.reparent(smith, true)
	button.position += Vector2(-3, 0)
	button.add_theme_font_size_override("font_size", 15)
	caption.name = "RenamedHero"
	caption.reparent(smith, true)
	next.name = "RelocatedNext"
	next.reparent(smith, true)
	var button_rect := button.get_global_rect()
	for cycle: int in 3: hub._render()
	check(button.get_global_rect() == button_rect and neighbor.get_global_rect() == neighbor_rect, "independent relocated nodes do not move neighbors")
	check(button.get_theme_font_size("font_size") == 15 and button.pressed.get_connections().size() == 1, "authored theme and callback count retained")
	await _click(button)
	check(int(hub.run.items[item_id].hero_id) == 0, "relocated action still saves equipment")
	button.hide()
	hub._render()
	var before := hub.run.to_dict()
	button.pressed.emit()
	check(not button.visible and hub.run.to_dict() == before, "hidden action stays hidden and inert")
	button.show()
	button.free()
	hub._render()
	var hint_before := hint.text
	await _click(next)
	check(hint.text != hint_before and caption.text.contains((hub.run.heroes[smith._selected_hero_id] as HeroProgression).name), "surviving hint and hero caption update without equipment button")
	caption.free()
	await _click(next)
	check(smith._selected_hero_id != hero_id, "hero navigation survives deleted caption")
	next.free()
	hint.free()
	hub._render()
	smith._on_action("smith_equipment")
	check(_action() == null and smith._slot("smith_equipment_hint") == null and smith._slot("smith_hero") == null, "deleted controls not recreated")
	check(hub.run.to_dict() == before, "authoring and local selection do not write profile")

func _check_sizes(label: String) -> void:
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		for name: String in ["Inventory", "ItemDetail"]:
			var panel := smith.get_node(name) as Control
			var controls: Array[Control] = []
			for node: Node in panel.get_children():
				if node is Control and (node as Control).is_visible_in_tree(): controls.append(node as Control)
			for control: Control in controls:
				check(panel.get_global_rect().grow(1).encloses(control.get_global_rect()), "%s fits %s" % [control.name, resolution])
			for index: int in controls.size():
				for other: int in range(index + 1, controls.size()):
					check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s/%s do not overlap at %s" % [controls[index].name, controls[other].name, resolution])
		await _capture("%s-%dx%d" % [label, resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()

func _reset() -> void:
	hub._commit(HeroHubState.from_dict(baseline))
	check(hub._pending_save == null, "fixture saves")

func _check_saved(label: String) -> void:
	var restored := HeroHubStore.read_run(path).get("run") as HeroHubState
	check(restored != null and restored.to_dict() == hub.run.to_dict(), label + " persists complete profile")

func _load_hub() -> void:
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await _settle()
	smith = hub.get_node("ExpeditionDashboard/SectionPages/SmithPage") as HubSectionPage
	check(hub.run != null, "profile loads")

func _control(key: String) -> Button:
	return smith._action_button(key)

func _action() -> Button:
	return _control("smith_equipment")

func _text(key: String) -> String:
	return (smith._slot(key) as Label).text

func _hero(id: int) -> void:
	var ids := hub.run.heroes.keys()
	ids.sort()
	for attempt: int in HeroHubState.MAX_ROSTER:
		if smith._selected_hero_id == id: break
		await _click(_control("smith_hero_next" if ids.find(smith._selected_hero_id) < ids.find(id) else "smith_hero_prev"))
	check(smith._selected_hero_id == id, "selected requested hero")

func _item(id: int) -> void:
	var index := smith._item_ids().find(id)
	check(index >= 0, "item exists")
	if index < 0: return
	var page := index / HubSectionPage.ITEMS_PAGE_SIZE
	for attempt: int in smith._item_ids().size():
		if smith._items_page == page: break
		await _click(_control("items_next" if smith._items_page < page else "items_prev"))
	check(smith._items_page == page, "requested item page reached")
	await _click(smith._slot("item_%d" % (index % HubSectionPage.ITEMS_PAGE_SIZE)) as Button)
	check(smith._selected_item_id == id, "selected requested item")

func _press_name(key: String) -> void:
	for node: Node in hub.find_children(key, "Button", true, false):
		if (node as Button).is_visible_in_tree():
			await _click(node as Button)
			return
	check(false, "visible button " + key)

func _click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "clickable control")
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

func _settle() -> void:
	for unused: int in 4: await process_frame

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
