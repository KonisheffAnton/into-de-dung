extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION RANGED: " + label)

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(),
		"rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}

func configure(s: BattleCoreReactionsSession, target: Vector2i, mode: String = "hp") -> void:
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
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
	check(s.board.move_unit(s.units[0], Vector2i(2, 3)) and s.board.move_unit(s.units[1], target), "fixture places shot participants")
	s.units[0].stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 4.0)
	if mode == "armor":
		for item: ItemInstance in s.state.get_owner(s.units[1].id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	if mode == "zero":
		s.units[0].stats.set_base_value(StatTypes.StatType.STRENGTH, 0.0)
		s.units[0].stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		for definition: AttackDefinition in s.context._attack_rules._definitions: definition.damage_components.clear()
	if mode == "lethal": s.units[1].vitals.set_hp(1.0)
	if mode == "critical": s.units[1].elemental.frozen_turns = 2

func packet(s: BattleCoreReactionsSession, fault: bool = false) -> Dictionary:
	var before := ActionPresentationState.capture(s.state)
	var a := s.units[0]
	var b := s.units[1]
	var command := AttackCommand.new(a.id, b.id, a.cell, b.cell, &"demo_strike", s.context.get_revision())
	if fault: s._queue = ActionQueue.new(1, 512)
	var preview := ForecastSimulation.run(s.context, s._queue, command)
	s._queue.capture_presentation = true
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == (ActionReceipt.FAULTED if fault else ActionReceipt.APPLIED), "real shot accepted or retains faulted prefix: " + String(receipt.reason))
	check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "shot events and steps equal isolated preview")
	check(snapshot(s) == {"state": preview.snapshot_after, "rng": preview.rng_after, "counters": preview.counters_after}, "shot snapshot RNG counters equal preview")
	return {"before": before, "frames": receipt.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}

func advance(seconds: float) -> void:
	if not player.active: return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	var guard := 0
	while player.active and guard < 100:
		advance(1.0)
		guard += 1
	check(not player.active, "packet completes")

func projectile() -> BattlePresentationProjectile:
	for child: Node in board._ghosts.get_children():
		if child is BattlePresentationProjectile: return child
	return null

func capture(label: String) -> void:
	if captures.is_empty(): return
	for impact: BattlePresentationImpact in board._impacts.get_children(): impact._tween.pause()
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func scenario(target: Vector2i, mode: String) -> void:
	player.cancel()
	board.reset_camera()
	var s := PlayerTurnFixture.create()
	configure(s, target, mode)
	var data := packet(s)
	if data.frames.is_empty():
		s.close()
		return
	var committed := snapshot(s)
	var actor: int = s.units[0].id
	var victim: int = s.units[1].id
	var stats_before := s.units[0].stats.to_snapshot_dict()
	check(float(data.before.units[actor].attack_range) == 4.0 and ActionPresentationState.capture(s.state).units[actor].attack_range == 4.0 and s.units[0].stats.to_snapshot_dict() == stats_before, "range capture is detached and read-only")
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	player._tween.pause()
	check(projectile() != null and not projectile().visible, "ranged actor prepares even when target is adjacent")
	advance(0.05)
	check(not projectile().visible and board._impacts.get_child_count() == 0 and board._numbers.get_child_count() == 0, "preparation has no premature flight or impact")
	var delta := target - Vector2i(2, 3)
	var distance := absi(delta.x) + absi(delta.y)
	var flight := 0.10 + 0.025 * float(distance - 1)
	advance(0.05 + flight * 0.25)
	if mode == "hp" and target == Vector2i(5, 3): await capture("arc-ascent")
	advance(flight * 0.25)
	var shot := projectile()
	check(shot != null and shot.visible and is_equal_approx(float(shot.get_meta("progress")), 0.5), "real Tween reaches middle of distance-timed flight")
	var art_scale := board.grid_config.tile_size.x / 128.0
	var source := board._world_cell_center(shot.get_meta("from_cell")) + (shot.get_meta("from_anchor") as Vector2) * art_scale
	var destination := board._world_cell_center(shot.get_meta("to_cell")) + (shot.get_meta("to_anchor") as Vector2) * art_scale
	var expected_height := 14.0 if distance == 1 else 54.0
	check(shot.position.is_equal_approx(source.lerp(destination, 0.5) - Vector2(0, expected_height * art_scale)), "flight midpoint has distance-scaled parabolic lift")
	check(board._presentation_visual(victim).unit.hp == data.before.units[victim].hp and board._impacts.get_child_count() == 0, "HP and impact wait for delivery")
	var tween := player._tween
	var position_before := shot.position
	board.zoom_camera(1.2, board.size * 0.5)
	board.pan_camera(Vector2(16, -8))
	check(projectile() == shot and player._tween == tween and shot.position == position_before, "camera transforms ongoing shot without restarting")
	board.size += Vector2(18, 12)
	check(projectile() == shot and is_equal_approx(float(shot.get_meta("progress")), 0.5) and shot.position != position_before, "resize reprojects paused shot from cells at same progress")
	art_scale = board.grid_config.tile_size.x / 128.0
	source = board._world_cell_center(shot.get_meta("from_cell")) + (shot.get_meta("from_anchor") as Vector2) * art_scale
	destination = board._world_cell_center(shot.get_meta("to_cell")) + (shot.get_meta("to_anchor") as Vector2) * art_scale
	check(shot.position.is_equal_approx(source.lerp(destination, 0.5) - Vector2(0, expected_height * art_scale)), "resize scales arc height with the field")
	check(shot.get_parent().transform == board.camera_view.get_transform(), "projectile shares field camera")
	if mode == "hp": await capture("flight-%d-%d" % [target.x, target.y])
	advance(flight * 0.25)
	if mode == "hp" and target == Vector2i(5, 3): await capture("arc-descent")
	advance(flight * 0.25 + 0.001)
	# Отдача теперь достигает раннего пика; старая середина попадала в ноль отскока.
	advance(0.04)
	check(projectile() == null and board._impacts.get_child_count() == 1 and board._presentation_visual(victim).action_offset.length() > 1.0, "delivery becomes exactly one contact and victim recoil")
	var recoil_peak := board._presentation_visual(victim).action_offset.length()
	check(board._presentation_visual(actor).action_offset.is_zero_approx(), "shooter recovery does not invent melee lunge")
	if mode in ["hp", "armor"]: await capture("contact-" + mode)
	advance(0.08)
	check(board._presentation_visual(victim).action_offset.length() < recoil_peak, "ranged impact recoil decays after early peak")
	finish()
	check(board._presentation_visual(victim).unit.hp == data.after.units[victim].hp, "result publishes HP after contact")
	var texts: Array[String] = []
	for number: BattlePresentationNumber in board._numbers.get_children():
		# Изменение состояния имеет отдельный вид обратной связи и не дублирует HP.
		if number.feedback_kind == &"result": texts.append(number._label.text)
	if mode == "armor": check(texts.size() == 1 and texts[0].contains("броня"), "armor absorption has one armor result")
	elif mode == "zero": check(texts == ["0 · без урона"], "zero has one honest result")
	elif mode == "critical": check(texts[0].begins_with("КРИТ"), "critical shot tagged")
	elif mode == "lethal": check(not board._presentation_visual(victim).unit.alive and texts[0].contains("1.0 HP"), "lethal shot displays actual loss")
	else:
		var hp_events: int = data.events.filter(func(e: Dictionary) -> bool: return e.kind in [&"damaged", &"healed"]).size()
		check(texts.size() == hp_events and texts[0].contains("HP"), "one number per actual HP event including item heal")
	check(snapshot(s) == committed, "playback preserves state RNG counters")
	player.cancel()
	s.close()
	await process_frame

func abort_cases() -> void:
	var s := PlayerTurnFixture.create()
	configure(s, Vector2i(5, 3))
	var data := packet(s)
	var committed := snapshot(s)
	player.set_speed(3.0)
	player.play(board, data.before, data.frames, data.after)
	advance(0.06)
	check(projectile() != null and projectile().visible, "x3 speeds preparation and flight together")
	player.skip()
	check(projectile() == null and board._pending_strikes.is_empty() and board._impacts.get_child_count() == 0 and board._numbers.get_child_count() == 0, "skip in flight clears every effect and pose")
	check(snapshot(s) == committed, "skip cannot change executed result")
	player.play(board, data.before, data.frames, data.after)
	advance(0.06)
	player.cancel()
	check(projectile() == null and board._action_offsets.is_empty(), "cancel clears flight and body recoil")
	s.close()
	s = PlayerTurnFixture.create()
	configure(s, Vector2i(5, 3))
	data = packet(s, true)
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	finish()
	check(projectile() == null and board._impacts.get_child_count() == 0 and board._numbers.get_child_count() == 0, "faulted launch without hit never invents contact")
	check(data.before.units[s.units[1].id].hp == data.after.units[s.units[1].id].hp, "faulted launch leaves target HP")
	player.cancel()
	s.close()
	s = PlayerTurnFixture.create()
	configure(s, Vector2i(3, 4))
	var before_rejection := snapshot(s)
	var a := s.units[0]
	var b := s.units[1]
	s._queue.capture_presentation = true
	var rejected := s._queue.submit(AttackCommand.new(a.id, b.id, a.cell, b.cell, &"demo_strike", s.context.get_revision()), s.context)
	check(rejected.status == ActionReceipt.REJECTED and rejected.reason == &"attack/not_aligned" and rejected.get_presentation_frames().is_empty(), "diagonal shot remains rejected without a flight frame")
	check(snapshot(s) == before_rejection, "rejected diagonal preserves state RNG counters")
	s.close()
	await process_frame

func ui_case(hub: bool) -> void:
	var demo: BattleDemo
	if hub:
		var view := HeroHubBattleView.new()
		view.supplied_session = PlayerTurnFixture.create()
		demo = view
	else:
		demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
		demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	PlayerTurnFixture.enter_player_turn(demo)
	var s := demo.session as BattleCoreReactionsSession
	configure(s, Vector2i(5, 3))
	s.select_unit(s.units[0].id)
	demo._refresh()
	demo._execute_live(&"attack_unit", [s.units[1].id], true)
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "real UI worker starts ranged presentation")
	board = demo.board_view
	player = demo._presentation_player
	advance(0.18)
	check(projectile() != null and projectile().visible, "real UI shows projectile in flight")
	var committed := snapshot(s)
	demo.handle_cell(Vector2i(3, 3))
	check(snapshot(s) == committed, "UI inspection during flight cannot execute next command")
	await capture("ui-hub-flight" if hub else "ui-main-flight")
	demo.skip_presentation()
	check(not demo.is_execution_pending() and projectile() == null and snapshot(s) == committed, "real UI skip releases completed shot")
	demo.queue_free()
	await process_frame

func run() -> void:
	arc_geometry()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 950)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	board.execution_pending = true
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	viewport.add_child(player)
	for mode: String in ["hp", "armor", "zero", "critical", "lethal"]: await scenario(Vector2i(5, 3), mode)
	await scenario(Vector2i(3, 3), "hp")
	await scenario(Vector2i(2, 6), "hp")
	check(is_equal_approx(BattleDemoBoard._shot_flight_seconds({"actor_cell": Vector2i.ZERO, "target_cell": Vector2i(99, 99)}), 0.24), "very long delivery duration is bounded")
	await abort_cases()
	board.queue_free()
	player.queue_free()
	await process_frame
	await ui_case(false)
	await ui_case(true)
	viewport.queue_free()
	await process_frame
	print("PRESENTATION RANGED RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func arc_geometry() -> void:
	var shot := BattlePresentationProjectile.new()
	var from := Vector2(80, 160)
	for delta: Vector2 in [Vector2(180, 90), Vector2(-180, 90), Vector2(180, -90), Vector2(-180, -90), Vector2(180, -130)]:
		var to := from + delta
		shot.sample(from, to, -1.0, 1.5, 54.0)
		check(shot.position == from and shot.scale == Vector2(1.5, 1.5), "arc launch clamps to source with independent artwork scale")
		shot.sample(from, to, 0.5, 1.5, 54.0)
		check(shot.position.is_equal_approx(from.lerp(to, 0.5) - Vector2(0, 54)), "arc midpoint lifts above endpoint chord including unequal heights")
		for progress: float in [0.25, 0.75]:
			shot.sample(from, to, progress - 0.001, 1.5, 54.0)
			var before := shot.position
			shot.sample(from, to, progress + 0.001, 1.5, 54.0)
			var after := shot.position
			shot.sample(from, to, progress, 1.5, 54.0)
			check(Vector2.RIGHT.rotated(shot.rotation).dot((after - before).normalized()) > 0.9999, "projectile points along measured ascent or descent tangent")
		shot.sample(from, to, 2.0, 1.5, 54.0)
		check(shot.position == to, "arc lands at exact destination in every direction")
	shot.sample(from, from, 0.5, 1.0)
	check(shot.position == from and is_finite(shot.rotation), "coincident endpoints and default straight sampler stay finite")
	var near_height := BattleDemoBoard._shot_arc_height(Vector2i.ZERO, Vector2i(1, 0))
	var far_height := BattleDemoBoard._shot_arc_height(Vector2i.ZERO, Vector2i(4, 0))
	check(far_height > near_height * 4.0, "long shot is steeper relative to chord length")
	check(BattleDemoBoard._shot_arc_height(Vector2i.ZERO, Vector2i(99, 0)) == 180.0, "extreme arc lift is bounded")
	shot.free()
