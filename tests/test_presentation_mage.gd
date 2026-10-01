extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo
var captures: String = ""
var publications: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION MAGE: " + label)

func snapshot(s: BattleDemoSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(),
		"rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters()}

func configure(s: BattleCoreReactionsSession) -> void:
	s._enemy_index = s._enemy_ids.size()
	s.step_enemy()
	check(s.state.abilities.mage_allowed, "real team boundary opens mage")
	for unit: UnitState in s.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.vitals.set_hp(80.0)
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0

func fresh(hub: bool = false) -> void:
	if is_instance_valid(demo):
		demo.free()
	if hub:
		var view := HeroHubBattleView.new()
		view.supplied_session = BattleCoreReactionsSession.new()
		demo = view
	else:
		demo = (load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene).instantiate() as BattleDemo
		demo.deployment_enabled = false
	viewport.add_child(demo)
	demo.set_process(false)
	configure(demo.session as BattleCoreReactionsSession)
	demo._refresh()
	publications.clear()
	demo._presentation_player.frame_finished.connect(func(state: Dictionary) -> void: publications.append(state))
	await process_frame

func wait_presentation() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while demo._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_execution()
		if demo.is_presentation_pending(): break
		await process_frame
	check(demo.is_presentation_pending(), "real execution joins into presentation")
	if demo.is_presentation_pending(): demo._presentation_player._tween.pause()

func advance(seconds: float) -> void:
	var player := demo._presentation_player
	if not player.active: return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	for index: int in 30:
		if not demo.is_presentation_pending(): break
		advance(1.0)
	check(not demo.is_presentation_pending(), "finite clip completes")

func capture(label: String) -> void:
	if captures.is_empty(): return
	for impact: BattlePresentationImpact in demo.board_view._impacts.get_children(): impact._tween.pause()
	for number: BattlePresentationNumber in demo.board_view._numbers.get_children(): number._tween.pause()
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func scenario(spell: StringName, mode: String = "normal", hub: bool = false) -> void:
	await fresh(hub)
	var s := demo.session as BattleCoreReactionsSession
	var target := s.units[0] if spell == &"mage.heal" else s.units[1]
	if mode == "lethal": target.vitals.set_hp(1.0)
	if mode == "armor":
		for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	if mode == "zero":
		target.armor.natural["fire"] = 10000
		target.armor.perks.append({"id": "r07_zero", "type": "fire", "branch": "natural", "bonus": 2500})
	if mode == "capped": target.vitals.set_hp(99.0)
	if mode == "fire_heals":
		target.armor.natural["fire"] = 20000
		target.armor.perks.append({"id": "r07_heal", "type": "fire", "branch": "natural", "bonus": 15000})
	demo._refresh()
	var before := snapshot(s)
	var before_view := ActionPresentationState.capture(s.state)
	var preview := ForecastSimulation.run_prepared(s.prepare_mage_forecast(spell, target.id))
	check(snapshot(s) == before, "hover preview preserves full live snapshot RNG counters")
	demo._execute_live(&"cast_mage_spell", [spell, target.id], true)
	await wait_presentation()
	var committed := snapshot(s)
	check(s.last_receipt.status == ActionReceipt.APPLIED, "existing spell accepted")
	check(s.last_receipt.get_events() == preview.events and s.last_receipt.get_steps() == preview.steps, "worker/live events and steps match preview")
	check(committed == {"state": preview.snapshot_after, "rng": preview.rng_after, "counters": preview.counters_after}, "full worker/live snapshot resources RNG counters match preview")
	var board := demo.board_view
	var effect := board._mage_effect
	check(effect != null and not before_view.units.has(0) and board._presentation_visual(0) == null, "external mage has effect but no board figure")
	check(publications.is_empty() and board._presentation_visual(target.id).unit.hp == before_view.units[target.id].hp, "preparation holds all published values")
	check(demo._mage_label.text.contains("6"), "mana HUD holds before until result boundary")
	demo.handle_cell(target.cell)
	demo.end_turn()
	check(snapshot(s) == committed, "busy input cannot execute another command or turn")
	advance(0.06)
	check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, "preparation has no premature result")
	await capture(String(spell).replace(".", "-") + "-" + mode + "-prepare")
	advance(0.15)
	check(board._mage_effect == effect and publications.is_empty(), "delivery retains same effect and before frame")
	check(effect.phase == &"delivery" and effect.progress > 0.0 and effect.progress < 1.0, "in-flight phase is observable")
	var tween := demo._presentation_player._tween
	var old_progress := effect.progress
	var old_target_point := effect.target_point
	board.zoom_camera(0.85, board.size * 0.5)
	board.pan_camera(Vector2(10, -8))
	board.size += Vector2(12, 8)
	check(board._mage_effect == effect and demo._presentation_player._tween == tween, "camera and resize keep in-flight node and clock")
	check(effect.progress == old_progress and effect.target_point != old_target_point, "camera resamples target without restarting phase")
	check(board._presentation_visual(s.units[0].id).action_offset == Vector2.ZERO, "external cast never moves selected hero")
	await capture(String(spell).replace(".", "-") + "-" + mode + "-flight")
	advance(0.14)
	check(publications.is_empty() and board._numbers.get_child_count() == 0, "contact still precedes atomic after and numbers")
	check(effect.phase == &"contact", "confirmed result reaches contact exactly once")
	if spell == &"mage.heal": check(board._presentation_visual(target.id).action_offset == Vector2.ZERO, "healing has no hit recoil")
	await capture(String(spell).replace(".", "-") + "-" + mode + "-contact")
	finish()
	check(board._mage_effect == null and not publications.is_empty(), "completion removes delivery and publishes after")
	check(publications.back() == ActionPresentationState.capture(s.state), "last publication matches entire committed projection")
	check(board._presentation_visual(target.id) == null or board._presentation_visual(target.id).action_offset == Vector2.ZERO, "completion clears body pose")
	var numbers: Array[String] = []
	for number: BattlePresentationNumber in board._numbers.get_children(): numbers.append(number._label.text)
	check(numbers.size() > 0, "actual result has readable number")
	if mode == "capped": check(numbers.has("+1.0 HP"), "heal number uses actual capped delta")
	if mode == "fire_heals": check(numbers.has("+4.0 HP"), "fire transformed by resistance shows actual healing")
	if mode == "zero": check(numbers.has("0 · без урона"), "absorbed fire has zero result")
	check(snapshot(s) == committed, "playback leaves snapshot RNG resources counters intact")
	var rejected := s.cast_mage_spell(spell, target.id)
	check(rejected.status == ActionReceipt.REJECTED and rejected.get_presentation_frames().is_empty() and snapshot(s) == committed, "cooldown rejects without delivery or mutation")
	await capture(String(spell).replace(".", "-") + "-" + mode + ("-hub" if hub else "") + "-after")

func controls() -> void:
	for spell: StringName in [&"mage.fire", &"mage.heal"]:
		for mode: String in ["speed", "skip", "reset", "exit"]:
			await fresh()
			var s := demo.session as BattleCoreReactionsSession
			var target := s.units[0] if spell == &"mage.heal" else s.units[1]
			demo._execute_live(&"cast_mage_spell", [spell, target.id], true)
			await wait_presentation()
			var committed := snapshot(s)
			advance(0.20)
			var old_effect := demo.board_view._mage_effect
			if mode == "speed":
				demo._presentation_player.set_speed(3.0)
				advance(0.20)
				check(demo.board_view._mage_effect == null, "x3 completes mage delivery and contact within accelerated time: " + String(spell))
				finish()
				check(snapshot(s) == committed, "x3 preserves live result")
			elif mode == "skip":
				demo.skip_presentation()
				check(snapshot(s) == committed and demo.board_view._mage_effect == null and demo.board_view._numbers.get_child_count() == 0 and demo.board_view._impacts.get_child_count() == 0, "skip clears effects and keeps exact committed result")
			elif mode == "reset":
				demo.reset_demo()
				check(not demo.is_execution_pending() and demo.board_view._mage_effect == null, "reset clears delivery and unlocks new battle")
			else:
				demo.free()
				demo = null
			await process_frame
			check(not is_instance_valid(old_effect), "old delivery freed on completion or interruption")

func refusals_and_fault() -> void:
	await fresh()
	var s := demo.session as BattleCoreReactionsSession
	var target := s.units[1]
	var before := snapshot(s)
	var rejected := s.cast_mage_spell(&"mage.heal", target.id)
	check(rejected.status == ActionReceipt.REJECTED and rejected.get_presentation_frames().is_empty() and snapshot(s) == before, "invalid target rejects without frames or mutation")
	s.units[0].vitals.set_hp(100.0)
	rejected = s.cast_mage_spell(&"mage.heal", s.units[0].id)
	check(rejected.status == ActionReceipt.REJECTED and demo.board_view._mage_effect == null, "full HP rejects without delivery")
	var mutation := func(_old: float, _new: float) -> void: s.state.abilities.mana -= 1
	target.vitals.hp_changed.connect(mutation)
	# Неизвестный callback закрывает worker/capture UI. Проверяем реальный prefix
	# через синхронную очередь и отдельно воспроизводим только её отделённые кадры.
	var fault_before := ActionPresentationState.capture(s.state)
	s.begin_presentation_capture()
	s.cast_mage_spell(&"mage.fire", target.id)
	s.take_presentation_capture()
	target.vitals.hp_changed.disconnect(mutation)
	check(s.last_receipt.status == ActionReceipt.FAULTED, "real HP callback retains faulted prefix")
	var committed := snapshot(s)
	demo._presentation_player.play(demo.board_view, fault_before, s.last_receipt.get_presentation_frames(), ActionPresentationState.capture(s.state))
	demo._presentation_player._tween.pause()
	finish()
	check(snapshot(s) == committed and demo.board_view._mage_effect == null, "faulted playback preserves real partial result")
	# Cast-only prefix is a detached fixture: no event may invent a hit from spell name.
	var frames := s.last_receipt.get_presentation_frames()
	var cast_only: Dictionary = frames[0].duplicate(true)
	cast_only.events = cast_only.events.filter(func(e: Dictionary) -> bool: return e.kind == &"mage_cast")
	var cast: Dictionary = cast_only.events[0]
	for key: String in ["root_id", "command_seq", "target_unit_id"]:
		var unrelated: Dictionary = cast.duplicate(true)
		unrelated[key] = int(unrelated[key]) + 1
		check(not demo.board_view._mage_result_matches(unrelated, cast), "unrelated result cannot confirm contact: " + key)
	var unrelated_source: Dictionary = cast.duplicate(true)
	unrelated_source.source.source_instance_id = 2
	check(not demo.board_view._mage_result_matches(unrelated_source, cast), "other spell source cannot confirm fire contact")
	cast_only.step.status = &"FAULTED"
	demo.board_view.clear_presentation_feedback()
	var detached := ActionPresentationState.capture(s.state)
	demo._presentation_player.play(demo.board_view, detached, [cast_only], detached)
	demo._presentation_player._tween.pause()
	advance(0.325)
	check(demo.board_view._impacts.get_child_count() == 0 and demo.board_view._numbers.get_child_count() == 0, "cast-only fault never fabricates impact or number")
	finish()
	check(snapshot(s) == committed, "detached fault fixture never mutates runtime")

func healing_fault() -> void:
	await fresh()
	var s := demo.session as BattleCoreReactionsSession
	var target := s.units[1]
	target.armor.natural["fire"] = 20000
	target.armor.perks.append({"id": "r07_heal_fault", "type": "fire", "branch": "natural", "bonus": 15000})
	var before := ActionPresentationState.capture(s.state)
	var mutation := func(_old: float, _new: float) -> void: s.state.abilities.mana -= 1
	target.vitals.hp_changed.connect(mutation)
	s.begin_presentation_capture()
	var receipt := s.cast_mage_spell(&"mage.fire", target.id)
	s.take_presentation_capture()
	target.vitals.hp_changed.disconnect(mutation)
	check(receipt.status == ActionReceipt.FAULTED and receipt.get_events().any(func(e: Dictionary) -> bool: return e.kind == &"healed") and not receipt.get_events().any(func(e: Dictionary) -> bool: return e.kind == &"hit_resolved"), "real fire-healing fault writes HP before final hit event")
	var committed := snapshot(s)
	demo._presentation_player.play(demo.board_view, before, receipt.get_presentation_frames(), ActionPresentationState.capture(s.state))
	demo._presentation_player._tween.pause()
	advance(0.35)
	check(demo.board_view._mage_effect != null and demo.board_view._mage_effect.phase == &"contact" and demo.board_view._impacts.get_child_count() == 1, "healed-only fire prefix confirms a single contact")
	check(demo.board_view._presentation_visual(target.id).unit.hp == before.units[target.id].hp and demo.board_view._numbers.get_child_count() == 0, "partial healing stays unpublished until contact completes")
	await capture("fire-healing-fault-contact")
	finish()
	check(snapshot(s) == committed and demo.board_view._presentation_visual(target.id).unit.hp == target.vitals.get_hp(), "partial-healing after preserves actual faulted result")
	check(demo.board_view._numbers.get_child_count() == 1 and (demo.board_view._numbers.get_child(0) as BattlePresentationNumber)._label.text == "+4.0 HP", "partial fire healing publishes one actual HP number")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 950)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await scenario(&"mage.fire")
	await scenario(&"mage.fire", "armor")
	await scenario(&"mage.fire", "zero")
	await scenario(&"mage.fire", "lethal")
	await scenario(&"mage.fire", "fire_heals")
	await scenario(&"mage.heal", "capped")
	await scenario(&"mage.heal", "normal", true)
	await scenario(&"mage.fire", "normal", true)
	await controls()
	await refusals_and_fault()
	await healing_fault()
	if is_instance_valid(demo): demo.free()
	viewport.free()
	print("PRESENTATION MAGE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
