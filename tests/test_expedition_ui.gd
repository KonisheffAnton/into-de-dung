extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var menu: Control
var hub: HeroHubScreen
var captures: String = ""
var path: String

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL EXPEDITION UI: " + label)

func _run() -> void:
	path = "user://u14-ui-%d.save" % Time.get_ticks_usec()
	viewport = SubViewport.new(); viewport.size = Vector2i(1280,850); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport); viewport.notify_mouse_entered()
	menu = (load("res://scenes/demo/main_menu.tscn") as PackedScene).instantiate()
	menu.set("save_path",path); viewport.add_child(menu)
	await process_frame; await process_frame
	await capture("u14-01-menu")
	await press("continue_game")
	hub = menu.find_child("ExpeditionHub",true,false) as HeroHubScreen
	check(hub != null and hub.run != null and hub.expedition_mode,"menu opens persistent expedition hub")
	if hub == null: quit(1); return
	hub._commit(HeroHubState.create(4280))
	await press("start_expedition")
	check(hub.run.phase == "expedition" and hub.run.expedition.phase == "route","start through real input")
	if hub.run.expedition == null:
		printerr("UI start state: " + hub._message + " / " + hub._storage_error)
		quit(1); return
	var map := hub.find_child("room_14",true,false) as Button
	check(map != null and map.disabled and map.tooltip_text.is_empty() and not map.text.contains("дозорных") and not map.text.contains("Без модификатора"),"future final visible, exact conditions hidden")
	check(hub.find_children("room_*","Button",true,false).size() == 14,"all fourteen nodes visible in map")
	var available: int = hub.run.expedition.available_nodes()[0]
	var button := hub.find_child("room_%d" % available,true,false) as Button
	check(button != null and not button.disabled and button.text.contains("3 дозорных") and button.tooltip_text.contains("HP 24") and button.tooltip_text.contains("Клетки:"),"nearest exact encounter disclosed")
	(hub.find_child("HeroHubScroll",true,false) as ScrollContainer).scroll_vertical = 0
	await capture("u14-02-map")
	var before := hub.run.to_dict()
	hub.save_path = path + "/cannot-write"
	await press("room_%d" % available)
	check(hub._pending_save != null and hub.run.to_dict() == before and hub.battle_view == null,"failed checkpoint write keeps published profile and blocks battle")
	var pending := hub._pending_save.to_dict()
	hub._expedition_action("choose",{"node":2})
	check(hub._pending_save.to_dict() == pending,"pending save blocks second action")
	hub.save_path = path
	await press("retry_save")
	check(hub.run.to_dict() == pending and hub.battle_view != null,"retry writes exact candidate then starts battle")
	check(HeroHubStore.read_run(path).run.to_dict() == pending,"disk checkpoint matches")
	await capture("u14-03-deployment")
	# Только fixture для проверки UI исхода; полный поход без DeathCommand покрыт playthrough runner.
	await terminal_fixture()
	check(hub.run.expedition.phase == "reward" and hub.battle_view == null,"real queue terminal hands off to reward panel")
	(hub.find_child("HeroHubScroll",true,false) as ScrollContainer).scroll_vertical = 0
	await capture("u14-04-reward")
	await press("reward_0")
	check(hub.run.expedition.phase == "route" and hub.run.expedition.artifacts.size() == 1,"reward real click")
	await press("artifact_1_slot_1")
	check(hub.run.expedition.artifact(1).hero_id == hub.selected_hero_id,"equip artifact real click")
	await capture("u14-05-inventory")
	await press("artifact_off_1")
	check(hub.run.expedition.artifact(1).hero_id == 0,"unequip real click")
	for unused: int in 10:
		if hub.run.expedition.current_node().get("kind") == "camp": break
		match hub.run.expedition.phase:
			"route": await press("room_%d" % hub.run.expedition.available_nodes()[0])
			"battle": await terminal_fixture()
			"reward": await press("reward_0")
			"service": await press("service_heal")
	check(hub.run.expedition.phase == "service" and hub.run.expedition.current_node().kind == "camp","arrives safe camp")
	await press("service_heal")
	check(hub.run.expedition.phase == "camp_departure","service before camp choice")
	await press("camp_leave")
	check(hub.run.phase == "hub" and hub.run.gold > 100 and hub.run.essence >= 20,"exit through input banks loot")
	(hub.find_child("HeroHubScroll",true,false) as ScrollContainer).scroll_vertical = 0
	await capture("u14-06-result")
	await process_frame; await process_frame
	var wallet := hub.find_child("HubWallet",true,false) as Label
	check(wallet != null and wallet.get_global_rect().end.x <= viewport.size.x - 10,"whole wallet fits viewport")
	check(wallet != null and wallet.size.x >= wallet.get_theme_font("font").get_string_size(wallet.text,HORIZONTAL_ALIGNMENT_LEFT,-1,wallet.get_theme_font_size("font_size")).x,"wallet width includes every digit")
	var final_profile := hub.run.to_dict()
	viewport.remove_child(menu); menu.queue_free(); await process_frame
	menu = (load("res://scenes/demo/main_menu.tscn") as PackedScene).instantiate(); menu.set("save_path",path); viewport.add_child(menu)
	await process_frame; await press("continue_game")
	hub = menu.find_child("ExpeditionHub",true,false) as HeroHubScreen
	check(hub.run.to_dict() == final_profile,"restart preserves settled result")
	viewport.remove_child(menu); menu.queue_free(); viewport.queue_free(); await process_frame; await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("EXPEDITION UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func terminal_fixture() -> void:
	if hub.battle_view == null: check(false,"fixture battle exists"); return
	hub.battle_view._join_execution(); hub.battle_view.set_process(false)
	var session: BattleCoreReactionsSession = hub._battle_bundle.session
	if session.is_deploying(): session.start_battle()
	for id: int in session.living_ids(Faction.Type.ENEMY): session._submit(DeathCommand.new(id,DamageSource.new(&"test",0,Vector2i.ZERO)))
	hub._process(0.0)
	await process_frame; await process_frame

func press(key: String) -> void:
	await process_frame; await process_frame
	var button := menu.find_child(key,true,false) as Button
	check(button != null and not button.disabled,"button " + key)
	if button == null or button.disabled: return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame; await process_frame
	var position := button.global_position + button.size * 0.5
	var motion := InputEventMouseMotion.new(); motion.position = position; viewport.push_input(motion,true)
	var event := InputEventMouseButton.new(); event.position = position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	viewport.push_input(event,true); event.pressed = false; viewport.push_input(event,true)
	await process_frame; await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	# Вложенные Container согласуют минимум размеров за несколько deferred layout проходов.
	for unused: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK,"capture " + label)
