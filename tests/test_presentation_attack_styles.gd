extends "res://tests/test_presentation_contact.gd"

var started: Array[Dictionary] = []
var published: Array[Dictionary] = []


func full_state(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "style fixture captures full state")
	return {"state": captured.snapshot.to_dict(), "rng": s.context.get_rng().to_dict(),
		"counters": s.context.simulation_counters(), "admission": SummonAdmission.values(s.context)}


func rogue_fixture(direction: Vector2i, ranged: bool = false) -> Dictionary:
	var hub := HeroHubState.create()
	check(hub.start_battle(), "real hub starts battle")
	var built := HeroHubBattleFactory.create(hub)
	var s := built.session as BattleCoreReactionsSession
	var actor: UnitState
	var target: UnitState
	for unit: UnitState in s.units:
		if s.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"rogue": actor = unit
		if unit.faction == Faction.Type.ENEMY: target = unit
	check(actor != null and target != null, "factory supplies a real rogue and enemy")
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in s.units.size():
		var unit := s.units[index]
		s.board.move_unit(unit, Vector2i(index, 0))
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
	s.board.move_unit(actor, Vector2i(3, 3))
	s.board.move_unit(target, actor.cell + direction)
	actor.debug_name = "Другой герой"
	if ranged: actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 4.0)
	s.selected_id = actor.id
	return {"session": s, "actor": actor, "target": target}


func style_packet(s: BattleCoreReactionsSession, command: Command) -> Dictionary:
	var before := ActionPresentationState.capture(s.state)
	var original := full_state(s)
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(s.context, s._queue, command)
	check(full_state(s) == original and UnitId.get_counter() == ids, "style preview leaves source and IDs unchanged")
	s._queue.capture_presentation = true
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == preview.status and receipt.reason == preview.reason
		and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps,
		"style real receipt matches preview events and steps")
	check(full_state(s) == {"state": preview.snapshot_after, "rng": preview.rng_after,
		"counters": preview.counters_after, "admission": preview.admission_after}, "style full preview/live parity")
	return {"before": before, "frames": receipt.get_presentation_frames(),
		"after": ActionPresentationState.capture(s.state), "status": receipt.status}


func prepare_board(s: BattleCoreReactionsSession) -> void:
	player.cancel()
	board.execution_pending = false
	board.session = s
	board.refresh()
	board.execution_pending = true
	# Во время клипа живой session недоступен; класс уже снят безопасным refresh.
	board.session = null
	started.clear()
	published.clear()


func start_style(data: Dictionary, speed_value: float = 1.0) -> void:
	player.set_speed(speed_value)
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()


func airborne_offset(actor_id: int, direction: Vector2) -> float:
	var offset: Vector2 = board._action_offsets.get(actor_id, Vector2.ZERO)
	return offset.y - direction.y * offset.x / direction.x


func rogue_case(direction: Vector2i, fallback: bool = false) -> void:
	var setup := rogue_fixture(direction)
	var s := setup.session as BattleCoreReactionsSession
	var actor := setup.actor as UnitState
	var target := setup.target as UnitState
	var attack_id: StringName = s.actor_loadouts[actor.id].attack_id
	var data := style_packet(s, AttackCommand.new(actor.id, target.id, actor.cell, target.cell, attack_id, s.context.get_revision()))
	check(data.status == ActionReceipt.APPLIED, "real rogue attack applied")
	var saved := full_state(s)
	var immutable := data.duplicate(true)
	var scene := board.unit_visual_scene
	if fallback: board.unit_visual_scene = null
	prepare_board(s)
	# Меняем источник после копирования: ни имя, ни последующие правки словаря не управляют клипом.
	s.actor_loadouts[actor.id].class_id = &"warrior"
	start_style(data)
	var origin := board._presentation_visual(actor.id).position
	var aim := board._strike_direction({"actor_cell": actor.cell, "target_cell": target.cell})
	advance(0.10)
	check(airborne_offset(actor.id, aim) > 0.0, "rogue prepares below idle pose")
	check(board._impacts.get_child_count() == 0 and number_texts().is_empty(), "preparation has no invented contact")
	advance(0.06)
	check(airborne_offset(actor.id, aim) < -8.0, "rogue rises visibly above the ground-directed lunge")
	check(board._presentation_visual(actor.id).position == origin and board._view_unit_cell(actor.id) == actor.cell,
		"pounce keeps cell and sort support fixed")
	check(board._presentation_visual(target.id).unit.hp == data.before.units[target.id].hp,
		"airborne attack does not publish target HP early")
	if direction == Vector2i.RIGHT and not fallback:
		await capture("rogue-airborne")
		var offset: Vector2 = board._action_offsets[actor.id]
		board.size = Vector2(1180, 780)
		board.zoom_camera(0.75, board.size * 0.5)
		board.pan_camera(Vector2(12, -8))
		check(board._action_offsets[actor.id] == offset
			and board._presentation_visual(actor.id).action_offset.is_equal_approx(offset * board.grid_config.tile_size.x / 128.0),
			"resize zoom and pan preserve sampled hop")
		await capture("rogue-airborne-camera")
	advance(0.06)
	check(is_zero_approx(airborne_offset(actor.id, aim)), "contact lands exactly on the attack direction")
	advance(0.001)
	check(board._impacts.get_child_count() == 1, "rogue produces one confirmed contact")
	if direction == Vector2i.RIGHT and not fallback: await capture("rogue-contact")
	finish()
	var expected: Array[Dictionary] = []
	for frame: Dictionary in data.frames: expected.append(frame.after)
	expected.append(data.after)
	check(started == data.frames and published == expected, "hop preserves all frame and after publication order")
	check(full_state(s) == saved and data == immutable, "hop leaves live state RNG resources and source packet unchanged")
	check(board._action_offsets.is_empty() and board._presentation_visual(actor.id).action_offset == Vector2.ZERO, "rogue settles to exact idle")
	player.cancel()
	board.unit_visual_scene = scene
	board.size = viewport.size
	s.close()
	await process_frame


func ranged_and_reset() -> void:
	var setup := rogue_fixture(Vector2i.RIGHT, true)
	var s := setup.session as BattleCoreReactionsSession
	var actor := setup.actor as UnitState
	var target := setup.target as UnitState
	var data := style_packet(s, AttackCommand.new(actor.id, target.id, actor.cell, target.cell,
		s.actor_loadouts[actor.id].attack_id, s.context.get_revision()))
	prepare_board(s)
	start_style(data)
	advance(0.15)
	var strike: Dictionary = board._pending_strikes.values()[0]
	check(strike.presentation_ranged and not strike.presentation_pounce, "ranged rogue uses projectile even against adjacent target")
	check(is_zero_approx(airborne_offset(actor.id, board._strike_direction(strike))), "ranged preparation has no hop")
	check(board._ghosts.get_children().any(func(child: Node) -> bool: return child is BattlePresentationProjectile and child.visible), "ranged rogue retains visible projectile")
	finish()
	player.cancel()
	board.execution_pending = false
	board.refresh()
	check(board._view_actor_classes.is_empty(), "null session clears previous roster styles")
	s.close()
	var generic := fixture("hp")
	prepare_board(generic)
	data = packet(generic)
	start_style(data)
	advance(0.126)
	advance(0.001)
	check(board._impacts.get_child_count() == 1 and not board._pending_strikes.values()[0].presentation_pounce,
		"classless next battle retains the original fast lunge")
	player.cancel()
	generic.close()
	await process_frame


func abort_hop(mode: String) -> void:
	var setup := rogue_fixture(Vector2i.RIGHT)
	var s := setup.session as BattleCoreReactionsSession
	var actor := setup.actor as UnitState
	var target := setup.target as UnitState
	if mode == "fault": s._queue = ActionQueue.new(1, 512)
	var data := style_packet(s, AttackCommand.new(actor.id, target.id, actor.cell, target.cell,
		s.actor_loadouts[actor.id].attack_id, s.context.get_revision()))
	var saved := full_state(s)
	prepare_board(s)
	start_style(data, 3.0)
	advance(0.16 / 3.0)
	var aim := board._strike_direction({"actor_cell": actor.cell, "target_cell": target.cell})
	check(airborne_offset(actor.id, aim) < -8.0, mode + " x3 reaches the same airborne phase")
	if mode == "skip": player.skip()
	elif mode == "cancel": player.cancel()
	else:
		check(data.status == ActionReceipt.FAULTED, "real failed child leaves only attack prefix")
		finish()
	check(board._action_offsets.is_empty() and board._impacts.get_child_count() == 0 and number_texts().is_empty(),
		mode + " clears airborne pose without invented hit")
	check(full_state(s) == saved, mode + " cannot mutate actual outcome")
	player.cancel()
	s.close()
	await process_frame


func reaction_style() -> void:
	var s := fixture("counter")
	# Реальная контратака; класс здесь только метаданные визуальной фикстуры, не новое право разбойника.
	s.actor_loadouts[s.units[1].id] = {"class_id": &"rogue"}
	var data := packet(s)
	prepare_board(s)
	start_style(data)
	var guard := 0
	while player.active and guard < 100:
		if board._pending_strikes.values().any(func(event: Dictionary) -> bool: return event.kind == &"counterattacked"): break
		advance(0.02)
		guard += 1
	var strike: Dictionary = board._pending_strikes.values()[0] if not board._pending_strikes.is_empty() else {}
	check(strike.get("actor_unit_id") == s.units[1].id and strike.get("presentation_pounce", false), "reaction selects actual attacker class, not selected unit")
	finish()
	player.cancel()
	s.close()
	await process_frame


func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	viewport.add_child(player)
	player.frame_started.connect(func(frame: Dictionary) -> void: started.append(frame))
	player.frame_finished.connect(func(state: Dictionary) -> void: published.append(state))
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]: await rogue_case(direction)
	await rogue_case(Vector2i.RIGHT, true)
	await ranged_and_reset()
	for mode: String in ["skip", "cancel", "fault"]: await abort_hop(mode)
	await reaction_style()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION ATTACK STYLES RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
