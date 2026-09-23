extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		printerr("FAIL INITIATIVE: " + label)

func _run() -> void:
	var battle := BattleInitiativeSession.new()
	_check(battle.turn_order_ids.size() == 6 and battle.current_actor_id == battle.units[0].id, "initial initiative roster")
	_check(battle.units[0].get_stat(StatTypes.StatType.INITIATIVE) == 60.0 and battle.units[5].get_stat(StatTypes.StatType.INITIATIVE) == 10.0, "fixture initiatives")
	var actor := battle.current_actor()
	var revision := battle.context.get_revision()
	_check(not battle.select_unit(battle.units[2].id) and battle.selected_unit() == actor, "cannot select another ally")
	_check(battle.context.get_revision() == revision and actor.action_resources.get_main_left() == 1, "selection does not refill")
	battle.selected_id = battle.units[2].id
	_check(not battle.can_player_act() and battle.move_to(Vector2i(1, 2)).status == ActionReceipt.REJECTED, "forged selected id cannot authorize actions")
	_check(battle.attack_unit(battle.units[1].id).status == ActionReceipt.REJECTED and not battle.end_player_turn(), "forged selected id cannot attack or pass")
	_check(battle.select_unit(actor.id) and battle.can_player_act(), "current actor can restore selection after forged id")
	battle.board.move_unit(actor, Vector2i(3, 2))
	var live_before := battle.board.to_snapshot_dict()
	var forecast := battle.preview_attack(battle.units[1].id)
	var after_forecast := battle.board.to_snapshot_dict()
	var attack_receipt := battle.attack_unit(battle.units[1].id)
	_check(forecast.status == ActionReceipt.APPLIED and attack_receipt.status == ActionReceipt.APPLIED, "individual attack forecast and live execution apply")
	_check(live_before == after_forecast and battle.units[1].vitals.get_hp() == float(forecast.units[battle.units[1].id]["after"]["hp"]), "forecast matches live result without mutating live state")
	battle.context._busy = true
	_check(not battle.can_player_act() and not battle.end_player_turn(), "busy queue locks actor input")
	battle.context._busy = false
	var teammate := battle.units[2]
	teammate.action_resources.try_spend_main(1)
	_check(battle.end_player_turn() and battle.current_actor_id == battle.units[1].id, "player actor passes to enemy")
	_check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "enemy initiative phase")
	_check(teammate.action_resources.get_main_left() == 0, "other teammate resources remain spent")
	for _step in 5:
		if battle.current_actor_id == teammate.id: break
		battle.step_enemy()
	_check(battle.current_actor_id == teammate.id and teammate.action_resources.get_main_left() == 1, "actor refills only on personal activation")
	var stable := battle.turn_order_ids.duplicate()
	var tied: Array[UnitState] = battle.units.duplicate()
	for unit in tied: unit.stats.set_base_value(StatTypes.StatType.INITIATIVE, 25.0)
	var tie_order := SimpleInitiativeStrategy.new().compute_order(tied)
	_check(tie_order[0].id < tie_order[1].id, "initiative ties use stable unit id")
	battle.units[0].stats.set_base_value(StatTypes.StatType.INITIATIVE, 5.0)
	for _step in 30:
		if battle.round_number != 1: break
		if battle.phase == BattleTacticalSession.Phase.ENEMY_TURN:
			battle.step_enemy()
		elif battle.current_actor() != null and battle.current_actor().faction == Faction.Type.PLAYER:
			battle.end_player_turn()
	_check(battle.round_number == 2 and battle.turn_order_ids != stable, "round boundary recomputes initiative")
	var grouped := BattleInitiativeSession.new()
	grouped.individual_turns = false
	grouped.reset()
	var grouped_actor := grouped.selected_unit()
	_check(grouped.select_unit(grouped.units[2].id), "team mode retains ally switching")
	grouped.units[2].action_resources.try_spend_main(1)
	_check(grouped.end_player_turn() and grouped.phase == BattleTacticalSession.Phase.ENEMY_TURN, "team mode retains team turn transition")
	_check(grouped_actor.action_resources.get_main_left() == 1 and grouped.units[2].action_resources.get_main_left() == 0, "team selection does not refill allies")
	for _step in 20:
		if grouped.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		grouped.step_enemy()
	_check(grouped.phase == BattleTacticalSession.Phase.PLAYER_TURN and grouped.units[2].action_resources.get_main_left() == 1, "team mode refills together at boundary")
	var death_skip := BattleInitiativeSession.new()
	var skip_target := death_skip.units[1]
	var source := DamageSource.new(&"test")
	var death_receipt := death_skip._submit(DamageCommand.new(DamageRequest.new(skip_target.id, 1000.0, &"physical", &"bypass", source)))
	_check(death_receipt.status == ActionReceipt.APPLIED and not skip_target.is_alive(), "queued damage removes future actor")
	_check(death_skip.end_player_turn() and death_skip.current_actor_id == death_skip.units[2].id, "dead roster entry is skipped without hanging")
	death_skip.close()
	var actor_death := BattleInitiativeSession.new()
	var dying_id := actor_death.current_actor_id
	var dying := actor_death.current_actor()
	var actor_death_receipt := actor_death._submit(DamageCommand.new(DamageRequest.new(dying_id, 1000.0, &"physical", &"bypass", DamageSource.new(&"test"))))
	_check(actor_death_receipt.status == ActionReceipt.APPLIED and not dying.is_alive(), "current actor death resolves through queue")
	_check(actor_death.current_actor_id == actor_death.units[1].id and actor_death.phase == BattleTacticalSession.Phase.ENEMY_TURN, "death advances after queue drain")
	actor_death.context._faulted = true
	_check(not actor_death.can_player_act() and actor_death.end_player_turn() == false, "faulted context locks turn input")
	actor_death.reset()
	_check(actor_death.phase == BattleTacticalSession.Phase.PLAYER_TURN and actor_death.round_number == 1, "reset rebuilds initiative runtime")
	actor_death.close()
	var guard_battle := BattleInitiativeSession.new()
	var guarding_id := guard_battle.current_actor_id
	_check(guard_battle.guard_selected().status == ActionReceipt.APPLIED and guard_battle.current_actor().guard_stance, "guard applies for current actor")
	for _step in guard_battle.turn_order_ids.size(): guard_battle._advance_actor()
	_check(guard_battle.current_actor_id == guarding_id and not guard_battle.current_actor().guard_stance, "guard expires at that actor next activation")
	guard_battle.close()
	var summon_battle := BattleInitiativeSession.new()
	var summoner := summon_battle.current_actor()
	var summon_receipt := summon_battle.use_summoning_item(summon_battle.summoning_cells(summoner.id)[0])
	var helper := summon_battle.state.active_summon(summoner.id)
	_check(summon_receipt.status == ActionReceipt.APPLIED and helper != null, "summon command admits helper")
	helper.stats.set_base_value(StatTypes.StatType.INITIATIVE, 1000.0)
	_check(not summon_battle.turn_order_ids.has(helper.id) and summon_battle.state.is_summon_pending(helper.id), "new summon waits for next roster")
	summon_battle.end_player_turn()
	for _step in 40:
		if summon_battle.round_number > 1 or summon_battle.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION, BattleTacticalSession.Phase.FAULTED]: break
		if summon_battle.phase == BattleTacticalSession.Phase.ENEMY_TURN: summon_battle.step_enemy()
		else: summon_battle.end_player_turn()
	_check(summon_battle.turn_order_ids.has(helper.id), "summoned unit joins next round")
	for _step in 40:
		if summon_battle.current_actor_id == helper.id or summon_battle.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION, BattleTacticalSession.Phase.FAULTED]: break
		if summon_battle.phase == BattleTacticalSession.Phase.ENEMY_TURN: summon_battle.step_enemy()
		else: summon_battle.end_player_turn()
	_check(summon_battle.current_actor_id == helper.id and not summon_battle.state.is_summon_pending(helper.id), "summon pending clears at own activation")
	summon_battle.close()
	var stress := BattleInitiativeSession.new()
	var ai := BattleDemoBT.new()
	for _step in 360:
		if stress.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION, BattleTacticalSession.Phase.FAULTED]: break
		var current := stress.current_actor()
		if current == null: continue
		if current.faction == Faction.Type.ENEMY:
			stress.step_enemy()
			continue
		var actor_id := current.id
		for _action in 2:
			current = stress.current_actor()
			if current == null or current.id != actor_id: break
			var intent := ai.decide(stress, current)
			if intent.kind == BattleAIIntent.Kind.WAIT: break
			var receipt: ActionReceipt
			if intent.kind == BattleAIIntent.Kind.ATTACK: receipt = stress.attack_unit(intent.target_id)
			elif intent.kind == BattleAIIntent.Kind.SUMMON: receipt = stress.use_summoning_item(intent.cell)
			else: receipt = stress.move_to(intent.path.back())
			if receipt == null or receipt.status != ActionReceipt.APPLIED: break
		if stress.current_actor_id == actor_id and stress.phase == BattleTacticalSession.Phase.PLAYER_TURN:
			stress.end_player_turn()
	_check(stress.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION], "bounded AI play reaches terminal outcome")
	stress.close()
	battle.close()
	grouped.close()
	var result := "INITIATIVE SESSION RESULTS: %d passed, %d failed" % [_passed, _failed]
	print(result)
	quit(0 if _failed == 0 else 1)
