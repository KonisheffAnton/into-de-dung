extends "res://tests/test_push_chain.gd"

var viewport: SubViewport
var board: BattleDemoBoard
var player: BattlePresentationPlayer
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func open_lane() -> BattleCoreReactionsSession:
	var s := fixture(4.0)
	s.board.move_unit(s.units[2], Vector2i(2, 0))
	s.board.move_unit(s.units[5], Vector2i(5, 0))
	s.units[1].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 12.0)
	return s

func packet(s: BattleCoreReactionsSession, label: String) -> Dictionary:
	var before := ActionPresentationState.capture(s.state)
	s._queue.capture_presentation = true
	var receipt := parity(s, label)
	return {"before": before, "frames": receipt.get_presentation_frames(), "after": ActionPresentationState.capture(s.state), "events": receipt.get_events()}

func feedback(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var before: Dictionary = data.before
	for frame: Dictionary in data.frames:
		result.append_array(BattleConsequenceFeedback.entries(frame.events, before, frame.after))
		before = frame.after
	return result

func count_text(entries: Array[Dictionary], text: String, id: int = 0) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if entry.text == text and (id == 0 or entry.unit_id == id): count += 1
	return count

func has_text(entries: Array[Dictionary], text: String) -> bool:
	return entries.any(func(entry: Dictionary) -> bool: return String(entry.text).contains(text))

func shown_texts() -> String:
	var texts: PackedStringArray = []
	for number: BattlePresentationNumber in board._numbers.get_children(): texts.append(number._label.text.replace("\n", " · "))
	return "\n".join(texts)

func advance(seconds: float) -> void:
	if not player.active: return
	player._tween.pause()
	player._tween.custom_step(seconds)
	if player.active: player._tween.pause()

func finish() -> void:
	var guard := 0
	while player.active and guard < 100:
		advance(1.0)
		guard += 1
	check(not player.active, "consequence playback completes")

func capture(label: String) -> void:
	if captures.is_empty(): return
	for number: BattlePresentationNumber in board._numbers.get_children(): number._tween.pause()
	for impact: BattlePresentationImpact in board._impacts.get_children(): impact._tween.pause()
	await process_frame
	await process_frame
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func play_checked(s: BattleCoreReactionsSession, data: Dictionary, expected: String, label: String) -> void:
	player.cancel()
	var state := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var copied := data.duplicate(true)
	player.set_speed(1.0)
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()
	check(board._numbers.get_child_count() == 0, label + " no result before publication")
	finish()
	check(shown_texts().contains(expected), label + " honest after feedback visible")
	var notice_owners: Dictionary = {}
	for number: BattlePresentationNumber in board._numbers.get_children():
		if number.feedback_kind != &"consequence": continue
		var id := int(number.get_meta("unit_id"))
		check(not notice_owners.has(id) and number.rise == 0.0 and number.lifetime == 1.2, label + " one stationary independent notice per figure")
		notice_owners[id] = true
		check(number.position.y - number._label.size.y >= board._world_cell_center(number.get_meta("cell")).y, label + " reasons stay below figures instead of displacing damage upward")
	check(snapshot(s) == state and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and data == copied, label + " playback does not mutate world RNG counters or receipt")
	for entry: Dictionary in data.after.units.values():
		check(board._view_unit_cell(entry.id) == entry.cell, label + " display follows actual final cell")
	await capture(label)
	board.size += Vector2(8, 8)
	board.zoom_camera(0.75, board.size * 0.5)
	check(shown_texts().contains(expected), label + " resize and zoom retain feedback")
	player.cancel()
	check(board._numbers.get_child_count() == 0, label + " cancel cleans feedback")
	player.set_speed(3.0)
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()
	finish()
	check(shown_texts().contains(expected), label + " x3 retains readable feedback")
	player.play(board, data.before, data.frames, data.after)
	player.skip()
	check(board._numbers.get_child_count() == 0 and board._ghosts.get_child_count() == 0 and board._action_offsets.is_empty(), label + " skip clears captions and poses")
	check(snapshot(s) == state, label + " skip preserves final world")
	player.set_speed(1.0)
	board.size = viewport.size
	board.zoom_camera(1.0, board.size * 0.5)
	s.close()
	await process_frame

func balance_cases() -> void:
	for mode: String in ["held", "open", "wall", "height", "fall"]:
		var s := open_lane()
		var target := s.units[1]
		if mode != "held": target.vitals.set_balance(8.0)
		if mode == "wall": s.board.set_terrain(Vector2i(3, 3), TerrainType.Type.WALL)
		if mode == "height": s.board.set_height_steps(Vector2i(3, 3), 2)
		if mode == "fall": s.board.set_terrain(Vector2i(3, 3), TerrainType.Type.VOID)
		var data := packet(s, mode)
		var entries := feedback(data)
		var expected := "Устоял · 4.0/12.0" if mode == "held" else "Потеря равновесия"
		check(count_text(entries, "Потеря равновесия", target.id) == (0 if mode == "held" else 1), mode + " change+break emit exactly one break cue")
		if mode in ["held", "wall", "height"]: check(not has_text(entries, "Сдвиг"), mode + " no invented displacement")
		if mode == "open": check(count_text(entries, "Сдвиг", target.id) == 1, "actual moved produces shift cue")
		if mode == "wall": expected = "Упор: стена"
		if mode == "height": expected = "Упор: уступ"
		if mode == "fall":
			expected = "Падение"
			check(not has_text(entries, "Упор"), "VOID fall is not blockage")
		await play_checked(s, data, expected, "balance-" + mode)

func chain_cases() -> void:
	for mode: String in ["held", "immune", "moves", "wall"]:
		var s := fixture()
		if mode == "held": s.units[2].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 20.0)
		if mode == "immune": s.units[2].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
		if mode == "wall": s.board.set_terrain(Vector2i(5, 3), TerrainType.Type.WALL)
		var data := packet(s, "chain " + mode)
		var entries := feedback(data)
		check(count_text(entries, "Импульс передан", s.units[1].id) == 1, "chain acknowledges original target passing force")
		check(count_text(entries, "Сдвиг", s.units[1].id) == 0, "original target never promised movement")
		var expected := "Столкновение:"
		if mode == "held": expected = "Цепь остановлена · устоял"
		if mode == "immune": expected = "Цепь остановлена · невосприимчив"
		if mode == "wall": expected = "Упор: стена"
		if mode != "moves": check(count_text(entries, "Сдвиг") == 0, "stopped chain has no shift cue")
		else: check(count_text(entries, "Сдвиг", s.units[5].id) == 1, "only terminal link receives shift cue")
		await play_checked(s, data, expected, "chain-" + mode)

func armor_cases() -> void:
	for mode: String in ["spent", "partial", "piercing"]:
		var s := open_lane()
		var target := s.units[1]
		s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		for definition: AttackDefinition in s.context._attack_rules._definitions: definition.damage_components.clear()
		s.units[0].stats.set_base_value(StatTypes.StatType.STRENGTH, 100.0 if mode == "spent" else 10.0)
		for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
		if mode == "piercing": s.units[0].stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 100.0)
		var data := packet(s, "armor " + mode)
		var entries := feedback(data)
		check(float(data.before.units[target.id].armor.current) > 0.0, "armor case begins with actual equipment armor")
		check(count_text(entries, "Броня исчерпана", target.id) == (1 if mode == "spent" else 0), mode + " full depletion is distinct from partial loss")
		check(count_text(entries, "Сквозь броню", target.id) == (1 if mode == "piercing" else 0), mode + " penetration only from resolved policy")
		if mode == "piercing": check(data.before.units[target.id].armor.current == data.after.units[target.id].armor.current, "100 percent penetration preserves armor")
		await play_checked(s, data, "Броня исчерпана" if mode == "spent" else ("Сквозь броню" if mode == "piercing" else "броня"), "armor-" + mode)

func threshold_and_fault() -> void:
	var s := open_lane()
	var target := s.units[1]
	target.control.entangled_turns = 1
	target.vitals.set_balance(18.0)
	var before := ActionPresentationState.capture(s.state)
	s._queue.capture_presentation = true
	var receipt := s._queue.submit(ControlTurnEndCommand.new(target.faction, s.context.get_revision()), s.context)
	var after := ActionPresentationState.capture(s.state)
	var data := {"before": before, "frames": receipt.get_presentation_frames(), "after": after, "events": receipt.get_events()}
	check(feedback(data).is_empty(), "18/24 to 18/12 never invents break or displacement")
	board.show_presentation_state(after)
	check(board.displayed_unit_details(target.id).contains("Снижение порога само по себе не вызывает сдвиг"), "inspection explains reached threshold without event")
	await play_checked(s, data, "Путы", "threshold-expiry")
	s = open_lane()
	s._queue = ActionQueue.new(1, 512)
	data = packet(s, "FAULTED windup")
	check(feedback(data).is_empty(), "faulted attack without result has no consequences")
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()
	finish()
	check(board._numbers.get_child_count() == 0, "FAULTED playback emits no captions")
	player.cancel()
	s.close()
	await process_frame

func absent_evidence() -> void:
	var before := {"units": {1: {"armor": {"current": 20}, "balance_max": 12}}}
	var partial := {"units": {1: {"armor": {"current": 15}, "balance_max": 12}}}
	var depleted := {"units": {1: {"armor": {"current": 0}, "balance_max": 12}}}
	var change := {"kind": &"armor_changed", "target_unit_id": 1, "items": [{"before": 5, "after": 0}], "grants": []}
	var hit := {"kind": &"hit_resolved", "target_unit_id": 1, "hit": {"rows": [{"policy": &"standard", "hp_damage": 8}]}}
	check(BattleConsequenceFeedback.entries([change, hit], before, partial).is_empty(), "one exhausted item and standard HP are neither full depletion nor penetration")
	check(BattleConsequenceFeedback.entries([change], before, depleted).is_empty(), "armor expiry without resolved hit is not attack depletion")
	check(BattleConsequenceFeedback.entries([change, hit], before, {}).is_empty(), "missing snapshot is not evidence of zero armor")
	var broken := {"kind": &"balance_broken", "target_unit_id": 1}
	check(BattleConsequenceFeedback.entries([broken, broken], before, depleted).size() == 1, "repeated evidence does not duplicate break caption")
	var link := {"kind": &"chain_link", "from_unit_id": 2, "target_unit_id": 1, "broke": false}
	check(not has_text(BattleConsequenceFeedback.entries([link], {}, {}), "невосприимчив"), "missing threshold does not invent immunity")

func consecutive_roots() -> void:
	var s := open_lane()
	var data := packet(s, "consecutive root hit")
	player.play(board, data.before, data.frames, data.after)
	if player.active: player._tween.pause()
	finish()
	check(shown_texts().contains("Устоял"), "first root leaves a readable balance notice")
	var target := s.units[1]
	var next_before := ActionPresentationState.capture(s.state)
	var receipt := s._queue.submit(MoveCommand.new(target.id, [target.cell, target.cell + Vector2i(0, 1)], s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.APPLIED, "following root is a real ordinary move: " + String(receipt.reason))
	var final_state := ActionPresentationState.capture(s.state)
	var state := snapshot(s)
	var retained_results := 0
	for number: BattlePresentationNumber in board._numbers.get_children():
		if number.feedback_kind == &"result": retained_results += 1
	# Намеренно без cancel: обычное play сохраняет остаточные числа прошлого удара.
	player.play(board, next_before, receipt.get_presentation_frames(), final_state)
	if player.active: player._tween.pause()
	check(not shown_texts().contains("Устоял"), "new ordinary movement clears the old reason before animation")
	var results_after := 0
	for number: BattlePresentationNumber in board._numbers.get_children():
		if number.feedback_kind == &"result": results_after += 1
	check(results_after == retained_results and results_after > 0, "new root keeps independent damage numbers")
	finish()
	check(board._view_unit_cell(target.id) == target.cell and snapshot(s) == state, "consecutive roots keep final display and world in sync")
	await capture("consecutive-roots")
	player.cancel()
	s.close()
	await process_frame

func obstacle_impacts() -> Array[BattlePresentationImpact]:
	var result: Array[BattlePresentationImpact] = []
	for impact: BattlePresentationImpact in board._impacts.get_children():
		if impact.get_meta("obstacle_contact", false): result.append(impact)
	return result

func seek_obstacle() -> Dictionary:
	var guard := 0
	while player.active and guard < 100:
		var frame: Dictionary = player._frames[player._index]
		for event: Dictionary in frame.events:
			if event.kind in [&"push_blocked", &"collision"]: return event
		advance(1.0)
		guard += 1
	return {}

func obstacle_contacts() -> void:
	for mode: String in ["wall", "height", "body"]:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			player.cancel()
			var s := open_lane()
			var target := s.units[1]
			var blocker := s.units[2]
			check(s.board.move_unit(target, Vector2i(7, 7)), "obstacle fixture parks target")
			check(s.board.move_unit(s.units[0], Vector2i(3, 3) - direction), "obstacle fixture places attacker")
			check(s.board.move_unit(target, Vector2i(3, 3)), "obstacle fixture places target")
			target.vitals.set_balance(8.0)
			var destination := target.cell + direction
			if mode == "wall": s.board.set_terrain(destination, TerrainType.Type.WALL)
			elif mode == "height": s.board.set_height_steps(destination, 2)
			else:
				check(s.board.move_unit(blocker, destination), "obstacle fixture places body")
				blocker.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 20.0)
			var label := "contact-%s-%d-%d" % [mode, direction.x, direction.y]
			var data := packet(s, label)
			var immutable := data.duplicate(true)
			var state := snapshot(s)
			var rng := s.context.get_rng().to_dict().duplicate(true)
			var counters := s.context.simulation_counters()
			player.set_speed(1.0)
			player.play(board, data.before, data.frames, data.after)
			if player.active: player._tween.pause()
			var event := seek_obstacle()
			check(not event.is_empty(), label + " real receipt contains obstacle contact")
			if event.is_empty():
				s.close()
				continue
			var visual := board._presentation_visual(target.id)
			var cell := board._view_unit_cell(target.id)
			var support := visual.position
			var hud := visual._status_hud.position
			var shown_hp := visual.unit.hp
			var expected_direction := Vector2(direction.x - direction.y, (direction.x + direction.y) * 0.5).normalized()
			check(obstacle_impacts().is_empty(), label + " no contact flash before contact")
			advance(BattleDemoBoard.OBSTACLE_APPROACH_SECONDS * 0.5)
			check(visual.action_offset.dot(expected_direction) > 1.0, label + " body approaches obstacle in correct direction")
			check(visual.position == support and visual._status_hud.position == hud and board._view_unit_cell(target.id) == cell, label + " approach preserves logical cell sorting support and HUD")
			advance(BattleDemoBoard.OBSTACLE_APPROACH_SECONDS * 0.5 + 0.002)
			var impacts := obstacle_impacts()
			check(impacts.size() == 1, label + " one contact flash per real obstacle event")
			check(visual.action_offset.dot(expected_direction) >= 27.0 and visual.unit.hp == shown_hp, label + " contact holds body without publishing damage early")
			if mode == "body":
				var receiver := board._presentation_visual(blocker.id)
				check(receiver.action_offset.dot(expected_direction) >= 9.0 and board._view_unit_cell(blocker.id) == destination, label + " receiver visibly recoils without changing cell")
			if not impacts.is_empty():
				var impact := impacts[0]
				var factor := board.grid_config.tile_size.x / 128.0
				var expected_contact := board._world_cell_center(cell) + (expected_direction * 38.0 + Vector2(0, -18)) * factor
				check(impact.position.is_equal_approx(expected_contact), label + " flash is at obstacle facing contact point")
				board.size += Vector2(16, 12)
				board.zoom_camera(0.75, board.size * 0.5)
				visual = board._presentation_visual(target.id)
				check(visual.action_offset.dot(expected_direction) >= 27.0 and obstacle_impacts().size() == 1 and impact.position.is_equal_approx(board._world_cell_center(cell) + (expected_direction * 38.0 + Vector2(0, -18)) * factor), label + " resize and zoom preserve contact pose and anchor")
			await capture(label)
			advance(BattleDemoBoard.OBSTACLE_HOLD_SECONDS + BattleDemoBoard.OBSTACLE_RECOVERY_SECONDS * 0.5)
			check(absf(board._presentation_visual(target.id).action_offset.dot(expected_direction)) < 27.0, label + " body rebounds from contact")
			if direction == Vector2i.RIGHT: await capture(label + "-rebound")
			finish()
			check(board._presentation_visual(target.id).action_offset == Vector2.ZERO and board._view_unit_cell(target.id) == cell, label + " completed contact returns body to unchanged cell")
			if mode == "body": check(board._presentation_visual(blocker.id).action_offset == Vector2.ZERO, label + " receiver returns after contact")
			check(not shown_texts().contains("Сдвиг"), label + " contact does not invent displacement")
			check(snapshot(s) == state and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and data == immutable, label + " contact never mutates world RNG counters or receipt")
			if direction == Vector2i.RIGHT:
				for cancel_playback: bool in [false, true]:
					player.cancel()
					player.set_speed(3.0)
					player.play(board, data.before, data.frames, data.after)
					if player.active: player._tween.pause()
					check(not seek_obstacle().is_empty(), label + " x3 reaches real obstacle event")
					advance((BattleDemoBoard.OBSTACLE_APPROACH_SECONDS + 0.01) / 3.0)
					check(obstacle_impacts().size() == 1 and board._presentation_visual(target.id).action_offset.dot(expected_direction) >= 27.0, label + " x3 preserves contact phase")
					if cancel_playback: player.cancel()
					else: player.skip()
					check(not player.active and board._action_offsets.is_empty() and board._impacts.get_child_count() == 0, label + " skip or cancel removes contact poses and flashes")
					check(snapshot(s) == state and data == immutable, label + " interrupted contact preserves world and packet")
			player.cancel()
			player.set_speed(1.0)
			board.size = viewport.size
			board.zoom_camera(1.0, board.size * 0.5)
			s.close()
			await process_frame

func chain_overlap() -> void:
	for mode: String in ["open", "wall", "middle-dead", "last-dead"]:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			player.cancel()
			var s := fixture()
			for i: int in 6:
				check(s.board.move_unit(s.units[i], Vector2i(i, 0)), "overlap fixture parks bodies")
			for pair: Array in [[0, -1], [1, 0], [2, 1], [5, 2]]:
				check(s.board.move_unit(s.units[pair[0]], Vector2i(4, 4) + direction * int(pair[1])), "overlap fixture places column")
			if mode == "wall": s.board.set_terrain(Vector2i(4, 4) + direction * 3, TerrainType.Type.WALL)
			if mode == "middle-dead": s.units[2].vitals.set_hp(1.0)
			if mode == "last-dead": s.units[5].vitals.set_hp(1.0)
			var label := "overlap-%s-%d-%d" % [mode, direction.x, direction.y]
			var data := packet(s, label)
			var immutable := data.duplicate(true)
			var state := snapshot(s)
			var rng := s.context.get_rng().to_dict().duplicate(true)
			var counters := s.context.simulation_counters()
			var started: Array[Dictionary] = []
			var published: Array[Dictionary] = []
			var on_start := func(frame: Dictionary) -> void: started.append(frame)
			var on_finish := func(after: Dictionary) -> void: published.append(after)
			player.frame_started.connect(on_start)
			player.frame_finished.connect(on_finish)
			player.play(board, data.before, data.frames, data.after)
			player._tween.pause()
			check(not seek_obstacle().is_empty() and player._chain != null, label + " receipt selects one shared chain clock")
			var first := player._index
			var chain := player._chain
			var axis := Vector2(direction.x - direction.y, (direction.x + direction.y) * 0.5).normalized()
			var a: int = s.units[1].id
			var b: int = s.units[2].id
			var c: int = s.units[5].id
			var a_cell := board._view_unit_cell(a)
			var b_cell := board._view_unit_cell(b)
			var approach := BattleDemoBoard.OBSTACLE_APPROACH_SECONDS
			var hold := BattleDemoBoard.OBSTACLE_HOLD_SECONDS
			advance(approach + hold)
			check(player._chain == chain and player._index == first + 1, label + " first after publishes at release while next collision starts")
			check(board._action_offsets[a].is_equal_approx(axis * 28.0), label + " first body starts return from contact")
			if mode != "middle-dead": check(board._action_offsets[b].is_equal_approx(axis * 10.0), label + " second receives continuous pose without zero reset")
			check(board._presentation_visual(b).unit.hp == float(data.frames[first].after.units[b].hp), label + " only first collision HP is published")
			advance(approach * 0.5)
			var a_offset: Vector2 = board._action_offsets[a]
			check(a_offset.dot(axis) > 0.0 and a_offset.dot(axis) < 28.0, label + " first return overlaps next approach")
			if mode != "middle-dead": check(board._action_offsets[b].dot(axis) > 10.0 and board._action_offsets[b].dot(axis) < 28.0, label + " next body accelerates before first finishes return")
			else: check(board._action_offsets[b] == Vector2.ZERO and not board._presentation_visual(b).unit.alive, label + " dead middle stays still while receipt continues")
			check(board._view_unit_cell(a) == a_cell and board._view_unit_cell(b) == b_cell, label + " temporary chain poses never move logical cells")
			board.size += Vector2(12, 10)
			board.zoom_camera(0.75, board.size * 0.5)
			check(board._presentation_visual(a).action_offset.is_equal_approx(a_offset), label + " resize preserves overlapping poses")
			if direction == Vector2i.RIGHT: await capture(label + "-handover")
			advance(approach * 0.5 + hold + 0.025)
			if mode in ["open", "middle-dead"]:
				var last := board._presentation_visual(c)
				check(last.presentation_offset.length() > 0.0 and absf(board._action_offsets[a].dot(axis)) > 0.1, label + " terminal movement overlaps remaining return")
				check(board._action_offsets[c].dot(axis) > 0.0 and board._action_offsets[c].dot(axis) < 10.0, label + " incoming offset decays continuously during terminal movement")
			elif mode == "last-dead": check(not board._presentation_visual(c).unit.alive and board._action_offsets[c] == Vector2.ZERO, label + " dead terminal never moves")
			finish()
			check(started == data.frames, label + " every frame starts once in receipt order")
			var expected: Array[Dictionary] = []
			for frame: Dictionary in data.frames: expected.append(frame.after)
			expected.append(data.after)
			check(published == expected, label + " all after snapshots including empty steps publish in exact order")
			for id: int in [a, b, c]:
				check(board._presentation_visual(id).action_offset == Vector2.ZERO and board._view_unit_cell(id) == data.after.units[id].cell, label + " final poses zero and cells authoritative")
			check(snapshot(s) == state and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and data == immutable, label + " overlap is isolated from runtime RNG counters and receipt")
			player.frame_started.disconnect(on_start)
			player.frame_finished.disconnect(on_finish)
			if mode == "open" and direction == Vector2i.RIGHT:
				await chain_boundaries(data, first, a, b, axis)
			player.cancel()
			player.set_speed(1.0)
			board.size = viewport.size
			board.zoom_camera(1.0, board.size * 0.5)
			s.close()
			await process_frame

func chain_boundaries(data: Dictionary, first: int, a: int, b: int, axis: Vector2) -> void:
	for boundary: String in ["root", "actor", "gap", "reaction", "fault", "eventless-change"]:
		var frames: Array[Dictionary] = data.frames.duplicate(true)
		var next: Dictionary = frames[first + 1]
		match boundary:
			"root": next.events[0].root_id += 1
			"actor": next.events[0].actor_unit_id += 10
			"gap": next.step.command_seq += 1
			"reaction": next.step.kind = &"attack_hit"
			"fault": next.step.status = &"FAULTED"
			"eventless-change":
				next.events.clear()
		check(BattleChainTimeline.collect(frames, first).is_empty(), boundary + " cannot bridge unrelated or faulted frames")
	for interruption: String in ["finish", "skip", "cancel", "replay"]:
		player.set_speed(1.0)
		player.play(board, data.before, data.frames, data.after)
		player._tween.pause()
		seek_obstacle()
		advance(BattleDemoBoard.OBSTACLE_APPROACH_SECONDS + BattleDemoBoard.OBSTACLE_HOLD_SECONDS)
		player.set_speed(3.0)
		advance(BattleDemoBoard.OBSTACLE_APPROACH_SECONDS / 6.0)
		check(board._action_offsets[a].dot(axis) < 28.0 and board._action_offsets[b].dot(axis) > 10.0, interruption + " speed change advances both bodies on one clock")
		match interruption:
			"finish": finish()
			"skip": player.skip()
			"cancel": player.cancel()
			"replay":
				player.play(board, data.before, data.frames, data.after)
				player._tween.pause()
				finish()
		check(not player.active and board._action_offsets.is_empty(), interruption + " clears all overlapping poses")
		if interruption in ["skip", "cancel"]: check(board._impacts.get_child_count() == 0, interruption + " clears chain flashes")
	player.set_speed(1.0)

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	board.camera_controls_enabled = true
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	root.add_child(player)
	await process_frame
	absent_evidence()
	await balance_cases()
	await chain_cases()
	await armor_cases()
	await threshold_and_fault()
	await consecutive_roots()
	await obstacle_contacts()
	await chain_overlap()
	player.queue_free()
	viewport.queue_free()
	await process_frame
	print("PRESENTATION CONSEQUENCES RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
