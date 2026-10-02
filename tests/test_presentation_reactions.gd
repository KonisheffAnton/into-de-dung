extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var captures: String = ""
var published: Array[Dictionary] = []
var started: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION REACTIONS: " + label)

func fixture() -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	s.state.environment.fires.clear()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	# Седьмая запись — уже существующее тело; её HP/клетку не меняем.
	for i: int in 6:
		var unit := s.units[i]
		s.board.move_unit(unit, Vector2i(i, 0))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 10.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 8.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	s.board.move_unit(s.units[0], Vector2i(3, 3))
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	return s

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "snapshot capture " + captured.reason)
	return {"state": captured.snapshot.to_dict() if captured.snapshot != null else {}, "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters(), "admission": SummonAdmission.values(s.context)}

func packet(s: BattleCoreReactionsSession, command: Command) -> Dictionary:
	var before := ActionPresentationState.capture(s.state)
	# Внутренний refill не входит в публичный command preview; проверяем настоящий
	# eventless кадр. Полный parity ниже относится к guard/attack/move и их реакциям.
	if command is BattleTurnRefill:
		s._queue.capture_presentation = true
		var refill := s._queue.submit(command, s.context)
		check(refill.status == ActionReceipt.APPLIED, "real team refill accepted")
		return {"before": before, "frames": refill.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "receipt": refill}
	var live := snapshot(s)
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(s.context, s._queue, command)
	check(snapshot(s) == live and UnitId.get_counter() == ids, "preview leaves full live state and IDs intact")
	s._queue.capture_presentation = true
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == preview.status and receipt.reason == preview.reason and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "real events steps status reason match preview: " + String(receipt.reason) + "/" + String(preview.reason))
	check(snapshot(s) == {"state": preview.snapshot_after, "rng": preview.rng_after, "counters": preview.counters_after, "admission": preview.admission_after}, "full snapshot resources RNG counters admission parity")
	return {"before": before, "frames": receipt.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "receipt": receipt}

func attack(s: BattleCoreReactionsSession, actor: UnitState, target: UnitState) -> AttackCommand:
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision())

func play(data: Dictionary) -> void:
	player.cancel()
	player.set_speed(1.0)
	published.clear()
	started.clear()
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()

func advance(seconds: float) -> void:
	if not player.active: return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	for i: int in 100:
		if not player.active: break
		advance(1.0)
	check(not player.active, "playback completes")

func capture(label: String) -> void:
	if captures.is_empty(): return
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	for impact: BattlePresentationImpact in board._impacts.get_children(): impact._tween.pause()
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func frame_order(data: Dictionary) -> void:
	var expected: Array[Dictionary] = []
	for frame: Dictionary in data.frames: expected.append(frame.after)
	expected.append(data.after)
	check(published == expected, "every atomic after including final is published in original order")
	check(started == data.frames, "every original frame starts once")

func stances() -> void:
	var s := fixture()
	var a := s.units[0]
	for mode: int in [0, 1, 2, 3]:
		a.action_resources._set_for_refill(1, 1)
		var ally := s.units[2]
		s.board.move_unit(ally, Vector2i(3, 4))
		var data := packet(s, GuardCommand.new(a.id, s.context.get_revision(), mode if mode != 0 else -1, ally.id if mode == 2 else 0))
		check(data.receipt.status == ActionReceipt.APPLIED, "guard mode accepted " + str(mode) + ": " + String(data.receipt.reason))
		play(data)
		advance(0.09)
		check(board._reaction_cues.size() == 1 and board._reaction_cues[0].kind == &"guard", "one guard activation cue")
		check(published.is_empty() and board._presentation_visual(a.id).reaction_view == data.before.units[a.id].reaction_view, "mode and charge stay before during activation")
		await capture("guard-%d-prepare" % mode)
		finish()
		check(board._presentation_visual(a.id).reaction_view == data.after.units[a.id].reaction_view, "guard after changes all indicators together")
		frame_order(data)
		await capture("guard-%d-after" % mode)
	# Выбор после расхода оставляет пустой заряд; refill снимает стойку, но не режим.
	a.combat_perks.reaction_left = 0
	a.action_resources._set_for_refill(1, 1)
	var switch_data := packet(s, GuardCommand.new(a.id, s.context.get_revision(), 1))
	play(switch_data)
	finish()
	check(board._presentation_visual(a.id).reaction_view.charge == 0, "switch does not visually refill")
	var data := packet(s, BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER))
	play(data)
	finish()
	var view: Dictionary = board._presentation_visual(a.id).reaction_view
	check(view.charge == 1 and not view.guard and view.mode == 1 and not view.ready, "refill shows full charge and remembered inactive mode")
	check(board.displayed_unit_details(a.id).contains("Общий заряд"), "tooltip explains shared charge")
	await capture("refill")
	s.close()

func reactions(kind: String, condition: String = "normal") -> void:
	var s := fixture()
	var a := s.units[0]
	var b := s.units[1]
	var target := a
	var reactor := b
	var command: Command
	if kind == "cover":
		var ally := s.units[2]
		s.board.move_unit(ally, Vector2i(4, 4))
		s.board.move_unit(a, Vector2i(3, 4))
		reactor = a
		target = ally
		s._queue.submit(GuardCommand.new(a.id, s.context.get_revision(), 2, ally.id), s.context)
		command = attack(s, b, ally)
	else:
		s._queue.submit(GuardCommand.new(b.id, s.context.get_revision(), 1 if kind == "opportunist" else 3), s.context)
		if kind == "opportunist":
			var path: Array[Vector2i] = [a.cell, Vector2i(2, 3)]
			command = MoveCommand.new(a.id, path, s.context.get_revision())
		else: command = attack(s, a, b)
	if condition == "stun": reactor.control.stunned_turns = 1
	if condition == "spent": reactor.combat_perks.reaction_left = 0
	if condition == "range" and kind == "cover": s.board.move_unit(reactor, Vector2i(1, 4))
	if condition == "lethal": b.vitals.set_hp(1.0)
	if condition == "armor":
		for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	if condition == "covered":
		var helper := s.units[2]
		s.board.move_unit(helper, Vector2i(3, 4))
		helper.combat_perks.definition.tank_reactions = true
		helper.combat_perks.reaction_left = 1
		check(s._queue.submit(GuardCommand.new(helper.id, s.context.get_revision(), 2, target.id), s.context).status == ActionReceipt.APPLIED, "ally arms cover against reaction strike")
		if kind == "opportunist":
			var path: Array[Vector2i] = [a.cell, Vector2i(2, 3)]
			command = MoveCommand.new(a.id, path, s.context.get_revision())
		else: command = attack(s, a, b)
	var data := packet(s, command)
	var committed := snapshot(s)
	var should_react := condition in ["normal", "armor", "covered"]
	var mode := 2 if kind == "cover" else (1 if kind == "opportunist" else 3)
	var used: Array = data.receipt.get_events().filter(func(e: Dictionary) -> bool: return e.kind == &"reaction_used" and e.mode == mode)
	check((used.size() == 1) == should_react, kind + " real eligibility " + condition)
	play(data)
	var seen: bool = false
	for i: int in 200:
		if not player.active: break
		advance(0.03)
		for cue: BattlePresentationReaction in board._reaction_cues:
			if cue.kind != StringName(kind) or not cue.visible: continue
			if not seen and cue.progress >= 0.5:
				seen = true
				check(cue.source_point.distance_to(cue.target_point) > 10.0, "cue connects actual separate figures")
				check(int(cue.get_meta("cue").actor_id) == reactor.id and int(cue.get_meta("cue").target_id) == target.id, "cue identifies real reactor and target")
				var tween := player._tween
				var progress := cue.progress
				board.size += Vector2(12, 8)
				board.zoom_camera(0.8, board.size * 0.5)
				board.pan_camera(Vector2(6, -5))
				check(player._tween == tween and cue.progress == progress and is_instance_valid(cue), "resize and camera preserve cue and clock")
				check(cue.source_point == board._reaction_anchor(reactor.id), "resize follows shown anchor")
				check(board._presentation_visual(reactor.id).reaction_view.charge == 1, "charge is not revealed before attack after")
				await capture(kind + "-" + condition + "-cue")
	check(seen == should_react, kind + " no invented reaction " + condition)
	finish()
	frame_order(data)
	check(board._reaction_cues.is_empty(), "natural end removes cues")
	check(snapshot(s) == committed, "playback never mutates committed runtime")
	if condition == "covered":
		check(s.units[2].combat_perks.reaction_left == 0 and reactor.combat_perks.reaction_left == 0, "reaction and cover consume their distinct shared charges")
		var combined := false
		for frame: Dictionary in data.frames:
			if BattleReactionPresentation.cues(frame.events, frame.step).size() == 2: combined = true
		check(combined, "reaction strike and cover coexist in one real frame")
	if kind == "cover" and should_react:
		check(data.after.units[reactor.id].hp == data.before.units[reactor.id].hp, "cover never transfers hit to protector")
	if kind == "opportunist" and should_react:
		check(data.after.units[target.id].cell == data.before.units[target.id].cell, "opportunist does not invent departure")
	await capture(kind + "-" + condition + "-after")
	s.close()

func controls_and_fault() -> void:
	for control: String in ["speed", "skip", "cancel", "fault", "paid_fault"]:
		var s := fixture()
		var a := s.units[0]
		var b := s.units[1]
		s._queue.submit(GuardCommand.new(b.id, s.context.get_revision(), 1), s.context)
		if control == "fault": s._queue._max_commands = 1
		if control == "paid_fault": s._queue._max_commands = 2
		var path: Array[Vector2i] = [a.cell, Vector2i(2, 3)]
		var data := packet(s, MoveCommand.new(a.id, path, s.context.get_revision()))
		var committed := snapshot(s)
		play(data)
		advance(0.06)
		if control == "paid_fault":
			check(b.combat_perks.reaction_left == 0 and a.vitals.get_hp() == data.before.units[a.id].hp and board._reaction_cues.size() == 1, "paid fault shows actual reaction cue and charge without unfinished hit")
		if control == "speed":
			player.set_speed(3.0)
			advance(0.1)
			finish()
		elif control == "skip":
			player.skip()
			check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, "skip clears all residual feedback")
		elif control == "cancel": player.cancel()
		else:
			check(data.receipt.status == ActionReceipt.FAULTED, "real command limit fault")
			finish()
			check(board._impacts.get_child_count() == 0, "unexecuted hit invents no contact")
		check(board._reaction_cues.is_empty() and board._action_offsets.is_empty(), control + " clears cues and poses")
		check(snapshot(s) == committed, control + " keeps exact committed result")
		s.close()

func dense_statuses() -> void:
	var s := fixture()
	var a := s.units[0]
	s._queue.submit(GuardCommand.new(a.id, s.context.get_revision(), 1), s.context)
	board.show_presentation_state(ActionPresentationState.capture(s.state))
	var visual := board._presentation_visual(a.id)
	# Синтетическое переполнение представления, без новых игровых состояний.
	for i: int in 7:
		visual.status_entries.append({"id": "synthetic-%d" % i, "title": "Fixture", "stacks": 0, "remaining": 2, "embodied": false})
	visual.sync_scene_art()
	check(visual.visible_status_entries().size() == 5 and visual.status_overflow_count() == 2, "dense fixture exercises full row and overflow")
	check(not visual.status_hud_bounds().intersects(visual.reaction_hud_bounds()), "reaction indicator leaves every status and overflow unobscured")
	await capture("reaction-dense-statuses")
	s.close()

func ui_path(hub: bool) -> void:
	var demo: BattleDemo
	if hub:
		var view := HeroHubBattleView.new()
		view.supplied_session = fixture()
		demo = view
	else:
		demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
		demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	PlayerTurnFixture.enter_player_turn(demo)
	var s := demo.session as BattleCoreReactionsSession
	var actor := s.units[0]
	demo._refresh()
	var before := ActionPresentationState.capture(s.state)
	var preview := ForecastSimulation.run(s.context, s._queue, GuardCommand.new(actor.id, s.context.get_revision(), 1))
	demo._execute_live(&"set_reaction_guard", [1], true)
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "main/H1 worker reaches real guard presentation")
	if demo.is_presentation_pending(): demo._presentation_player._tween.pause()
	var committed := snapshot(s)
	check(s.last_receipt.get_events() == preview.events and s.last_receipt.get_steps() == preview.steps and committed.state == preview.snapshot_after and committed.rng == preview.rng_after and committed.counters == preview.counters_after, "main/H1 worker full preview parity")
	check(demo.board_view._presentation_visual(actor.id).reaction_view == before.units[actor.id].reaction_view, "busy UI holds published stance")
	demo.handle_cell(s.units[1].cell)
	demo.end_turn()
	check(snapshot(s) == committed, "busy clicks cannot mutate battle")
	demo.skip_presentation()
	check(demo.board_view._presentation_visual(actor.id).reaction_view.guard, "skip publishes active stance")
	await capture("main-guard-after" if not hub else "hub-guard-after")
	demo.reset_demo()
	check(demo.board_view._reaction_cues.is_empty() and not demo.is_execution_pending(), "reset cleans worker and presentation")
	PlayerTurnFixture.enter_player_turn(demo)
	# H1 удерживает supplied session при reset; следующий независимый тест выхода
	# получает отдельное допустимое действие, не меняя правил восстановления.
	var reset_actor := demo.session.selected_unit()
	reset_actor.guard_stance = false
	reset_actor.action_resources._set_for_refill(1, 1)
	demo._refresh()
	demo._execute_live(&"set_reaction_guard", [1], true)
	deadline = Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "exit fixture reaches active presentation " + str(hub))
	var cue: BattlePresentationReaction = demo.board_view._reaction_cues[0] if not demo.board_view._reaction_cues.is_empty() else null
	demo.free()
	await process_frame
	check(not is_instance_valid(cue), "exit frees active reaction cue")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	board.execution_pending = true
	player = BattlePresentationPlayer.new()
	viewport.add_child(player)
	player.frame_finished.connect(func(state: Dictionary) -> void: published.append(state))
	player.frame_started.connect(func(frame: Dictionary) -> void: started.append(frame))
	await stances()
	for kind: String in ["cover", "opportunist", "counterattack"]:
		await reactions(kind)
		await reactions(kind, "stun")
		await reactions(kind, "spent")
	await reactions("cover", "range")
	await reactions("cover", "armor")
	await reactions("opportunist", "covered")
	await reactions("counterattack", "covered")
	await reactions("counterattack", "lethal")
	controls_and_fault()
	await dense_statuses()
	board.hide()
	await ui_path(false)
	await ui_path(true)
	viewport.free()
	print("PRESENTATION REACTIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
