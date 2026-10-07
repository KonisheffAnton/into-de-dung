extends "res://tests/test_push_chain.gd"

var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var captures: String = ""
var started: Array[Dictionary] = []
var published: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("run")


func field_fixture() -> BattleCoreReactionsSession:
	var s := fixture()
	s.state.environment.corpses.clear()
	s.state.environment.collapse = {"turn": 0, "marked": []}
	return s

func seek_cell(cell: Vector2i, kind: StringName) -> void:
	var guard := 0
	while player.active and guard < 150:
		if board._field_presentation.cells.get(cell, {}).get("kind") == kind: return
		advance(0.025)
		guard += 1

func packet_attack(s: BattleCoreReactionsSession, label: String) -> Dictionary:
	var before: Dictionary = ActionPresentationState.capture(s.state)
	s._queue.capture_presentation = true
	var receipt: ActionReceipt = parity(s, label)
	return {"before": before, "frames": receipt.get_presentation_frames(),
		"after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}


func packet_move(s: BattleCoreReactionsSession, destination: Vector2i, label: String) -> Dictionary:
	var before: Dictionary = ActionPresentationState.capture(s.state)
	var rng_before: Dictionary = s.context.get_rng().to_dict().duplicate(true)
	var counters_before: Dictionary = s.context.simulation_counters()
	var snapshot_before: Dictionary = snapshot(s)
	var forecast: MoveForecast = s.preview_move(destination)
	check(forecast.snapshot_before == snapshot_before and snapshot(s) == snapshot_before
		and rng_before == s.context.get_rng().to_dict() and counters_before == s.context.simulation_counters(),
		label + " preview leaves source untouched")
	s._queue.capture_presentation = true
	var receipt: ActionReceipt = s.move_to(destination)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason
		and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps,
		label + " live move matches preview receipt")
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after
		and s.context.simulation_counters() == forecast.counters_after,
		label + " live move matches preview state/RNG/counters")
	return {"before": before, "frames": receipt.get_presentation_frames(),
		"after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}


func advance(seconds: float) -> void:
	if not player.active or player._tween == null:
		return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active and player._tween != null:
		player._tween.pause()


func finish() -> void:
	var guard: int = 0
	while player.active and guard < 100:
		advance(1.0)
		guard += 1
	check(not player.active, "presentation naturally completes")


func capture(label: String) -> void:
	if captures.is_empty():
		return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)


func start_packet(data: Dictionary, s: BattleCoreReactionsSession, label: String) -> Dictionary:
	var state_before: Dictionary = snapshot(s)
	var rng_before: Dictionary = s.context.get_rng().to_dict().duplicate(true)
	var counters_before: Dictionary = s.context.simulation_counters()
	var immutable: Dictionary = data.duplicate(true)
	started.clear()
	published.clear()
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	if player.active and player._tween != null:
		player._tween.pause()
	check(snapshot(s) == state_before and s.context.get_rng().to_dict() == rng_before
		and s.context.simulation_counters() == counters_before and data == immutable,
		label + " playback preserves world, RNG, counters and packet")
	return {"snapshot": state_before, "rng": rng_before, "counters": counters_before, "packet": immutable}


func assert_playback_unchanged(s: BattleCoreReactionsSession, saved: Dictionary, data: Dictionary, label: String) -> void:
	check(snapshot(s) == saved.snapshot and s.context.get_rng().to_dict() == saved.rng
		and s.context.simulation_counters() == saved.counters and data == saved.packet,
		label + " samples are read-only")
	var expected: Array[Dictionary] = []
	for frame: Dictionary in data.frames: expected.append(frame.after)
	expected.append(data.after)
	check(started == data.frames and published == expected, label + " every frame and after publishes once in receipt order")


func seek_pose(id: int, kinds: Array[StringName]) -> Dictionary:
	var guard: int = 0
	while player.active and guard < 100:
		var pose: Dictionary = board._field_presentation.poses.get(id, {})
		if StringName(pose.get("kind", &"")) in kinds:
			return pose
		advance(0.025)
		guard += 1
	return board._field_presentation.poses.get(id, {})


func lower_floor_chain() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	check(s.board.set_height_steps(Vector2i(5, 3), -4), "lower-floor fixture sets a supported destination")
	var data: Dictionary = packet_attack(s, "environment lower floor")
	var events_in_packet: Array[Dictionary] = data.events
	check(events_in_packet.any(func(event: Dictionary) -> bool: return event.kind == &"moved" and event.to_cell == Vector2i(5, 3)),
		"real chain receipt moves terminal unit onto lower floor")
	var saved: Dictionary = start_packet(data, s, "lower-floor")
	var terminal_id: int = s.units[5].id
	var pose: Dictionary = seek_pose(terminal_id, [&"fall", &"land"])
	check(not pose.is_empty(), "real chain publishes fall or landing pose")
	if pose.get("kind") == &"fall":
		advance(0.08)
		pose = board._field_presentation.poses[terminal_id]
		check(float(pose.progress) > 0.0 and float(pose.progress) < 1.0, "lower-floor fall sampled between endpoints")
		var preserved := pose.duplicate(true)
		board.size += Vector2(24, 16)
		board.zoom_camera(0.75, board.size * 0.5)
		board.pan_camera(Vector2(12, -8))
		check(board._field_presentation.poses[terminal_id] == preserved and board._presentation_visual(terminal_id).presentation_lift != 0.0, "resize and camera preserve airborne phase")
		await capture("fall")
	else:
		check(float(pose.get("progress", -1.0)) >= 0.0, "lower-floor landing has intermediate compression progress")
		await capture("landing")
	check(board._view_unit_cell(terminal_id) == Vector2i(4, 3), "fall does not publish destination before landing")
	check(not seek_pose(terminal_id, [&"land"]).is_empty(), "supported fall reaches contact before damage publication")
	advance(0.02)
	await capture("landing")
	finish()
	check(board._view_unit_cell(terminal_id) == s.units[5].cell, "lower-floor natural playback publishes actual final position")
	assert_playback_unchanged(s, saved, data, "lower-floor")
	player.cancel()
	board.size = viewport.size
	board.reset_camera()
	s.close()
	await process_frame


func out_of_bounds_chain() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	for i: int in 6: s.board.move_unit(s.units[i], Vector2i(i, 0))
	for pair: Array in [[0, Vector2i(4, 3)], [1, Vector2i(5, 3)], [2, Vector2i(6, 3)], [5, Vector2i(7, 3)]]:
		check(s.board.move_unit(s.units[int(pair[0])], pair[1]), "fall fixture places chain member")
	var data: Dictionary = packet_attack(s, "environment out of bounds")
	check(data.events.any(func(event: Dictionary) -> bool: return event.kind == &"fell" and event.target_unit_id == s.units[5].id),
		"out-of-bounds terminal fall is in real chain receipt")
	check(not data.after.units[s.units[5].id].alive and not data.after.corpses.any(func(corpse: Dictionary) -> bool: return corpse.source_unit_id == s.units[5].id), "void death has no corpse in published result")
	var saved: Dictionary = start_packet(data, s, "out-of-bounds")
	var dead_id: int = s.units[5].id
	check(board._presentation_visual(dead_id).unit.alive, "void victim remains visible until its fall cue publishes")
	var pose: Dictionary = seek_pose(dead_id, [&"fall"])
	check(not pose.is_empty() and bool(pose.get("vanish", false)), "out-of-bounds death uses a vanishing fall pose")
	advance(0.1)
	await capture("fall-void")
	finish()
	check(not board._presentation_visual(dead_id).unit.alive and board._view_corpses.is_empty(), "void final state hides victim without adding a body")
	assert_playback_unchanged(s, saved, data, "void death")
	player.cancel()
	s.close()
	await process_frame


func void_chain_same_frame() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.VOID)
	var data: Dictionary = packet_attack(s, "environment in-bounds void")
	var terminal_id: int = s.units[5].id
	var same_frame: bool = false
	var terminal_index: int = -1
	for frame: Dictionary in data.frames:
		var has_move: bool = frame.events.any(func(event: Dictionary) -> bool:
			return event.kind == &"moved" and event.get("target_unit_id", 0) == terminal_id)
		var has_death: bool = frame.events.any(func(event: Dictionary) -> bool:
			return event.kind == &"died" and event.get("target_unit_id", 0) == terminal_id)
		if has_move and has_death:
			same_frame = true
			terminal_index = data.frames.find(frame)
	check(same_frame, "spatial VOID publishes terminal move and death in one captured frame")
	check(not data.after.corpses.any(func(corpse: Dictionary) -> bool: return corpse.source_unit_id == terminal_id),
		"in-bounds VOID death creates no corpse")
	var saved: Dictionary = start_packet(data, s, "void-same-frame")
	check(board._presentation_visual(terminal_id).unit.alive, "same-frame death does not preempt the visible body")
	var pose: Dictionary = seek_pose(terminal_id, [&"fall"])
	check(not pose.is_empty() and pose.get("kind") == &"fall", "same-frame void event drives a local fall pose")
	check(player._chain != null and board._action_offsets.get(s.units[2].id, Vector2.ZERO).length() > 0.1,
		"in-bounds void fall starts while previous collision body is still returning")
	check(pose.get("from") == Vector2i(4, 3) and pose.get("to") == Vector2i(5, 3) and pose.get("vanish", false), "grouped void fall is one continuous terminal displacement")
	advance(0.1)
	await capture("fall-void-same-frame")
	finish()
	check((board._presentation_visual(terminal_id) == null or not board._presentation_visual(terminal_id).unit.alive) and board._view_corpses.all(
		func(corpse: Dictionary) -> bool: return corpse.source_unit_id != terminal_id),
		"same-frame final publication hides the void victim without a corpse")
	assert_playback_unchanged(s, saved, data, "same-frame void death")
	player.cancel()
	# Тот же реальный кадр без предшествующей цепи проверяет обычный проигрыватель.
	if terminal_index > 0:
		var frame: Dictionary = data.frames[terminal_index]
		var isolated_frames: Array[Dictionary] = [frame]
		var isolated := {"before": data.frames[terminal_index - 1].after, "frames": isolated_frames, "after": frame.after}
		var isolated_saved := start_packet(isolated, s, "isolated void frame")
		var isolated_pose := seek_pose(terminal_id, [&"fall"])
		check(player._chain == null and isolated_pose.get("from") == Vector2i(5, 3) and isolated_pose.get("to") == Vector2i(5, 3), "standalone void death does not replay the completed move")
		finish()
		assert_playback_unchanged(s, isolated_saved, isolated, "isolated void frame")
		player.cancel()
	s.close()
	await process_frame


func lethal_attack_corpse() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	var victim: UnitState = s.units[1]
	victim.vitals.set_hp(1.0)
	var data: Dictionary = packet_attack(s, "environment lethal attack")
	check(data.events.any(func(event: Dictionary) -> bool: return event.kind == &"died" and event.target_unit_id == victim.id),
		"ordinary lethal attack receipt includes death")
	check(data.after.corpses.size() == 1 and data.after.corpses[0].source_unit_id == victim.id,
		"ordinary death receipt publishes one source-linked corpse")
	var saved: Dictionary = start_packet(data, s, "corpse")
	var view: BattleDemoIsoVisual = board._presentation_visual(victim.id)
	check(view.unit.alive and board._view_corpses.is_empty(), "before death publication body is alive and no corpse is drawn")
	var pose: Dictionary = seek_pose(victim.id, [&"death"])
	view = board._presentation_visual(victim.id)
	check(not pose.is_empty() and view.death_progress > 0.0 and view.death_progress < 1.0,
		"death animation samples a live figure before publication")
	advance(0.07)
	await capture("death")
	finish()
	check(not board._presentation_visual(victim.id).unit.alive and board._view_corpses.size() == 1,
		"corpse appears with final dead unit publication")
	var overlay: BattleEnvironmentVisual = board._environment_visuals.get(victim.cell) as BattleEnvironmentVisual
	check(overlay != null and overlay.corpse_records.size() == 1, "surface overlay receives copied corpse value")
	if overlay != null:
		var copied_records: Array[Dictionary] = overlay.corpse_records.duplicate(true)
		var supplied: Array[Dictionary] = copied_records.duplicate(true)
		overlay.configure(false, false, false, supplied)
		supplied[0].faction = 99
		check(overlay.corpse_records == copied_records, "corpse presentation deeply detaches supplied records")
	await capture("corpse")
	assert_playback_unchanged(s, saved, data, "ordinary death")
	player.cancel()
	s.close()
	await process_frame


func field_entry_cases() -> void:
	for effect: String in ["bleeding", "burning"]:
		var s: BattleCoreReactionsSession = field_fixture()
		var destination: Vector2i = Vector2i(1, 4)
		check(not s.state.environment.ignite(destination, effect).is_empty(), effect + " fixture creates real cell hazard")
		var data: Dictionary = packet_move(s, destination, "environment entry " + effect)
		var saved: Dictionary = start_packet(data, s, "hazard " + effect)
		var overlay: BattleEnvironmentVisual = board._environment_visuals.get(destination) as BattleEnvironmentVisual
		check(overlay != null, effect + " floor has a reusable environment overlay")
		if overlay != null:
			check(overlay.has_spikes == (effect == "bleeding"), effect + " value config identifies spike versus fire tile")
			check(overlay.corpse_records.is_empty(), effect + " hazard overlay has no invented corpses")
		seek_cell(destination, &"hazard")
		check(board._field_presentation.cells.has(destination), effect + " real entry receipt animates the source cell")
		advance(0.025)
		var cell_pose: Dictionary = board._field_presentation.cells.get(destination, {})
		check(cell_pose.get("kind") == &"hazard" and float(cell_pose.get("progress", 0.0)) > 0.0,
			effect + " hazard accent is sampled from receipt")
		await capture("hazard-" + effect)
		finish()
		assert_playback_unchanged(s, saved, data, "hazard entry " + effect)
		player.cancel()
		s.close()
		await process_frame


func collapse_and_corpse_cleanup() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	var victim: UnitState = s.units[5]
	var cell: Vector2i = victim.cell
	var death: ActionReceipt = s._submit(DeathCommand.new(victim.id, DamageSource.new(&"test", 0, cell)))
	check(death.status == ActionReceipt.APPLIED and s.state.environment.corpses_at(cell).size() == 1,
		"collapse fixture starts with a real corpse")
	var second := s.units[2]
	check(s.board.move_unit(second, cell), "corpse does not occupy cell for second victim")
	s._submit(DeathCommand.new(second.id, DamageSource.new(&"test", 0, cell)))
	s.state.environment.collapse = {"turn": 1, "marked": [cell]}
	var before: Dictionary = ActionPresentationState.capture(s.state)
	var snapshot_before: Dictionary = snapshot(s)
	var rng_before: Dictionary = s.context.get_rng().to_dict().duplicate(true)
	var counters_before: Dictionary = s.context.simulation_counters()
	var preview: ForecastSimulation = s.preview_environment()
	check(snapshot_before == preview.snapshot_before and snapshot(s) == snapshot_before
		and rng_before == s.context.get_rng().to_dict() and counters_before == s.context.simulation_counters(),
		"collapse preview leaves world, RNG and counters unchanged")
	s._queue.capture_presentation = true
	var receipt: ActionReceipt = s._submit(CollapsePhaseCommand.new(s.context.get_revision()))
	var after: Dictionary = ActionPresentationState.capture(s.state)
	check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
		and snapshot(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after
		and s.context.simulation_counters() == preview.counters_after,
		"real collapse command matches forecast events, steps, snapshots, RNG and counters")
	check(receipt.get_events().size() >= 2 and receipt.get_events()[0].kind == &"environment_turn"
		and receipt.get_events()[1].kind == &"support_collapsed", "actual phase publishes mark then collapse order")
	check(before.corpses.size() == 2 and after.corpses.is_empty(), "collapsed corpses are removed only in final snapshot")
	var data: Dictionary = {"before": before, "frames": receipt.get_presentation_frames(), "after": after, "events": receipt.get_events()}
	board.show_presentation_state(data.before)
	var overlay: BattleEnvironmentVisual = board._environment_visuals.get(cell) as BattleEnvironmentVisual
	check(overlay != null and overlay.is_warning and overlay.corpse_records.size() == 2,
		"marked floor warns and keeps corpse before collapse publication")
	await capture("warning")
	var saved: Dictionary = start_packet(data, s, "collapse")
	# Граница environment_turn теперь уступает рендеру: измеряем прогресс
	# относительно начала настоящего клипа обвала, а не начала всего пакета.
	seek_cell(cell, &"collapse")
	advance(0.11)
	overlay = board._environment_visuals.get(cell) as BattleEnvironmentVisual
	var cell_pose: Dictionary = board._field_presentation.cells.get(cell, {})
	check(cell_pose.get("kind") == &"collapse" and float(cell_pose.get("progress", 0.0)) > 0.0
		and float(cell_pose.get("progress", 1.0)) < 1.0, "collapse event samples intermediate deterministic progress")
	if overlay != null:
		check(overlay.collapse_progress > 0.0 and overlay.collapse_progress < 1.0,
			"collapse fades hazard and corpse layer before tile removal")
	await capture("collapse")
	finish()
	check(board._view_terrain_at(cell) == TerrainType.Type.VOID and board._view_corpses.is_empty(),
		"collapse final publication removes floor and corpse")
	assert_playback_unchanged(s, saved, data, "collapse")
	player.cancel()
	s.close()
	await process_frame


func interruption_cleanup() -> void:
	var s: BattleCoreReactionsSession = field_fixture()
	s.board.set_height_steps(Vector2i(5, 3), -4)
	var data: Dictionary = packet_attack(s, "environment cleanup")
	for mode: String in ["natural", "x3", "skip", "cancel"]:
		player.cancel()
		player.set_speed(3.0 if mode == "x3" else 1.0)
		player.play(board, data.before, data.frames, data.after)
		if player.active and player._tween != null:
			player._tween.pause()
		check(not seek_pose(s.units[5].id, [&"fall"]).is_empty(), mode + " interruption targets actual fall")
		if mode in ["natural", "x3"]:
			finish()
		else:
			advance(0.03)
			if mode == "skip": player.skip()
			else: player.cancel()
		check(not player.active and board._field_presentation.poses.is_empty()
			and board._field_presentation.cells.is_empty(), mode + " clears field pose registries")
		check(board._environment_visuals.is_empty() or board._field_presentation.cells.is_empty(),
			mode + " leaves no running field animation")
	player.cancel()
	s.close()
	await process_frame

func occupied_collapse() -> void:
	for fault: bool in [false, true]:
		var s := field_fixture()
		var victim := s.units[5]
		var cell := victim.cell
		s.state.environment.collapse = {"turn": 1, "marked": [cell]}
		var before := ActionPresentationState.capture(s.state)
		var changed: Array[bool] = [false]
		var corrupt := func() -> void:
			if changed[0]: return
			changed[0] = true
			s.state.environment.next_fire_id += 1
		if fault: s.board.board_changed.connect(corrupt)
		s._queue.capture_presentation = true
		var receipt := s._submit(CollapsePhaseCommand.new(s.context.get_revision()))
		if fault: s.board.board_changed.disconnect(corrupt)
		check(receipt.status == (ActionReceipt.FAULTED if fault else ActionReceipt.APPLIED), "real occupied collapse status")
		var data := {"before": before, "frames": receipt.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}
		check(data.events.any(func(e: Dictionary) -> bool: return e.kind == &"died") == not fault, "fault prefix never invents unexecuted death")
		var saved := start_packet(data, s, "occupied collapse")
		seek_cell(cell, &"collapse")
		advance(0.08)
		check(board._view_terrain_at(cell) == TerrainType.Type.FLOOR and board._presentation_visual(victim.id).unit.alive, "collapse clip retains pre-publication floor and victim")
		if not fault:
			var pose := seek_pose(victim.id, [&"fall"])
			check(pose.get("vanish", false) and board._view_terrain_at(cell) == TerrainType.Type.VOID, "confirmed death falls only after support publication")
			advance(0.08)
			await capture("collapse-victim")
		finish()
		check(board._view_corpses.is_empty() and bool(data.after.units[victim.id].alive) == fault, "occupied collapse final prefix has no invented body")
		assert_playback_unchanged(s, saved, data, "occupied collapse")
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
	board.camera_controls_enabled = true
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	root.add_child(player)
	player.frame_started.connect(func(frame: Dictionary) -> void: started.append(frame))
	player.frame_finished.connect(func(state: Dictionary) -> void: published.append(state))
	await process_frame
	await lower_floor_chain()
	await out_of_bounds_chain()
	await void_chain_same_frame()
	await lethal_attack_corpse()
	await field_entry_cases()
	await collapse_and_corpse_cleanup()
	await occupied_collapse()
	await interruption_cleanup()
	player.queue_free()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION ENVIRONMENT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
