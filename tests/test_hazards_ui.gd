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
			check(is_equal_approx(BattleFieldPresentation.SPIKE_EXTEND_SECONDS + BattleFieldPresentation.SPIKE_HOLD_SECONDS + BattleFieldPresentation.SPIKE_RETRACT_SECONDS, 0.30),
				"impale cue remains a short deterministic sequence")
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
