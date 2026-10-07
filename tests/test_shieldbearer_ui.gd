extends SceneTree

var passed: int = 0
var failed: int = 0
var demo: HeroHubBattleView
var viewport: SubViewport
var captures: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): captures = arg.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SHIELDBEARER UI: "+label)

func button(id: StringName) -> Button:
	for candidate: Button in demo._action_bar._buttons:
		if candidate.visible and candidate.get_meta("action_id",&"") == id: return candidate
	return null

func snapshot() -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(demo.session.state,[])
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func mouse(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=pos; motion.global_position=pos
	viewport.push_input(motion,true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/action_forecast_wait.gd").settle(self,demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label+".png"))==OK,"capture "+label)

func run() -> void:
	var hub := HeroHubState.create(73191,2)
	var hub_view := HeroHubScreen.new()
	hub_view.run=hub
	var hero_detail := hub_view._hero_detail(hub.heroes[1])
	check(hero_detail.contains("только меч своего класса") and not hero_detail.contains("общий отход"),"hub describes class weapon and actual abilities")
	hub_view.free()
	hub.enable_mage_deck()
	hub=ExpeditionTransitions.apply(hub,"start").profile
	check(hub!=null and hub.phase=="expedition","new deck profile starts expedition")
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(),"production factory")
	if bundle.is_empty(): quit(1); return
	var battle: BattleCoreReactionsSession = bundle.session
	check(battle.confirm_mage_deployment(),"production deployment confirmed")
	check(battle.confirm_mage_mulligan([]).status==ActionReceipt.APPLIED,"production hand confirmed")
	check(battle.start_battle(),"deployment starts combat")
	if battle.phase==BattleTacticalSession.Phase.ENEMY_TURN:
		battle._enemy_index=battle._enemy_ids.size(); battle.step_enemy()
	battle.select_unit(bundle.hero_units[1])
	demo=(load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	demo.supplied_session=battle
	viewport=SubViewport.new(); viewport.size=Vector2i(1280,850)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport); viewport.add_child(demo); viewport.notify_mouse_entered()
	await process_frame; await process_frame
	check(button(&"raise_shields")!=null,"class active is visible")
	var actor_id := battle.selected_id
	check(demo.board_view._view_actor_classes.get(actor_id)==&"shieldbearer" and demo.board_view._view_visual_classes.get(actor_id)==&"warrior","class identity retains explicit warrior visual")
	var has_sprite := false
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if visual.unit != null and visual.unit.id==actor_id:
			var sprite := visual.get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
			has_sprite=sprite!=null and sprite.visible
	check(has_sprite,"accepted player sprite is visible for new class")
	check(button(&"opportunity_guard")==null and button(&"cover_guard")==null and button(&"stunning_strike")==null,"old manual perks absent")
	var active_button := button(&"raise_shields")
	if active_button==null: demo.queue_free(); await process_frame; quit(1); return
	check(viewport.get_visible_rect().encloses(active_button.get_global_rect()),"class button fully visible in production viewport")
	var center := active_button.get_global_rect().get_center()
	var before := snapshot()
	await mouse(center)
	check(demo._guard_forecast!=null and demo._guard_forecast.status==ActionReceipt.APPLIED,"hover actual isolated ability preview")
	check(snapshot()==before,"hover does not spend action/shield/RNG")
	check(demo._forecast_panel.text.contains("90%") and demo._forecast_panel.text.contains("Откат: 1"),"forecast describes class effect and cooldown")
	check(demo.board_view.compact_forecast.label.text.contains("90%") and demo.board_view.compact_forecast.label.text.contains("откат 1"),"compact forecast explains class effect")
	await capture("shieldbearer-ready")
	# Нажатие и отпускание в разных кадрах ловят исчезновение/перестройку кнопки.
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=center; event.global_position=center
		event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		viewport.push_input(event,true)
		await process_frame; await process_frame
	for i: int in 500:
		if not demo.is_execution_pending(): break
		demo.skip_presentation(); await process_frame
	check(not demo.is_execution_pending(),"live worker/playback completes")
	var actor := demo.session.selected_unit()
	check(actor.armor.raised_shield.active and actor.action_resources.get_main_left()==0,"frame-separated click activates class shield")
	check(actor.action_resources.get_bonus_left()==1 and not actor.guard_stance,"reaction resource preserved; no ordinary guard")
	check(viewport.get_visible_rect().encloses(demo._action_bar.get_global_rect()),"whole panel fits viewport")
	check(demo._inspection_text(actor).contains("Оппортунист (пассивный)") and demo._inspection_text(actor).contains("90%"),"inspection explains passive and shield")
	await capture("shieldbearer-active")
	demo.queue_free(); await process_frame; await process_frame
	viewport.queue_free(); await process_frame
	print("SHIELDBEARER UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed==0 else 1)
