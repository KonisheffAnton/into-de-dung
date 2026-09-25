extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SUMMON COMPOSITION: " + label)

func snapshot(session: BattleCoreCombinationSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	return result.snapshot.to_dict() if result.code == ItemSnapshotResult.Code.OK else {}

func item_command(session: BattleCoreCombinationSession, actor_id: int, cell: Vector2i) -> UseSummoningItemCommand:
	return UseSummoningItemCommand.new(actor_id, session.summoning_item(actor_id).get_item_instance_id(), cell, session.context.get_revision())

func assert_rejected_pure(session: BattleCoreCombinationSession, command: Command, reason: StringName, label: String) -> void:
	var before := snapshot(session)
	var counters := session.context.simulation_counters()
	var admission := SummonAdmission.values(session.context)
	var rng := session.context.get_rng().to_dict().duplicate(true)
	var actor_id := (command as UseSummoningItemCommand)._actor_id if command is UseSummoningItemCommand else (command as RaiseCorpseCommand)._actor_id
	var actor := session.board.get_unit_by_id(actor_id)
	var main_before := actor.action_resources.get_main_left() if actor != null else -1
	var item_before := session.summoning_item(actor.id).get_charges_left() if actor != null and session.summoning_item(actor.id) != null else -1
	var receipt := session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == reason, label + " reason=" + String(receipt.reason))
	check(snapshot(session) == before and counters == session.context.simulation_counters() and admission == SummonAdmission.values(session.context) and rng == session.context.get_rng().to_dict(), label + " runtime purity")
	check(actor != null and actor.action_resources.get_main_left() == main_before and session.summoning_item(actor.id) != null and session.summoning_item(actor.id).get_charges_left() == item_before, label + " no resource payment")

func _run() -> void:
	_test_preview_restore_and_live_parity()
	_test_refusal_gates()
	_test_mutual_exclusion()
	_test_player_helper_actions()
	_test_enemy_bt_helper_action()
	print("SUMMON COMPOSITION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_preview_restore_and_live_parity() -> void:
	var session := BattleCoreCombinationSession.new()
	var actor := session.units[0]
	actor.armor = ArmorState.new()
	actor.armor.natural["physical"] = 2
	actor.bleeding = BleedingState.new()
	var cmd := item_command(session, actor.id, Vector2i(0, 1))
	var before := snapshot(session)
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters()
	var admission_before := SummonAdmission.values(session.context)
	var first := ItemUseForecast.build(session.context, session._queue, cmd)
	var second := ItemUseForecast.build(session.context, session._queue, cmd.copy_for_queue())
	check(first.status == ActionReceipt.APPLIED and second.status == ActionReceipt.APPLIED, "two K2 forecasts admitted " + String(first.reason))
	check(first.snapshot_before == before and first.snapshot_after == second.snapshot_after and first.events == second.events and first.steps == second.steps, "two forecasts identical snapshots/events/steps")
	check(first.rng_after == second.rng_after and first.counters_after == second.counters_after and first.admission_before == second.admission_before and first.admission_after == second.admission_after, "two forecasts identical RNG/counters/admission")
	check(snapshot(session) == before and rng_before == session.context.get_rng().to_dict() and counters_before == session.context.simulation_counters() and admission_before == SummonAdmission.values(session.context), "forecast calls leave live runtime unchanged")
	var parsed := ItemSimulationSnapshot.from_dict(first.snapshot_after)
	var definitions: Dictionary = {}
	for owner in session.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := parsed.snapshot.instantiate(definitions) if parsed.code == ItemSnapshotResult.Code.OK else parsed
	check(restored.code == ItemSnapshotResult.Code.OK, "forecast snapshot restores with catalogue")
	if restored.code == ItemSnapshotResult.Code.OK:
		var forecast_before_mutation := first.snapshot_after.duplicate(true)
		var restored_helper := restored.state.active_summon(actor.id)
		check(restored_helper != null and restored_helper.armor != null and restored_helper.armor.natural == {"physical": 0, "fire": 0} and restored_helper.bleeding != null and restored.state.is_summon_pending(restored_helper.id), "restored helper has empty capabilities and pending state")
		restored_helper.vitals.set_hp(1.0)
		restored_helper.armor.natural["physical"] = 3
		check(snapshot(session) == before and first.snapshot_after == forecast_before_mutation, "mutating restore cannot affect live board/forecast DTO")
		AttackForecast._close(restored.state)
	var receipt := session._queue.submit(cmd, session.context)
	var helper := session.state.active_summon(actor.id)
	var after := snapshot(session)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == first.events and receipt.get_steps() == first.steps and after == first.snapshot_after, "direct K2 command matches forecast")
	check(session.context.get_rng().to_dict() == first.rng_after and session.context.simulation_counters() == first.counters_after and SummonAdmission.values(session.context) == first.admission_after, "direct K2 counters/RNG/admission match forecast")
	check(helper != null and helper.armor != null and helper.armor.in_battle and helper.armor.natural == {"physical": 0, "fire": 0} and helper.bleeding != null and helper.bleeding.ticks_left == 0, "summoned helper gets empty armor/bleeding runtime")
	session.close()

func _test_refusal_gates() -> void:
	var stun := BattleCoreCombinationSession.new()
	assert_rejected_pure(stun, item_command(stun, stun.units[4].id, Vector2i(5, 6)), &"control/stunned", "K2 stunned actor")
	stun.close()
	var occupied := BattleCoreCombinationSession.new()
	occupied.board.move_unit(occupied.units[2], Vector2i(0, 1))
	assert_rejected_pure(occupied, item_command(occupied, occupied.units[0].id, Vector2i(0, 1)), &"summon/invalid_cell", "occupied adjacent cell")
	occupied.close()
	var spikes := BattleCoreCombinationSession.new()
	spikes.board.set_terrain(Vector2i(0, 1), TerrainType.Type.HAZARD)
	assert_rejected_pure(spikes, item_command(spikes, spikes.units[0].id, Vector2i(0, 1)), &"summon/invalid_cell", "spike cell")
	spikes.close()
	var no_main := BattleCoreCombinationSession.new()
	no_main.units[0].action_resources.try_spend_main(1)
	assert_rejected_pure(no_main, item_command(no_main, no_main.units[0].id, Vector2i(0, 1)), &"item/insufficient_main", "no main action")
	no_main.close()
	var active := BattleCoreCombinationSession.new()
	var owner := active.units[0]
	check(active._queue.submit(item_command(active, owner.id, Vector2i(0, 1)), active.context).status == ActionReceipt.APPLIED, "active-helper refusal fixture")
	owner.try_refill_turn_resources()
	assert_rejected_pure(active, item_command(active, owner.id, Vector2i(0, 1)), &"summon/active_helper", "active helper cap")
	active.close()
	var fire := BattleCoreCombinationSession.new()
	fire.state.environment.ignite(Vector2i(4, 2))
	assert_rejected_pure(fire, item_command(fire, fire.units[2].id, Vector2i(4, 2)), &"summon/invalid_cell", "environment fire cell")
	fire.close()

func _test_mutual_exclusion() -> void:
	var seal_first := BattleCoreCombinationSession.new()
	var actor := seal_first.units[0]
	check(seal_first._queue.submit(item_command(seal_first, actor.id, Vector2i(0, 1)), seal_first.context).status == ActionReceipt.APPLIED, "seal->raise summon succeeds")
	actor.try_refill_turn_resources()
	var raise_cmd := seal_first._raise_command(Vector2i(0, 3))
	var before := snapshot(seal_first)
	var counters := seal_first.context.simulation_counters()
	var raise_result := seal_first._queue.submit(raise_cmd, seal_first.context)
	check(raise_result.status == ActionReceipt.REJECTED and raise_result.reason == &"summon/active_helper" and snapshot(seal_first) == before and counters == seal_first.context.simulation_counters(), "seal->raise exclusion without cost")
	seal_first.close()
	var raise_first := BattleCoreCombinationSession.new()
	var raiser := raise_first.units[0]
	var raised := raise_first._queue.submit(raise_first._raise_command(Vector2i(0, 3)), raise_first.context)
	check(raised.status == ActionReceipt.APPLIED, "raise->seal raise succeeds")
	raiser.try_refill_turn_resources()
	var seal_before := snapshot(raise_first)
	var seal_counters := raise_first.context.simulation_counters()
	var seal_after_raise := raise_first._queue.submit(item_command(raise_first, raiser.id, Vector2i(0, 1)), raise_first.context)
	check(seal_after_raise.status == ActionReceipt.REJECTED and seal_after_raise.reason == &"summon/active_helper" and snapshot(raise_first) == seal_before and seal_counters == raise_first.context.simulation_counters(), "raise->seal exclusion without cost")
	raise_first.close()

func _test_player_helper_actions() -> void:
	var session := BattleCoreCombinationSession.new()
	var owner := session.units[0]
	owner.armor = ArmorState.new()
	owner.bleeding = BleedingState.new()
	var receipt := session._queue.submit(item_command(session, owner.id, Vector2i(0, 1)), session.context)
	var helper := session.state.active_summon(owner.id)
	check(receipt.status == ActionReceipt.APPLIED and helper != null and session.state.is_summon_pending(helper.id), "player helper pending")
	check(session.end_player_turn(), "player turn reaches enemy boundary")
	for _i in 40:
		if session.phase != BattleCoreCombinationSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	check(session.phase == BattleCoreCombinationSession.Phase.PLAYER_TURN and helper != null and not session.state.is_summon_pending(helper.id), "helper activates at next owner turn")
	if helper != null:
		var target := session.units[1]
		var attack_cell := Vector2i(1, 0)
		if not session.board.is_in_bounds(attack_cell) or session.board.is_occupied(attack_cell): attack_cell = Vector2i(0, 0)
		if session.board.is_in_bounds(attack_cell) and not session.board.is_occupied(attack_cell):
			session.board.move_unit(target, attack_cell)
			session.select_unit(helper.id)
			var move := session.move_to(Vector2i(0, 0))
			check(move.status == ActionReceipt.APPLIED and helper.armor != null and helper.bleeding != null, "activated armored helper moves through command")
			if absi(helper.cell.x - target.cell.x) + absi(helper.cell.y - target.cell.y) == 1:
				var attack := session.attack_unit(target.id)
				check(attack.status == ActionReceipt.APPLIED, "activated armored helper attacks through command")
			else:
				check(false, "test setup places attack target adjacent")
	session.close()

func _test_enemy_bt_helper_action() -> void:
	var session := BattleCoreCombinationSession.new()
	var player := session.units[0]
	check(session.end_player_turn(), "first enemy BT turn starts")
	for _i in 40:
		if session.phase != BattleCoreCombinationSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	check(session.phase == BattleCoreCombinationSession.Phase.PLAYER_TURN, "stunned enemy turn completes")
	check(session.end_player_turn(), "enemy BT turn starts after stun expiry")
	var summoned: UnitState = null
	for _i in 40:
		if session.phase != BattleCoreCombinationSession.Phase.ENEMY_TURN: break
		var receipt := session.step_enemy()
		if receipt == null: continue
		for event: Dictionary in receipt.get_events():
			if event["kind"] == &"summoned": summoned = session.board.get_unit_by_id(event["target_unit_id"])
	check(summoned != null and session.state.is_summon_pending(summoned.id), "enemy BT summons pending helper")
	for _i in 40:
		if session.phase != BattleCoreCombinationSession.Phase.ENEMY_TURN: break
		session.step_enemy()
	check(session.phase == BattleCoreCombinationSession.Phase.PLAYER_TURN, "enemy phase completes")
	if summoned != null:
		var target_cell := summoned.cell + Vector2i(0, 1)
		if not session.board.is_in_bounds(target_cell) or session.board.is_occupied(target_cell): target_cell = summoned.cell + Vector2i(1, 0)
		if session.board.is_in_bounds(target_cell) and not session.board.is_occupied(target_cell): session.board.move_unit(player, target_cell)
	check(session.end_player_turn(), "next round enemy turn starts")
	var acted := false
	for _i in 40:
		if session.phase != BattleCoreCombinationSession.Phase.ENEMY_TURN: break
		var receipt := session.step_enemy()
		if receipt == null: continue
		for event: Dictionary in receipt.get_events():
			if summoned != null and event["actor_unit_id"] == summoned.id and event["kind"] in [&"moved", &"attacked"]: acted = true
	check(summoned != null and not session.state.is_summon_pending(summoned.id) and acted, "enemy helper acts via BT after next-round admission")
	session.close()
