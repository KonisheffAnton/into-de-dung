extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport
var board: BattleDemoBoard

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HAZARDS UI: " + label)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func run() -> void:
	var wall_toward := Vector2(1.0, -0.5).normalized()
	check(BattleEnvironmentVisual.wall_spike_direction(Vector2i.UP).dot(wall_toward) < -0.99,
		"wall spikes extend from wall into the contact cell")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await authored_presets()
	board = BattleDemoBoard.new()
	board.size = Vector2(1280, 800)
	viewport.add_child(board)
	await process_frame
	var profile := HeroHubState.create(443)
	profile.enable_mage_deck()
	var started := ExpeditionTransitions.apply(profile, "start")
	check(started.is_ok(), "production H1/U14 opening can be entered")
	if started.is_ok():
		var bundle := HeroHubBattleFactory.create(started.profile)
		check(not bundle.is_empty(), "production opening bundle is available")
		if not bundle.is_empty():
			var session: BattleCoreReactionsSession = bundle.session
			board.session = session
			board.refresh()
			var value := ActionPresentationState.capture(session.state)
			var hazards: Dictionary = value.get("hazards", {})
			check(hazards.get("traps", []).size() == 3 and hazards.get("acid", []).size() == 1,
				"production presentation snapshot publishes three traps and one acid cell")
			for trap: Dictionary in hazards.get("traps", []):
				var overlay := board._environment_visuals.get(trap.cell) as BattleEnvironmentVisual
				check(overlay != null and (overlay.floor_trap or overlay.wall_trap_direction != Vector2i.ZERO),
					"trap contact cell receives its authored floor or wall visual")
				if String(trap.kind) == "wall":
					board._field_presentation.sample_trap(1.0, board, trap.cell, "wall", trap.direction)
					check(is_equal_approx(overlay.trap_progress, 1.0) and overlay.wall_trap_direction == trap.direction,
						"wall spikes extend from wall into contact cell")
					await capture("wall-impale")
					board._field_presentation.sample_trap(0.0, board, trap.cell, "wall", trap.direction)
			var acid_cell: Vector2i = hazards.get("acid", [Vector2i(-1, -1)])[0]
			var acid_overlay := board._environment_visuals.get(acid_cell) as BattleEnvironmentVisual
			check(acid_overlay != null and acid_overlay.acid_pool, "acid cell receives green pool overlay")
			await capture("production-opening-hazards")
			var detached := value.duplicate(true)
			board.show_presentation_state(detached)
			var saved_hazards: Dictionary = board._view_hazards.duplicate(true)
			detached.hazards.traps[0].cell = Vector2i(7, 7)
			check(board._view_hazards == saved_hazards and board._environment_visuals.has(saved_hazards.traps[0].cell),
				"render keeps detached hazard snapshot after source metadata changes")
			var spike_cell: Vector2i = saved_hazards.traps[0].cell
			board._field_presentation.sample_trap(0.2, board, spike_cell)
			var overlay := board._environment_visuals[spike_cell] as BattleEnvironmentVisual
			check(is_equal_approx(overlay.trap_progress, 0.2), "spike has a sharp extension sample")
			board.execution_pending = true
			board.size += Vector2(16, 12)
			board._rebuild_visuals()
			overlay = board._environment_visuals[spike_cell] as BattleEnvironmentVisual
			check(is_equal_approx(overlay.trap_progress, 0.2), "pending visual rebuild restores the sampled spike pose")
			board._field_presentation.sample_trap(1.0, board, spike_cell)
			check(is_equal_approx(overlay.trap_progress, 1.0), "spike holds at full extension")
			await capture("floor-impale")
			board._field_presentation.sample_trap(0.0, board, spike_cell)
			check(is_equal_approx(overlay.trap_progress, 0.0), "spike retracts to the plate after impact")
			board.execution_pending = false
			var unit_ids: Array = value.get("units", {}).keys()
			if not unit_ids.is_empty():
				var acid_frame := value.duplicate(true)
				var acid_id: int = int(unit_ids[0])
				acid_frame.units[acid_id].elemental["acid_ticks"] = 3
				board.show_presentation_state(acid_frame)
				check(board._presentation_visual(acid_id).visible_status_entries().any(func(entry: Dictionary) -> bool: return entry.id == "acid")
					and board.displayed_unit_details(acid_id).contains("В кислоте")
					and board.displayed_unit_details(acid_id).contains("3 ход., 10 брони/ход"),
					"visible acid debuff names its remaining duration and armor-only tick")
				await capture("acid-status")
			await trap_playback(session)
			board.session = null
			session.close()
	var acid_status := BattleStatusPresentation.entries({"elemental": {"acid_ticks": 3}})
	check(acid_status.size() == 1 and acid_status[0].id == "acid" and acid_status[0].title == "В кислоте"
		and int(acid_status[0].remaining) == 3 and String(acid_status[0].duration_unit).contains("10 брони/ход"),
		"acid status shows duration and armor-only tick description")
	check(BattleStatusPresentation.entries({"elemental": {"acid_ticks": 0}}).is_empty(), "expired acid status is removed from the presentation")
	board.show_presentation_state({"width": 0, "height": 0, "hazards": {}})
	check(board._view_hazards.is_empty(), "legacy frames without hazards remain disabled")
	board.queue_free()
	viewport.queue_free()
	await process_frame
	print("HAZARDS UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func authored_presets() -> void:
	var scene := preload("res://scenes/demo/visuals/environment_overlay.tscn")
	var gallery := Node2D.new()
	viewport.add_child(gallery)
	var names: Array[String] = ["FloorTrap", "WallTrapUp", "WallTrapRight", "WallTrapDown", "WallTrapLeft"]
	var directions: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var positions: Array[Vector2] = [Vector2(180, 280), Vector2(460, 280), Vector2(770, 250), Vector2(470, 560), Vector2(820, 580)]
	# Контракт опоры: общая грань соседних ромбов и вертикальная высота стены 32.
	var edges: Array[Vector2] = [Vector2.ZERO, Vector2(0, -32), Vector2(64, 0), Vector2(0, 32), Vector2(-64, 0)]
	for index: int in names.size():
		var overlay := scene.instantiate() as BattleEnvironmentVisual
		gallery.add_child(overlay)
		overlay.position = positions[index]
		overlay.scale = Vector2(2.5, 2.5)
		overlay.configure(false, false, false, [], false, index == 0, directions[index], true)
		overlay.trap_progress = 1.0
		var preset := overlay.get_node(names[index]) as Node2D
		var spikes := preset.get_node("Spikes")
		check(preset.visible and spikes.get_child_count() == 16, names[index] + " shows 16 authored spikes")
		var tip := spikes.get_child(0).get_node("Tip") as Polygon2D
		var original := tip.polygon.duplicate()
		# Изменённый в редакторе силуэт должен пережить семплирование анимации.
		var edited := original.duplicate()
		edited[0] += Vector2(0.25, 0.5)
		tip.polygon = edited
		overlay.trap_progress = 0.4
		check(tip.polygon == edited, names[index] + " playback preserves authored polygon overrides")
		tip.polygon = original
		overlay.trap_progress = 1.0
		var panel := preset.get_node("Panel") as Polygon2D
		if index == 0:
			check(panel.polygon.has(Vector2(62, 0)) and panel.polygon.has(Vector2(-62, 0))
				and panel.polygon.has(Vector2(0, 30)) and panel.polygon.has(Vector2(0, -30)), "floor preset fills the tile rhombus")
			check(tip.polygon[0].is_equal_approx(Vector2(0, -36)), "floor spikes retain their accepted 36px extension")
		else:
			var start := edges[index]
			var end := edges[index % 4 + 1]
			for corner: Vector2 in [start, end, start + Vector2(0, -32), end + Vector2(0, -32)]:
				var near := false
				for point: Vector2 in panel.polygon:
					if (preset.transform * panel.transform * point).distance_to(corner) <= 4.0: near = true
				check(near, names[index] + " panel reaches shared wall face corner " + str(corner))
			var inward := BattleEnvironmentVisual.wall_spike_direction(directions[index])
			var columns: Dictionary = {}
			var rows: Dictionary = {}
			var inward_tips := true
			for spike: Node2D in spikes.get_children():
				var u := (spike.position.x - start.x) / (end.x - start.x)
				var v := (start.lerp(end, u).y - spike.position.y) / 32.0
				columns[snappedf(u, 0.001)] = true
				rows[snappedf(v, 0.001)] = true
				var shape := spike.get_node("Tip") as Polygon2D
				var extended := spike.transform * shape.polygon[0] - spike.position
				inward_tips = inward_tips and extended.dot(inward) > 35.9
			check(columns.size() == 4 and rows.size() == 4 and rows.has(0.125) and rows.has(0.875)
				and columns.has(0.125) and columns.has(0.875), names[index] + " spike bases cover all four rows and columns")
			check(inward_tips, names[index] + " authored spikes extend 36px from wall into contact tile")
		overlay.collapse_progress = 1.0
		check(preset.modulate.a == 0.0, names[index] + " disappears with its collapsed support")
		overlay.collapse_progress = -1.0
	var acid := scene.instantiate() as BattleEnvironmentVisual
	gallery.add_child(acid)
	acid.position = Vector2(1080, 400)
	acid.scale = Vector2(2.5, 2.5)
	acid.configure(false, false, false, [], true)
	check(acid.get_node("AcidPool").visible, "acid uses its authored scene preset")
	await capture("authored-hazard-presets")
	gallery.queue_free()
	await process_frame

func advance(player: BattlePresentationPlayer, seconds: float) -> void:
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active and player._tween != null: player._tween.pause()

func trap_playback(session: BattleCoreReactionsSession) -> void:
	var unit := session.units[0]
	var cell := Vector2i(2, 4)
	session.board.move_unit(unit, cell)
	var trap: Dictionary = session.state.environment.hazards.traps[0]
	trap.occupant_id = unit.id
	trap.armed_team = int(unit.faction)
	var before := ActionPresentationState.capture(session.state)
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(BleedingTurnCommand.new(unit.faction, session.context.get_revision()), session.context)
	var frames := receipt.get_presentation_frames()
	var index := frames.find_custom(func(frame: Dictionary) -> bool: return not BattleFieldPresentation.trap_event(frame.events).is_empty())
	check(receipt.status == ActionReceipt.APPLIED and index >= 0, "real delayed trap supplies its damage presentation frame")
	if index < 0: return
	var frame: Dictionary = frames[index].duplicate(true)
	if index > 0: before = frames[index - 1].after.duplicate(true)
	var packet: Array[Dictionary] = [frame]
	var original := packet.duplicate(true)
	var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict()
	var counters := session.context.simulation_counters()
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	board.execution_pending = true
	var publications: Array[Dictionary] = []
	player.frame_finished.connect(func(value: Dictionary) -> void: publications.append(value))
	player.play(board, before, packet, frame.after)
	advance(player, 1.0)
	check(player.active and publications == [frame.after] and player._published.units[unit.id].hp == 0.0
		and board._numbers.get_child_count() > 0 and is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0),
		"damage HP and result number publish while spikes remain fully raised")
	advance(player, 0.35)
	check(is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0), "spikes remain visible 350ms after damage publication")
	board.size += Vector2(8, 6)
	board._rebuild_visuals()
	check(is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0), "resize preserves the raised spikes during the result hold")
	await capture("damage-spikes-held")
	advance(player, 0.34)
	check(player.active and is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0), "spikes still hold at 690ms after damage")
	advance(player, 0.06)
	check(player.active and board._environment_visuals[cell].trap_progress > 0.0 and board._environment_visuals[cell].trap_progress < 1.0, "spikes retract only after the 700ms result hold")
	advance(player, 0.06)
	check(not player.active and publications == [frame.after, frame.after] and board._field_presentation.cells.is_empty(), "retraction finishes without duplicate frame publication or lingering poses")
	for abort: String in ["skip", "cancel", "speed"]:
		player.play(board, before, packet, frame.after)
		advance(player, 1.0)
		if abort == "skip": player.skip()
		elif abort == "cancel": player.cancel()
		else:
			player.set_speed(2.0)
			advance(player, 0.34)
			check(player.active and is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0), "playback speed applies to the post-damage hold")
			advance(player, 0.07)
		check(not player.active and board._field_presentation.cells.is_empty(), "result hold cleans up on " + abort)
	player.set_speed(1.0)
	var empty := BattleFieldPresentation.trap_event(frame.events)
	empty.target_unit_id = 0
	var empty_packet: Array[Dictionary] = [{"step": frame.step.duplicate(true), "events": [empty], "after": before.duplicate(true)}]
	player.play(board, before, empty_packet, before)
	advance(player, 0.05)
	check(player.active and is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0), "empty armed plate still visibly extends and holds")
	player.skip()
	check(packet == original and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == snapshot
		and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters,
		"timed playback and cancellation leave source packet, live state, RNG and counters unchanged")
	board.execution_pending = false
	player.queue_free()
