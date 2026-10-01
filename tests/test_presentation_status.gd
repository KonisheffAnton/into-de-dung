extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION STATUS: " + label)

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}

func fixture() -> Dictionary:
	var heights := PackedInt32Array()
	var terrain := PackedByteArray()
	heights.resize(64)
	terrain.resize(64)
	terrain.fill(TerrainType.Type.FLOOR)
	var units: Dictionary = {}
	for index: int in 4:
		units[index + 1] = {"id": index + 1, "name": ["Астра", "Бор", "Рей", "Страж"][index], "faction": Faction.Type.PLAYER,
			"cell": Vector2i(2 + index % 2, 3 + index / 2), "alive": true, "hp": 20.0, "hp_max": 32.0,
			"balance": 4.0, "balance_max": 12.0, "armor": {"current": 8.0, "maximum": 16.0, "extra": 0.0},
			"elemental": {}, "bleeding": {}, "control": {}, "main": 1, "bonus": 0, "move": 3.0, "reaction": 1}
	units[1].elemental = {"frozen_turns": 2}
	units[1].control = {"stunned_turns": 1, "entangled_turns": 1}
	units[1].bleeding = {"stacks": 2, "ticks_left": 3}
	units[2].elemental = {"burning_stacks": 3, "burning_ticks": 2}
	units[3].elemental = {"wet_turns": 2}
	units[3].bleeding = {"stacks": 123, "ticks_left": 3}
	return {"width": 8, "height": 8, "heights": heights, "terrain": terrain, "units": units, "fires": [], "corpses": [], "collapse": {}}

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	board.camera_controls_enabled = true
	viewport.add_child(board)
	await process_frame
	var value := fixture()
	board.show_presentation_state(value)
	var visual := board._presentation_visual(1)
	check(visual.frozen and visual.stunned and visual.entangled, "three embodied states coexist")
	check(visual.visible_status_entries().size() == 1 and visual.visible_status_entries()[0].id == "bleeding", "embodied states are not repeated below figure")
	check(visual.get_node("ArtRoot/EffectRoot/IceSprite").visible and visual.get_node("ArtRoot/EffectRoot/StunSprite").visible and visual.get_node("ArtRoot/EffectRoot/EntangleSprite").visible, "separate control overlays visible")
	check(visual._status_hud.z_index > visual.z_index and visual.status_hud_shift != 0.0, "dense group keeps status HUD above tiles and shifts it away from foreground body")
	var hud_box := visual.status_hud_bounds()
	hud_box.position += visual.position + visual.get_visual_offset() + Vector2(visual.status_hud_shift, 0)
	var front := board._presentation_visual(4)
	var body_box := front.body_pick_rect
	body_box.position += front.position + front.get_visual_offset()
	check(not hud_box.intersects(body_box), "dense group icon row does not cover front figure")
	var details := board.displayed_unit_details(1)
	check(details.contains("стаки: 2") and details.contains("3 тиков") and details.contains("2 концов хода") and details.contains("до конца ближайшего хода"), "inspection distinguishes stacks ticks elemental expiry and control expiry")
	check(details.contains("равновесие 4.0/12.0") and details.contains("реакция 1"), "inspection carries balance and action resources")
	value.units[1].bleeding.stacks = 999
	check(board.displayed_unit_details(1) == details, "projection does not alias incoming dictionaries")
	await capture("dense-states-100")
	var hud_id := visual._status_hud.get_instance_id()
	board.zoom_camera(0.75, board.size * 0.5)
	board.pan_camera(Vector2(20, 12))
	check(visual._status_hud.get_instance_id() == hud_id and board.displayed_unit_details(1) == details, "zoom and pan transform published HUD without rebuilding or reading mutated input")
	await capture("dense-states-75")
	board.zoom_camera(1.0, board.size * 0.5)
	var art := visual.get_node("ArtRoot") as Node2D
	var stun := visual.get_node("ArtRoot/EffectRoot/StunSprite") as Node2D
	var local_stun := stun.position
	board._presentation_motion(0.5, 1, Vector2i(2, 3), Vector2i(3, 3))
	visual.action_offset = Vector2(7, -2)
	check(art.position.is_equal_approx(visual.get_visual_offset() + visual.action_offset) and stun.position == local_stun, "control effects follow motion height and action pose without moving sort root")
	await capture("controlled-motion-midpoint")
	board.show_presentation_state(value)
	visual = board._presentation_visual(1)
	visual.status_entries = []
	for index: int in 8:
		visual.status_entries.append({"id": "test-%d" % index, "stacks": 0, "embodied": false})
	visual.status_entries.append(visual.status_entries[0].duplicate(true))
	check(visual.visible_status_entries().size() == 5 and visual.status_overflow_count() == 3, "five icons plus distinct overflow ignores duplicate kinds")
	visual.queue_redraw()
	visual.sync_scene_art()
	await capture("synthetic-overflow")
	var dead := fixture()
	dead.units[1].alive = false
	board.show_presentation_state(dead)
	visual = board._presentation_visual(1)
	check(not visual.get_node("ArtRoot/EffectRoot/StunSprite").visible and not visual.get_node("ArtRoot/EffectRoot/EntangleSprite").visible and not visual.get_node("ArtRoot/EffectRoot/IceSprite").visible, "death hides every control overlay")
	check(not board.displayed_unit_details(1).contains("стаки"), "dead inspection does not advertise active statuses")
	board.unit_visual_scene = null
	board.show_presentation_state(fixture())
	check(board._presentation_visual(1).stunned and board._presentation_visual(1).entangled, "procedural fallback accepts the same values")
	await capture("procedural-controls")
	board.queue_free()
	await process_frame
	await actual_frames()
	await ui_case(false)
	await ui_case(true)
	viewport.queue_free()
	await process_frame
	print("PRESENTATION STATUS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func actual_frames() -> void:
	var s := PlayerTurnFixture.create()
	var target := s.units[1]
	target.elemental.wet_turns = 2
	for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	var before := ActionPresentationState.capture(s.state)
	var command := ControlTurnEndCommand.new(target.faction, s.context.get_revision())
	s._queue.capture_presentation = true
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == ActionReceipt.APPLIED, "real expiry command accepted: " + String(receipt.reason))
	var committed := snapshot(s)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	var player := BattlePresentationPlayer.new()
	viewport.add_child(player)
	player.set_speed(3.0)
	player.play(board, before, receipt.get_presentation_frames(), ActionPresentationState.capture(s.state))
	check(player.active, "expiry has visible presentation")
	player._tween.pause()
	check(board.displayed_unit_details(target.id).contains("2 концов"), "before state remains visible until publication")
	await capture("expiry-before-x3")
	var remaining_frames := 100
	while player.active and remaining_frames > 0:
		player._tween.pause()
		player._tween.custom_step(1.0)
		remaining_frames -= 1
	check(not player.active and board.displayed_unit_details(target.id).contains("1 концов"), "expiry atomically publishes remaining duration")
	check(board._numbers.get_child_count() > 0, "status change retains short feedback after packet")
	await capture("expiry-after-x3")
	player.play(board, before, receipt.get_presentation_frames(), ActionPresentationState.capture(s.state))
	player.skip()
	check(not player.active and board._numbers.get_child_count() == 0 and board.displayed_unit_details(target.id).contains("1 концов"), "skip clears feedback and publishes final state")
	player.cancel()
	check(board._numbers.get_child_count() == 0, "cancel clears residual feedback")
	var removal := {"kind": &"control_changed", "before": {"entangled_turns": 1}, "after": {"entangled_turns": 0}, "reason": &"push"}
	check(BattleStatusPresentation.event_feedback(removal) == "− Путы", "forced displacement says removal rather than application")
	var replacement := {"kind": &"elemental_changed", "before": {"wet_turns": 2}, "after": {"frozen_turns": 2}, "reason": &"freeze"}
	check(BattleStatusPresentation.event_feedback(replacement).contains("− Мокрый") and BattleStatusPresentation.event_feedback(replacement).contains("+ Заморожен"), "replacement retains both sides of transition")
	check(BattleStatusPresentation.event_feedback({"kind": &"elemental_cast", "effect": &"freeze"}).is_empty(), "attempt does not falsely announce applied status")
	check(BattleStatusPresentation.event_feedback({"kind": &"bleeding_changed", "before": {"ticks_left": 1, "stacks": 2}, "after": {}, "reason": &"tick"}).contains("Тик: Кровотечение · снято"), "last tick is distinguished from new application")
	check(BattleStatusPresentation.entries({"bleeding": {"ticks_left": 2}}).size() == 1, "legacy bleeding is shown without inventing stack count")
	check(snapshot(s) == committed, "expiry playback and skip preserve state RNG counters")
	# Конец хода имеет отдельный прогноз сессии; общий ForecastSimulation принимает cast.
	var actor := s.units[0]
	var cast := ElementalCastCommand.new(actor.id, actor.id, &"wet", s.context.get_revision())
	var preview := ForecastSimulation.run(s.context, s._queue, cast)
	var applied := s._queue.submit(cast, s.context)
	check(applied.status == ActionReceipt.APPLIED and applied.get_events() == preview.events and snapshot(s) == {"state": preview.snapshot_after, "rng": preview.rng_after, "counters": preview.counters_after}, "real status application keeps preview events state RNG counters parity")
	player.queue_free()
	board.queue_free()
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
	var actor := s.selected_unit()
	var target := s.units[1]
	for unit: UnitState in s.units:
		if unit.control != null:
			unit.control.stunned_turns = 0
			unit.control.entangled_turns = 0
	# Осмотр другой фигуры во время обычного движения не обращается к занятому runtime.
	target.control.entangled_turns = 1
	target.control.stunned_turns = 1
	target.elemental.frozen_turns = 2
	demo._refresh()
	await process_frame
	await process_frame
	var id := target.id
	var rect := demo.board_view.get_global_rect()
	var expected := demo.board_view.displayed_unit_details(id)
	demo._displayed_unit_hovered(id)
	check(demo._compact_inspection.tooltip_text == expected, "main/H1 inspection uses full published detail")
	demo._execute_live(&"move_to", [Vector2i(1, 2)])
	demo._displayed_unit_hovered(id)
	check(demo._compact_inspection.tooltip_text == expected, "worker inspection keeps published control durations")
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "real movement starts presentation in main/H1")
	if demo.is_presentation_pending(): demo._presentation_player._tween.pause()
	var committed := snapshot(s)
	demo._displayed_unit_hovered(id)
	demo.handle_cell(target.cell)
	check(snapshot(s) == committed and s.selected_unit() == actor, "inspection during presentation does not mutate battle or select actor")
	check(demo._compact_inspection.tooltip_text.contains("Путы") and demo.board_view.tooltip_text.contains("до конца"), "details available over figure and compact strip")
	await process_frame
	check(demo.board_view.get_global_rect() == rect and not demo._diagnostics.visible, "one-line to two-line inspection preserves exact field layout")
	await capture("hub-pending-controls" if hub else "main-pending-controls")
	demo.skip_presentation()
	check(not demo.is_execution_pending() and snapshot(s) == committed, "skip preserves committed state")
	demo.queue_free()
	await process_frame
