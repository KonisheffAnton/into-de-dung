extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var screen: HeroHubScreen
var path: String
var captures: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST RESELECTION UI: " + label)

func _has_label_text(root_node: Node, text_value: String) -> bool:
	for node: Node in root_node.find_children("*", "Label", true, false):
		if (node as Label).text.contains(text_value): return true
	return false

func _save_capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	_check(viewport.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK,
		"optional GPU capture " + name)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	path = "user://host-reselection-%d.save" % Time.get_ticks_usec()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var packed := load("res://scenes/demo/hero_hub.tscn") as PackedScene
	screen = packed.instantiate() as HeroHubScreen
	screen.save_path = path
	screen.mage_deck_mode = true
	screen.expedition_mode = true
	viewport.add_child(screen)
	await process_frame
	await process_frame
	if screen.run == null or screen.run.party.size() < 2:
		_check(false, "deck profile and party fixture load")
		await _cleanup()
		quit(1)
		return
	var selected_host: int = screen.run.party[0]
	var prepared := screen._copy_run()
	_check(prepared.select_mage_host(selected_host), "initial permanent host can start the run")
	var started := ExpeditionTransitions.apply(prepared, "start")
	_check(started.is_ok(), "deck expedition start fixture succeeds")
	if not started.is_ok():
		await _cleanup()
		quit(1)
		return
	var on_route := _finish_first_room(started.profile)
	if on_route == null:
		_check(false, "synthetic first-room fixture reaches route")
		await _cleanup()
		quit(1)
		return
	on_route.mage_deck.host_hero_id = 0
	on_route.expedition.host_hero_id = 0
	if HeroHubState.from_dict(on_route.to_dict()) == null:
		_check(false, "route fixture with missing host passes profile validation")
		await _cleanup()
		quit(1)
		return
	screen._commit(on_route)
	await process_frame
	await process_frame
	_check(_has_label_text(screen, "Прежний носитель погиб. Выберите нового носителя для продолжения."), "route panel explains mandatory reselection")
	await _save_capture("host-reselection-required")
	var route_before: Array[int] = screen.run.expedition.route.duplicate()
	var party_buttons: int = 0
	for id: int in screen.run.party:
		var hero: HeroProgression = screen.run.heroes[id]
		if hero.hp_current <= 0.0: continue
		var choice := screen.find_child("select_host_%d" % id, true, false) as Button
		var class_definition := HeroCatalog.class_definition(hero.class_id)
		_check(choice != null and class_definition != null and choice.text.contains(hero.name)
			and choice.text.contains(class_definition.display_name), "living party candidate has a named, localized class-labelled choice")
		party_buttons += 1
	var bench_id: int = screen.run.candidates[0].id
	_check(screen.find_child("select_host_%d" % bench_id, true, false) == null, "roster candidate outside current party is not offered")
	_check(party_buttons == screen.run.party.size(), "all current living party members are offered")
	var map := screen.find_child("ExpeditionMap", true, false) as ExpeditionMapView
	var host_choice := screen.find_child("HostReselection", true, false) as Control
	var viewport_rect := viewport.get_visible_rect()
	var map_rect := map.get_global_rect() if map != null else Rect2()
	var host_rect := host_choice.get_global_rect() if host_choice != null else Rect2()
	_check(host_choice != null and viewport_rect.encloses(host_rect) and map != null
		and host_rect.end.y <= map_rect.position.y,
		"mandatory host prompt and candidates fit above the route map at 1280x850")
	for id: int in screen.run.party:
		var hero: HeroProgression = screen.run.heroes[id]
		if hero.hp_current <= 0.0: continue
		var choice := screen.find_child("select_host_%d" % id, true, false) as Button
		if choice == null: continue
		var choice_rect := choice.get_global_rect()
		_check(viewport_rect.encloses(choice_rect) and choice_rect.end.y <= map_rect.position.y,
			"host choice remains fully visible above map for hero %d" % id)
	var available_nodes: Array[int] = screen.run.expedition.available_nodes()
	var available := -1
	for node_data: Dictionary in screen.run.expedition.plan.nodes:
		var node_id := int(node_data.id)
		if available_nodes.has(node_id) and node_data.kind in ["battle", "elite", "final"]:
			available = node_id
			break
	_check(available > 0, "fixture offers an available battle room for explicit-entry verification")
	var room := screen.find_child("room_%d" % available, true, false) as Button
	var room_count := 0
	var all_rooms_disabled := map != null
	if map != null:
		for map_child: Node in map.get_children():
			if not map_child is Button or not map_child.name.begins_with("room_"): continue
			room_count += 1
			if not (map_child as Button).disabled: all_rooms_disabled = false
		if room_count != screen.run.expedition.plan.nodes.size(): all_rooms_disabled = false
	_check(map != null and room != null and all_rooms_disabled, "all room entries are disabled until a host is saved")
	var failed_route: Array[int] = screen.run.expedition.route.duplicate()
	screen._expedition_action("choose", {"node": available})
	_check(screen.run.expedition.route == failed_route and screen.run.expedition.phase == "route", "room action cannot bypass required host selection")
	var next_host: int = screen.run.party[1]
	var host_button := screen.find_child("select_host_%d" % next_host, true, false) as Button
	var blocker := FileAccess.open(path + ".block", FileAccess.WRITE)
	blocker.store_string("fixture")
	blocker.close()
	screen.save_path = path + ".block/save.dat"
	if host_button != null: host_button.pressed.emit()
	_check(screen._pending_save != null and int(screen.run.mage_deck.host_hero_id) == 0 and screen.run.expedition.host_hero_id == 0, "failed save keeps old hostless profile published")
	_check(screen._pending_save != null and int(screen._pending_save.mage_deck.host_hero_id) == next_host and screen._pending_save.expedition.host_hero_id == next_host and screen._pending_save.expedition.route == route_before, "failed save retains exact selection candidate without entering a room")
	await _save_capture("host-reselection-save-retry")
	screen.save_path = path
	screen._retry_save()
	_check(screen._pending_save == null and screen.run.mage_deck.host_hero_id == next_host and screen.run.expedition.host_hero_id == next_host and screen.run.expedition.route == route_before, "retry publishes saved host and leaves route unchanged")
	_check(HeroHubStore.read_run(path).run.to_dict() == screen.run.to_dict(), "retry host selection survives store reload")
	var saved_route := screen.run.to_dict()
	viewport.remove_child(screen)
	screen.queue_free()
	await process_frame
	screen = packed.instantiate() as HeroHubScreen
	screen.save_path = path
	screen.mage_deck_mode = true
	screen.expedition_mode = true
	viewport.add_child(screen)
	await process_frame
	await process_frame
	_check(screen.run != null and screen.run.to_dict() == saved_route, "reopened route retains selected host and checkpoint state")
	var reloaded_room := screen.find_child("room_%d" % available, true, false) as Button
	_check(reloaded_room != null and not reloaded_room.disabled, "reloaded host enables room entry")
	if reloaded_room != null: reloaded_room.pressed.emit()
	await process_frame
	await process_frame
	_check(screen.run.expedition.phase == "battle" and screen.run.expedition.route.size() == route_before.size() + 1, "room opens only after host selection and explicit entry")
	_check(screen.battle_view != null, "room entry reaches the existing battle view")
	await _cleanup()
	print("HOST RESELECTION UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _finish_first_room(source: HeroHubState) -> HeroHubState:
	var run := source
	if run.expedition == null or run.expedition.phase != "battle": return null
	var hp: Dictionary = {}
	var gear: Dictionary = {}
	for id: int in run.party:
		hp[id] = float((run.heroes[id] as HeroProgression).max_hp())
	for item: Dictionary in run.expedition.checkpoint.legacy_inputs.items:
		gear[item.id] = item.remaining
	var outcome := {"ruleset_id": ExpeditionRulesRegistry.DECK, "run_id": run.run_serial,
		"node_id": run.expedition.current_node().id, "serial": run.expedition.battle_serial,
		"victory": true, "hp": hp, "gear": gear, "host_has_died": false}
	var result := ExpeditionTransitions.apply(run, "outcome", outcome)
	if not result.is_ok(): return null
	run = result.profile
	result = ExpeditionTransitions.apply(run, "reward", {"index": -1})
	if not result.is_ok(): return null
	run = result.profile
	if run.expedition == null or run.expedition.phase != "route" or not run.dismiss_battle_report(): return null
	return run

func _cleanup() -> void:
	if screen != null and is_instance_valid(screen):
		if screen.battle_view != null: screen._clear_battle()
		viewport.remove_child(screen)
		screen.queue_free()
		await process_frame
	if viewport != null and is_instance_valid(viewport):
		root.remove_child(viewport)
		viewport.queue_free()
		await process_frame
	for suffix: String in ["", ".bak", ".block"]:
		var absolute := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)
