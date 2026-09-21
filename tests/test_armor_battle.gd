extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""
var party_commands_ok: bool = true
var party_enemy_steps: int = 0

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
	await _test_original_map()
	await _test_turn_flow()
	await _test_inspection()
	await _test_full_parties()
	viewport.queue_free()
	await process_frame
	await process_frame
	print("ARMOR UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _test_original_map() -> void:
	# Плейтест на исходной карте нужен отдельно: перестановка из старого smoke-теста
	# скрывала толчок в пропасть на исходном рельефе и могла оставить прогноз без геометрии.
	demo.reset_demo()
	var s := demo.session as BattleArmorSession
	var original_board := s.board.to_snapshot_dict()
	var original_item_snapshot := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	var original_rng := s.context.get_rng().to_dict()
	var original_revision := s.context.get_revision()
	var original_counters := s.context.simulation_counters()
	check(s.units[4].cell == Vector2i(5, 6) and s.units[5].cell == Vector2i(6, 6) and s.board.get_terrain(Vector2i(6, 6)) == TerrainType.Type.FLOOR, "untouched source map keeps Rey F7 and target G7")
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[4].cell))
	await key(KEY_A)
	await motion(demo.board_view.global_position + demo.board_view.cell_center(s.units[5].cell) - Vector2(0, 25.0 * demo.board_view.grid_config.tile_size.x / 128.0))
	var forecast := demo._forecast
	check(forecast != null and forecast.status == &"APPLIED", "source-map F7 attack builds applied forecast")
	if forecast == null or forecast.status != &"APPLIED": return
	check(forecast != null and forecast.units[s.units[5].id]["after"]["hp"] == 0.0 and not forecast.units[s.units[5].id]["after"]["alive"], "forecast predicts armor spend and void death")
	check(demo._forecast_panel.text.contains("броня") and demo._forecast_panel.text.contains("погиб"), "source-map forecast explains armor and death")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == original_item_snapshot and s.board.to_snapshot_dict() == original_board and s.context.get_rng().to_dict() == original_rng and s.context.get_revision() == original_revision and s.context.simulation_counters() == original_counters, "full preview snapshot RNG revision counters stay unchanged")
	await capture("armor-05-source-map-forecast")
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[5].cell) - Vector2(0, 25.0 * demo.board_view.grid_config.tile_size.x / 128.0))
	var live_after := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	check(not s.units[5].is_alive() and s.units[4].action_resources.get_main_left() == 0, "source-map click matches lethal forecast and costs one main")
	check(live_after == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after and s.last_receipt.get_events() == forecast.events and s.last_receipt.get_steps() == forecast.steps, "live receipt matches forecast snapshots RNG counters events and steps")
	var hit_event_found := false
	for event: Dictionary in forecast.events:
		if event.get("kind", &"") == &"hit_resolved":
			hit_event_found = hit_event_found or int(event["hit"].get("armor_spent", 0)) > 0
	check(hit_event_found, "forecast records positive armor spend")

func _test_turn_flow() -> void:
	demo.reset_demo()
	var s := demo.session as BattleArmorSession
	var astra := s.units[0]
	check(ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(astra.id)))["current"] == 100, "reset starts with full armor kit")
	await key(KEY_4)
	check(astra.armor.grants.size() == 1 and astra.armor.grants[0]["remaining"] == 20 and astra.action_resources.get_main_left() == 0, "real key4 on full kit grants twenty temporary armor for one main")
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[2].cell))
	check(s.selected_id == s.units[2].id, "real click switches to Bor")
	await click(demo.board_view.global_position + demo.board_view.cell_center(astra.cell))
	check(s.selected_id == astra.id and astra.armor.grants[0]["remaining"] == 20 and astra.action_resources.get_main_left() == 0, "switching allies does not refill armor or actions")
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN, "Enter starts actual enemy phase")
	# Приостанавливаем только таймер UI, чтобы законный шаг ИИ между кадрами
	# не смешивался с проверкой мутаций от запрещённых клавиш.
	demo.set_process(false)
	var locked_snapshot := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var locked_counters := s.context.simulation_counters()
	var locked_rng := s.context.get_rng().to_dict()
	await key(KEY_ENTER)
	await key(KEY_4)
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == locked_snapshot and s.context.simulation_counters() == locked_counters and s.context.get_rng().to_dict() == locked_rng, "repeated input during AI preserves full state")
	demo.set_process(true)
	var ai_started_msec := Time.get_ticks_msec()
	while s.phase == BattleTacticalSession.Phase.ENEMY_TURN and Time.get_ticks_msec() - ai_started_msec < 12000:
		await process_frame
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.round_number == 2, "UI process returns from AI at round two")
	check(demo._phase_label.text.contains("Раунд 2") and demo._phase_label.text.contains("Ваш ход"), "round two result is visible")
	await capture("armor-06-ai-return")
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN, "reset starts during enemy phase")
	await key(KEY_R)
	await create_timer(1.0).timeout
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.context.get_revision() == 0 and s.round_number == 1, "reset during AI cancels previous scenario")
	await capture("armor-07-ai-reset")

func _test_inspection() -> void:
	demo.reset_demo()
	var s := demo.session as BattleArmorSession
	await click(demo.board_view.global_position + demo.board_view.cell_center(s.units[1].cell))
	check(demo.inspected_id == s.units[1].id and demo._stats.text.contains("Печать: призыв недоступен в сценарии брони"), "armor inspection explains unavailable summon")
	var stats_scroll := demo._stats.get_parent() as ScrollContainer
	var stats_scroll_before := stats_scroll.get_v_scroll_bar().value
	await motion(stats_scroll.global_position + Vector2(40, stats_scroll.size.y - 8))
	for _wheel in 8:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = stats_scroll.global_position + Vector2(40, stats_scroll.size.y - 8)
		wheel.global_position = wheel.position
		viewport.push_input(wheel, true)
		wheel.pressed = false
		viewport.push_input(wheel, true)
	await process_frame
	check(stats_scroll.get_v_scroll_bar().value > stats_scroll_before, "inspection scroll moves inside armor side panel")
	await capture("armor-08-inspection")

func _test_full_parties() -> void:
	demo.reset_demo()
	var active_session := demo.session as BattleArmorSession
	party_commands_ok = true
	party_enemy_steps = 0
	var active_outcome := _play_armor(active_session, true)
	demo._refresh()
	print("ARMOR FULL active outcome=%s rounds=%d enemy_steps=%d" % [active_outcome, active_session.round_number, party_enemy_steps])
	check(active_outcome == BattleTacticalSession.Phase.VICTORY, "untouched armor session wins with active player")
	check(party_commands_ok, "active armor party applies bounded command drain")
	check(demo._phase_label.text.contains("ПОБЕДА") and demo._end_turn_button.disabled, "victory UI locks terminal controls")
	for unit: UnitState in active_session.units:
		check(not unit.armor.in_battle and unit.armor.grants.is_empty(), "victory armor grants expire and battle closes")
	await capture("armor-09-victory")
	demo.reset_demo()
	active_session = demo.session as BattleArmorSession
	check(active_session.select_unit(active_session.units[0].id), "passive party can select recovery actor")
	var passive_recovery := active_session.restore_selected_armor()
	check(passive_recovery.status == ActionReceipt.APPLIED, "passive party recovery is a real applied command")
	check(active_session.units[0].armor.grants.size() == 1 and active_session.units[0].armor.grants[0]["remaining"] == 20, "passive party starts with actual temporary grant")
	party_commands_ok = true
	party_enemy_steps = 0
	var passive_outcome := _play_armor(active_session, false)
	demo._refresh()
	print("ARMOR FULL passive outcome=%s rounds=%d enemy_steps=%d" % [passive_outcome, active_session.round_number, party_enemy_steps])
	check(passive_outcome == BattleTacticalSession.Phase.DEFEAT, "untouched armor session loses with passive player")
	check(party_commands_ok, "passive armor party applies bounded enemy drain")
	check(demo._phase_label.text.contains("ПОРАЖЕНИЕ") and demo._end_turn_button.disabled, "defeat UI locks terminal controls")
	await capture("armor-10-defeat")
	var terminal_revision := active_session.context.get_revision()
	var terminal_board := active_session.board.to_snapshot_dict()
	check(not active_session.context.is_busy() and not active_session.end_player_turn() and active_session.attack_unit(active_session.units[3].id).status == ActionReceipt.REJECTED, "terminal armor actions are rejected")
	check(active_session.context.get_revision() == terminal_revision and active_session.board.to_snapshot_dict() == terminal_board, "terminal armor state stays stable")
	for unit: UnitState in active_session.units:
		check(not unit.armor.in_battle and unit.armor.grants.is_empty(), "terminal armor grants expire and battle closes")
	active_session.reset()
	check(active_session.phase == BattleTacticalSession.Phase.PLAYER_TURN and active_session.round_number == 1 and active_session.context.get_revision() == 0, "armor session reset creates fresh state")

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

func _play_armor(battle: BattleArmorSession, active_player: bool) -> BattleTacticalSession.Phase:
	var ai := BattleDemoBT.new()
	for _round in 30:
		if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if active_player:
			for id in battle.living_ids(Faction.Type.PLAYER):
				if not battle.select_unit(id): break
				for _action in 2:
					var actor := battle.board.get_unit_by_id(id)
					if actor == null or not actor.is_alive(): break
					var intent := ai.decide(battle, actor)
					if intent.kind == BattleAIIntent.Kind.WAIT: break
					var receipt: ActionReceipt
					if intent.kind == BattleAIIntent.Kind.ATTACK: receipt = battle.attack_unit(intent.target_id)
					elif intent.kind == BattleAIIntent.Kind.MOVE and not intent.path.is_empty(): receipt = battle.move_to(intent.path.back())
					else:
						party_commands_ok = false
						break
					if receipt.status != ActionReceipt.APPLIED:
						party_commands_ok = false
						break
					if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if not battle.end_player_turn():
			party_commands_ok = false
			break
		for _step in 24:
			if battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			party_enemy_steps += 1
			var enemy_receipt := battle.step_enemy()
			if enemy_receipt != null and enemy_receipt.status != ActionReceipt.APPLIED: party_commands_ok = false
		if battle.phase == BattleTacticalSession.Phase.ENEMY_TURN: party_commands_ok = false
		if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
	return battle.phase

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK,"PNG " + label)
