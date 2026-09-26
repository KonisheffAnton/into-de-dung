extends SceneTree

var passed: int = 0
var failed: int = 0

class CallbackRng extends ActionRngPort:
	pass

class CallbackSink extends ActionEventSink:
	pass

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE EXECUTION: " + label)

func state(s: BattleCoreReactionsSession) -> Dictionary:
	return {"snapshot": ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict(), "rng": s.context.get_rng().to_dict(), "counters": s.context.simulation_counters(), "phase": s.phase, "selected": s.selected_id, "round": s.round_number, "flow": s.flow_log.duplicate(), "turn_events": s.turn_events.duplicate(true), "enemy_ids": s._enemy_ids.duplicate(), "enemy_index": s._enemy_index, "enemy_actions": s._enemy_actions}

func receipt(result: Variant) -> Variant:
	if not result is ActionReceipt: return result
	return {"status": result.status, "reason": result.reason, "events": result.get_events(), "steps": result.get_steps(), "before": result.revision_before, "after": result.revision_after}

func prepare(s: BattleCoreReactionsSession, kind: String) -> Array:
	match kind:
		"move": return [&"move_to", [Vector2i(1, 2)]]
		"attack", "rune", "entangle", "stun", "fault":
			s.select_unit(s.units[2].id)
			if kind == "rune": s.rune_selected = true
			if kind == "entangle": s.entangle_selected = true
			if kind == "stun":
				s.select_unit(s.units[0].id)
				s.board.move_unit(s.units[0], Vector2i(2, 3))
				s.stun_selected = true
			if kind == "fault": s._queue._max_commands = 1
			return [&"attack_unit", [s.units[3].id]]
		"guard": return [&"guard_selected", []]
		"opportunity": return [&"set_reaction_guard", [CombatPerksState.Mode.OPPORTUNIST]]
		"cover":
			s.board.move_unit(s.units[2], Vector2i(1, 2))
			return [&"set_reaction_guard", [CombatPerksState.Mode.COVER, s.units[2].id]]
		"heal":
			s.selected_unit().vitals.set_hp(10)
			return [&"use_healing_item", []]
		"summon": return [&"use_summoning_item", [Vector2i(0, 1)]]
		"raise": return [&"raise_corpse", [Vector2i(0, 3)]]
		"armor":
			for item: ItemInstance in s.state.get_owner(s.selected_id)._items.values():
				if item.get_definition().armor_max > 0: item.armor_remaining = 0
			return [&"restore_selected_armor", []]
		"refused":
			s.selected_unit().action_resources.try_spend_main(1)
			return [&"guard_selected", []]
		"end": return [&"end_player_turn", []]
		"enemy":
			s.end_player_turn()
			return [&"step_enemy", []]
	return []

func parity(kind: String) -> void:
	var initial_id := UnitId.get_counter()
	var s := BattleCoreReactionsSession.new()
	var request := prepare(s, kind)
	var expected: Variant = receipt(s.callv(request[0], request[1]))
	var expected_state := state(s)
	s.close()
	UnitId.set_counter(initial_id)
	s = BattleCoreReactionsSession.new()
	request = prepare(s, kind)
	var allocator := UnitId.get_counter()
	check(BattleExecutionWorker.can_transfer(s), kind + " graph owned")
	var worker := BattleExecutionWorker.new()
	check(worker.start(s, request[0], request[1]), kind + " started")
	var completed: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 10000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		completed = worker.take_finished()
		await create_timer(0.001).timeout
	if completed.is_empty():
		check(false, kind + " timeout")
		completed = worker.take_finished(true)
	check(receipt(completed.result) == expected, kind + " receipt/events/steps parity")
	check(state(s) == expected_state, kind + " full state/RNG/counters/session parity")
	check(UnitId.get_counter() == allocator, kind + " global allocator unchanged")
	check(not worker.is_started() and worker.take_finished().is_empty(), kind + " one completion")
	if kind == "fault": check(s.phase == BattleTacticalSession.Phase.FAULTED, "fault prefix remains terminal")
	s.close()

func callback() -> void: pass

func round_parity() -> void:
	var initial_id := UnitId.get_counter()
	var expected: Array[Dictionary] = []
	for threaded: bool in [false, true]:
		UnitId.set_counter(initial_id)
		var s := BattleCoreReactionsSession.new()
		s.end_player_turn()
		var index: int = 0
		while s.phase == BattleTacticalSession.Phase.ENEMY_TURN and index < 40:
			var result: Variant
			if threaded:
				var worker := BattleExecutionWorker.new()
				check(worker.start(s, &"step_enemy", []), "round step transfers owned graph")
				var completed := worker.take_finished(true)
				result = completed.result
			else:
				result = s.step_enemy()
			var actual := {"receipt": receipt(result), "state": state(s)}
			if threaded: check(index < expected.size() and actual == expected[index], "AI step / summon / player refill parity " + str(index))
			else: expected.append(actual)
			index += 1
		check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and index == expected.size(), "complete deterministic round")
		s.close()

func run() -> void:
	for kind: String in ["move", "attack", "rune", "entangle", "stun", "guard", "opportunity", "cover", "heal", "summon", "raise", "armor", "refused", "fault", "end", "enemy"]:
		await parity(kind)
	round_parity()
	var s := BattleCoreReactionsSession.new()
	check(BattleExecutionWorker.can_transfer(s), "normal session eligible")
	s.board.board_changed.connect(callback)
	check(not BattleExecutionWorker.can_transfer(s), "board listener falls back")
	s.board.board_changed.disconnect(callback)
	s.units[0].vitals.died.connect(callback)
	check(not BattleExecutionWorker.can_transfer(s), "external death listener falls back")
	s.units[0].vitals.died.disconnect(callback)
	s.units[0].bleeding.changed.connect(callback)
	check(not BattleExecutionWorker.can_transfer(s), "bleeding listener falls back")
	s.units[0].bleeding.changed.disconnect(callback)
	s.units[0].combat_perks.definition.changed.connect(callback)
	check(not BattleExecutionWorker.can_transfer(s), "resource listener falls back")
	s.units[0].combat_perks.definition.changed.disconnect(callback)
	check(BattleExecutionWorker.can_transfer(s), "no stale revision cache after callback removal")
	var rng := s.context._rng
	s.context._rng = CallbackRng.new()
	var refused := BattleExecutionWorker.new()
	check(not refused.start(s, &"guard_selected", []) and not refused.is_started(), "custom RNG never dispatched")
	s.context._rng = rng
	s.context._sink = CallbackSink.new()
	check(not refused.start(s, &"guard_selected", []), "custom event sink never dispatched")
	s.context._sink = ActionEventSink.new()
	check(not refused.start(s, &"reset", []) and not refused.start(s, &"attack_unit", [self]), "unknown method and non-value arguments refused")
	s._queue._pending.append({"command": self})
	check(not BattleExecutionWorker.can_transfer(s), "foreign object hidden in queue never dispatched")
	s._queue._pending.clear()
	s.close()
	print("BATTLE EXECUTION WORKER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
