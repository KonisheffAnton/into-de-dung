extends "res://tests/test_presentation_consequences.gd"

func _slide_data(direction: Vector2i) -> Dictionary:
	var s := open_lane()
	var actor := s.units[0]
	var target := s.units[1]
	target.vitals.set_balance(8.0)
	s.unit_visual_classes[target.id] = &"warrior"
	check(s.board.move_unit(actor, Vector2i(0, 7)), "slide fixture parks actor")
	check(s.board.move_unit(target, Vector2i(1, 7)), "slide fixture parks target")
	check(s.board.move_unit(actor, Vector2i(3, 3) - direction), "slide fixture places attacker")
	check(s.board.move_unit(target, Vector2i(3, 3)), "slide fixture places target")
	var data := packet(s, "grounded slide %s" % str(direction))
	var moved := false
	for event: Dictionary in data.events:
		if event.get("kind") == &"moved" and int(event.get("target_unit_id", 0)) == target.id:
			moved = true
	check(moved and target.cell == Vector2i(3, 3) + direction, "real receipt pushes target one cell")
	check(actor.cell == Vector2i(3, 3) - direction, "slide fixture leaves attacker adjacent")
	return {"session": s, "data": data, "target_id": target.id, "start": Vector2i(3, 3), "end": Vector2i(3, 3) + direction}

func _wait_for_slide(id: int) -> bool:
	var guard := 0
	while player.active and not board._slide_poses.has(id) and guard < 200:
		advance(0.01)
		guard += 1
	return board._slide_poses.has(id)

func _check_slide_pose(id: int, start: Vector2i, destination: Vector2i, direction: Vector2i, label: String) -> void:
	var visual := board._presentation_visual(id)
	var expected := expected_screen_direction(direction)
	var progress := float(board._slide_poses[id].progress)
	var eased := BattleDemoBoard.push_slide_distance(progress)
	var start_screen := IsoGridUtils.grid_to_screen(start, board.grid_config, 0)
	var end_screen := IsoGridUtils.grid_to_screen(destination, board.grid_config, 0)
	var expected_support := start_screen.lerp(end_screen, eased)
	var actual_support := visual.position + visual.get_visual_offset()
	check(actual_support.is_equal_approx(expected_support), label + " foot support follows grounded path")
	check(visual.fall_drop == 0.0 and visual.presentation_lift == 0.0, label + " slide adds no hop or fall")
	check(visual.push_lean.dot(expected) > 0.0, label + " body leans along screen impulse")
	check(board._view_unit_cell(id) == start, label + " logical cell publishes only at segment end")
	var art := visual.get_node_or_null("ArtRoot") as Node2D
	if art != null:
		check(art.transform.origin.is_equal_approx(visual.get_visual_offset() + visual.action_offset), label + " ArtRoot keeps foot origin")
		var authored_scale := board.grid_config.tile_size.x / 128.0 * visual.get_unit_art_scale()
		check(is_equal_approx(art.transform.x.length(), authored_scale), label + " ArtRoot retains authored horizontal zoom scale under lean")
	if visual._ground_shadow != null:
		check(is_zero_approx(visual._ground_shadow.rotation) and visual._ground_shadow.position == visual.get_visual_offset(), label + " shadow stays at support without lean")
	if visual._status_hud != null:
		check(visual._status_hud.position == visual.get_visual_offset(), label + " HUD stays at support without lean")

func _check_damping_curve() -> void:
	var prior_distance := -1.0
	var prior_increment := INF
	var prior_speed := 2.0
	for index: int in range(101):
		var u := float(index) / 100.0
		var distance := BattleDemoBoard.push_slide_distance(u)
		var speed := BattleDemoBoard.push_slide_speed_ratio(u)
		check(is_finite(distance) and distance >= 0.0 and distance <= 1.0, "damping distance stays finite and bounded at %.2f" % u)
		check(distance >= prior_distance, "damping distance is monotonic at %.2f" % u)
		check(speed >= 0.0 and speed <= 1.0 and speed <= prior_speed, "damping speed decreases from one to zero at %.2f" % u)
		if index > 0:
			var increment := distance - prior_distance
			check(increment <= prior_increment + 0.000001, "damping increments decrease at %.2f" % u)
			prior_increment = increment
		prior_distance = distance
		prior_speed = speed
	check(is_equal_approx(BattleDemoBoard.push_slide_distance(-1.0), 0.0) and is_equal_approx(BattleDemoBoard.push_slide_distance(2.0), 1.0), "damping distance clamps out-of-range input")
	check(is_equal_approx(BattleDemoBoard.push_slide_speed_ratio(-1.0), 1.0) and is_equal_approx(BattleDemoBoard.push_slide_speed_ratio(2.0), 0.0), "damping speed clamps out-of-range input")
	check(BattleDemoBoard.push_slide_distance(0.25) >= 0.60 and BattleDemoBoard.push_slide_distance(0.25) <= 0.63, "damping travels about 61 percent at quarter time")
	check(BattleDemoBoard.push_slide_distance(0.5) >= 0.87 and BattleDemoBoard.push_slide_distance(0.5) <= 0.89, "damping travels about 88 percent at half time")
	check(BattleDemoBoard.push_slide_distance(0.9) < 1.0, "damping approaches but does not reach destination early")
	check(1.0 - BattleDemoBoard.push_slide_distance(0.99) < 0.0001, "damping covers less than 0.01 percent in final percent")

func _run_direction(direction: Vector2i, native_scene: bool, save_captures: bool) -> void:
	player.cancel()
	var case := _slide_data(direction)
	var s := case.session as BattleCoreReactionsSession
	var data: Dictionary = case.data
	var id := int(case.target_id)
	var start: Vector2i = case.start
	var destination: Vector2i = case.end
	if not native_scene: board.unit_visual_scene = null
	# Класс — отделённый вход представления; playback не получает ссылку на session.
	board._view_visual_classes.assign(s.unit_visual_classes)
	var state := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var immutable := data.duplicate(true)
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()
	check(_wait_for_slide(id), "real receipt starts grounded slide")
	if not board._slide_poses.has(id):
		s.close()
		return
	var visual := board._presentation_visual(id)
	if native_scene:
		var native_sprite := visual.class_still_sprite()
		check(native_sprite != null and native_sprite.texture != null and native_sprite.visible, "native slide uses visible authored sprite")
	if save_captures: await capture("push-slide-start")
	var distances: Array[float] = []
	var lean_amounts: Array[float] = []
	for sample: float in [0.25, 0.5, 0.9]:
		var pose: Dictionary = board._slide_poses[id]
		var remaining := (sample - float(pose.progress)) * BattleDemoBoard.FORCED_MOVE_SEGMENT_SECONDS
		if remaining > 0.0: advance(remaining)
		_check_slide_pose(id, start, destination, direction, "slide %.2f" % sample)
		var travelled := (visual.position + visual.get_visual_offset() - IsoGridUtils.grid_to_screen(start, board.grid_config, 0)).length()
		var segment_length := (IsoGridUtils.grid_to_screen(destination, board.grid_config, 0) - IsoGridUtils.grid_to_screen(start, board.grid_config, 0)).length()
		distances.append(travelled / segment_length)
		lean_amounts.append(visual.push_lean.length())
		if save_captures and is_equal_approx(sample, 0.5): await capture("push-slide-mid")
	check(distances[0] > 0.0 and distances[1] > distances[0] and distances[2] > distances[1], "slide never moves backward")
	check(distances[0] >= 0.60 and distances[0] <= 0.63 and distances[1] >= 0.87 and distances[1] <= 0.89, "real receipt follows damped quarter and half distances")
	check(distances[0] / 0.25 > (distances[1] - distances[0]) / 0.25 and (distances[1] - distances[0]) / 0.25 > (distances[2] - distances[1]) / 0.4, "slide speed decreases toward destination")
	check(lean_amounts[1] < lean_amounts[0] and lean_amounts[2] < lean_amounts[0], "real receipt lean fades after its early peak")
	board.size += Vector2(12, 10)
	board.zoom_camera(0.8, board.size * 0.5)
	if board._slide_poses.has(id): _check_slide_pose(id, start, destination, direction, "resized slide")
	finish()
	visual = board._presentation_visual(id)
	check(board._slide_poses.is_empty() and visual.push_lean == Vector2.ZERO, "completed slide clears registry and lean")
	check(board._view_unit_cell(id) == destination, "completed slide publishes destination")
	var factor := board.grid_config.tile_size.x / 128.0 * visual.get_unit_art_scale()
	var neutral := Transform2D(0.0, Vector2.ONE * factor, 0.0, visual.get_visual_offset() + visual.action_offset)
	check(is_zero_approx(visual.push_lean.length()) and neutral.origin == visual.get_visual_offset() + visual.action_offset, "neutral pose restores body foot transform")
	var art := visual.get_node_or_null("ArtRoot") as Node2D
	if art != null:
		check(art.transform.is_equal_approx(neutral), "neutral ArtRoot transform restores unit scale")
	if save_captures: await capture("push-slide-after")
	check(snapshot(s) == state and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and data == immutable, "presentation leaves battle state RNG counters and receipt unchanged")
	s.close()
	board.size = viewport.size
	board.zoom_camera(1.0, board.size * 0.5)
	await process_frame

func _interruptions() -> void:
	var case := _slide_data(Vector2i.RIGHT)
	var s := case.session as BattleCoreReactionsSession
	var data: Dictionary = case.data
	var id := int(case.target_id)
	var state := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var immutable := data.duplicate(true)
	for mode: String in ["finish", "skip", "cancel", "replay", "speed3"]:
		player.cancel()
		player.set_speed(1.0)
		player.play(board, data.before, data.frames, data.after)
		if player.active: player._tween.pause()
		check(_wait_for_slide(id), mode + " reaches actual slide")
		advance(0.04)
		if mode == "speed3": player.set_speed(3.0)
		match mode:
			"finish": finish()
			"skip": player.skip()
			"cancel": player.cancel()
			"replay":
				player.play(board, data.before, data.frames, data.after)
				if player.active: player._tween.pause()
				finish()
			"speed3": finish()
		check(not player.active and board._slide_poses.is_empty() and board._presentation_visual(id).push_lean == Vector2.ZERO, mode + " clears slide registry and lean")
		check(not (board._presentation_visual(id) as BattleManagedUnitVisual).ambient_animation_paused, mode + " resumes idle")
		check(snapshot(s) == state and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and data == immutable, mode + " interruption preserves state RNG counters and receipt")
	player.cancel()
	s.close()

func run() -> void:
	_check_damping_curve()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	board.camera_controls_enabled = true
	board.unit_visual_scene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	root.add_child(player)
	await process_frame
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		await _run_direction(direction, true, direction == Vector2i.RIGHT)
	await _run_direction(Vector2i.RIGHT, false, false)
	board.unit_visual_scene = preload("res://scenes/demo/visuals/placeholder_unit.tscn")
	await _interruptions()
	player.cancel()
	player.queue_free()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION PUSH SLIDE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
