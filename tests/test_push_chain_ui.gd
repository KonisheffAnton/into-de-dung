extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PUSH CHAIN UI: " + label)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene
	demo = scene.instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	demo.set_process(false)
	var s := demo.session as BattleCoreReactionsSession
	check(s != null, "real reactions scene created")
	if s == null:
		quit(1)
		return
	_setup_chain(s)
	demo._refresh()
	var actor: UnitState = s.units[0]
	var target: UnitState = s.units[1]
	var middle: UnitState = s.units[2]
	var last: UnitState = s.units[5]
	await click(at(actor.cell))
	check(s.selected_id == actor.id, "board click selects actor")
	await key(KEY_1)
	check(demo.attack_mode, "attack action enters target mode")
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	await motion(at(target.cell))
	var forecast: AttackForecast = demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED, "hover returns successful chain forecast")
	if forecast != null:
		var links := _events(forecast.events, &"chain_link")
		var moved := _events(forecast.events, &"moved")
		check(links.size() == 2 and links[0].get("impulse") == 12.0 and links[1].get("impulse") == 9.0, "hover shows both transmitted forces")
		check(moved.size() == 1 and moved[0].get("target_unit_id") == last.id and moved[0].get("to_cell") == Vector2i(5, 3), "forecast has one final movement arrow")
		check(forecast.units.get(middle.id, {}).get("after", {}).get("cell") == Vector2i(3, 3) and forecast.units.get(last.id, {}).get("after", {}).get("cell") == Vector2i(5, 3), "hover predicts stationary middle and shifted last")
	check(demo._forecast_panel.text.find("Цепь · сила") < demo._forecast_panel.text.find("Кровотечение:") and demo._forecast_panel.text.contains("Пунктир — импульс; стрелка — сдвиг."), "chain summary precedes detailed HP and armor")
	check(demo.board_view.forecast == forecast and demo._forecast_panel.text.contains("Цепь") and demo._forecast_panel.text.contains("12") and demo._forecast_panel.text.contains("9"), "board and panel expose chain forecast")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "hover keeps complete live state isolated")
	await capture("push-chain-forecast")
	# Упор и вылет за границу не создают moved и не должны изображаться стрелкой сдвига.
	s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.WALL)
	await motion(at(Vector2i(0, 7)))
	await motion(at(target.cell))
	check(demo._forecast != null and _events(demo._forecast.events, &"push_blocked").size() == 1 and _events(demo._forecast.events, &"moved").is_empty(), "blocked chain has no movement arrow")
	await capture("push-chain-blocked")
	s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.FLOOR)
	check(s.board.move_unit(last, Vector2i(7, 3)) and s.board.move_unit(middle, Vector2i(6, 3)) and s.board.move_unit(target, Vector2i(5, 3)) and s.board.move_unit(actor, Vector2i(4, 3)), "place chain at board edge")
	demo._refresh()
	await motion(at(Vector2i(0, 7)))
	await motion(at(target.cell))
	check(demo._forecast != null and _events(demo._forecast.events, &"fell").size() == 1 and _events(demo._forecast.events, &"moved").is_empty() and not demo._forecast.units[last.id].after.alive, "edge fall has death marker without movement arrow")
	await capture("push-chain-edge")
	check(s.board.move_unit(actor, Vector2i(1, 3)) and s.board.move_unit(target, Vector2i(2, 3)) and s.board.move_unit(middle, Vector2i(3, 3)) and s.board.move_unit(last, Vector2i(4, 3)), "restore open chain")
	demo._refresh()
	await motion(at(Vector2i(0, 7)))
	await motion(at(target.cell))
	forecast = demo._forecast
	check(forecast != null and forecast.status == ActionReceipt.APPLIED and _events(forecast.events, &"moved").size() == 1, "fresh forecast after geometry edits without revision-only cache")
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.position = at(target.cell)
	click_event.global_position = click_event.position
	click_event.pressed = true
	viewport.push_input(click_event, true)
	click_event.pressed = false
	viewport.push_input(click_event, true)
	await process_frame
	check(demo.is_execution_pending() and demo.session == null and demo.board_view.session == null, "live worker owns session during pending attack")
	var locked := InputEventKey.new()
	locked.keycode = KEY_1
	locked.pressed = true
	viewport.push_input(locked, true)
	locked.pressed = false
	viewport.push_input(locked, true)
	check(demo.is_execution_pending(), "input does not start a second action while worker owns session")
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	var receipt: ActionReceipt = s.last_receipt
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, "live click completes chain")
	if forecast != null and receipt != null:
		check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after, "click matches forecast events, steps and snapshot")
		check(s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "click matches forecast RNG and counters")
	check(target.cell == Vector2i(2, 3) and middle.cell == Vector2i(3, 3) and last.cell == Vector2i(5, 3), "only last body moved live")
	check(demo._journal.any(func(line: String) -> bool: return line.contains("Цепь")), "journal reports actual chain")
	await capture("push-chain-applied")
	demo.queue_free(); await process_frame
	viewport.queue_free(); await process_frame
	print("PUSH CHAIN UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _setup_chain(s: BattleCoreReactionsSession) -> void:
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for i: int in 6:
		var unit: UnitState = s.units[i]
		check(s.board.move_unit(unit, Vector2i(i, 0)), "UI park " + str(i))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ARMOR, 0.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	check(s.board.move_unit(s.units[0], Vector2i(1, 3)), "UI actor placement")
	check(s.board.move_unit(s.units[1], Vector2i(2, 3)), "UI target placement")
	check(s.board.move_unit(s.units[2], Vector2i(3, 3)), "UI middle placement")
	check(s.board.move_unit(s.units[5], Vector2i(4, 3)), "UI last placement")
	check(s.context.get_attack_rules().get_definition(&"demo_strike").chain_push, "main attack enables chain")

func _events(all: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in all:
		if event.get("kind") == kind: out.append(event)
	return out

func at(cell: Vector2i) -> Vector2:
	return demo.board_view.global_position + demo.board_view.cell_center(cell)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo)

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await process_frame
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
