extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var publications: Array[Dictionary] = []
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION SUPPORT: " + label)

func snapshot(session: BattleDemoSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	return result.snapshot.to_dict() if result.code == ItemSnapshotResult.Code.OK and result.snapshot != null else {}

func setup_board(session: BattleDemoSession) -> void:
	if is_instance_valid(viewport): viewport.free()
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.session = session
	board.size = Vector2(960, 720)
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	board.add_child(player)
	publications.clear()
	player.frame_finished.connect(func(state: Dictionary) -> void: publications.append(state))
	board.show_presentation_state(ActionPresentationState.capture(session.state))
	await process_frame

func advance(seconds: float) -> void:
	if player == null or not player.active: return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	for index: int in 20:
		if not player.active: break
		advance(1.0)
	check(not player.active, "support clip completes")

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func play_real_action(session: BattleDemoSession, receipt: ActionReceipt, before: Dictionary, label: String, expected_kind: StringName) -> void:
	var committed := snapshot(session)
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and frames.size() == 1, label + " has one real receipt frame")
	if frames.is_empty(): return
	var frame: Dictionary = frames[0]
	player.play(board, before, frames, frame.after)
	player._tween.pause()
	var effect := board._support_effect
	check(effect != null and effect.effect_kind == expected_kind, label + " creates the confirmed effect")
	check(publications.is_empty() and board._presentation_visual(int(frame.events[0].get("actor_unit_id", -1))) != null, label + " holds before projection")
	check(snapshot(session) == committed and board._numbers.get_child_count() == 0, label + " playback has no writes or duplicate HP number")
	advance(0.15)
	var saved_progress := effect.progress if is_instance_valid(effect) else -1.0
	var saved_target := effect.target_point if is_instance_valid(effect) else Vector2.ZERO
	board.zoom_camera(0.85, board.size * 0.5)
	board.pan_camera(Vector2(12.0, -9.0))
	board.size += Vector2(16.0, 10.0)
	check(is_instance_valid(effect) and effect.progress == saved_progress and effect.target_point != saved_target, label + " resamples camera without resetting animation")
	await capture(label + "-mid")
	finish()
	check(not publications.is_empty() and publications.back() == frame.after, label + " publishes complete after projection")
	check(snapshot(session) == committed and board._support_effect == null, label + " completion keeps committed game state")
	board.reset_camera()

func test_item_events() -> void:
	var healing := BattleTacticalSession.new()
	var actor := healing.selected_unit()
	actor.vitals.apply_damage(5.0)
	await setup_board(healing)
	var before := ActionPresentationState.capture(healing.state)
	healing.begin_presentation_capture()
	var heal_receipt := healing.use_healing_item()
	healing.take_presentation_capture()
	await play_real_action(healing, heal_receipt, before, "potion", &"item_potion")
	var summon := BattleTacticalSession.new()
	await setup_board(summon)
	before = ActionPresentationState.capture(summon.state)
	summon.begin_presentation_capture()
	var summon_receipt := summon.use_summoning_item(Vector2i(0, 1))
	summon.take_presentation_capture()
	await play_real_action(summon, summon_receipt, before, "seal", &"item_seal")
	var frame: Dictionary = summon_receipt.get_presentation_frames()[0]
	var step: Dictionary = frame.step
	var unrelated: Array[Dictionary] = frame.events.duplicate(true)
	unrelated.append({"kind": &"summoned", "root_id": int(step.command_seq) + 100, "command_seq": step.command_seq,
		"actor_unit_id": frame.events[0].actor_unit_id, "target_unit_id": 900, "item_instance_id": frame.events[0].item_instance_id, "cell": Vector2i(2, 2)})
	check(board._matching_support_action(unrelated, step).is_empty(), "inconsistent root events cannot confirm a seal spawn")
	var unrelated_only: Array[Dictionary] = [unrelated.back()]
	check(board._matching_support_action(unrelated_only, step).is_empty(), "unrelated root alone cannot fabricate a seal spawn")
	check(board._matching_support_action(frame.events, {"kind": step.kind, "command_seq": int(step.command_seq) + 1}).is_empty(), "unrelated command cannot create effect")
	healing.close()
	summon.close()

func test_corpse_raise() -> void:
	var session := BattleEnvironmentSession.new()
	await setup_board(session)
	var before := ActionPresentationState.capture(session.state)
	session.begin_presentation_capture()
	var receipt := session.raise_corpse(Vector2i(0, 3))
	session.take_presentation_capture()
	await play_real_action(session, receipt, before, "corpse-raise", &"character_raise")
	session.close()

func test_controls() -> void:
	var session := BattleTacticalSession.new()
	session.selected_unit().vitals.apply_damage(5.0)
	await setup_board(session)
	var before := ActionPresentationState.capture(session.state)
	session.begin_presentation_capture()
	var receipt := session.use_healing_item()
	session.take_presentation_capture()
	var frame: Dictionary = receipt.get_presentation_frames()[0]
	player.play(board, before, [frame], frame.after)
	player._tween.pause()
	var committed := snapshot(session)
	player.set_speed(3.0)
	advance(1.0)
	check(not player.active and board._support_effect == null and snapshot(session) == committed, "x3 completes without changing live state")
	before = ActionPresentationState.capture(session.state)
	session.selected_unit().try_refill_turn_resources()
	session.selected_unit().vitals.apply_damage(2.0)
	session.begin_presentation_capture()
	receipt = session.use_healing_item()
	session.take_presentation_capture()
	frame = receipt.get_presentation_frames()[0]
	player.play(board, before, [frame], frame.after)
	player._tween.pause()
	player.skip()
	check(not player.active and board._support_effect == null and board._numbers.get_child_count() == 0, "skip clears all clip visuals")
	session.close()

func run() -> void:
	await test_item_events()
	await test_corpse_raise()
	await test_controls()
	await test_supreme_mage()
	print("PRESENTATION SUPPORT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func test_supreme_mage() -> void:
	for spell: StringName in [&"mage.test_summon", &"mage.test_raise", &"mage.shield"]:
		var session := BattleCoreReactionsSession.new()
		session._enemy_index = session._enemy_ids.size(); session.step_enemy()
		var ally := session.units[0]
		session.selected_id = ally.id
		var cell := Vector2i(-1, -1)
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if UseSummoningItemCommand.valid_cell(session.board, ally.cell, ally.cell + direction) and session.state.environment.fire_at(ally.cell + direction).is_empty(): cell = ally.cell + direction; break
		if spell == &"mage.test_raise":
			var victim := session.units[1]
			session.board.move_unit(victim, cell)
			session._queue.submit(DeathCommand.new(victim.id, DamageSource.new(&"test", 0, cell)), session.context)
		await setup_board(session)
		var before := ActionPresentationState.capture(session.state)
		session.begin_presentation_capture()
		var receipt := session.cast_mage_spell(spell, ally.id) if spell == &"mage.shield" else session.cast_mage_cell(spell, cell)
		session.take_presentation_capture()
		check(receipt.status == ActionReceipt.APPLIED, "real supreme mage visual fixture: " + String(spell))
		if receipt.status != ActionReceipt.APPLIED: session.close(); continue
		var committed := snapshot(session)
		var frames := receipt.get_presentation_frames()
		var final_state := ActionPresentationState.capture(session.state)
		player.play(board, before, frames, final_state)
		advance(0.40)
		check(player.active and publications.is_empty(), "contact holds whole before: " + String(spell))
		if spell == &"mage.shield":
			check(board._presentation_visual(ally.id).shield_view.is_empty(), "shield not revealed before contact completion")
		else:
			check(board._support_effect != null and board._support_effect.visible and board._support_effect.effect_kind == (&"mage_raise" if spell == &"mage.test_raise" else &"mage_summon"), "distinct confirmed mage appearance")
			check(board._view_units.size() == before.units.size(), "new helper remains unpublished during contact")
		await capture(String(spell).replace(".", "-") + "-contact")
		finish()
		check(snapshot(session) == committed and board._support_effect == null and board._mage_effect == null, "playback changes no core values and clears effects")
		if spell == &"mage.shield": check(board._presentation_visual(ally.id).shield_view == ally.armor.shield, "final shield view equals committed shield")
		else:
			var helper_id := int(session.state.get_summons()[-1].unit_id)
			check(board._presentation_visual(helper_id).summon_pending, "new helper visibly waits for next turn")
		await capture(String(spell).replace(".", "-") + "-after")
		session.close()
