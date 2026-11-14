extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var hub: HeroHubScreen
var merc: HubSectionPage
var captures: String = ""
var path: String
var baseline: Dictionary

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB MERCENARIES: " + label)

func _run() -> void:
	path = "user://hub-mercenaries-%d-%d.save" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := HeroHubState.create(73191, 2)
	initial.enable_mage_deck()
	baseline = initial.to_dict()
	check(HeroHubStore.write_run(path, initial).is_empty(), "seeded v2 profile saved")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	await _load_hub()
	await _press_name("TabMercenaries")
	var initial_bytes := FileAccess.get_file_as_bytes(path)
	await _select_slot("candidate_1")
	for cycle: int in 4: hub._render()
	check(_action().pressed.get_connections().size() == 1 and merc.hire_requested.get_connections().size() == 1, "refresh keeps one handler on action and host route")
	await _press_name("TabSmith")
	await _press_name("TabMercenaries")
	check(merc._selected_hero_id == hub.run.candidates[1].id, "tab navigation retains selected candidate")
	check(hub.run.to_dict() == baseline and FileAccess.get_file_as_bytes(path) == initial_bytes, "selection render navigation preserve state RNG and file")
	await _check_sizes("candidate")

	var hired_id := hub.run.candidates[1].id
	var expected := HeroHubState.from_dict(baseline)
	check(expected.hire(1), "expected existing hire succeeds")
	await _click(_action())
	check(hub.run.to_dict() == expected.to_dict(), "click hires exactly displayed candidate with existing starter gear rules")
	check(not merc._selected_candidate and merc._selected_hero_id == hired_id, "successful publication selects hired hero")
	check(not hub.run.party.has(hired_id) and _action().disabled, "new hire goes to reserve and full party blocks join")
	check(_hint().contains("Отряд заполнен"), "full party explains blocked join")
	_check_saved("hire")
	var after_hire := hub.run.to_dict()
	var after_bytes := FileAccess.get_file_as_bytes(path)
	merc.hire_requested.emit(hired_id)
	merc.party_requested.emit(hired_id, true)
	check(hub.run.to_dict() == after_hire and FileAccess.get_file_as_bytes(path) == after_bytes, "stale candidate ID and full party request cannot mutate")
	await _check_sizes("full-party")

	await _select_slot("party_0")
	var removed_id := merc._selected_hero_id
	await _click(_action())
	check(not hub.run.party.has(removed_id) and _action().text == "В отряд", "party member moves to reserve and stays selected")
	var removed_state := hub.run.to_dict()
	merc.party_requested.emit(removed_id, false)
	check(hub.run.to_dict() == removed_state, "repeated desired-state removal does not toggle back")
	await _click(_action())
	check(hub.run.party.has(removed_id) and _action().text == "В резерв", "reserve member rejoins party")
	_check_saved("party change")
	var party_ids: Array[int] = hub.run.party.duplicate()
	for id: int in party_ids:
		merc._on_selected("hero:%d" % id)
		await _click(_action())
	check(hub.run.party.is_empty(), "last member may move into reserve")
	await _press_name("TabExpedition")
	check((hub.find_child("StartJourney", true, false) as Button).disabled, "empty party blocks existing departure")
	await _press_name("TabMercenaries")
	await _click(_action())
	check(hub.run.party.size() == 1, "empty party can be rebuilt")
	await _press_name("TabExpedition")
	check(not (hub.find_child("StartJourney", true, false) as Button).disabled, "rebuilt party enables departure")
	await _press_name("TabMercenaries")
	await _test_failure_retry()
	await _test_limits()
	await _test_guards()
	await _test_reload_and_legacy()
	await _test_authoring()
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HUB MERCENARIES RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_failure_retry() -> void:
	_reset()
	await _select_slot("candidate_2")
	var candidate_id := merc._selected_hero_id
	var before := hub.run.to_dict()
	var file_before := FileAccess.get_file_as_bytes(path)
	hub.save_path = path + "/blocked"
	await _click(_action())
	check(hub._pending_save != null and hub.run.to_dict() == before, "failed hire save does not publish")
	check(merc._selected_candidate and merc._selected_hero_id == candidate_id, "failed write retains candidate selection")
	check(not merc.is_visible_in_tree() and hub._page("ErrorPage").is_visible_in_tree(), "save error takes priority over mercenaries")
	var pending := hub._pending_save.to_dict()
	merc.hire_requested.emit(candidate_id)
	hub._on_mercenary_hire_requested(candidate_id)
	hub._on_mercenary_party_requested(hub.run.party[0], false)
	check(hub._pending_save.to_dict() == pending and FileAccess.get_file_as_bytes(path) == file_before, "pending write blocks further requests and preserves old file")
	hub.save_path = path
	await _press_name("retry_save")
	check(hub._pending_save == null and hub.run.to_dict() == pending, "real retry publishes exactly pending hire")
	check(not merc._selected_candidate and merc._selected_hero_id == candidate_id, "retry selects hired hero after publication")
	_check_saved("hire retry")
	await _select_slot("party_0")
	var member_id := merc._selected_hero_id
	before = hub.run.to_dict()
	hub.save_path = path + "/blocked"
	await _click(_action())
	check(hub.run.to_dict() == before and hub._pending_save != null, "failed party save keeps old roster")
	hub.save_path = path
	await _press_name("retry_save")
	check(not hub.run.party.has(member_id) and merc._selected_hero_id == member_id, "party retry preserves selection and publishes removal")
	_check_saved("party retry")

func _test_limits() -> void:
	var fixture := HeroHubState.from_dict(baseline)
	while fixture.heroes.size() < HeroHubState.MAX_ROSTER - 1: check(fixture.hire(0), "fill roster fixture")
	hub._commit(fixture)
	await _select_slot("candidate_0")
	var hired_id := merc._selected_hero_id
	await _click(_action())
	check(hub.run.heroes.size() == HeroHubState.MAX_ROSTER and merc._selected_hero_id == hired_id, "twelfth hero can be hired")
	var hired_card := _card("hero:%d" % hired_id)
	check(hired_card != null and hired_card.is_visible_in_tree(), "hired reserve card appears in the all-heroes grid")
	await _select_slot("candidate_0")
	check(_action().disabled and _hint().contains("12"), "roster limit is disabled and explained")
	var before := hub.run.to_dict()
	_action().pressed.emit()
	check(hub.run.to_dict() == before, "forced disabled roster action rejected")
	await _capture("roster-limit")

	fixture = HeroHubState.from_dict(baseline)
	while fixture.items.size() < HeroHubState.MAX_ITEMS - 1:
		var id := fixture.next_item_id
		fixture.next_item_id += 1
		fixture.items[id] = {"id":id, "definition":"weapon:warrior", "hero_id":0, "remaining":0}
	hub._commit(fixture)
	await _select_slot("candidate_0")
	check(_action().disabled and _hint().contains("2 свободных места"), "one free storage place blocks hire with explanation")
	before = hub.run.to_dict()
	_action().pressed.emit()
	check(hub.run.to_dict() == before, "forced storage-limit action rejected")
	await _capture("storage-limit")
	fixture = HeroHubState.from_dict(before)
	check(fixture.discard_item(fixture.next_item_id - 1), "fixture frees second storage place")
	hub._commit(fixture)
	check(not _action().disabled, "exactly two free places permits hire")
	await _click(_action())
	check(hub.run.items.size() == HeroHubState.MAX_ITEMS, "hire fills last two places without deleting existing gear")
	_check_saved("full storage hire")
	fixture = HeroHubState.from_dict(baseline)
	fixture.next_id = 1000000000
	hub._commit(fixture)
	await _select_slot("candidate_0")
	check(_action().disabled and not _hint().is_empty(), "ID boundary explained without trying invalid save")
	before = hub.run.to_dict()
	_action().pressed.emit()
	check(hub.run.to_dict() == before, "ID boundary action rejected")
	_reset()

func _test_guards() -> void:
	await _select_slot("candidate_0")
	var id := merc._selected_hero_id
	var before := hub.run.to_dict()
	var bytes := FileAccess.get_file_as_bytes(path)
	await _press_name("TabSmith")
	merc._on_action("mercenary_action")
	merc.hire_requested.emit(id)
	hub._on_mercenary_hire_requested(id)
	check(hub.run.to_dict() == before, "hidden tab requests rejected at page dashboard and host")
	await _press_name("TabMercenaries")
	await _press_name("TabExpedition")
	await _press_name("ManageParty")
	hub._on_mercenary_hire_requested(id)
	check(hub.run.to_dict() == before, "old management page cannot execute section request")
	await _press_name("deck_edit")
	var draft := hub.deck_draft.duplicate()
	await _press_name("DashboardBack")
	await _press_name("TabMercenaries")
	await _click(_action())
	check(hub.deck_editing and hub.deck_draft == draft, "hire preserves unsaved deck draft")
	await _press_name("TabExpedition")
	await _press_name("ManageParty")
	await _press_name("deck_cancel")
	await _press_name("DashboardBack")
	await _press_name("TabMercenaries")
	_reset()
	before = hub.run.to_dict()
	bytes = FileAccess.get_file_as_bytes(path)
	id = hub.run.candidates[0].id
	# Временные барьеры проверяют отложенный сигнал без запуска боевого runtime.
	hub.run.phase = "battle"
	hub._on_mercenary_hire_requested(id)
	hub._on_mercenary_party_requested(hub.run.party[0], false)
	hub.run.phase = "hub"
	hub.run.battle_report = {"open":true}
	hub._on_mercenary_hire_requested(id)
	hub._on_mercenary_party_requested(hub.run.party[0], false)
	hub.run.battle_report = before.battle_report.duplicate(true)
	hub._storage_error = "test barrier"
	hub._on_mercenary_hire_requested(id)
	hub._storage_error = ""
	hub._on_mercenary_hire_requested(-1)
	hub._on_mercenary_party_requested(-1, true)
	check(hub.run.to_dict() == before and FileAccess.get_file_as_bytes(path) == bytes, "phase report storage and unknown ID barriers preserve profile and file")

func _test_reload_and_legacy() -> void:
	await _select_slot("candidate_3")
	await _click(_action())
	var before := hub.run.to_dict()
	viewport.remove_child(hub)
	hub.queue_free()
	await process_frame
	await _load_hub()
	check(hub.run.to_dict() == before, "reopening hub restores hired hero gear and composition")
	await _press_name("TabMercenaries")
	var legacy := HeroHubState.create(5501, 1)
	hub._commit(legacy)
	await _select_slot("candidate_3")
	var mage := hub.run.candidates[3].to_dict()
	await _click(_action())
	check((hub.run.heroes[mage.id] as HeroProgression).to_dict() == mage, "legacy H1 mage candidate hires through same UI")
	_check_saved("legacy hire")
	_reset()

func _test_authoring() -> void:
	await _select_slot("party_0")
	var button := _action()
	var hint := merc._slot("mercenary_hint") as Label
	var sibling := merc.get_node("Roster") as Control
	var sibling_rect := sibling.get_global_rect()
	button.name = "RenamedAction"
	button.reparent(merc, true)
	button.position += Vector2(-5, 0)
	button.add_theme_font_size_override("font_size", 15)
	hint.name = "RenamedHint"
	hint.reparent(merc, true)
	var rect := button.get_global_rect()
	for cycle: int in 3: hub._render()
	check(button.get_global_rect() == rect and sibling.get_global_rect() == sibling_rect, "action rename/reparent/move preserves own and neighbor placement")
	check(button.get_theme_font_size("font_size") == 15 and button.pressed.get_connections().size() == 1, "action theme and single connection survive render")
	var id := merc._selected_hero_id
	await _click(button)
	check(not hub.run.party.has(id), "reparented renamed action still saves selected hero change")
	var before := hub.run.to_dict()
	button.hide()
	hub._render()
	button.pressed.emit()
	check(not button.visible and hub.run.to_dict() == before, "hidden action remains hidden and inert")
	button.show()
	button.free()
	hub._render()
	check(_hint() == "Перевод без стоимости", "surviving hint renders without action button")
	await _select_slot("candidate_0")
	check(_hint().begins_with("Бесплатно"), "surviving hint updates when selection changes after button deletion")
	hint.free()
	hub._render()
	merc._on_action("mercenary_action")
	check(_action() == null and merc._slot("mercenary_hint") == null and hub.run.to_dict() == before, "deleted action and hint stay deleted without mutation")

func _check_sizes(label: String) -> void:
	for resolution: Vector2i in [Vector2i(1024, 720), Vector2i(1280, 850), Vector2i(1920, 1080)]:
		viewport.size = resolution
		await _settle()
		var panel := merc.get_node("HeroDetail") as Control
		var detail_rect := panel.get_global_rect().grow(1.0)
		var stage_rect := (merc.get_node("HeroStage") as Control).get_global_rect().grow(1.0)
		var detail_controls: Array[Control] = [_action(), merc._slot("mercenary_hint") as Control, merc._slot("hero_points") as Control, merc._slot("hero_detail") as Control, merc._slot("hero_equipment") as Control, merc._slot("passive_icons") as Control, merc._slot("ability_icons") as Control]
		var stage_controls: Array[Control] = [merc._slot("hero_title") as Control, merc._slot("hero_identity") as Control, merc._slot("hero_portrait") as Control, merc._slot("skin_label") as Control, merc._slot("skin_choice") as Control, merc._slot("skin_notice") as Control]
		for control: Control in detail_controls:
			check(detail_rect.encloses(control.get_global_rect()), "%s inside inspection panel at %s" % [control.name, resolution])
		for control: Control in stage_controls:
			check(stage_rect.encloses(control.get_global_rect()), "%s inside hero stage at %s" % [control.name, resolution])
		var stats := merc._slot("hero_detail") as Control
		var equipment := merc._slot("hero_equipment") as Control
		check(not stats.get_global_rect().intersects(equipment.get_global_rect()), "stats and equipment rows do not overlap at %s" % resolution)
		await _capture("%s-%dx%d" % [label, resolution.x, resolution.y])
	viewport.size = Vector2i(1280, 850)
	await _settle()

func _reset() -> void:
	hub._commit(HeroHubState.from_dict(baseline))
	check(hub._pending_save == null, "fixture publishes through store")

func _check_saved(label: String) -> void:
	var loaded: HeroHubState = HeroHubStore.read_run(path).get("run") as HeroHubState
	check(loaded != null and loaded.to_dict() == hub.run.to_dict(), label + " persists complete profile")

func _load_hub() -> void:
	hub = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	hub.save_path = path
	hub.expedition_mode = true
	hub.mage_deck_mode = true
	viewport.add_child(hub)
	await _settle()
	merc = hub.get_node("ExpeditionDashboard/SectionPages/MercenariesPage") as HubSectionPage
	check(hub.run != null, "hub loaded")

func _action() -> Button:
	for node: Node in merc.find_children("*", "Button", true, false):
		if String(node.get_meta(&"hub_action", "")) == "mercenary_action": return node as Button
	return null

func _hint() -> String:
	return (merc._slot("mercenary_hint") as Label).text

func _select_slot(key: String) -> void:
	var parts: PackedStringArray = key.split("_")
	if parts.size() != 2:
		check(false, "selection target key is valid: " + key)
		return
	var candidate_selection: bool = parts[0] == "candidate"
	var mode_action: String = "mercenaries_hire" if candidate_selection else "mercenaries_owned"
	var mode_button := merc._action_button(mode_action)
	if mode_button != null and not mode_button.button_pressed:
		await _click(mode_button)
	var index: int = int(parts[1])
	var hero_id: int = 0
	if candidate_selection:
		if index >= 0 and index < hub.run.candidates.size(): hero_id = hub.run.candidates[index].id
	elif index >= 0 and index < hub.run.party.size():
		hero_id = hub.run.party[index]
	if hero_id <= 0:
		check(false, "selection target exists: " + key)
		return
	var card := _card(("candidate:" if candidate_selection else "hero:") + str(hero_id))
	check(card != null, "new dynamic grid contains " + key)
	if card != null: await _click(card)

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
