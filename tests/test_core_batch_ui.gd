extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CORE BATCH UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = (load("res://scenes/demo/core_combination_battle.tscn") as PackedScene).instantiate()
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var s := demo.session as BattleCoreCombinationSession
	check(s.is_deploying() and demo._end_turn_button.text.contains("Начать бой"), "F5 enters visible deployment")
	await capture("batch-deployment")
	var before := snapshot(s)
	await key(KEY_1); await key(KEY_4); await key(KEY_7); await key(KEY_8)
	check(snapshot(s) == before and not demo.attack_mode and not demo.summoning_mode, "shortcuts cannot act during deployment")
	await click(at(s.units[4].cell)); await click(at(Vector2i(1, 4)))
	check(s.units[4].cell == Vector2i(1, 4) and s.units[4].control.stunned_turns == 1, "real input deploys stunned ally without expiry")
	await click(at(s.units[1].cell))
	check(demo.inspected_id == s.units[1].id and demo._stats.text.contains(s.units[1].debug_name), "enemy inspection works before battle")
	await key(KEY_R)
	check(s.is_deploying() and s.units[4].cell == Vector2i(5, 5), "reset returns deployment")
	await click(demo._end_turn_button.global_position + demo._end_turn_button.size * 0.5)
	check(s.can_player_act() and not s.is_deploying(), "start button begins player turn")
	check(demo._action_bar._buttons[7].get_meta("action_id") == &"summoning_item", "eighth slot exposes seal alongside seven existing actions")
	var armor_button := demo._action_bar._buttons[3]
	before = snapshot(s)
	await motion(armor_button.global_position + armor_button.size * 0.5)
	var armor := demo._armor_forecast
	check(armor != null and armor.status == ActionReceipt.APPLIED and demo._forecast_panel.text.contains("Временная броня"), "armor hover forecasts real overflow")
	check(snapshot(s) == before, "armor hover isolates live")
	await capture("batch-armor-forecast")
	demo._refresh()
	check(demo._armor_forecast != null, "refresh rebuilds hovered armor forecast")
	await key(KEY_4)
	check(armor != null and snapshot(s) == armor.snapshot_after and s.last_receipt.get_events() == armor.events, "armor key executes forecast command")
	await click(at(s.units[2].cell)); await click(at(Vector2i(4, 4)))
	await key(KEY_7); await motion(at(s.units[5].cell))
	var entangle := demo._forecast
	check(entangle != null and entangle.status == ActionReceipt.APPLIED, "same battle has K8 forecast")
	await click(at(s.units[5].cell))
	check(entangle != null and snapshot(s) == entangle.snapshot_after and s.units[5].control.entangled_turns == 1, "K8 live shares the combined battle")
	await key(KEY_ENTER)
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN and demo._armor_forecast == null, "turn closes previews")
	for step: int in 100:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	demo._refresh()
	check(s.can_player_act() and s.units[4].control.stunned_turns == 0, "whole enemy turn and control boundary complete")
	await click(at(s.units[0].cell)); await key(KEY_8)
	check(demo.summoning_mode, "seal is selectable in armored battle")
	var cells := s.summoning_cells()
	check(not cells.is_empty(), "seal has valid targets")
	if not cells.is_empty():
		await motion(at(cells[0]))
		var forecast := demo._item_forecast
		check(forecast != null and forecast.status == ActionReceipt.APPLIED, "seal preview inside environment")
		await capture("batch-summon-forecast")
		await click(at(cells[0]))
		var helper := s.state.active_summon(s.units[0].id)
		check(forecast != null and snapshot(s) == forecast.snapshot_after and helper != null and s.state.is_summon_pending(helper.id), "seal click matches preview and pending roster")
		await capture("batch-combined-battle")
	await key(KEY_R)
	check(s.is_deploying() and demo._armor_forecast == null and demo._item_forecast == null and not demo.summoning_mode, "reset after multi-turn battle clears previews and deployment")
	await key(KEY_ENTER)
	check(s.can_player_act(), "Enter starts reset battle, phase=%d" % s.phase)
	await click(at(s.units[2].cell))
	await motion(armor_button.global_position + armor_button.size * 0.5)
	check(demo._armor_forecast != null, "new battle has fresh armor forecast")
	# Изменение без revision не должно подменять новый клик сохранённым прогнозом.
	if s.selected_unit() != null: s.selected_unit().action_resources.try_spend_main(1)
	await key(KEY_4)
	check(s.last_receipt.status == ActionReceipt.REJECTED and demo._armor_forecast == null, "armor executes fresh live validation after preview")
	await click(demo._mode_button.global_position + demo._mode_button.size * 0.5)
	check(not demo.core_combination_mode and demo._armor_forecast == null, "scenario switch discards batch state")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("CORE BATCH UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func snapshot(s: BattleCoreCombinationSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

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

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var texture := viewport.get_texture()
	var picture := texture.get_image() if texture != null else null
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
