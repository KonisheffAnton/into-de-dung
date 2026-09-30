extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""
var frame_sequences: Array[int] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE PRESENTATION: " + label)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func snapshot(s: BattleDemoSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(),
		"rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}

func wait_presentation() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "joined result starts presentation")
	# Короткий клип не должен закончиться за первый дорогой кадр render-backend.
	# Осматриваем точную фазу, затем явно возобновляем естественное воспроизведение.
	if demo.is_presentation_pending(): demo._presentation_player._tween.pause()

func shown(id: int) -> BattleUnitView:
	for row: Dictionary in demo.board_view._view_units:
		if row.unit.id == id: return row.unit
	return null

func fresh() -> void:
	if demo != null:
		demo.queue_free()
		await process_frame
	demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	PlayerTurnFixture.enter_player_turn(demo)
	demo._presentation_player.frame_started.connect(func(frame: Dictionary) -> void: frame_sequences.append(int(frame.step.command_seq)))
	await process_frame

func chain_fall() -> void:
	await fresh()
	var s := demo.session as BattleCoreReactionsSession
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for index: int in 6:
		var unit := s.units[index]
		s.board.move_unit(unit, Vector2i(index, 0))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if index == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if index == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	s.board.move_unit(s.units[0], Vector2i(4, 3))
	s.board.move_unit(s.units[1], Vector2i(5, 3))
	s.board.move_unit(s.units[2], Vector2i(6, 3))
	s.board.move_unit(s.units[5], Vector2i(7, 3))
	demo._refresh()
	demo._execute_live(&"attack_unit", [s.units[1].id], true)
	await wait_presentation()
	check(not s.units[5].is_alive() and shown(s.units[5].id).alive, "chain fall does not hide victim before its cue")
	var committed := snapshot(s)
	var events := s.last_receipt.get_events()
	check(events.any(func(e: Dictionary) -> bool: return e.kind == &"chain_link") and events.any(func(e: Dictionary) -> bool: return e.kind == &"fell"), "real chain and out-of-board fall in receipt")
	demo._presentation_player.set_speed(3.0)
	demo._presentation_player._tween.play()
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	check(snapshot(s) == committed and not shown(s.units[5].id).alive, "natural chain playback leaves exact dead prefix")

func hub_terminal() -> void:
	demo.queue_free()
	await process_frame
	var view := HeroHubBattleView.new()
	view.supplied_session = PlayerTurnFixture.create()
	demo = view
	viewport.add_child(view)
	view.set_process(false)
	var s := view.session as BattleCoreReactionsSession
	var enemies := s.living_ids(Faction.Type.ENEMY)
	var target := s.board.get_unit_by_id(enemies[0])
	for id: int in enemies:
		if id != target.id: s._submit(DeathCommand.new(id, DamageSource.new(&"cell", 0, s.board.get_unit_by_id(id).cell)))
	var actor := s.board.get_unit_by_id(s.living_ids(Faction.Type.PLAYER)[0])
	s.select_unit(actor.id)
	s.board.move_unit(actor, Vector2i(2, 2))
	s.board.move_unit(target, Vector2i(3, 2))
	target.vitals.set_hp(1.0)
	for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	view._refresh()
	view._execute_live(&"attack_unit", [target.id], true)
	await wait_presentation()
	check(s.phase == BattleTacticalSession.Phase.VICTORY and shown(target.id).alive, "terminal runtime waits behind visible last hit")
	var screen := HeroHubScreen.new()
	screen.battle_view = view
	# run намеренно отсутствует: родитель обязан выйти до чтения/сохранения исхода.
	screen._process(0.0)
	view._refresh()
	check(view._return_button.disabled and not view._stats.text.contains("Победа"), "hub does not publish terminal outcome during playback")
	view.skip_presentation()
	check(not view._return_button.disabled and not shown(target.id).alive, "terminal view is released after final shown state")
	screen.battle_view = null
	screen.free()

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 950)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await fresh()
	var s := demo.session as BattleCoreReactionsSession
	var actor := s.units[0]
	var original := actor.cell
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	await wait_presentation()
	check(demo.board_view._view_unit_cell(actor.id) == original and actor.cell != original, "shown cell waits while live result is already committed")
	var committed := snapshot(s)
	demo.handle_cell(Vector2i(2, 2))
	demo.select_character(s.units[1].id)
	demo.end_turn()
	demo._hover(s.units[3].cell)
	demo._process(5.0)
	check(snapshot(s) == committed and demo._forecast == null, "input, AI and hover cannot execute during playback")
	demo.board_view.size += Vector2(15, 10)
	await capture("presentation-movement")
	# moved и died/control_changed могут принадлежать одному шагу: after ещё не опубликован.
	demo.board_view._presentation_motion(1.0, actor.id, original, actor.cell)
	demo.board_view._rebuild_visuals()
	demo.board_view._presentation_badge({"kind": &"died", "target_unit_id": actor.id, "source": {"kind": &"fall"}})
	var badge := demo.board_view._ghosts.get_child(0) as Label
	check(badge != null and badge.position.is_equal_approx(demo.board_view.cell_center(actor.cell) + Vector2(-35, -72)), "death badge follows already-shown movement inside same frame")
	demo._toggle_presentation_speed()
	demo._speed_presentation_button.grab_focus()
	check(demo._speed_presentation_button.has_focus(), "speed button focus retained before Space")
	var skip_key := InputEventKey.new()
	skip_key.keycode = KEY_SPACE
	skip_key.pressed = true
	viewport.push_input(skip_key, true)
	skip_key.pressed = false
	viewport.push_input(skip_key, true)
	check(not demo.is_execution_pending() and demo.board_view._view_unit_cell(actor.id) == actor.cell, "skip publishes exact final board and unlocks")
	check(snapshot(s) == committed, "speed and skip preserve snapshot RNG and resources")
	await fresh()
	s = demo.session as BattleCoreReactionsSession
	actor = s.units[0]
	var target := s.units[3]
	check(s.board.move_unit(actor, Vector2i(2, 2)) and s.board.move_unit(target, Vector2i(3, 2)), "adjacent attack fixture")
	for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	demo._refresh()
	var hp_before := target.vitals.get_hp()
	var expected := AttackForecast.build(s.context, s._queue, AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision()))
	frame_sequences.clear()
	demo._execute_live(&"attack_unit", [target.id], true)
	await wait_presentation()
	check(shown(target.id).hp == hp_before and target.vitals.get_hp() != hp_before, "HUD and figure keep pre-hit HP at attack cue")
	await capture("presentation-attack")
	demo._presentation_player.set_speed(3.0)
	demo._presentation_player._tween.play()
	await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self, demo)
	check(shown(target.id).hp == target.vitals.get_hp(), "natural completion publishes actual HP")
	check(not demo.is_execution_pending() and demo.board_view._numbers.get_child_count() > 0, "result numbers outlive playback without blocking commands")
	var ordered := frame_sequences.duplicate()
	ordered.sort()
	check(frame_sequences == ordered and frame_sequences.size() > 1, "native tweens present command frames in order")
	check(s.last_receipt.get_events() == expected.events and snapshot(s).state == expected.snapshot_after and s.context.get_rng().to_dict() == expected.rng_after, "animated real attack equals isolated command execution")
	await capture("presentation-completed")
	# Шаг последнего врага закрывает границу: в одном вызове несколько roots без событий.
	demo.reset_demo()
	s = demo.session as BattleCoreReactionsSession
	s._enemy_index = s._enemy_ids.size()
	demo._refresh()
	demo._execute_live(&"step_enemy")
	await wait_presentation()
	check(demo._presentation_roots.size() > 3 and s.phase == BattleTacticalSession.Phase.PLAYER_TURN, "multi-root team boundary captured before UI accepts new turn")
	committed = snapshot(s)
	demo.skip_presentation()
	check(snapshot(s) == committed and not demo.is_execution_pending(), "boundary skip preserves abilities refill and turn result")
	var mana_before := s.state.abilities.mana
	demo._execute_live(&"cast_mage_spell", [&"mage.fire", s.units[3].id], true)
	await wait_presentation()
	check(demo._mage_label.text.contains(str(mana_before)) and s.state.abilities.mana < mana_before, "mage HUD waits for its cast frame")
	demo.skip_presentation()
	await fresh()
	s = demo.session as BattleCoreReactionsSession
	s._queue = ActionQueue.new(256, 1)
	check(s.board.move_unit(s.units[0], Vector2i(2, 2)) and s.board.move_unit(s.units[3], Vector2i(3, 2)), "fault fixture")
	demo._refresh()
	demo._execute_live(&"attack_unit", [s.units[3].id], true)
	await wait_presentation()
	committed = snapshot(s)
	check(s.last_receipt.status == ActionReceipt.FAULTED, "faulted prefix reaches playback")
	demo.skip_presentation()
	check(snapshot(s) == committed and demo._status.text.contains("остановлено"), "fault skip keeps prefix and reports failure")
	await chain_fall()
	await hub_terminal()
	await fresh()
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	await wait_presentation()
	demo.reset_demo()
	check(not demo.is_execution_pending() and demo._presentation_before.is_empty(), "reset cancels old tween and packet")
	await create_timer(0.3).timeout
	check(not demo.is_execution_pending(), "old callbacks do not resume after reset")
	PlayerTurnFixture.enter_player_turn(demo)
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	await wait_presentation()
	demo.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	viewport.queue_free()
	await process_frame
	print("BATTLE PRESENTATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
