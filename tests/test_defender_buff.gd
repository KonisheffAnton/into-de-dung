extends SceneTree

const BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const BUFF_FRAMES: SpriteFrames = preload("res://assets/art_presets/trials/defender_buff_v1/buff_frames.tres")
const ROGUE_BUFF: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/buff_frames.tres")

var rogue: bool = false
var frames_resource: SpriteFrames = BUFF_FRAMES
var suite: String = "DEFENDER BUFF"

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
		if argument == "--rogue":
			rogue = true
			frames_resource = ROGUE_BUFF
			suite = "ROGUE BUFF"
	call_deferred("run")


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL " + suite + ": " + label)


func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return {"state": capture.snapshot.to_dict() if capture.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}


func make_battle(catalog_version: int, seed: int) -> Dictionary:
	var profile := HeroHubState.create(seed, catalog_version)
	if profile == null or not profile.start_battle(): return {}
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty(): return {}
	var session := bundle.session as BattleCoreReactionsSession
	if not session.start_battle(): session.close(); return {}
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	if not session.can_player_act(): session.close(); return {}
	var demo := BATTLE_SCENE.instantiate() as HeroHubBattleView
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_process(false)
	demo.board_view.unit_visual_scene = UNIT_SCENE
	demo.board_view.refresh()
	return {"session": session, "bundle": bundle, "demo": demo}


func close_battle(fixture: Dictionary) -> void:
	if fixture.is_empty(): return
	var demo := fixture.get("demo") as HeroHubBattleView
	var session := fixture.get("session") as BattleCoreReactionsSession
	if demo != null: demo.queue_free()
	if session != null: session.close()
	await process_frame


func find_ally_visual(board: BattleDemoBoard, unit_id: int) -> BattleDefenderIdleVisual:
	return board._presentation_visual(unit_id) as BattleDefenderIdleVisual


func capture(label: String) -> void:
	if captures.is_empty(): return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "capture " + label)


func invoke_action(session: BattleCoreReactionsSession, action: StringName, mode: int = -1, cover_id: int = 0) -> ActionReceipt:
	session.begin_presentation_capture()
	var receipt: ActionReceipt
	match action:
		&"raise_shields": receipt = session.raise_shields()
		&"guard": receipt = session.guard_selected()
		_: receipt = session.set_reaction_guard(mode, cover_id)
	session.take_presentation_capture()
	return receipt


func run_real_action(catalog_version: int, action: StringName, mode: int, label: String) -> Dictionary:
	var fixture := make_battle(catalog_version, 91000 + catalog_version * 100 + mode + (10 if action == &"raise_shields" else 0))
	check(not fixture.is_empty(), label + " creates a production HeroHub battle")
	if fixture.is_empty(): return {}
	var session := fixture.session as BattleCoreReactionsSession
	var bundle: Dictionary = fixture.bundle
	var actor_id := int(session.actor_loadouts.keys()[0])
	var expected_class: StringName = &"rogue" if rogue else (&"shieldbearer" if action == &"raise_shields" else &"warrior")
	for candidate: Variant in session.actor_loadouts:
		if session.actor_loadouts[candidate].class_id == expected_class:
			actor_id = int(candidate)
			break
	session.selected_id = actor_id
	var actor := session.board.get_unit_by_id(actor_id)
	var cover_id := 0
	if mode == CombatPerksState.Mode.COVER:
		var ally: UnitState
		for unit: UnitState in session.units:
			if unit.faction == Faction.Type.PLAYER and unit.id != actor_id: ally = unit; break
		check(ally != null, label + " has an allied cover recipient")
		if ally != null:
			var open_actor := Vector2i(2, 2)
			var open_ally := Vector2i(3, 2)
			check(session.board.move_unit(actor, open_actor) and session.board.move_unit(ally, open_ally), label + " places adjacent eligible cover pair")
			check(MeleeThreat.cover_eligible(session.context, actor, ally), label + " cover recipient passes real capability gate")
			cover_id = ally.id
	fixture.demo.board_view.refresh()
	var board := fixture.demo.board_view as BattleDemoBoard
	var visual := find_ally_visual(board, actor_id)
	check(visual != null and visual._active_buff_frames() == frames_resource and visual.visual_class_id == (&"rogue" if rogue else &"warrior"),
		label + " uses the production art scene, class and buff resource")
	if visual == null:
		await close_battle(fixture)
		return {}
	var before := ActionPresentationState.capture(session.state)
	var receipt := invoke_action(session, action, mode, cover_id)
	var committed := snapshot(session)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and frames.size() == 1, label + " is a real applied receipt with one presentation frame")
	if receipt.status != ActionReceipt.APPLIED or frames.is_empty():
		await close_battle(fixture)
		return {}
	var frame: Dictionary = frames[0]
	var expected_kind: StringName = &"raise_shields" if action == &"raise_shields" else &"guard"
	check(frame.step.get("status") == &"APPLIED" and frame.step.get("kind") == expected_kind,
		label + " frame identifies the successful command")
	check(board._matching_defender_buff(frame.events, frame.step) == visual, label + " receipt confirms the visual actor")
	var after := ActionPresentationState.capture(session.state)
	var player := BattlePresentationPlayer.new()
	fixture.demo.add_child(player)
	var publications: Array[Dictionary] = []
	player.frame_finished.connect(func(state: Dictionary) -> void: publications.append(state))
	player.play(board, before, frames, after)
	player._tween.pause()
	check(player.active and board._defender_buff_visual == visual and visual._buff_elapsed == 0.0,
		label + " begins from before projection and starts the buff clip")
	check(snapshot(session) == committed and publications.is_empty(), label + " playback does not write live state, RNG, counters, or publish early")
	var idle_sprite := visual.get_node("ArtRoot/RogueIdleSprite" if rogue else "ArtRoot/DefenderIdleSprite") as Sprite2D
	var still_sprite := visual.class_still_sprite()
	check(idle_sprite.visible and not still_sprite.visible, label + " replaces only the idle drawing")
	var ticks: float = 0.0
	for index: int in frames_resource.get_frame_count(&"buff"):
		var duration := frames_resource.get_frame_duration(&"buff", index)
		var midpoint := (ticks + duration * 0.5) / frames_resource.get_animation_speed(&"buff")
		visual.sample_buff(midpoint)
		check(idle_sprite.texture == frames_resource.get_frame_texture(&"buff", index), label + " samples authored frame %02d" % (index + 1))
		ticks += duration
	check(is_equal_approx(ticks / frames_resource.get_animation_speed(&"buff"), 1.02 if rogue else 56.75 / 30.0), label + " preserves selected clip timing")
	board._sample_defender_buff(0.8)
	var identity := visual.get_instance_id()
	var texture := idle_sprite.texture
	var phase := visual._buff_elapsed
	var idle_phase := visual.idle_clock.get_elapsed()
	var anchor := (visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform
	board.size += Vector2(23, 11)
	board._rescale_layout()
	check(visual.get_instance_id() == identity and board._defender_buff_visual == visual
		and idle_sprite.texture == texture and is_equal_approx(visual._buff_elapsed, phase)
		and visual.idle_clock.get_elapsed() == idle_phase
		and (visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform == anchor,
		label + " resize preserves visual identity, frame, clip/idle phase and anchor")
	await capture(label + "-mid")
	player.set_speed(3.0)
	player._tween.custom_step(0.9)
	check(not player.active and board._defender_buff_visual == null and visual._buff_elapsed < 0.0,
		label + " x3 completes one clip and restores idle")
	check(not publications.is_empty() and publications.back() == frame.after,
		label + " publishes committed after projection once playback completes")
	check(snapshot(session) == committed, label + " completion still leaves all live core values unchanged")
	player.play(board, before, frames, after)
	player._tween.pause()
	player.skip()
	check(not player.active and board._defender_buff_visual == null and visual._buff_elapsed < 0.0,
		label + " skip clears the buff without a stale tween")
	player.play(board, before, frames, after)
	player._tween.pause()
	player.cancel()
	check(not player.active and board._defender_buff_visual == null and visual._buff_elapsed < 0.0,
		label + " cancel clears the buff without a stale tween")
	player.queue_free()
	await close_battle(fixture)
	return {"fixture": fixture}


func test_receipt_families() -> void:
	if rogue:
		await run_real_action(1, &"guard", -1, "rogue-guard")
		return
	await run_real_action(2, &"raise_shields", -1, "raise-shields")
	await run_real_action(1, &"guard", -1, "guard-ordinary")
	await run_real_action(1, &"guard_mode", CombatPerksState.Mode.OPPORTUNIST, "guard-opportunist")
	await run_real_action(1, &"guard_mode", CombatPerksState.Mode.COVER, "guard-cover")
	await run_real_action(1, &"guard_mode", CombatPerksState.Mode.COUNTERATTACK, "guard-counterattack")


func test_matcher_gates_and_cleanup() -> void:
	var fixture := make_battle(1, 91234)
	check(not fixture.is_empty(), "matcher fixture uses production session")
	if fixture.is_empty(): return
	var session := fixture.session as BattleCoreReactionsSession
	var board := fixture.demo.board_view as BattleDemoBoard
	var actor_id := int(session.actor_loadouts.keys()[0])
	for candidate: Variant in session.actor_loadouts:
		if session.actor_loadouts[candidate].class_id == (&"rogue" if rogue else &"warrior"): actor_id = int(candidate); break
	session.selected_id = actor_id
	board.refresh()
	var visual := find_ally_visual(board, actor_id)
	var enemy_id := 0
	var mage_id := 0
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.ENEMY: enemy_id = unit.id
		if session.actor_loadouts.has(unit.id) and session.actor_loadouts[unit.id].class_id == &"mage": mage_id = unit.id
	var before := ActionPresentationState.capture(session.state)
	var receipt := invoke_action(session, &"guard")
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and not frames.is_empty(), "gate probe starts from a successful Guard receipt")
	if frames.is_empty(): await close_battle(fixture); return
	var frame: Dictionary = frames[0]
	var events: Array = frame.events
	var step: Dictionary = frame.step
	check(board._matching_defender_buff(events, step) == visual, "matching successful Guard is accepted")
	if rogue:
		check(board._matching_defender_buff([{ "kind": &"raised_shields", "command_seq": step.command_seq,
			"actor_unit_id": actor_id, "target_unit_id": actor_id }],
			{"kind": &"raise_shields", "status": &"APPLIED", "command_seq": step.command_seq}) == null,
			"Rogue cannot borrow the Shieldbearer buff route")
	var rejected_step := step.duplicate(true)
	rejected_step["status"] = &"SKIPPED"
	check(board._matching_defender_buff(events, rejected_step) == null, "skipped step is refused")
	rejected_step = step.duplicate(true)
	rejected_step["command_seq"] = int(step.command_seq) + 1
	check(board._matching_defender_buff(events, rejected_step) == null, "unrelated command sequence is refused")
	rejected_step = step.duplicate(true)
	rejected_step["kind"] = &"move"
	check(board._matching_defender_buff(events, rejected_step) == null, "unrelated command kind is refused")
	check(board._matching_defender_buff([{ "kind": &"reaction_used", "command_seq": step.command_seq,
		"actor_unit_id": actor_id, "target_unit_id": actor_id }], step) == null,
		"passive reaction_used cannot trigger the active buff")
	check(board._matching_defender_buff([{ "kind": &"raised_shield_used", "command_seq": step.command_seq,
		"actor_unit_id": actor_id, "target_unit_id": actor_id }], step) == null,
		"passive raised-shield use cannot trigger the active buff")
	check(board._matching_defender_buff([{ "kind": &"guarded", "command_seq": step.command_seq,
		"actor_unit_id": actor_id, "target_unit_id": actor_id }], {"status": &"APPLIED", "kind": &"guard"}) == null,
		"event without matching command sequence is refused")
	check(board._matching_defender_buff([{ "kind": &"guarded", "command_seq": step.command_seq,
		"actor_unit_id": enemy_id, "target_unit_id": enemy_id }], step) == null,
		"enemy without matching Defender class cannot receive its buff")
	check(board._matching_defender_buff([{ "kind": &"guarded", "command_seq": step.command_seq,
		"actor_unit_id": mage_id, "target_unit_id": mage_id }], step) == null,
		"Mage cannot receive the Defender buff")
	check(board._matching_defender_buff([{ "kind": &"guarded", "command_seq": step.command_seq,
		"actor_unit_id": actor_id, "target_unit_id": mage_id }], step) == null,
		"Guard event aimed at Mage is refused")
	var committed := snapshot(session)
	var player := BattlePresentationPlayer.new()
	fixture.demo.add_child(player)
	player.play(board, before, frames, ActionPresentationState.capture(session.state))
	player._tween.pause()
	board.clear_presentation_effects()
	player.cancel(false)
	check(board._defender_buff_visual == null and visual._buff_elapsed < 0.0,
		"cancel and explicit cleanup clear clip state")
	player.queue_free()
	# Старый callback после retire не должен оживить визуал с тем же ID.
	player = BattlePresentationPlayer.new()
	fixture.demo.add_child(player)
	player.play(board, before, frames, ActionPresentationState.capture(session.state))
	player._tween.pause()
	visual.retire_view()
	board._sample_defender_buff(1.0)
	check(board._presentation_visual(actor_id) == null and visual._buff_elapsed < 0.0,
		"retired scene rejects later sample and stale callback cannot target it")
	player.cancel()
	player.queue_free()
	check(snapshot(session) == committed, "gate and cleanup probes do not mutate the battle")
	await close_battle(fixture)


func test_exact_resource_timing() -> void:
	check(BUFF_FRAMES.has_animation(&"buff") and not BUFF_FRAMES.get_animation_loop(&"buff"), "resource declares a non-looping buff animation")
	check(BUFF_FRAMES.get_animation_speed(&"buff") == 30.0 and BUFF_FRAMES.get_frame_count(&"buff") == 33,
		"resource has 33 frames at 30 fps")
	for index: int in BUFF_FRAMES.get_frame_count(&"buff"):
		var expected := 2.0 if index >= 8 and index <= 23 else (8.75 if index == 32 else 1.0)
		check(BUFF_FRAMES.get_frame_duration(&"buff", index) == expected, "resource frame %02d has exact duration" % (index + 1))


func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if not rogue: test_exact_resource_timing()
	await test_receipt_families()
	await test_matcher_gates_and_cleanup()
	viewport.queue_free()
	await process_frame
	print("%s RESULTS: %d passed, %d failed" % [suite, passed, failed])
	quit(1 if failed > 0 else 0)
