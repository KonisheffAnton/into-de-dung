extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SUMMON: " + label)

func snap(s: BattleTacticalSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "capture " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func command(s: BattleTacticalSession, cell: Vector2i = Vector2i(0, 1)) -> UseSummoningItemCommand:
	return UseSummoningItemCommand.new(s.selected_id, s.summoning_item().get_item_instance_id(), cell, s.context.get_revision())

func refuse(s: BattleTacticalSession, cmd: Command, reason: StringName) -> void:
	var before := snap(s)
	var counters := s.context.simulation_counters()
	var rules := SummonAdmission.values(s.context)
	var rng := s.context.get_rng().to_dict()
	var receipt := s._queue.submit(cmd, s.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == reason, "reject " + String(reason) + ": " + String(receipt.reason))
	check(snap(s) == before and counters == s.context.simulation_counters() and rules == SummonAdmission.values(s.context) and rng == s.context.get_rng().to_dict(), "rejection pure")

func _run() -> void:
	_test_spawn()
	_test_refusals()
	_test_pending_and_turn()
	_test_death_outcome_cleanup()
	_test_enemy()
	_test_forecast()
	_test_helper_forecasts()
	_test_faults()
	print("SUMMON RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_spawn() -> void:
	var s := BattleTacticalSession.new()
	var actor := s.selected_unit()
	var seal := s.summoning_item()
	var flask := s.healing_item()
	actor.guard_stance = true
	var old := snap(s)
	var last := s.last_receipt
	check(s.summoning_reason() == &"" and snap(s) == old and s.last_receipt == last, "availability pure")
	var global_id := UnitId.get_counter()
	var seen: Array[bool] = []
	var callback := func() -> void:
		var helper := s.state.active_summon(actor.id)
		seen.append(helper != null and s.board.occupant_at(Vector2i(0, 1)) == helper and s.state.get_owner(helper.id).get_owner() == helper and s.state.get_inventory(helper.id) != null and seal.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0)
	s.board.board_changed.connect(callback)
	var stale := command(s)
	var receipt := s.use_summoning_item(Vector2i(0, 1))
	s.board.board_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.APPLIED, "spawn applied " + String(receipt.reason))
	var helper := s.state.active_summon(actor.id)
	check(helper != null, "helper registered")
	if helper == null:
		s.close()
		return
	check(s.units.size() == 7 and s.units.has(helper) and s.state.get_owners().size() == 7 and seen == [true], "full admission before callback")
	check(helper.vitals.get_hp() == 16.0 and helper.faction == actor.faction and s.state.is_summon_pending(helper.id), "helper stats/faction/pending")
	check(helper.move_points_left == 0.0 and helper.action_resources.get_main_left() == 0 and helper.action_resources.get_bonus_left() == 0, "no initial resources")
	check(actor.guard_stance and actor.move_points_left == 5.0 and actor.action_resources.get_bonus_left() == 1 and not actor.has_attacked and flask.get_charges_left() == 2, "preserve stance/other resources/flask")
	check(receipt.get_steps().size() == 1 and receipt.get_events().size() == 2 and receipt.get_events()[1]["kind"] == &"summoned" and receipt.revision_after == 1 and UnitId.get_counter() == global_id, "atomic events/revision/no allocator")
	check(not s.context.get_move_rules().allows(helper.id) and s.context.get_attack_rules().allows(s.units[1].id, helper.id) and not s.context.get_attack_rules().allows(helper.id, s.units[1].id), "immediate target admission only")
	refuse(s, stale, &"item/stale_revision")
	actor.try_refill_turn_resources()
	refuse(s, command(s), &"summon/active_helper")
	check(s.select_unit(s.units[2].id) and s.summoning_item().get_charges_left() == 2, "second owner has independent seal")
	check(s.use_summoning_item(Vector2i(2, 4)).status == ActionReceipt.APPLIED and s.units.size() == 8, "two owners can each summon")
	s.close()

func _test_refusals() -> void:
	var s := BattleTacticalSession.new()
	for cell: Vector2i in [Vector2i(-1, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(4, 2), Vector2i(1, 1)]:
		refuse(s, command(s, cell), &"summon/invalid_cell")
	s.board.set_terrain(Vector2i(0, 1), TerrainType.Type.HAZARD)
	refuse(s, command(s), &"summon/invalid_cell")
	s.board.set_terrain(Vector2i(0, 1), TerrainType.Type.WALL)
	refuse(s, command(s), &"summon/invalid_cell")
	s.board.set_terrain(Vector2i(0, 1), TerrainType.Type.VOID)
	refuse(s, command(s), &"summon/invalid_cell")
	s.board.set_terrain(Vector2i(0, 1), TerrainType.Type.FLOOR)
	var actor := s.selected_unit()
	var seal := s.summoning_item()
	actor.action_resources.try_spend_main(1)
	refuse(s, command(s), &"item/insufficient_main")
	check(actor.action_resources.get_bonus_left() == 1, "bonus cannot pay main")
	actor.try_refill_turn_resources()
	seal._charges_left = 0
	refuse(s, command(s), &"item/no_charges")
	seal._charges_left = 2
	s.state.get_inventory(actor.id).remove_item(seal)
	refuse(s, UseSummoningItemCommand.new(actor.id, seal.get_item_instance_id(), Vector2i(0, 1), s.context.get_revision()), &"item/inactive")
	s.state.get_inventory(actor.id).add_item(seal)
	refuse(s, UseSummoningItemCommand.new(actor.id, 999, Vector2i(0, 1), s.context.get_revision()), &"item/not_owned")
	refuse(s, UseSummoningItemCommand.new(actor.id, s.healing_item().get_item_instance_id(), Vector2i(0, 1), s.context.get_revision()), &"item/not_usable")
	refuse(s, UseHealingItemCommand.new(actor.id, seal.get_item_instance_id(), s.context.get_revision()), &"item/not_usable")
	check(s.end_player_turn() and s.use_summoning_item(Vector2i(0, 1)).reason == &"battle/input_locked", "phase gate")
	s.close()

func _test_pending_and_turn() -> void:
	var s := BattleTacticalSession.new()
	var owner := s.selected_unit()
	var seal := s.summoning_item()
	check(s.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "pending fixture")
	var helper := s.state.active_summon(owner.id)
	if helper == null:
		s.close()
		return
	check(s.select_unit(helper.id) and s.selected_unit() == helper and helper.action_resources.get_main_left() == 0, "player can select pending without refill")
	check(s.guard_selected().status == ActionReceipt.REJECTED and s.move_to(Vector2i(0, 0)).status == ActionReceipt.REJECTED, "pending rejects guard/move")
	helper.try_refill_turn_resources()
	check(s.state.is_summon_pending(helper.id) and not s.context.get_move_rules().allows(helper.id) and not s.context.get_attack_rules().allows(helper.id, s.units[1].id), "technical refill cannot grant admission")
	helper.action_resources._set_for_refill(0, 0)
	helper.move_points_left = 0.0
	check(s.end_player_turn() and s.state.is_summon_pending(helper.id), "other team does not activate helper")
	for _step in 40:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and not s.state.is_summon_pending(helper.id) and helper.action_resources.get_main_left() == 1 and helper.move_points_left == 4.0, "next own turn ready/refill")
	check(s.select_unit(helper.id) and s.move_to(Vector2i(0, 0)).status == ActionReceipt.APPLIED and s.guard_selected().status == ActionReceipt.APPLIED, "ready helper obeys player move/guard")
	check(seal.get_charges_left() == 1, "turn did not refill seal even after owner death")
	s.close()

func _test_death_outcome_cleanup() -> void:
	var s := BattleTacticalSession.new()
	var owner := s.selected_unit()
	s.use_summoning_item(Vector2i(0, 1))
	var helper := s.state.active_summon(owner.id)
	if helper == null:
		s.close()
		return
	helper.vitals.apply_damage(100.0)
	check(s.board.occupant_at(helper.cell) == null and s.state.active_summon(owner.id) == null, "death clears occupancy/limit")
	owner.try_refill_turn_resources()
	check(s.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED and s.summoning_item().get_charges_left() == 0, "replacement uses final charge")
	var replacement := s.state.active_summon(owner.id)
	for unit in s.units:
		if unit.faction == Faction.Type.PLAYER and unit != replacement: unit.vitals.apply_damage(100.0)
	s._check_outcome()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and s.living_ids(Faction.Type.PLAYER) == [replacement.id] and s.selected_id == replacement.id, "last helper preserves team after owner death")
	replacement.vitals.apply_damage(100.0)
	s._check_outcome()
	check(s.phase == BattleTacticalSession.Phase.DEFEAT, "last helper death loses battle")
	var owners := s.state.get_owners()
	var board := s.board
	s.reset()
	check(s.units.size() == 6 and s.state.get_summons().is_empty() and s.summoning_item().get_charges_left() == 2 and board.get_all_units().is_empty(), "reset fresh roster/charges/board")
	for old in owners: check(old.is_closed(), "old helper owner closed")
	s.close()

func _test_enemy() -> void:
	var s := BattleTacticalSession.new()
	var enemy := s.units[1]
	s.board.move_unit(enemy, Vector2i(4, 1))
	check(s.end_player_turn(), "enemy starts")
	var before := snap(s)
	var intent := BattleDemoBT.new().decide(s, enemy)
	check(intent.kind == BattleAIIntent.Kind.SUMMON and snap(s) == before, "BT pure summon intention")
	var receipt := s.step_enemy()
	check(receipt != null and receipt.status == ActionReceipt.APPLIED and receipt.get_events()[1]["kind"] == &"summoned", "enemy summons through queue")
	var helper := s.state.active_summon(enemy.id)
	if helper == null:
		s.close()
		return
	check(not s._enemy_ids.has(helper.id) and s.state.is_summon_pending(helper.id), "new enemy excluded from current turn")
	for _step in 40:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	# Свободная соседняя цель делает обязательный сценарий атаки помощника однозначным.
	s.board.move_unit(s.units[0], Vector2i(3, 0))
	s.board.move_unit(helper, Vector2i(3, 1))
	check(s.end_player_turn() and s._enemy_ids.has(helper.id) and not s.state.is_summon_pending(helper.id), "enemy helper admitted next turn")
	var acted := false
	for _step in 40:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		receipt = s.step_enemy()
		if receipt == null: continue
		for event in receipt.get_events():
			if event["actor_unit_id"] == helper.id and event["kind"] in [&"moved", &"attacked"]: acted = true
	check(acted, "enemy helper executes real BT action next turn")
	s.close()

func _test_forecast() -> void:
	var s := BattleTacticalSession.new()
	s.use_summoning_item(Vector2i(0, 1))
	var helper := s.state.active_summon(s.selected_id)
	if helper == null:
		s.close()
		return
	s.select_unit(s.units[2].id)
	var before := snap(s)
	var counters := s.context.simulation_counters()
	var rules := SummonAdmission.values(s.context)
	var id_counter := UnitId.get_counter()
	var forecast := s.preview_attack(s.units[3].id)
	check(forecast.status == ActionReceipt.APPLIED and forecast.units.has(helper.id), "forecast includes pending helper " + String(forecast.reason))
	check(snap(s) == before and counters == s.context.simulation_counters() and rules == SummonAdmission.values(s.context) and UnitId.get_counter() == id_counter, "forecast live isolation")
	var receipt := s.attack_unit(s.units[3].id)
	check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snap(s) == forecast.snapshot_after and s.context.simulation_counters() == forecast.counters_after, "full summoned snapshot forecast parity")
	s.close()

func _test_faults() -> void:
	var s := BattleTacticalSession.new()
	s._queue = ActionQueue.new(1, 1, 1)
	var receipt := s.use_summoning_item(Vector2i(0, 1))
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"event_limit" and receipt.get_events().size() == 2 and s.units.size() == 7 and s.units[0].action_resources.get_main_left() == 0, "limit preserves atomic spawn/payment prefix")
	s.close()
	s = BattleTacticalSession.new()
	var actor := s.selected_unit()
	var seal := s.summoning_item()
	var cb := func() -> void: actor.move_points_left -= 1.0
	s.board.board_changed.connect(cb)
	receipt = s.use_summoning_item(Vector2i(0, 1))
	s.board.board_changed.disconnect(cb)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"summon/invalid_mutation" and receipt.get_events().size() == 2 and s.units.size() == 7 and seal.get_charges_left() == 1, "callback preserves spawn/payment with fault")
	s.close()
	s = BattleTacticalSession.new()
	s.context._busy = true
	refuse(s, command(s), &"BUSY")
	s.context._busy = false
	s.context._faulted = true
	refuse(s, command(s), &"CONTEXT_FAULTED")
	s.context._faulted = false
	s.close()

func _test_helper_forecasts() -> void:
	for pending_target in [true, false]:
		var s := BattleTacticalSession.new()
		s.use_summoning_item(Vector2i(0, 1))
		var helper := s.state.active_summon(s.selected_id)
		if helper == null:
			check(false, "helper forecast fixture")
			s.close()
			continue
		var enemy := s.units[1]
		s.board.move_unit(enemy, Vector2i(1, 1))
		if not pending_target: check(s._refill(Faction.Type.PLAYER), "activate helper for attack parity")
		var actor := enemy if pending_target else helper
		var target := helper if pending_target else enemy
		var cmd := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision())
		var before := snap(s)
		var rng := s.context.get_rng().to_dict()
		var forecast := AttackForecast.build(s.context, s._queue, cmd)
		var repeated := AttackForecast.build(s.context, s._queue, cmd)
		check(forecast.status == ActionReceipt.APPLIED and repeated.snapshot_after == forecast.snapshot_after and snap(s) == before, "helper actor/target repeated isolated forecast " + String(forecast.reason))
		var receipt := s._submit(cmd)
		check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snap(s) == forecast.snapshot_after and s.context.simulation_counters() == forecast.counters_after and s.context.get_rng().to_dict() == forecast.rng_after and rng == forecast.rng_after, "helper actor/target complete forecast parity")
		check(not helper.is_alive() if pending_target else helper.action_resources.get_main_left() == 0, "pending helper can die / ready helper spends main")
		s.close()
