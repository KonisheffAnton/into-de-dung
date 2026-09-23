extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleInitiativeDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var launcher := (load("res://scenes/demo/tactical_battle.tscn") as PackedScene).instantiate() as BattleDemo
	viewport.add_child(launcher)
	await process_frame; await process_frame
	var entry := launcher.find_child("CompareTurnsButton", true, false) as Button
	check(entry != null and entry.visible, "F5 entry for comparison")
	if entry != null: await click(entry.global_position + entry.size * 0.5)
	await process_frame; await process_frame
	check(current_scene is BattleInitiativeDemo, "real launcher click loads comparison scene")
	if current_scene != null:
		var opened := current_scene
		current_scene = null
		opened.queue_free()
	launcher.queue_free()
	await process_frame; await process_frame
	demo = (load("res://scenes/demo/initiative_battle.tscn") as PackedScene).instantiate() as BattleInitiativeDemo
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame; await process_frame
	var battle := demo.session as BattleInitiativeSession
	check(battle.individual_turns and battle.current_actor_id == battle.units[0].id, "starts in individual mode with Astra")
	check(demo._order_label.text.contains("Астра 60") and demo._order_label.text.contains("Страж 50"), "mixed order and initiative visible")
	check(demo.size.x <= viewport.size.x and demo._individual_button.get_global_rect().end.x <= viewport.size.x, "comparison fits viewport")
	check(demo.size.y <= viewport.size.y and demo._instructions.get_global_rect().end.y <= viewport.size.y, "instructions and action bar fit viewport height")
	check((demo._roster.get_child(2) as Button).disabled, "other allied roster button disabled")
	var start := fixture(battle)
	await click(at(battle.units[2]))
	check(battle.selected_id == battle.units[0].id, "real click cannot select out-of-turn ally")
	await capture("initiative-01-order")
	var stats_scroll := demo._stats.get_parent() as ScrollContainer
	await wheel_down(stats_scroll.global_position + Vector2(40, 40))
	check(stats_scroll.get_v_scroll_bar().value > 0 and fixture(battle) == start, "real inspection scrolling leaves battle unchanged")
	await click(demo._action_bar._buttons[1].global_position + demo._action_bar._buttons[1].size * 0.5)
	check(battle.units[0].guard_stance and battle.units[0].action_resources.get_main_left() == 0, "GUI guard uses current actor main")
	await key(KEY_ENTER)
	check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN and battle.current_actor_id == battle.units[1].id, "Enter after GUI click advances one actor")
	var revision := battle.context.get_revision()
	await key(KEY_ENTER); await key(KEY_A)
	await click(at(battle.units[2]))
	check(battle.context.get_revision() == revision and not demo.attack_mode, "AI input cannot skip or spend")
	check(demo._stats.text.contains("Страж") and demo._end_turn_button.disabled, "current enemy explained during AI")
	await capture("initiative-02-enemy")
	# Ускоряется только интервал UI; намерения и команды остаются настоящими.
	demo.set_process(true)
	for _frame: int in 30:
		if battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		demo._ai_delay = 0.0
		await process_frame
	demo.set_process(false)
	check(battle.current_actor_id == battle.units[2].id and battle.can_player_act(), "single enemy finishes, Bor acts next")
	check(battle.units[0].guard_stance and battle.units[0].action_resources.get_main_left() == 0, "other actor turn retains Astra guard and resources")
	await key(KEY_A)
	await motion(at(battle.units[3]))
	check(demo._forecast != null and demo._forecast.status == ActionReceipt.APPLIED, "active Bor gets real attack forecast")
	var before := ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict()
	var expected: Dictionary = demo._forecast.snapshot_after.duplicate(true) if demo._forecast != null else {}
	await capture("initiative-03-forecast")
	await wheel_down(demo._forecast_panel.global_position + Vector2(40, 40))
	check(demo._forecast != null, "wheel input while reading retains forecast")
	check(ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == before, "reading forecast leaves live state intact")
	await click(at(battle.units[3]))
	check(ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == expected, "real input attack matches preview")
	await capture("initiative-04-attack")
	await key(KEY_ENTER)
	check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "next enemy starts")
	await click(demo._team_button.global_position + demo._team_button.size * 0.5)
	check(not battle.individual_turns and battle.round_number == 1 and fixture(battle) == start, "switch during AI starts identical fresh team battle")
	var fresh_board := battle.board
	demo._process(1.0)
	check(battle.board == fresh_board and battle.context.get_revision() == 0, "mode switch cancels old AI work")
	await click(at(battle.units[4]))
	check(battle.selected_id == battle.units[4].id, "team comparison allows free selection")
	check(demo._end_turn_button.text.contains("команды"), "team end-turn label")
	await capture("initiative-05-team")
	await key(KEY_ENTER)
	check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "team Enter starts whole enemy team")
	await click(demo._individual_button.global_position + demo._individual_button.size * 0.5)
	check(battle.individual_turns and fixture(battle) == start and battle.current_actor_id == battle.units[0].id, "switch back reproduces individual fixture")
	await key(KEY_ENTER)
	await key(KEY_R)
	fresh_board = battle.board
	demo._process(1.0)
	check(battle.board == fresh_board and battle.current_actor_id == battle.units[0].id and battle.can_player_act(), "reset during AI cancels old actor")
	await capture("initiative-06-reset")
	var back := find_button(demo, "К основному бою")
	await click(back.global_position + back.size * 0.5)
	await process_frame; await process_frame
	check(current_scene is BattleDemo and not current_scene is BattleInitiativeDemo, "real exit returns to original battle")
	if current_scene is BattleDemo:
		check((current_scene as BattleDemo).session.get_script() == BattleTacticalSession, "default battle retains original session")
	if current_scene != null:
		var opened := current_scene
		current_scene = null
		opened.queue_free()
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("INITIATIVE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func fixture(battle: BattleInitiativeSession) -> Array[Dictionary]:
	# ID нового боя другой, сравниваем исходные игровые условия без идентичности экземпляров.
	var result: Array[Dictionary] = []
	for unit: UnitState in battle.units:
		var items: Array[Dictionary] = []
		for item: ItemInstance in battle.state.get_owner(unit.id)._items.values():
			items.append({"def": item.get_definition_id(), "charges": item.get_charges_left()})
		result.append({"name": unit.debug_name, "faction": unit.faction, "cell": unit.cell, "stats": unit.stats.to_snapshot_dict(), "hp": unit.vitals.get_hp(), "move": unit.move_points_left, "main": unit.action_resources.get_main_left(), "bonus": unit.action_resources.get_bonus_left(), "items": items})
	return result

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL INITIATIVE UI: " + label)

func find_button(node: Node, label: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text == label: return child as Button
		var found := find_button(child, label)
		if found != null: return found
	return null

func at(unit: UnitState) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(unit.cell) - Vector2(0, 25.0 * demo.board_view.grid_config.tile_size.x / 128.0)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame

func wheel_down(position: Vector2) -> void:
	await motion(position)
	for _i: int in 12:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.position = position; wheel.global_position = position
		wheel.pressed = true
		viewport.push_input(wheel, true)
		wheel.pressed = false
		viewport.push_input(wheel, true)
		await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
