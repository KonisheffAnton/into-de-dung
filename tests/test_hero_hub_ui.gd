extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: HeroHubScreen
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HERO HUB UI: " + label)

func _run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/demo/hero_hub.tscn", "F5 starts the persistent hero hub")
	demo = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate()
	demo.save_path = "user://hero-hub-ui-%d.save" % Time.get_ticks_usec()
	var path := demo.save_path
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport); viewport.add_child(demo); viewport.notify_mouse_entered()
	await process_frame; await process_frame
	check(demo.run != null and demo.run.phase == "hub", "opens hub")
	if demo.run == null:
		quit(1); return
	check(FileAccess.file_exists(path), "initial roster persisted before interaction")
	await capture("h1-01-hub")
	var fixture := HeroHubState.from_dict(demo.run.to_dict())
	var id: int = fixture.party[0]
	(fixture.heroes[id] as HeroProgression).award_experience_tenths(1000)
	(fixture.heroes[id] as HeroProgression).hp_current = 10.0
	demo._commit(fixture)
	await process_frame; await process_frame
	var before := demo.run.to_dict()
	await press("alloc_plus_2")
	check(demo.pending_delta[2] == 1 and demo.run.to_dict() == before, "real input allocates only preview")
	(demo.find_child("HeroHubScroll", true, false) as ScrollContainer).ensure_control_visible(demo.find_child("apply_allocation", true, false) as Control)
	await process_frame; await process_frame
	await capture("h1-02-allocation")
	await press("apply_allocation")
	check((demo.run.heroes[id] as HeroProgression).hp_current == 12.0 and (demo.run.heroes[id] as HeroProgression).allocated[2] == 1, "Apply commits HP growth and point")
	await press("respec")
	check(demo.run.gold == 50 and (demo.run.heroes[id] as HeroProgression).available_points() == 1, "paid reset through UI")
	var count := demo.run.heroes.size()
	var candidate := demo.run.candidates[0].to_dict()
	await press("hire_0")
	check(demo.run.heroes.size() == count + 1 and (demo.run.heroes[candidate.id] as HeroProgression).to_dict() == candidate, "free hire keeps displayed candidate")
	var scroll := demo.find_child("HeroHubScroll",true,false) as ScrollContainer
	if scroll == null:
		for node: Node in demo.find_children("*","ScrollContainer",true,false): scroll = node as ScrollContainer
	check(scroll != null and scroll.scroll_vertical > 0, "long hub stays scrollable")
	var saved := demo.run.to_dict()
	demo.save_path = path + "/blocked"
	await press("hire_1")
	check(demo._pending_save != null and demo.run.to_dict() == saved, "write failure leaves live roster untouched")
	demo.save_path = path
	demo._retry_save()
	await process_frame; await process_frame
	check(demo._pending_save == null and demo.run.heroes.size() == count + 2, "retry publishes once")
	var discarded_id: int = demo.run.equipped(id, "weapon").id
	await press("unequip_%d" % discarded_id)
	await press("discard_%d" % discarded_id)
	check(not demo.run.items.has(discarded_id) and HeroHubStore.read_run(path).run.to_dict() == demo.run.to_dict(), "warehouse discard uses explicit input and persists")
	await press_text("Отправиться в настоящий бой")
	check(demo.run.phase == "battle" and demo.battle_view != null, "input enters saved real battle")
	if demo.battle_view != null:
		var session: BattleCoreReactionsSession = demo._battle_bundle.session
		check(session.is_deploying(), "deployment precedes enemy team")
		await capture("h1-03-deployment")
		var original_board := session.board
		demo.battle_view.reset_demo()
		check(session.board == original_board, "R cannot reset checkpoint")
		demo.battle_view.end_turn()
		var ticks: int = 0
		while demo.battle_view != null and (demo.battle_view.is_execution_pending() or session.phase == BattleTacticalSession.Phase.ENEMY_TURN) and ticks < 180:
			await process_frame
			ticks += 1
		if demo.battle_view != null: demo.battle_view._join_execution()
		# Test-only terminal fixture still uses the production queue and result extraction.
		for enemy_id: int in session.living_ids(Faction.Type.ENEMY):
			session._submit(DeathCommand.new(enemy_id,DamageSource.new(&"test",0,Vector2i.ZERO)))
		await process_frame; await process_frame; await process_frame
		check(demo.run.phase == "hub" and demo.battle_view == null, "terminal outcome autosaves and returns without extra click")
		check(HeroHubStore.read_run(path).run.to_dict() == demo.run.to_dict(), "on-disk outcome matches visible roster")
		await capture("h1-04-result")
	# Аварийный prefix не коммитится; явная кнопка повторяет сохранённый старт.
	demo._start_battle()
	await process_frame; await process_frame
	var checkpoint := demo.run.to_dict()
	var broken: BattleCoreReactionsSession = demo._battle_bundle.session
	broken.start_battle()
	var steps: int = 0
	while broken.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		broken.step_enemy(); steps += 1
	var actor := broken.selected_unit()
	var enemy := broken.board.get_unit_by_id(broken.living_ids(Faction.Type.ENEMY)[0])
	broken.board.move_unit(enemy, actor.cell + Vector2i(1,0))
	broken._queue._max_commands = 1
	demo.battle_view._execute_live(&"attack_unit", [enemy.id], true)
	var deadline := Time.get_ticks_msec() + 5000
	while demo.battle_view.is_execution_pending() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(broken.phase == BattleTacticalSession.Phase.FAULTED and demo.run.to_dict() == checkpoint, "fault prefix gives no persistent rewards")
	check(not demo.battle_view._stats.text.contains("Нажмите R") and not demo.battle_view._status.text.contains("заново: R"), "fault screen gives actionable checkpoint instruction")
	await press("ReturnToHeroHubButton")
	check(demo._battle_bundle.session != broken and (demo._battle_bundle.session as BattleCoreReactionsSession).is_deploying() and demo.run.to_dict() == checkpoint, "real fault retry button restores unchanged checkpoint")
	check(HeroHubStore.read_run(path).run.to_dict() == checkpoint, "fault retry preserves saved roster and XP")
	var final_profile := demo.run.to_dict()
	viewport.remove_child(demo); demo.queue_free()
	await process_frame
	demo = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate()
	demo.save_path = path; viewport.add_child(demo)
	await process_frame; await process_frame
	check(demo.run.to_dict() == final_profile, "reopening does not reroll candidates or duplicate XP")
	viewport.remove_child(demo); demo.queue_free(); viewport.queue_free()
	await process_frame; await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HERO HUB UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func press(name_value: String) -> void:
	var button := demo.find_child(name_value,true,false) as Button
	check(button != null,"button exists: " + name_value)
	if button != null: await click(button)

func press_text(value: String) -> void:
	for node: Node in demo.find_children("*","Button",true,false):
		var button := node as Button
		if button.text == value:
			await click(button); return
	check(false,"button text: " + value)

func click(button: Button) -> void:
	var node: Node = button.get_parent()
	while node != null:
		if node is ScrollContainer: (node as ScrollContainer).ensure_control_visible(button)
		node = node.get_parent()
	await process_frame; await process_frame
	var position := button.global_position + button.size * 0.5
	var motion := InputEventMouseMotion.new(); motion.position = position
	viewport.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	viewport.push_input(event,true)
	event.pressed = false; viewport.push_input(event,true)
	await process_frame; await process_frame

func capture(name_value: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(name_value + ".png")) == OK,"capture " + name_value)
