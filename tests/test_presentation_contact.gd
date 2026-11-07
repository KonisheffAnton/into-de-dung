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
	for number: BattlePresentationNumber in board._numbers.get_children():
		# Подпись состояния не считается ещё одним результатом HP/брони.
		if number.feedback_kind == &"result": values.append(number._label.text)
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
	advance(0.10)
	check(board._presentation_visual(a).action_offset.length() > 1.0 and board._presentation_visual(a).position == origin, mode + " windup only moves artwork")
	check(board._numbers.get_child_count() == 0 and board._presentation_visual(b).unit.hp == data.before.units[b].hp, mode + " no premature result")
	if mode == "mixed": await capture("windup")
	var strike_direction := (board._world_cell_center(data.before.units[b].cell) - board._world_cell_center(data.before.units[a].cell)).normalized()
	var lunge_start := board._presentation_visual(a).action_offset.dot(strike_direction)
	advance(0.00625)
	var lunge_quarter := board._presentation_visual(a).action_offset.dot(strike_direction)
	advance(0.0125)
	var lunge_three_quarters := board._presentation_visual(a).action_offset.dot(strike_direction)
	advance(0.00625)
	var lunge_end_distance := 32.0 * board.grid_config.tile_size.x / 128.0
	check(is_equal_approx(board._presentation_visual(a).action_offset.length(), lunge_end_distance), mode + " real Tween reaches lunge endpoint after 0.025s")
	check(lunge_end_distance - lunge_three_quarters > lunge_quarter - lunge_start, mode + " lunge accelerates into contact instead of travelling at constant speed")
	advance(0.001)
	check(board._impacts.get_child_count() == 1 and not number_texts().is_empty(), mode + " total appears at contact without delay")
	check(board._presentation_visual(b).unit.hp == data.before.units[b].hp, mode + " immediate number does not publish after early")
	advance(0.024)
	check(board._presentation_visual(a).action_offset.length() < lunge_end_distance
		and board._presentation_visual(b).action_offset.length() > 1.0, mode + " return and recoil begin without hit stop")
	if mode == "hp":
		var strike: Dictionary = board._pending_strikes.values()[0]
		var target_support := board._presentation_visual(b).position
		board._hit_recovery(0.2, strike, false)
		var peak := board._presentation_visual(b).action_offset.dot(strike_direction)
		board._hit_recovery(0.6, strike, false)
		var rebound := board._presentation_visual(b).action_offset.dot(strike_direction)
		board._hit_recovery(0.9, strike, false)
		var tail := board._presentation_visual(b).action_offset.dot(strike_direction)
		var expected_normal_peak := 18.0 * board.grid_config.tile_size.x / 128.0
		check(is_equal_approx(peak, expected_normal_peak) and rebound < 0.0 and absf(tail) < absf(rebound) and absf(rebound) < peak, "normal hit reaches 18px early peak then rebounds with diminishing amplitude")
		check(board._presentation_visual(b).position == target_support and board._view_unit_cell(b) == data.before.units[b].cell, "damped recoil leaves support and cell fixed")
		board._hit_recovery(0.5, strike, false)
	if mode == "critical":
		var critical_strike: Dictionary = board._pending_strikes.values()[0]
		var critical_cell: Vector2i = board._view_unit_cell(b)
		var target_root_position: Vector2 = board._presentation_visual(b).position
		var normal_strike := critical_strike.duplicate(true)
		normal_strike["modifiers"] = {"critical": false}
		board._hit_recovery(0.0, critical_strike, false)
		check(board._presentation_visual(b).action_offset == Vector2.ZERO, "critical recovery has exact zero start")
		board._hit_recovery(0.25, normal_strike, false)
		var normal_pose: Vector2 = board._presentation_visual(b).action_offset
		board._hit_recovery(0.25, critical_strike, false)
		var critical_pose: Vector2 = board._presentation_visual(b).action_offset
		check(bool(critical_strike.get("modifiers", {}).get("critical", false)), "real critical receipt selects critical recovery")
		check(critical_pose.length() > normal_pose.length(), "critical recoil exceeds normal recoil at same sample")
		board._hit_recovery(0.2, critical_strike, false)
		var expected_critical_peak := 24.0 * board.grid_config.tile_size.x / 128.0
		check(is_equal_approx(board._presentation_visual(b).action_offset.dot(board._strike_direction(critical_strike)), expected_critical_peak), "critical hit reaches 24px early peak")
		var direction := board._strike_direction(critical_strike)
		var perpendicular := Vector2(-direction.y, direction.x)
		board._hit_recovery(1.0 / 12.0, critical_strike, false)
		var lateral_a: float = board._presentation_visual(b).action_offset.dot(perpendicular)
		board._hit_recovery(3.0 / 12.0, critical_strike, false)
		var lateral_b: float = board._presentation_visual(b).action_offset.dot(perpendicular)
		check(lateral_a * lateral_b < 0.0, "critical lateral shake alternates direction")
		board._hit_recovery(1.0, critical_strike, false)
		check(board._presentation_visual(b).action_offset == Vector2.ZERO, "critical recovery has exact zero endpoint")
		check(board._view_unit_cell(b) == critical_cell and board._presentation_visual(b).position == target_root_position, "critical shake leaves logical cell and HUD anchor root fixed")
	if mode == "mixed":
		await capture("contact-recoil")
		board.size += Vector2(16, 16)
		check(board._presentation_visual(b).action_offset.length() > 1.0, "resize preserves recoil")
	finish()
	check(board._presentation_visual(a).action_offset == Vector2.ZERO and board._presentation_visual(b).action_offset == Vector2.ZERO, mode + " poses restored")
	check(board._presentation_visual(b).unit.hp == data.after.units[b].hp, mode + " shown HP equals committed state")
	var texts := number_texts()
	var feedback_count := board._numbers.get_child_count()
	var totals: Dictionary = {}
	var heals: int = 0
	for event: Dictionary in data.events:
		var recipient: int = int(event.get("target_unit_id", 0))
		if event.kind == &"healed":
			heals += 1
			check(texts.has("+%.1f HP" % float(event.amount)), mode + " actual item healing stays separate")
		elif event.kind == &"damaged": totals[recipient] = float(totals.get(recipient, 0.0)) + float(event.amount)
		elif event.kind == &"armor_changed":
			for change: Dictionary in event.grants + event.items:
				totals[recipient] = float(totals.get(recipient, 0.0)) + maxf(0.0, float(change.before) - float(change.after))
		elif event.kind == &"hit_resolved" and not totals.has(recipient): totals[recipient] = 0.0
	check(texts.size() == totals.size() + heals, mode + " one combined damage number per hit plus actual healing")
	for recipient: int in totals:
		var expected_text: String = "−%.1f" % float(totals[recipient]) if float(totals[recipient]) > 0.0 else "0"
		var matches: int = 0
		for number: BattlePresentationNumber in result_numbers():
			if int(number.get_meta("unit_id", 0)) == recipient and number._label.text.ends_with(expected_text):
				matches += 1
				check(number.get_meta("cell") == data.before.units[recipient].cell, mode + " total is anchored to its own recipient")
		check(matches == 1, mode + " exact HP plus armor total without separate loss labels")
	if mode == "critical": check(texts[0].begins_with("КРИТ"), "critical tags the single total")
	if mode == "lethal": check(not board._presentation_visual(b).unit.alive and texts[0] == "−1.0", "lethal retains actual capped loss")
	check(ActionPresentationState.capture(s.state) == data.after and rng == s.context.get_rng().to_dict() and counters == s.context.simulation_counters(), mode + " playback leaves live/RNG/counters unchanged")
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	if mode in ["mixed", "armor", "zero", "critical", "counter"]: await capture("result-" + mode)
	if mode == "mixed":
		var first := board._numbers.get_child(0) as BattlePresentationNumber
		var second := board._add_result_number(b, "+1.0 HP", Color("65dfcc"))
		feedback_count = board._numbers.get_child_count()
		check(not first._label.get_global_rect().intersects(second._label.get_global_rect()), "independent healing does not cover total damage")
		first.sample(0.75)
		second.sample(0.0)
		check(not first._label.get_global_rect().intersects(second._label.get_global_rect()), "older rising number cannot cover fresh number")
		first.sample(0.0)
		board.show_presentation_state(data.after)
		check(board._numbers.get_child_count() == feedback_count, "next snapshot retains all feedback")
		player.set_speed(3.0)
		player.play(board, data.before, data.frames, data.after)
		player._tween.pause()
		var label_y := first._label.position.y
		first._tween.custom_step(0.2)
		check(board._numbers.get_child_count() == feedback_count and is_equal_approx(label_y - first._label.position.y, first.rise / 6.0), "next command and x3 retain real-time number lifetime")
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
	check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, mode + " cancel after early result clears feedback")
	s.close()
	await process_frame

func result_numbers() -> Array[BattlePresentationNumber]:
	var values: Array[BattlePresentationNumber] = []
	for number: BattlePresentationNumber in board._numbers.get_children():
		if number.feedback_kind == &"result": values.append(number)
	return values

func emit_damage(actor: int, target: int, amount: float) -> BattlePresentationNumber:
	board._show_event_feedback([
		{"kind": &"damaged", "actor_unit_id": actor, "target_unit_id": target, "amount": amount},
		{"kind": &"hit_resolved", "actor_unit_id": actor, "target_unit_id": target}
	], {}, true, false)
	var number := result_numbers().back() as BattlePresentationNumber
	number._tween.pause()
	return number

func compact_damage_numbers() -> void:
	var s := fixture("hp")
	var snapshot := ActionPresentationState.capture(s.state)
	var rng := s.context.get_rng().to_dict()
	board.show_presentation_state(snapshot)
	var actor: int = s.units[0].id
	var target: int = s.units[1].id
	var first := emit_damage(actor, target, 12.0)
	first.sample(0.2)
	var second := emit_damage(actor, target, 7.0)
	var first_rect := first._label.get_global_rect()
	var second_rect := second._label.get_global_rect()
	check(first._tint == Color("f3ead7") and second._tint == Color("f3ead7"), "ordinary damage uses warm white")
	check(first._label.text == "−12.0" and second._label.text == "−7.0", "compact burst preserves both actual hit amounts")
	check(first_rect.intersects(second_rect) and is_equal_approx(first_rect.end.y - second_rect.end.y, 12.0),
		"new damage overlaps old label with a compact 12px baseline step")
	check(absf(first_rect.get_center().x - second_rect.get_center().x) <= 4.1, "burst stays at the recipient instead of a distant column")
	first.sample(0.4)
	second.sample(0.2)
	check(is_equal_approx(first._label.get_global_rect().end.y - second._label.get_global_rect().end.y, 12.0),
		"equal elapsed time preserves compact separation")
	var before_resize := second.position - first.position
	board.size += Vector2(16, 8)
	check((second.position - first.position).is_equal_approx(before_resize), "resize retains compact burst offsets")
	var third := emit_damage(actor, target, 3.0)
	check(is_equal_approx(second._label.get_global_rect().end.y - third._label.get_global_rect().end.y, 12.0),
		"third damage joins the moving stack without waiting for older numbers")
	await capture("damage-burst")
	var heal := board._add_result_number(target, "+2.0 HP", Color("65dfcc"))
	heal._tween.pause()
	for number: BattlePresentationNumber in [first, second, third]:
		check(not number._label.get_global_rect().intersects(heal._label.get_global_rect()), "healing remains outside compact damage stack")
	var retained_offset: Vector2 = second.get_meta("damage_offset")
	board._numbers.remove_child(first)
	first.queue_free()
	board._place_result_numbers()
	check(second.get_meta("damage_offset") == retained_offset, "expiration of oldest damage does not reset younger offset")
	board.clear_presentation_feedback()
	first = emit_damage(actor, target, 1.0)
	second = emit_damage(actor, s.units[3].id, 2.0)
	check(second.get_meta("damage_offset", Vector2.ZERO) == Vector2.ZERO, "another recipient does not join the first stack")
	var moved := snapshot.duplicate(true)
	moved.units[target].cell = Vector2i(2, 4)
	board.show_presentation_state(moved)
	third = emit_damage(actor, target, 3.0)
	check(third.get_meta("damage_offset", Vector2.ZERO) == Vector2.ZERO and first.get_meta("cell") != third.get_meta("cell"),
		"same recipient at a new cell starts a separate stack")
	board.clear_presentation_feedback()
	board.show_presentation_state(snapshot)
	for i: int in 35: emit_damage(actor, target, float(i + 1))
	var positions: Array[Vector2] = []
	var has_overflow_column := false
	var first_x := result_numbers()[0].position.x
	for number: BattlePresentationNumber in result_numbers():
		var rect := number._label.get_global_rect()
		check(rect.position.y >= 0.0 and rect.end.x <= viewport.size.x, "overflow burst stays inside top and right viewport bounds")
		check(not positions.has(number.position), "overflow avoids piling multiple results at one point")
		positions.append(number.position)
		if absf(number.position.x - first_x) > number._label.size.x * 0.5: has_overflow_column = true
	check(has_overflow_column, "long burst actually reaches top and uses another column")
	await capture("damage-burst-overflow")
	check(ActionPresentationState.capture(s.state) == snapshot and s.context.get_rng().to_dict() == rng, "number layout never changes battle state or RNG")
	board.clear_presentation_feedback()
	s.close()
	await process_frame

func event_anchor_fixtures() -> void:
	var s := fixture("hp")
	var actor_a: int = s.units[0].id
	var actor_b: int = s.units[2].id
	var target: int = s.units[1].id
	board.show_presentation_state(ActionPresentationState.capture(s.state))
	var strike: Dictionary = {}
	var initial_cell: Vector2i = board._view_unit_cell(target)
	board._show_event_feedback([
		{"kind": &"damaged", "actor_unit_id": actor_a, "target_unit_id": target, "amount": 3.0},
		{"kind": &"damaged", "actor_unit_id": actor_b, "target_unit_id": target, "amount": 4.0},
		{"kind": &"hit_resolved", "actor_unit_id": actor_a, "target_unit_id": target}
	], strike, true, false)
	var numbers := result_numbers()
	check(numbers.size() == 2, "different actors damage one target with separate hits and no duplicate zero")
	check(numbers.size() == 2 and int(numbers[0].get_meta("unit_id", 0)) == target and int(numbers[1].get_meta("unit_id", 0)) == target,
		"same-target results both belong to the recipient")
	check(numbers.size() == 2 and numbers[0].get_meta("cell") == initial_cell, "number stores recipient cell at creation")
	var moved_projection := ActionPresentationState.capture(s.state)
	var projected_units: Dictionary = moved_projection.units
	var projected_target: Dictionary = projected_units[target]
	projected_target["cell"] = Vector2i(2, 4)
	projected_units[target] = projected_target
	moved_projection["units"] = projected_units
	board.show_presentation_state(moved_projection)
	board.size += Vector2(24, 16)
	check(numbers.size() == 2 and numbers[0].get_meta("cell") == initial_cell and board._view_unit_cell(target) != initial_cell,
		"movement, resize and next snapshot retain pinned recipient cell")
	board.clear_presentation_feedback()
	board._show_event_feedback([
		{"kind": &"damaged", "actor_unit_id": actor_a, "target_unit_id": target, "amount": 1.0},
		{"kind": &"hit_resolved", "actor_unit_id": actor_a, "target_unit_id": target},
		{"kind": &"damaged", "actor_unit_id": actor_a, "target_unit_id": s.units[3].id, "amount": 2.0},
		{"kind": &"hit_resolved", "actor_unit_id": actor_a, "target_unit_id": s.units[3].id}
	], strike, true, false)
	numbers = result_numbers()
	check(numbers.size() == 2 and int(numbers[0].get_meta("unit_id", 0)) == target
		and int(numbers[1].get_meta("unit_id", 0)) == s.units[3].id,
		"one actor hitting multiple targets places each result at its recipient")
	board.clear_presentation_feedback()
	for source_actor: int in [0, target, 999999]:
		board._show_event_feedback([
			{"kind": &"hit_resolved", "actor_unit_id": source_actor, "target_unit_id": target}
		], strike, true, false)
		numbers = result_numbers()
		check(numbers.size() == 1 and numbers[0]._label.text == "0" and int(numbers[0].get_meta("unit_id")) == target,
			"zero result belongs to recipient even for absent or self source")
		board.clear_presentation_feedback()
		board._show_event_feedback([
			{"kind": &"damaged", "actor_unit_id": source_actor, "target_unit_id": target, "amount": 2.0},
			{"kind": &"armor_changed", "actor_unit_id": source_actor, "target_unit_id": target,
				"grants": [{"before": 4.0, "after": 2.0}], "items": []},
			{"kind": &"shield_changed", "actor_unit_id": source_actor, "target_unit_id": target, "absorbed": 1.0, "after": {}},
			{"kind": &"hit_resolved", "actor_unit_id": source_actor, "target_unit_id": target}
		], strike, true, false)
		numbers = result_numbers()
		check(numbers.size() == 1 and numbers[0]._label.text == "−5.0" and int(numbers[0].get_meta("unit_id")) == target,
			"environment, self and missing actors retain one combined result at recipient")
		board.clear_presentation_feedback()
	board._show_event_feedback([
		{"kind": &"shield_changed", "actor_unit_id": actor_a, "target_unit_id": target, "absorbed": 2.5, "after": {"hp": 4.0}},
		{"kind": &"shield_changed", "actor_unit_id": actor_a, "target_unit_id": target, "absorbed": 0.0, "after": {"hp": 6.0}},
		{"kind": &"healed", "actor_unit_id": actor_a, "target_unit_id": target, "amount": 1.5},
		{"kind": &"armor_changed", "actor_unit_id": actor_a, "target_unit_id": target,
			"grants": [{"before": 1.0, "after": 2.0}], "items": []}
	], strike, true, false)
	numbers = result_numbers()
	check(numbers.size() == 4, "shield absorption, application, heal and armor application each show")
	check(numbers.size() == 4 and int(numbers[0].get_meta("unit_id", 0)) == target
		and int(numbers[1].get_meta("unit_id", 0)) == target and int(numbers[2].get_meta("unit_id", 0)) == target
		and int(numbers[3].get_meta("unit_id", 0)) == target,
		"shield absorption and positive changes all belong to recipient")
	board.clear_presentation_feedback()
	var dead_projection := ActionPresentationState.capture(s.state)
	dead_projection.units[actor_a]["alive"] = false
	dead_projection.units[actor_a]["hp"] = 0.0
	board.environment_mode = true
	board.show_presentation_state(dead_projection)
	board._show_event_feedback([
		{"kind": &"damaged", "actor_unit_id": actor_a, "target_unit_id": target, "amount": 2.0},
		{"kind": &"hit_resolved", "actor_unit_id": actor_a, "target_unit_id": target}
	], strike, true, false)
	numbers = result_numbers()
	check(numbers.size() == 1 and numbers[0]._label.text == "−2.0" and int(numbers[0].get_meta("unit_id")) == target,
		"dead DOT author retains damage at living recipient")
	board.clear_presentation_feedback()
	board._show_event_feedback([
		{"kind": &"hit_resolved", "actor_unit_id": actor_a, "target_unit_id": target}
	], strike, true, false)
	numbers = result_numbers()
	check(numbers.size() == 1 and numbers[0]._label.text == "0" and int(numbers[0].get_meta("unit_id")) == target,
		"dead author retains zero result at recipient")
	board.clear_presentation_feedback()
	for absent_target: int in [0, 999999]:
		board._show_event_feedback([
			{"kind": &"damaged", "actor_unit_id": actor_b, "target_unit_id": absent_target, "amount": 3.0}
		], strike, true, false)
		check(result_numbers().is_empty(), "missing recipient never redirects damage to attacker")
	board._show_event_feedback([
		{"kind": &"damaged", "actor_unit_id": 0, "target_unit_id": target, "amount": 3.0,
			"source": {"kind": &"cell", "origin_cell": Vector2i(0, 0)}}
	], strike, true, false)
	numbers = result_numbers()
	check(numbers.size() == 1 and int(numbers[0].get_meta("unit_id")) == target
		and numbers[0].get_meta("cell") == board._view_unit_cell(target), "remote hazard anchors to recipient, not origin cell")
	board.environment_mode = false
	board.clear_presentation_feedback()
	board.show_presentation_state(ActionPresentationState.capture(s.state))
	for absorbed_by: String in ["armor", "shield"]:
		var status_events: Array = [{"kind": &"elemental_changed", "root_id": 123, "command_seq": 90,
			"actor_unit_id": actor_a, "target_unit_id": target}]
		var source := {"kind": &"status_snapshot", "instigator_unit_id": actor_a}
		if absorbed_by == "armor":
			status_events.append({"kind": &"armor_changed", "root_id": 123, "command_seq": 90,
				"actor_unit_id": actor_a, "target_unit_id": target, "source": source,
				"grants": [{"before": 6.0, "after": 2.0}], "items": []})
		else:
			status_events.append({"kind": &"shield_changed", "root_id": 123, "command_seq": 90,
				"actor_unit_id": actor_a, "target_unit_id": target, "source": source, "absorbed": 4.0, "after": {"hp": 2.0}})
		status_events.append({"kind": &"hit_resolved", "root_id": 123, "command_seq": 90,
			"actor_unit_id": actor_a, "target_unit_id": target, "source": source})
		var status_tween := board.animate_presentation_frame(status_events, {"kind": &"elemental_tick"})
		status_tween.pause()
		status_tween.custom_step(0.001)
		numbers = result_numbers()
		check(numbers.size() == 1 and numbers[0]._label.text == "−4.0" and int(numbers[0].get_meta("unit_id")) == target,
			absorbed_by + " only status tick shows immediate combined damage before status pulse completes")
		status_tween.kill()
		board.clear_presentation_feedback()
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
	await combat_font_pair()
	for mode: String in ["hp", "mixed", "armor", "zero", "lethal", "critical", "counter"]: await scenario(mode)
	await event_anchor_fixtures()
	await compact_damage_numbers()
	await movement_timing()
	await abort_cases()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION CONTACT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func combat_font_pair() -> void:
	var scene := preload("res://scenes/demo/visuals/result_number.tscn")
	var samples: Array[String] = ["−12.5 HP", "КРИТ · −28.0 HP", "+8.0 HP", "Щит −6.0",
		"БЛОК", "ПРОМАХ", "КРОВОТЕЧЕНИЕ", "0 · без урона", "0123456789.,+-%− ·×—:/",
		"−3.5 броня\nРавновесие −2.0"]
	var server := TextServerManager.get_primary_interface()
	var colors: Array[Color] = [Color("f29b9b"), Color("f29b9b"), Color("65dfcc"), Color("71cefa")]
	var numbers: Array[BattlePresentationNumber] = []
	for i: int in samples.size():
		var number := scene.instantiate() as BattlePresentationNumber
		viewport.add_child(number)
		number.position = Vector2(640, 100 + i * 75)
		if i == samples.size() - 1:
			number._label.add_theme_font_size_override("font_size", 20)
		number.start(samples[i], colors[i] if i < colors.size() else Color("ffd08a"))
		number._tween.pause()
		numbers.append(number)
		check(number._label.text == samples[i], "font selection preserves original feedback text")
		var font := number._label.get_theme_font("font")
		# Проверяем всю строку: наличие glyph в TTF не доказывает отсутствие системной подмены.
		for text_line: String in samples[i].split("\n"):
			var line := TextLine.new()
			check(line.add_string(text_line, font, number._label.get_theme_font_size("font_size")), "combat font shapes line")
			for glyph: Dictionary in server.shaped_text_get_glyphs(line.get_rid()):
				var character := text_line.substr(int(glyph.start), 1)
				if character == " ": continue
				var expected := "Combat Jersey 20 Numbers" if "0123456789.,+-%−".contains(character) else "Combat Lettering"
				check(int(glyph.index) != 0 and server.font_get_name(glyph.font_rid) == expected,
					"combat glyph %s uses %s" % [character, expected])
		check(number._label.size.x > 0 and number._label.size.y > 0 and not number._label.clip_text, "feedback has measured unclipped bounds")
	await process_frame
	await process_frame
	if not captures.is_empty():
		check(viewport.get_texture().get_image().save_png(captures.path_join("combat-font-pair.png")) == OK, "PNG selected combat font pair")
	for number: BattlePresentationNumber in numbers: number.queue_free()
	await process_frame

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
	var origin := board._world_cell_center(start)
	var length := origin.distance_to(board._world_cell_center(middle))
	tween.custom_step(0.02)
	var visual := board._presentation_visual(actor_id)
	var quarter := (visual.position + visual.get_visual_offset()).distance_to(origin) / length
	tween.custom_step(0.02)
	var midpoint := (visual.position + visual.get_visual_offset()).distance_to(origin) / length
	tween.custom_step(0.02)
	var three_quarters := (visual.position + visual.get_visual_offset()).distance_to(origin) / length
	check(quarter > 0.0 and quarter < 0.25 and is_equal_approx(midpoint, 0.5) and three_quarters > 0.75 and three_quarters < 1.0, "voluntary movement accelerates and brakes within unchanged duration")
	check(midpoint - quarter > quarter and three_quarters - midpoint > 1.0 - three_quarters, "middle movement is faster than departure and arrival")
	tween.custom_step(0.019)
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
	tween.custom_step(0.025)
	visual = board._presentation_visual(actor_id)
	var forced_quarter := (visual.position + visual.get_visual_offset()).distance_to(origin) / length
	check(forced_quarter > 0.25 and forced_quarter < 1.0, "forced push starts with an impulse and decelerates")
	tween.custom_step(0.055)
	check(board._view_unit_cell(actor_id) == start, "grounded slide does not publish the cell before completion")
	tween.custom_step(BattleDemoBoard.FORCED_MOVE_SEGMENT_SECONDS - 0.08 + 0.001)
	check(board._view_unit_cell(actor_id) == middle, "grounded slide completes at its own segment duration")
	tween.kill()
	board.clear_strike_poses()
	s.close()
	await process_frame

func abort_cases() -> void:
	var s := fixture("hp")
	var data := packet(s)
	player.set_speed(3.0)
	player.play(board, data.before, data.frames, data.after)
	advance(0.126 / 3.0)
	advance(0.001 / 3.0)
	check(board._impacts.get_child_count() == 1 and board._numbers.get_child_count() > 0, "x3 contact immediately shows total")
	player.skip()
	check(board._impacts.get_child_count() == 0 and board._numbers.get_child_count() == 0 and board._action_offsets.is_empty(), "skip after early x3 result cancels all effects")
	check(ActionPresentationState.capture(s.state) == data.after, "contact skip cannot change actual result")
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	player._tween.pause()
	advance(0.126)
	advance(0.001)
	check(board._impacts.get_child_count() == 1 and board._numbers.get_child_count() > 0, "replay setup shows immediate contact total")
	var cancelled_tween := player._tween
	player.cancel()
	check(board._numbers.get_child_count() == 0 and board._impacts.get_child_count() == 0, "cancel removes immediate result")
	player.play(board, data.before, data.frames, data.after)
	player._tween.pause()
	advance(0.126)
	advance(0.001)
	var replay_count: int = board._numbers.get_child_count()
	await process_frame
	check(not cancelled_tween.is_valid() and replay_count > 0 and board._numbers.get_child_count() == replay_count,
		"killed prior tween cannot spawn or duplicate feedback during same-packet replay")
	player.cancel()
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
