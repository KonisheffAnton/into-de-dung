extends SceneTree

## Запись настоящего death receipt: тот же рендер поля, тени и останков, что в бою.
const BOARD: PackedScene = preload("res://scenes/demo/battle/battle_board.tscn")
const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const ENVIRONMENT: PackedScene = preload("res://scenes/demo/visuals/dungeon_room_environment.tscn")
const STEP: float = 0.08

var output: String = ""
var viewport: SubViewport
var board: BattleDemoBoard
var target: UnitState
var rows: Array[Dictionary] = []
var failed: int = 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			output = argument.trim_prefix("--captures=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if not value:
		failed += 1
		printerr("FAIL C2 CAPTURE: " + label)


func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision()}


func capture(stage: String, duration_ms: int = 80) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var name := "frame-%03d.png" % rows.size()
	check(viewport.get_texture().get_image().save_png(output.path_join(name)) == OK, "save " + name)
	var visual := board._presentation_visual(target.id) as BattleCharacterSkinVisual
	var shadow_visible: bool = visual != null and visual._ground_shadow.is_visible_in_tree()
	var shadow: Vector2 = visual._ground_shadow.global_position if visual != null else Vector2.ZERO
	var pose: Dictionary = board._field_presentation.poses.get(target.id, {})
	var source_frame: int = -1
	if visual != null and pose.get("kind") == &"death":
		for index: int in visual.skin_definition.animations.get_frame_count(&"death"):
			if visual.class_still_sprite().texture == visual.skin_definition.animations.get_frame_texture(&"death", index):
				source_frame = index
	rows.append({"file": name, "stage": stage, "duration_ms": duration_ms,
		"source_frame": source_frame,
		"death_progress": float(pose.get("progress", -1.0)),
		"shadow_visible": shadow_visible, "shadow_center": [shadow.x, shadow.y],
		"corpse_count": board._view_corpses.size(),
		"figure_visible": visual != null and visual.class_still_sprite().is_visible_in_tree()})


func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a GPU renderer and -- --captures=<absolute output directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var profile := HeroHubState.create(73191, 4)
	check(profile.start_battle(), "start isolated test battle")
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty():
		printerr("Battle factory returned no session")
		quit(1)
		return
	var session: BattleCoreReactionsSession = bundle.session
	for unit: UnitState in session.units:
		if TroglodyteKit.owns(unit): target = unit
	if target == null:
		printerr("Opening test battle has no troglodyte")
		session.close()
		quit(1)
		return
	var before := ActionPresentationState.capture(session.state)
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(DeathCommand.new(target.id, DamageSource.new(&"test", 0, target.cell)), session.context)
	session._queue.capture_presentation = false
	var after := ActionPresentationState.capture(session.state)
	var committed := snapshot(session)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and not target.is_alive(), "real command commits death")
	check(not frames.is_empty() and after.get("corpses", []).size() == 1, "receipt creates one fresh corpse")
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BOARD.instantiate() as BattleDemoBoard
	board.size = Vector2(viewport.size)
	board.session = session
	board.camera_controls_enabled = true
	board.unit_visual_scene = UNIT
	board.tile_visual_scene = TILE
	board.environment_visual_scene = ENVIRONMENT
	viewport.add_child(board)
	board.refresh()
	board.show_presentation_state(before)
	board.get_node("CameraControls").hide()
	board.zoom_camera(2.0, board.size * 0.5)
	board.pan_camera(Vector2(540, 350) - board.cell_center(target.cell))
	# Камера приближена внутри игры; сохранённые кадры не растягиваются и не сглаживаются.
	await process_frame
	var visual := board._presentation_visual(target.id) as BattleCharacterSkinVisual
	check(visual != null and is_equal_approx(visual.death_duration(), 2.64), "selected C2 lasts 2.64 seconds")
	await capture("before", 720)
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	player.play(board, before, frames, after)
	if player.active: player._tween.pause()
	# Небольшой первый шаг выбирает кадр 0, затем сохраняются середины всех 33 кадров.
	var step: float = STEP * 0.5
	var guard: int = 0
	while player.active and guard < 80:
		player._tween.custom_step(step)
		if player.active: player._tween.pause()
		await capture("death" if board._field_presentation.poses.get(target.id, {}).get("kind") == &"death" else "transition")
		step = STEP
		guard += 1
	check(not player.active, "receipt playback completes")
	await capture("after", 2000)
	check(board._view_corpses.size() == 1, "fresh corpse is published on field")
	check(not bool(rows[-1].shadow_visible) and not bool(rows[-1].figure_visible), "dead figure and ground shadow are hidden after publication")
	check(snapshot(session) == committed, "presentation leaves state, RNG, counters and revision unchanged")
	var shadow_reference: Array = rows[0].shadow_center
	var death_frames: int = 0
	for row: Dictionary in rows:
		if row.stage == "death":
			check(int(row.source_frame) == death_frames, "source frame order matches C2")
			death_frames += 1
			check(row.shadow_visible and row.shadow_center == shadow_reference, "shadow stays at support during fall")
	check(death_frames == 33, "all 33 source frames are captured once")
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": "production DeathCommand and BattlePresentationPlayer",
		"animation": "C2 / death-2", "viewport": [960, 640], "camera_zoom": 2.0,
		"target_id": target.id, "target_cell": [target.cell.x, target.cell.y],
		"failed_checks": failed, "death_frames": death_frames, "frames": rows}, "\t"))
	file.close()
	player.queue_free()
	viewport.queue_free()
	session.close()
	await process_frame
	print("C2 CAPTURE: %d frames, %d death frames, %d failed checks" % [rows.size(), death_frames, failed])
	quit(1 if failed > 0 else 0)
