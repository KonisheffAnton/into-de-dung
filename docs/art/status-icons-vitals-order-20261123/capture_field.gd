extends SceneTree

## Проверка реального маршрута «выбрать → навести атаку → выбрать другого».
const BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
var output_dir: String = ""
var failed: Array[String] = []
var viewport: SubViewport
var demo: HeroHubBattleView
var session: BattleCoreReactionsSession

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): output_dir = arg.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failed.append(label)
		printerr("FAIL STATUS FIELD: " + label)

func snapshot() -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision()}

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.save_png(output_dir.path_join(name + ".png")) == OK, name + " PNG saved")
	var field_rect := Rect2i(demo.board_view.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	check(image.get_region(field_rect).save_png(output_dir.path_join(name + "-field.png")) == OK,
		name + " field crop saved without scaling")

func _run() -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var profile := HeroHubState.create(73191, 4)
	check(profile.start_battle(), "isolated profile starts battle")
	session = HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1100)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	demo = BATTLE.instantiate() as HeroHubBattleView
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.set_process(false)
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	var actor: UnitState
	var other: UnitState
	var target: UnitState
	for unit: UnitState in session.units:
		if not unit.is_alive(): continue
		if unit.faction == Faction.Type.PLAYER:
			if session.unit_visual_classes.get(unit.id, &"") == &"fighter": actor = unit
			else: other = unit
		elif target == null: target = unit
	check(actor != null and other != null and target != null, "actor, ally and enemy exist")
	if actor == null or other == null or target == null: quit(1); return
	demo.select_character(actor.id)
	demo._refresh()
	await process_frame
	await process_frame
	var board := demo.board_view
	board.zoom_camera(1.0, board.size * 0.5)
	var events: Array[Dictionary] = []
	for unit: UnitState in session.units: events.append({"actor_unit_id": unit.id})
	board.set_presentation_animation_events(events)
	var before := snapshot()
	var selected_visual: BattleManagedUnitVisual = board._unit_visuals[actor.id]
	check(selected_visual.selected and not selected_visual._vitals_hud.z_as_relative
		and selected_visual._vitals_hud.z_index == 501, "real selection promotes only actor HUD")
	# Записи только для показа типографики: runtime статусы не выдаются и не тикают.
	selected_visual.status_entries = [
		{"id": "bleeding", "stacks": 3, "remaining": 2},
		{"id": "burning", "stacks": 2, "remaining": 3},
		{"id": "poison", "stacks": 5, "remaining": 2}]
	board.set_hovered_unit(actor.id)
	selected_visual.queue_screen_hud_redraw()
	await capture("status-selected-100")
	var field_image := viewport.get_texture().get_image()
	for visual: BattleManagedUnitVisual in board._unit_visuals.values():
		if visual.unit == null or not visual.unit.alive: continue
		var local_anchor := visual.get_visual_offset() + visual.get_unit_bars_offset() * board.grid_config.tile_size.x / 128.0
		var screen_anchor := Vector2i((visual.get_global_transform_with_canvas() * local_anchor).round())
		var intact_frame := true
		for x: int in range(-24, 24):
			for y: int in [14, 24]:
				intact_frame = intact_frame and field_image.get_pixelv(screen_anchor + Vector2i(x, y)).is_equal_approx(Color.BLACK)
		for y: int in range(14, 25):
			for x: int in [-24, 23]:
				intact_frame = intact_frame and field_image.get_pixelv(screen_anchor + Vector2i(x, y)).is_equal_approx(Color.BLACK)
		check(intact_frame, "full HP frame survives floor tiles for unit %d" % visual.unit.id)
	demo.set_attack_mode(true)
	board.hover_cell = target.cell
	demo._hover(target.cell)
	board.set_hovered_unit(target.id)
	check(demo.attack_mode and demo._forecast_target_id == target.id and demo._attack_forecast_pending,
		"production hover route recognizes an attack target")
	check(session.selected_id == actor.id, "attack hover does not select target")
	var target_visual: BattleManagedUnitVisual = board._unit_visuals[target.id]
	check(not target_visual.selected and not target_visual._vitals_hud.z_as_relative
		and target_visual._vitals_hud.z_index == 501
		and int((target_visual._vitals_hud.material as ShaderMaterial).get_shader_parameter("blocker_count")) > 0,
		"real attack target remains above tiles with model masking")
	await capture("attack-target-100")
	demo.set_attack_mode(false)
	demo.select_character(other.id)
	selected_visual = board._unit_visuals[actor.id]
	var other_visual: BattleManagedUnitVisual = board._unit_visuals[other.id]
	check(session.selected_id == other.id and not selected_visual.selected
		and not selected_visual._vitals_hud.z_as_relative and selected_visual._vitals_hud.z_index == 501
		and int((selected_visual._vitals_hud.material as ShaderMaterial).get_shader_parameter("blocker_count")) > 0
		and other_visual.selected and not other_visual._vitals_hud.z_as_relative
		and other_visual._vitals_hud.z_index == 501
		and int((other_visual._vitals_hud.material as ShaderMaterial).get_shader_parameter("blocker_count")) == 0,
		"switching actor transfers model mask bypass only")
	await capture("selection-switched-100")
	check(before == snapshot(), "UI inspection and selection preserve combat state, RNG and counters")
	var report := {"failed_checks": failed, "snapshot_unchanged": before == snapshot(),
		"actor": actor.id, "other": other.id, "target": target.id,
		"zoom": board.camera_view.zoom, "statuses_are_presentation_only": true}
	var file := FileAccess.open(output_dir.path_join("field-check.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("STATUS FIELD RESULTS: %d failed" % failed.size())
	quit(0 if failed.is_empty() else 1)
