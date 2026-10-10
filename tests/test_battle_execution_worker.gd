extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

class CallbackRng extends ActionRngPort:
	pass

class CallbackSink extends ActionEventSink:
	pass

class FailedLaunchWorker extends BattleExecutionWorker:
	func _start_thread(_args: Array) -> Error:
		return ERR_CANT_CREATE

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
	var s := PlayerTurnFixture.create()
	var request := prepare(s, kind)
	var expected: Variant = receipt(s.callv(request[0], request[1]))
	var expected_state := state(s)
	s.close()
	UnitId.set_counter(initial_id)
	s = PlayerTurnFixture.create()
	request = prepare(s, kind)
	var allocator := UnitId.get_counter()
	check(BattleExecutionWorker.can_transfer(s), kind + " graph owned")
	var worker := BattleExecutionWorker.new()
	check(worker.start(s, request[0], request[1]), kind + " started")
	check(worker.take_presentation_before().is_empty(), kind + " default presentation before empty")
	var completed: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 10000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		completed = worker.take_finished()
		await create_timer(0.001).timeout
	if completed.is_empty():
		check(false, kind + " timeout")
		completed = worker.take_finished(true)
	check(not s._queue.capture_presentation, kind + " default presentation capture unchanged")
	check(receipt(completed.result) == expected, kind + " receipt/events/steps parity")
	check(state(s) == expected_state, kind + " full state/RNG/counters/session parity")
	check(UnitId.get_counter() == allocator, kind + " global allocator unchanged")
	check(not worker.is_started() and worker.take_finished().is_empty(), kind + " one completion")
	if kind == "fault": check(s.phase == BattleTacticalSession.Phase.FAULTED, "fault prefix remains terminal")
	s.close()

func presentation_parity(kind: String) -> void:
	var initial_id := UnitId.get_counter()
	var s := PlayerTurnFixture.create()
	var request := prepare(s, kind)
	var expected_before := ActionPresentationState.capture(s.state).duplicate(true)
	s.begin_presentation_capture()
	var expected_result: Variant = receipt(s.callv(request[0], request[1]))
	var expected_packets := s.take_presentation_capture()
	var expected_state := state(s)
	s.close()
	UnitId.set_counter(initial_id)
	s = PlayerTurnFixture.create()
	request = prepare(s, kind)
	var worker := BattleExecutionWorker.new()
	check(worker.start(s, request[0], request[1], false, true), kind + " capture worker started")
	var actual_before := worker.take_presentation_before()
	check(actual_before == expected_before, kind + " detached before snapshot parity")
	var completed := worker.take_finished(true)
	check(receipt(completed.result) == expected_result, kind + " capture receipt parity")
	check(s.take_presentation_capture() == expected_packets, kind + " ordered root presentation parity")
	check(state(s) == expected_state, kind + " capture full state/RNG/counters parity")
	check(worker.take_presentation_before().is_empty(), kind + " before snapshot transfers once")
	s.close()

func presentation_refusals_and_fallback() -> void:
	var s := PlayerTurnFixture.create()
	var worker := BattleExecutionWorker.new()
	check(not worker.start(s, &"reset", [], false, true), "invalid request refused")
	check(worker.take_presentation_before().is_empty() and not s._queue.capture_presentation, "invalid request has no capture mutation")
	var rng := s.context._rng
	s.context._rng = CallbackRng.new()
	check(not worker.start(s, &"guard_selected", [], false, true), "custom RNG transfer refused")
	check(worker.take_presentation_before().is_empty() and not s._queue.capture_presentation, "custom RNG refusal has no capture")
	s.context._rng = rng
	s.board.board_changed.connect(callback)
	check(not worker.start(s, &"guard_selected", [], false, true), "custom board callback transfer refused")
	check(worker.take_presentation_before().is_empty() and not s._queue.capture_presentation, "callback refusal has no capture")
	s.board.board_changed.disconnect(callback)
	s._queue._pending.append({"foreign": self})
	check(not worker.start(s, &"guard_selected", [], false, true), "foreign queued object transfer refused")
	check(worker.take_presentation_before().is_empty() and not s._queue.capture_presentation, "foreign graph refusal has no capture")
	s._queue._pending.clear()
	s.close()

	s = PlayerTurnFixture.create()
	var request := prepare(s, "guard")
	var initial_state := state(s)
	var expected_before := ActionPresentationState.capture(s.state).duplicate(true)
	var failed := FailedLaunchWorker.new()
	check(not failed.start(s, request[0], request[1], false, true), "simulated thread launch failure")
	var transferred_before := failed.take_presentation_before()
	check(transferred_before == expected_before, "launch failure retains before snapshot")
	check(s._queue.capture_presentation and state(s) == initial_state, "launch failure leaves capture armed before fallback")
	var fallback_result: ActionReceipt = s.callv(request[0], request[1])
	var fallback_packets := s.take_presentation_capture()
	check(fallback_result.status == ActionReceipt.APPLIED and fallback_packets.size() == 1, "launch failure synchronous fallback records one packet")
	check(failed.take_presentation_before().is_empty() and state(s) != initial_state, "fallback consumes retained packet exactly once")
	s.close()

func presentation_before_replaced() -> void:
	var s := PlayerTurnFixture.create()
	var worker := BattleExecutionWorker.new()
	check(worker.start(s, &"guard_selected", [], false, true), "first capture-enabled start")
	var first := worker.take_presentation_before()
	worker.take_finished(true)
	s.take_presentation_capture()
	s.units[0].vitals.set_hp(1)
	check(worker.start(s, &"guard_selected", [], false, true), "fresh capture-enabled start")
	var second := worker.take_presentation_before()
	check(second != first, "fresh start replaces prior before metadata")
	worker.take_finished(true)
	s.close()

func callback() -> void: pass

func fresh_same_script_objects() -> void:
	var s := PlayerTurnFixture.create()
	check(BattleExecutionWorker.can_transfer(s), "same-script fixture initially eligible")
	# Поля одного script описываются один раз, но значения всех экземпляров
	# и добавленные каждому из них сигналы обязаны проверяться в том же аудите.
	for unit: UnitState in s.units:
		var stats := unit.stats
		var original: Variant = stats._stats[StatTypes.StatType.HP_MAX]
		stats._stats[StatTypes.StatType.HP_MAX] = self
		check(not BattleExecutionWorker.can_transfer(s), "foreign field on every same-script instance refused")
		stats._stats[StatTypes.StatType.HP_MAX] = original
		check(BattleExecutionWorker.can_transfer(s), "restored instance read without revision change")
		stats.add_user_signal(&"audit_probe_signal")
		stats.connect(&"audit_probe_signal", callback)
		check(not BattleExecutionWorker.can_transfer(s), "instance-added signal listener refused")
		stats.disconnect(&"audit_probe_signal", callback)
		check(BattleExecutionWorker.can_transfer(s), "removed instance listener read fresh")
	s.close()

func round_parity() -> void:
	var initial_id := UnitId.get_counter()
	var expected: Array[Dictionary] = []
	for threaded: bool in [false, true]:
		UnitId.set_counter(initial_id)
		var s := PlayerTurnFixture.create()
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
	for kind: String in ["guard", "refused", "fault", "end", "enemy"]:
		presentation_parity(kind)
	presentation_refusals_and_fallback()
	presentation_before_replaced()
	fresh_same_script_objects()
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
