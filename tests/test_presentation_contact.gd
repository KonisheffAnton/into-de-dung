extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PRESENTATION CONTACT: " + label)

func capture(label: String) -> void:
	if captures.is_empty(): return
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	for impact: BattlePresentationImpact in board._impacts.get_children(): impact._tween.pause()
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func fixture(mode: String) -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for i: int in 6:
		var unit := s.units[i]
		s.board.move_unit(unit, Vector2i(i, 0))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 10.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 8.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	s.board.move_unit(s.units[0], Vector2i(3, 3))
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	if mode in ["mixed", "armor"]:
		for item: ItemInstance in s.state.get_owner(s.units[1].id)._items.values():
			item.armor_remaining = mini(1, item.get_definition().armor_max) if mode == "mixed" else item.get_definition().armor_max
	if mode == "zero":
		s.units[0].stats.set_base_value(StatTypes.StatType.STRENGTH, 0.0)
		s.units[0].stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		for definition: AttackDefinition in s.context._attack_rules._definitions: definition.damage_components.clear()
	if mode == "lethal": s.units[1].vitals.set_hp(1.0)
	if mode == "critical": s.units[1].elemental.frozen_turns = 2
	if mode == "counter":
		check(s._queue.submit(GuardCommand.new(s.units[1].id, s.context.get_revision(), CombatPerksState.Mode.COUNTERATTACK), s.context).status == ActionReceipt.APPLIED, "counter fixture")
	return s

func packet(s: BattleCoreReactionsSession) -> Dictionary:
	var before := ActionPresentationState.capture(s.state)
	s._queue.capture_presentation = true
	var a := s.units[0]
	var b := s.units[1]
	var command := AttackCommand.new(a.id, b.id, a.cell, b.cell, &"demo_strike", s.context.get_revision())
	var preview := ForecastSimulation.run(s.context, s._queue, command)
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events, "real receipt equals isolated preview")
	return {"before": before, "frames": receipt.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}

func advance(seconds: float) -> void:
	if not player.active: return
	var tween := player._tween
	tween.pause()
	tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	var guard := 0
	while player.active and guard < 100:
		advance(1.0)
		guard += 1
	check(not player.active, "clip reaches command boundary")

func number_texts() -> Array[String]:
	var values: Array[String] = []
	for number: BattlePresentationNumber in board._numbers.get_children(): values.append(number._label.text)
	return values

func scenario(mode: String) -> void:
	player.cancel()
	var s := fixture(mode)
	var data := packet(s)
	var a := s.units[0].id
	var b := s.units[1].id
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	player._tween.pause()
	var origin := board._presentation_visual(a).position
	advance(0.12)
	check(board._presentation_visual(a).action_offset.length() > 1.0 and board._presentation_visual(a).position == origin, mode + " windup only moves artwork")
	check(board._numbers.get_child_count() == 0 and board._presentation_visual(b).unit.hp == data.before.units[b].hp, mode + " no premature result")
	if mode == "mixed": await capture("windup")
	advance(0.03)
	var lunge_end_distance := 24.0 * board.grid_config.tile_size.x / 128.0
	check(is_equal_approx(board._presentation_visual(a).action_offset.length(), lunge_end_distance), mode + " real Tween reaches lunge endpoint after 0.03s")
	advance(0.10)
	check(board._presentation_visual(b).action_offset.length() > 1.0 and board._impacts.get_child_count() == 1, mode + " one contact and recoil")
	if mode == "mixed":
		await capture("contact-recoil")
		board.size += Vector2(16, 16)
		check(board._presentation_visual(b).action_offset.length() > 1.0, "resize preserves recoil")
	finish()
	check(board._presentation_visual(a).action_offset == Vector2.ZERO and board._presentation_visual(b).action_offset == Vector2.ZERO, mode + " poses restored")
	check(board._presentation_visual(b).unit.hp == data.after.units[b].hp, mode + " shown HP equals committed state")
	var texts := number_texts()
	var hp_loss := 0.0
	var expected_hp_numbers := 0
	for event: Dictionary in data.events:
		if event.kind in [&"damaged", &"healed"]: expected_hp_numbers += 1
		if event.kind == &"damaged" and event.target_unit_id == b: hp_loss = float(event.amount)
	if mode in ["mixed", "armor"]:
		check(texts.size() == expected_hp_numbers + 1 and texts[0].contains("броня"), mode + " armor number distinct, no technical duplicates")
	if mode in ["hp", "lethal", "critical"]: check(texts.size() == expected_hp_numbers, mode + " one number per HP change including item heal")
	if mode != "zero" and hp_loss > 0.0:
		check(texts.any(func(t: String) -> bool: return t.contains("%.1f HP" % hp_loss)), mode + " actual HP delta displayed")
	if mode == "zero": check(texts.size() == 1 and texts[0] == "0 · без урона", "explicit zero hit")
	if mode == "critical": check(texts[0].begins_with("КРИТ"), "critical tagged without extra damage")
	if mode == "lethal": check(not board._presentation_visual(b).unit.alive and texts[0].contains("1.0 HP"), "lethal shows actual lost HP after death")
	if mode == "counter": check(texts.size() == expected_hp_numbers and expected_hp_numbers >= 2, "counter is a separate contact/result")
	check(ActionPresentationState.capture(s.state) == data.after and rng == s.context.get_rng().to_dict() and counters == s.context.simulation_counters(), mode + " playback leaves live/RNG/counters unchanged")
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	if mode in ["mixed", "armor", "zero", "critical", "counter"]: await capture("result-" + mode)
	if mode == "mixed":
		var first := board._numbers.get_child(0) as BattlePresentationNumber
		var second := board._numbers.get_child(1) as BattlePresentationNumber
		check(absf(first.position.y - second.position.y) >= 28.0, "HP and armor occupy separate lines")
		first.sample(0.75)
		second.sample(0.0)
		check(not first._label.get_global_rect().intersects(second._label.get_global_rect()), "older rising number cannot cover fresh number")
		first.sample(0.0)
		board.show_presentation_state(data.after)
		check(board._numbers.get_child_count() == texts.size(), "next snapshot retains numbers")
		player.set_speed(3.0)
		player.play(board, data.before, data.frames, data.after)
		player._tween.pause()
		var label_y := first._label.position.y
		first._tween.custom_step(0.2)
		check(board._numbers.get_child_count() == texts.size() and is_equal_approx(label_y - first._label.position.y, first.rise / 6.0), "next command and x3 retain real-time number lifetime")
		advance(0.041)
		check(board._presentation_visual(a).action_offset.length() > 1.0, "x3 advances windup")
		player.skip()
		check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, "skip removes old and current feedback")
		check(board._presentation_visual(a).action_offset == Vector2.ZERO, "skip clears pose")
	if mode == "hp":
		var number := board._numbers.get_child(0) as BattlePresentationNumber
		number._tween.custom_step(0.85)
		check(is_equal_approx(number._label.modulate.a, 1.0), "number holds readable before fade")
		number._tween.custom_step(0.25)
		check(number._label.modulate.a < 1.0 and number._label.modulate.a > 0.0, "number fades after hold")
		number._tween.custom_step(0.2)
		await process_frame
		check(not is_instance_valid(number), "number expires independently after clip")
	player.cancel()
	check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, mode + " reset cleanup")
	s.close()
	await process_frame

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	viewport.add_child(board)
	board.execution_pending = true
	player = BattlePresentationPlayer.new()
	viewport.add_child(player)
	for mode: String in ["hp", "mixed", "armor", "zero", "lethal", "critical", "counter"]: await scenario(mode)
	await movement_timing()
	await abort_cases()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION CONTACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func movement_timing() -> void:
	var s := fixture("hp")
	var actor_id: int = s.units[0].id
	var start: Vector2i = s.units[0].cell
	var middle := Vector2i(2, 3)
	var finish_cell := Vector2i(1, 3)
	var after := ActionPresentationState.capture(s.state)
	var voluntary := {"kind": &"moved", "actor_unit_id": actor_id, "target_unit_id": actor_id,
		"from_cell": start, "to_cell": finish_cell, "movement_kind": &"voluntary",
		"transit_path": [start, middle, finish_cell]}
	board.show_presentation_state(after)
	var tween := board.animate_presentation_frame([voluntary])
	tween.pause()
	tween.custom_step(0.079)
	check(board._view_unit_cell(actor_id) == start, "voluntary segment is still in flight before 0.08s")
	tween.custom_step(0.002)
	check(board._view_unit_cell(actor_id) == middle, "voluntary transit segment completes at 0.08s per cell")
	tween.custom_step(0.078)
	check(board._view_unit_cell(actor_id) == middle, "second voluntary transit segment uses same duration")
	tween.custom_step(0.003)
	check(board._view_unit_cell(actor_id) == finish_cell, "second voluntary transit segment completes at 0.08s")
	tween.kill()
	var forced := {"kind": &"moved", "actor_unit_id": actor_id, "target_unit_id": actor_id,
		"from_cell": start, "to_cell": middle, "movement_kind": &"push",
		"transit_path": [start, middle]}
	board.show_presentation_state(after)
	tween = board.animate_presentation_frame([forced])
	tween.pause()
	tween.custom_step(0.08)
	check(board._view_unit_cell(actor_id) == start, "forced displacement retains 0.10s segment")
	tween.custom_step(0.021)
	check(board._view_unit_cell(actor_id) == middle, "forced segment completes after prior 0.10s timing")
	tween.kill()
	board.clear_strike_poses()
	s.close()
	await process_frame

func abort_cases() -> void:
	var s := fixture("hp")
	var data := packet(s)
	player.set_speed(3.0)
	player.play(board, data.before, data.frames, data.after)
	advance(0.068)
	advance(0.025)
	check(board._impacts.get_child_count() == 1, "x3 contact has independent flash")
	player.skip()
	check(board._impacts.get_child_count() == 0 and board._numbers.get_child_count() == 0 and board._action_offsets.is_empty(), "skip at contact cancels all effects")
	check(ActionPresentationState.capture(s.state) == data.after, "contact skip cannot change actual result")
	s.close()
	s = fixture("hp")
	s._queue = ActionQueue.new(1, 512)
	var before := ActionPresentationState.capture(s.state)
	s._queue.capture_presentation = true
	var a := s.units[0]
	var b := s.units[1]
	var receipt := s._queue.submit(AttackCommand.new(a.id, b.id, a.cell, b.cell, &"demo_strike", s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.FAULTED, "real fault prefix")
	player.play(board, before, receipt.get_presentation_frames(), ActionPresentationState.capture(s.state))
	finish()
	check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0 and board._action_offsets.is_empty(), "faulted windup invents no contact or numbers")
	s.close()
	await process_frame
