extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BLEEDING UI: " + label)

func _run() -> void:
	demo = (load("res://scenes/demo/bleeding_battle.tscn") as PackedScene).instantiate()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport); viewport.add_child(demo); viewport.notify_mouse_entered()
	await process_frame; await process_frame
	check(demo.session is BattleBleedingSession and demo.bleeding_mode,"D3 scene")
	var s := demo.session as BattleBleedingSession
	flatten(s)
	await click(at(s.units[0]))
	await key(KEY_A)
	var before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	await motion(at(s.units[1]))
	check(demo._forecast != null and demo._forecast.status == &"APPLIED","input exact forecast")
	check(demo._forecast_panel.text.contains("кровотечение 0 → 2") and demo._forecast_panel.text.contains("до лечения"),"forecast duration and HP gate")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before,"hover isolated")
	await capture("bleeding-01-forecast")
	var panel := demo._forecast_panel
	await motion(panel.global_position + Vector2(50,50))
	for _i in 10:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
		wheel.position = panel.global_position + Vector2(50,50); wheel.global_position = wheel.position
		viewport.push_input(wheel,true)
		wheel = wheel.duplicate()
		wheel.pressed = false
		viewport.push_input(wheel,true)
	await process_frame
	check(panel.get_v_scroll_bar().value > 0 and demo._forecast != null,"real scroll retains forecast")
	await click(at(s.units[1]))
	check(s.units[1].bleeding.ticks_left == 2 and s.units[0].action_resources.get_main_left() == 0,"input attack applies and pays")
	await key(KEY_M)
	await click(at(s.units[1]))
	check(demo._inspection_text(s.units[1]).contains("Кровотечение: тиков — 2"),"inspection active status")
	await capture("bleeding-02-applied")
	var actor_before := s.units[0].to_snapshot_dict()
	await click(at(s.units[2])); await click(at(s.units[0]))
	check(s.units[0].to_snapshot_dict() == actor_before and s.units[1].bleeding.ticks_left == 2,"input selection no resources or tick")
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN and s.units[1].bleeding.ticks_left == 1,"input team boundary one tick")
	check(demo._log.text.contains("тик кровотечения"),"boundary events visible")
	await key(KEY_R)
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.units[1].bleeding.ticks_left == 0,"reset fresh runtime")
	flatten(s)
	for item: ItemInstance in s.state.get_owner(s.units[1].id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	demo._refresh()
	await key(KEY_5)
	await motion(at(s.units[1]))
	check(s.rune_selected and demo._forecast != null and demo._forecast.status == &"APPLIED","input rune forecast")
	check(demo._forecast_panel.text.contains("Перк «Кровавая руна» обходит") and demo._forecast_panel.text.contains("кровотечение 0 → 2"),"bypass explained on armor-only")
	await capture("bleeding-03-rune")
	await click(at(s.units[1]))
	check(s.units[1].bleeding.ticks_left == 2 and s.units[1].vitals.get_hp() == 32.0,"rune applies without HP loss")
	await key(KEY_R)
	flatten(s)
	await key(KEY_5); await motion(at(s.units[1]))
	check(demo._forecast_panel.text.contains("кровотечение 0 → 2"),"stack setup forecast adds two ticks")
	await click(at(s.units[1]))
	check(s.units[1].bleeding.ticks_left == 2,"first stack attack applies two ticks")
	s.units[0].try_refill_turn_resources()
	# Прямое восстановление ресурсов не меняет revision, поэтому обновляем UI
	# и явно уводим курсор, чтобы следующий hover построил прогноз заново.
	demo._refresh()
	var stack_before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	await key(KEY_5); await motion(Vector2(-10,-10)); await motion(at(s.units[1]))
	check(demo._forecast_panel.text.contains("кровотечение 2 → 4"),"stack forecast adds two to remaining duration")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == stack_before,"stack preview remains isolated")
	await capture("bleeding-06-stacked")
	await click(at(s.units[1]))
	check(s.units[1].bleeding.ticks_left == 4,"second stack attack leaves four live ticks")
	check(demo._log.text.contains("кровотечение продлено — тиков: 4"),"stack log shows resulting duration")
	await key(KEY_M); await click(at(s.units[1]))
	check(demo._inspection_text(s.units[1]).contains("Кровотечение: тиков — 4"),"stack inspection shows four ticks")
	await key(KEY_R)
	flatten(s)
	s.units[1].bleeding.immune = true
	demo._refresh()
	await key(KEY_5); await motion(at(s.units[1]))
	check(demo._forecast != null and demo._forecast_panel.text.contains("не наложено: иммунитет"),"rune respects immunity in forecast")
	await capture("bleeding-04-immunity")
	await click(at(s.units[1]))
	check(s.units[1].bleeding.ticks_left == 0,"rune immune no status")
	await key(KEY_R)
	flatten(s)
	# Последний противник умирает на границе: UI должен обновиться и при false return.
	for enemy: UnitState in s.units:
		if enemy.faction == Faction.Type.ENEMY and enemy != s.units[1]: s._queue.submit(DeathCommand.new(enemy.id,DamageSource.new(&"test",0,enemy.cell)),s.context)
	var target := s.units[1]
	target.vitals.set_hp(1.0)
	target.bleeding.ticks_left = 2
	target.bleeding.source = DamageSource.new(&"attack",0,s.units[0].cell,s.units[0].id,s.units[0].id).to_dict()
	target.bleeding.hit_id = "test-final"
	demo._refresh()
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.VICTORY and demo._phase_label.text.contains("ПОБЕДА"),"lethal boundary displayed immediately")
	await capture("bleeding-05-victory")
	viewport.queue_free()
	await process_frame; await process_frame
	print("BLEEDING UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func flatten(s: BattleBleedingSession) -> void:
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x,y),0)
			s.board.set_terrain(Vector2i(x,y),TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0],Vector2i(2,3))
	s.board.move_unit(s.units[1],Vector2i(3,3))
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
	demo._refresh()

func at(unit: UnitState) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(unit.cell)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event,true)
	event.pressed = false; viewport.push_input(event,true)
	await process_frame

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event,true)
	await process_frame; await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event,true)
	event.pressed = false; viewport.push_input(event,true)
	await process_frame; await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK,"PNG " + label)
