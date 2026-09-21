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
		printerr("FAIL ARMOR UI: " + label)

func _run() -> void:
	demo = (load("res://scenes/demo/armor_battle.tscn") as PackedScene).instantiate()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	check(demo.session is BattleArmorSession and demo.armor_mode and demo.tactical_mode, "armor scene available")
	var s := demo.session as BattleArmorSession
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x,y),0)
			s.board.set_terrain(Vector2i(x,y),TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0],Vector2i(3,3))
	s.board.move_unit(s.units[1],Vector2i(4,3))
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
	demo._refresh()
	await process_frame
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[0].cell))
	await key(KEY_A)
	var before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	await motion(demo.board_view.global_position + demo.board_view.cell_center(s.units[1].cell))
	check(demo.attack_mode and demo._forecast != null and demo._forecast.status == &"APPLIED", "real input opens exact forecast")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before, "hover preserves live")
	check(demo._forecast_panel.text.contains("Физический: вход 10") and demo._forecast_panel.text.contains("Огонь: вход 10"), "two quantized types explained")
	check(demo._forecast_panel.text.contains("броня 25 → 15 / 100") and demo._forecast_panel.text.contains("урон 10 · лечение 0"), "armor and gross HP explained")
	var armor_bar := false
	for visual: BattleDemoIsoVisual in demo.board_view._entity_visuals:
		if visual.unit == s.units[1]: armor_bar = visual.armor_values.get("current") == 25 and visual.forecast_entry["after"].get("armor_current") == 15
	check(armor_bar, "unit armor bar shows forecast marker")
	await capture("armor-01-forecast")
	var panel := demo._forecast_panel
	var scroll_before := panel.get_v_scroll_bar().value
	await motion(panel.global_position + Vector2(40,40))
	for index in 12:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		event.position = panel.global_position + Vector2(40,40)
		event.global_position = event.position
		viewport.push_input(event,true)
		event = event.duplicate()
		event.pressed = false
		viewport.push_input(event,true)
	await process_frame
	await process_frame
	check(demo._forecast != null and panel.get_v_scroll_bar().value > scroll_before, "real wheel scroll keeps forecast")
	await capture("armor-02-scroll")
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[1].cell))
	check(s.units[1].vitals.get_hp() == 24.0 and ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(s.units[1].id)))["current"] == 15, "mouse attack matches forecast including item heal")
	check(s.units[0].action_resources.get_main_left() == 0, "attack costs1")
	await capture("armor-03-applied")
	demo.reset_demo()
	await process_frame
	check(demo._action_bar._buttons[3].get_meta("action_id") == &"restore_armor", "explicit restore ability")
	await key(KEY_4)
	check(s.units[0].armor.grants.size() == 1 and s.units[0].armor.grants[0]["remaining"] == 20 and s.units[0].action_resources.get_main_left() == 0, "real key4 restores and pays full action")
	check(demo._stats.text.contains("120 / 100") and demo._stats.text.contains("временная: 20"), "extra armor visible")
	await capture("armor-04-recovery")
	viewport.queue_free()
	await process_frame
	await process_frame
	print("ARMOR UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event,true)
	event.pressed = false
	viewport.push_input(event,true)
	await process_frame

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event,true)
	await process_frame
	await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event,true)
	event.pressed = false
	viewport.push_input(event,true)
	await process_frame
	await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK,"PNG " + label)
