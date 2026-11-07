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
	var wall_toward := Vector2(1.0, -0.75).normalized()
	check(BattleEnvironmentVisual.wall_spike_direction(Vector2i.UP).dot(wall_toward) < -0.99,
		"wall spikes extend from wall into the contact cell")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await authored_presets()
	if DisplayServer.get_name() != "headless":
		await wall_trap_occlusion()
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

func wall_trap_occlusion() -> void:
	var probe := BattleDemoBoard.new()
	probe.size = Vector2(1280, 800)
	probe.unit_visual_scene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
	probe.tile_visual_scene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")
	probe.environment_visual_scene = preload("res://scenes/demo/visuals/environment_overlay.tscn")
	viewport.add_child(probe)
	await process_frame
	var contact := Vector2i(3, 3)
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var wall_cell := contact + direction
		var heights := PackedInt32Array()
		heights.resize(64)
		var terrain := PackedByteArray()
		terrain.resize(64)
		terrain.fill(TerrainType.Type.FLOOR)
		terrain[wall_cell.y * 8 + wall_cell.x] = TerrainType.Type.WALL
		var state := {"width": 8, "height": 8, "heights": heights, "terrain": terrain,
			"units": {1: {"id": 1, "name": "Защитник", "faction": Faction.Type.ENEMY,
				"cell": contact, "alive": true, "hp": 20.0, "hp_max": 32.0,
				"balance": 0.0, "balance_max": 12.0,
				"armor": {"current": 8.0, "maximum": 16.0, "extra": 0.0},
				"elemental": {}, "bleeding": {}, "control": {}}},
			"hazards": {"traps": []}, "fires": [], "corpses": [], "collapse": {}}
		probe.show_presentation_state(state)
		var unit := probe._presentation_visual(1) as BattleDefenderIdleVisual
		unit.visual_class_id = &"warrior"
		unit.ambient_animation_paused = true
		unit.sync_scene_art()
		var without_trap := await _viewport_image()
		var art_root := unit.get_node("ArtRoot") as Node2D
		art_root.visible = false
		var without_art := await _viewport_image()
		art_root.visible = true
		var active_state: Dictionary = state.duplicate(true)
		active_state.hazards.traps = [{"cell": contact, "kind": "wall", "direction": direction, "armed_team": -1}]
		probe.show_presentation_state(active_state)
		unit = probe._presentation_visual(1) as BattleDefenderIdleVisual
		unit.visual_class_id = &"warrior"
		unit.ambient_animation_paused = true
		unit.sync_scene_art()
		var overlay := probe._environment_visuals[contact] as BattleEnvironmentVisual
		var preset_name := "WallTrapUp" if direction == Vector2i.UP else "WallTrapRight" if direction == Vector2i.RIGHT else "WallTrapDown" if direction == Vector2i.DOWN else "WallTrapLeft"
		var preset := overlay.get_node(NodePath(preset_name)) as Node2D
		var spikes := preset.get_node("Spikes") as Node2D
		spikes.visible = false
		var rendered_panel := await _viewport_image()
		if not captures.is_empty():
			check(rendered_panel.save_png(captures.path_join("static-wall-trap-panel-" + preset_name.to_snake_case() + ".png")) == OK,
				"PNG static wall trap panel " + preset_name)
		var sprite := unit.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var bounds := sprite.get_global_transform_with_canvas() * sprite.get_rect()
		var counts := _wall_trap_pixel_differences(without_trap, without_art, rendered_panel, bounds)
		print("WALL TRAP PANEL PIXELS %s sprite=%d changed=%d visible_outside=%d strongly_changed_body=%d" % [preset_name, counts.x, counts.y, counts.z, counts.w])
		check(int(counts.x) > 100, preset_name + " native sprite mask contains rendered pixels")
		# Сильное изменение вклада спрайта отличает перекрытие тела от сглаженных краёв и теней.
		check(counts.w == 0, preset_name + " flat panel does not strongly change visible hero pixels")
		check(counts.z > 50, preset_name + " flat panel still renders outside hero")
		check(preset.z_index == 0, preset_name + " follows the contact tile depth")
		spikes.visible = true
		overlay.trap_progress = 1.0
		var rendered_spikes := await _viewport_image()
		if not captures.is_empty():
			check(rendered_spikes.save_png(captures.path_join("static-wall-trap-active-" + preset_name.to_snake_case() + ".png")) == OK,
				"PNG active wall trap " + preset_name)
		var spike_counts := _wall_trap_pixel_differences(rendered_panel, without_art, rendered_spikes, bounds, without_trap)
		check(spike_counts.z > 100, preset_name + " active spikes remain visible outside hero")
	probe.queue_free()
	await process_frame

func _viewport_image() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _wall_trap_pixel_differences(base: Image, no_art: Image, trap: Image, sprite_bounds: Rect2, unit_reference: Image = null) -> Vector4i:
	var mask_image := unit_reference if unit_reference != null else base
	var start_x := maxi(0, floori(sprite_bounds.position.x))
	var start_y := maxi(0, floori(sprite_bounds.position.y))
	var end_x := mini(viewport.size.x, ceili(sprite_bounds.end.x))
	var end_y := mini(viewport.size.y, ceili(sprite_bounds.end.y))
	var sprite_pixels: int = 0
	var covered_pixels: int = 0
	var strongly_changed_body_pixels: int = 0
	for y: int in range(start_y, end_y):
		for x: int in range(start_x, end_x):
			var base_color := base.get_pixel(x, y)
			if not mask_image.get_pixel(x, y).is_equal_approx(no_art.get_pixel(x, y)):
				sprite_pixels += 1
				var trap_difference := _max_rgb_delta(base_color, trap.get_pixel(x, y))
				if not base_color.is_equal_approx(trap.get_pixel(x, y)):
					covered_pixels += 1
				var no_art_color := no_art.get_pixel(x, y)
				var unit_contribution := _max_rgb_delta(mask_image.get_pixel(x, y), no_art_color)
				if unit_contribution > 0.12 and trap_difference > 0.2:
					strongly_changed_body_pixels += 1
	var visible_trap_pixels: int = 0
	for y: int in viewport.size.y:
		for x: int in viewport.size.x:
			# Прозрачные поля PNG не являются телом: проверяем маску видимых пикселей,
			# иначе крупный авторский rect ошибочно скрывает свободные промежутки вокруг героя.
			if x >= start_x and x < end_x and y >= start_y and y < end_y \
				and not mask_image.get_pixel(x, y).is_equal_approx(no_art.get_pixel(x, y)):
				continue
			if not base.get_pixel(x, y).is_equal_approx(trap.get_pixel(x, y)):
				visible_trap_pixels += 1
	return Vector4i(sprite_pixels, covered_pixels, visible_trap_pixels, strongly_changed_body_pixels)

func _max_rgb_delta(left: Color, right: Color) -> float:
	return maxf(maxf(absf(left.r - right.r), absf(left.g - right.g)), absf(left.b - right.b))

func authored_presets() -> void:
	var scene := preload("res://scenes/demo/visuals/environment_overlay.tscn")
	var gallery := Node2D.new()
	viewport.add_child(gallery)
	var names: Array[String] = ["FloorTrap", "WallTrapUp", "WallTrapRight", "WallTrapDown", "WallTrapLeft"]
	var directions: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var positions: Array[Vector2] = [Vector2(180, 280), Vector2(460, 280), Vector2(770, 250), Vector2(470, 560), Vector2(820, 580)]
	# Контракт опоры: общая грань соседних ромбов и вертикальная высота стены 32.
	var edges: Array[Vector2] = [Vector2.ZERO, Vector2(0, -48), Vector2(64, 0), Vector2(0, 48), Vector2(-64, 0)]
	for index: int in names.size():
		var overlay := scene.instantiate() as BattleEnvironmentVisual
		gallery.add_child(overlay)
		overlay.position = positions[index]
		overlay.scale = Vector2(2.5, 2.5)
		overlay.configure(false, false, false, [], false, index == 0, directions[index], true)
		overlay.trap_progress = 1.0
		var preset := overlay.get_node(names[index]) as Node2D
		if index == 0:
			var pose := preset.get_node("Pose") as AnimatedSprite2D
			var original_transform := preset.transform
			check(preset.visible and pose != null and pose.sprite_frames != null
				and pose.sprite_frames.resource_path.ends_with("spikes_selected_v2/trap01_frames.tres")
				and pose.animation == &"poses" and pose.sprite_frames.get_frame_count(&"poses") == 3,
				"floor preset uses the selected three-pose atlas clip")
			check(not pose.is_playing(), "floor poses are selected manually and remain paused")
			var pose_transform := pose.transform
			for frame_index: int in 3:
				var atlas_cell := pose.sprite_frames.get_frame_texture(&"poses", frame_index) as AtlasTexture
				check(atlas_cell != null and atlas_cell.atlas.resource_path.ends_with("spikes_selected_v2/trap01.png")
					and atlas_cell.region == Rect2(frame_index * 256, 0, 256, 256),
					"floor pose %d maps its exact selected atlas cell" % frame_index)
			var armed_rim := preset.get_node("ArmedRim") as CanvasItem
			check(armed_rim != null and armed_rim.visible, "armed floor trap shows its rim")
			for sample: Dictionary in [{"progress": -0.1, "frame": 0}, {"progress": 0.0, "frame": 0},
				{"progress": 0.5, "frame": 1}, {"progress": 1.0, "frame": 2}, {"progress": 1.1, "frame": 2}]:
				overlay.trap_progress = float(sample.progress)
				check(pose.frame == int(sample.frame), "floor progress %s selects pose %d" % [sample.progress, sample.frame])
			check(preset.transform == original_transform and pose.transform == pose_transform,
				"floor pose selection leaves authored transforms unchanged")
		else:
			var spikes := preset.get_node("Spikes")
			check(preset.visible and spikes.get_child_count() == 16, names[index] + " shows 16 authored spikes")
			var tip := spikes.get_child(0).get_node("Tip") as Polygon2D
			var original := tip.polygon.duplicate()
			# Редакторские поправки wall-trap должны переживать выбор процедурной позы.
			var edited := original.duplicate()
			edited[0] += Vector2(0.25, 0.5)
			tip.polygon = edited
			overlay.trap_progress = 0.4
			check(tip.polygon == edited, names[index] + " playback preserves authored polygon overrides")
			tip.polygon = original
			overlay.trap_progress = 1.0
			var panel := preset.get_node("Panel") as Polygon2D
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
	var floor_pose := board._environment_visuals[cell].get_node(^"FloorTrap/Pose") as AnimatedSprite2D
	check(floor_pose != null and floor_pose.frame == 1, "floor trap selects the sharp half pose as its event starts")
	advance(player, 0.020)
	check(floor_pose.frame == 1, "floor trap remains on the half pose at 20ms")
	advance(player, 0.021)
	check(floor_pose.frame == 2, "floor trap selects the full pose after the independent 40ms extension")
	var total: float = 0.0
	for event: Dictionary in frame.events:
		if event.kind == &"damaged": total += float(event.amount)
		elif event.kind == &"armor_changed":
			for change: Dictionary in event.grants + event.items: total += maxf(0.0, float(change.before) - float(change.after))
		elif event.kind == &"shield_changed": total += float(event.absorbed)
	var damage_numbers: Array = board._numbers.get_children().filter(func(number: BattlePresentationNumber) -> bool: return number.feedback_kind == &"result")
	check(damage_numbers.size() == 1 and damage_numbers[0]._label.text == "−%.1f" % total
		and damage_numbers[0].get_meta("cell") == cell and int(damage_numbers[0].get_meta("unit_id")) == unit.id,
		"real trap shows one exact total at its recipient immediately after extension")
	check(publications.is_empty(), "lethal trap total does not wait for death or advance after publication")
	advance(player, 1.0)
	check(player.active and publications == [frame.after] and player._published.units[unit.id].hp == 0.0
		and board._numbers.get_child_count() > 0 and is_equal_approx(board._environment_visuals[cell].trap_progress, 1.0)
		and floor_pose.frame == 2,
		"damage HP and result number publish while spikes remain fully raised")
	advance(player, 0.04)
	check(player.active and board._environment_visuals[cell].trap_progress < 1.0,
		"spikes retract immediately after publication without a 700ms hold")
	board.size += Vector2(8, 6)
	board._rebuild_visuals()
	floor_pose = board._environment_visuals[cell].get_node(^"FloorTrap/Pose") as AnimatedSprite2D
	check(board._environment_visuals[cell].trap_progress < 1.0, "resize preserves the active retraction")
	await capture("damage-spikes-retract")
	advance(player, 0.061)
	check(not player.active and publications == [frame.after, frame.after] and board._field_presentation.cells.is_empty()
		and floor_pose.frame == 0, "retraction releases the queue within 100ms without duplicate publication")
	for abort: String in ["skip", "cancel", "speed"]:
		player.play(board, before, packet, frame.after)
		advance(player, 1.0)
		if abort == "skip": player.skip()
		elif abort == "cancel": player.cancel()
		else:
			player.set_speed(2.0)
			advance(player, 0.02)
			check(player.active and board._environment_visuals[cell].trap_progress < 1.0, "playback speed applies to immediate retraction")
			advance(player, 0.031)
		check(not player.active and board._field_presentation.cells.is_empty() and floor_pose.frame == 0,
			"retraction resets the floor pose on " + abort)
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
