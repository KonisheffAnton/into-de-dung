extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ENEMY FIRST: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()

func finish_enemies(session: BattleCoreReactionsSession) -> void:
	# Граница проверяется отдельно от решений ИИ, которые меняют поле и RNG.
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()

func run() -> void:
	var session := BattleCoreReactionsSession.new()
	check(session.phase == BattleTacticalSession.Phase.ENEMY_TURN and session.round_number == 1 and not session.can_player_act(), "direct start belongs to enemies in round one")
	session.units[1].action_resources.try_spend_main(1)
	var before := snapshot(session)
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	check(session.begin_deployment() and session.selected_unit() != null, "deployment selects player despite enemy-first start")
	check(session.start_battle() and not session.start_battle(), "deployment starts once")
	check(session.phase == BattleTacticalSession.Phase.ENEMY_TURN and session.selected_unit() == null, "deployment hands control to enemy")
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng_before, "start neither refills nor expires control nor consumes RNG")
	finish_enemies(session)
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and session.round_number == 1, "enemy completion keeps round one")
	check(session.units[1].control.stunned_turns == 0 and session.units[4].control.stunned_turns == 1, "only outgoing enemy control expires")
	check(session.state.environment.collapse.turn == 0 and session.context.get_rng().to_dict() == rng_before, "no environment between teams")
	check(session.end_player_turn() and session.round_number == 2, "player completion begins next round")
	check(session.state.environment.collapse.turn == 1 and session.units[4].control.stunned_turns == 0, "player control expires before first mark")
	var mark: Vector2i = session.state.environment.collapse.marked[0]
	check(session.board.get_terrain(mark) == TerrainType.Type.FLOOR, "first phase only warns")
	finish_enemies(session)
	check(session.round_number == 2 and session.state.environment.collapse.turn == 1 and session.board.get_terrain(mark) == TerrainType.Type.FLOOR, "next enemy team gets full turn before collapse")
	var isolated_before := snapshot(session)
	var preview := TurnForecast.build(session)
	check(preview.status == ActionReceipt.APPLIED and snapshot(session) == isolated_before, "end-turn prediction isolates environment cascade")
	check(preview.events.any(func(event: Dictionary) -> bool: return event.kind == &"support_collapsed"), "end-turn prediction includes collapse")
	var worker := BattleExecutionWorker.new()
	check(worker.start(session, &"end_player_turn", []), "end-player boundary transfers to worker")
	var completed := worker.take_finished(true)
	check(not completed.is_empty() and completed.result and session.round_number == 3, "worker advances round after environment")
	check(snapshot(session) == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after, "worker live equals preview world RNG and counters")
	check(session.board.get_terrain(mark) == TerrainType.Type.VOID, "mark survives both teams then collapses")
	session.reset()
	check(session.is_deploying() and session.round_number == 1 and session.selected_unit() != null and session.state.environment.collapse.turn == 0, "reset returns to initial deployment")
	check(session.start_battle() and session.phase == BattleTacticalSession.Phase.ENEMY_TURN, "reset again starts enemies")
	session.close()
	_test_fault_prefix()
	_test_terminal_collapse()
	_test_legacy()
	print("ENEMY FIRST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_fault_prefix() -> void:
	var session := BattleCoreReactionsSession.new()
	finish_enemies(session)
	var cell := Vector2i(2, 2)
	for id: int in session.living_ids(Faction.Type.PLAYER):
		session.board.get_unit_by_id(id).control = ControlState.new()
	session.state.environment.collapse = {"turn": 1, "marked": [cell]}
	session._queue._max_commands = 1
	var enemy := session.units[1]
	enemy.action_resources.try_spend_main(1)
	var old_round := session.round_number
	var forecast := TurnForecast.build(session)
	check(forecast.status == ActionReceipt.FAULTED, "prediction catches collapse child capacity fault")
	check(not session.end_player_turn() and session.phase == BattleTacticalSession.Phase.FAULTED, "fault blocks new enemy turn")
	check(session.round_number == old_round and enemy.action_resources.get_main_left() == 0, "fault does not advance round or refill enemies")
	check(session.state.environment.collapse.turn == 2 and session.board.get_terrain(cell) == TerrainType.Type.FLOOR, "fault retains mark-only executed prefix")
	check(snapshot(session) == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after, "fault prefix matches isolated prediction")
	session.close()

func _test_legacy() -> void:
	var legacy := BattleCoreCombinationSession.new()
	check(legacy.phase == BattleTacticalSession.Phase.PLAYER_TURN and legacy.begin_deployment() and legacy.start_battle(), "K2 retains player-first deployment")
	check(legacy.end_player_turn() and legacy.round_number == 1, "K2 enemy turn remains same round")
	legacy._enemy_index = legacy._enemy_ids.size()
	legacy.step_enemy()
	check(legacy.round_number == 2 and legacy.phase == BattleTacticalSession.Phase.PLAYER_TURN, "K2 round boundary unchanged")
	legacy.close()

func _test_terminal_collapse() -> void:
	var session := BattleCoreReactionsSession.new()
	finish_enemies(session)
	var enemies := session.living_ids(Faction.Type.ENEMY)
	var last_enemy := session.board.get_unit_by_id(enemies[0])
	for index: int in range(1, enemies.size()):
		var extra := session.board.get_unit_by_id(enemies[index])
		session._submit(DeathCommand.new(extra.id, DamageSource.new(&"test", 0, extra.cell)))
	session.state.environment.collapse = {"turn": 1, "marked": [last_enemy.cell]}
	last_enemy.action_resources.try_spend_main(1)
	var forecast := TurnForecast.build(session)
	check(forecast.status == ActionReceipt.APPLIED and forecast.phase_after == BattleTacticalSession.Phase.VICTORY, "last enemy collapse predicts terminal victory")
	check(not session.end_player_turn() and session.phase == BattleTacticalSession.Phase.VICTORY, "collapse victory prevents enemy phase")
	check(session.round_number == 1 and last_enemy.action_resources.get_main_left() == 0, "terminal victory advances neither round nor refill")
	check(snapshot(session) == forecast.snapshot_after and session.state.environment.corpses_at(last_enemy.cell).is_empty(), "terminal live equals prediction and creates no corpse")
	session.close()
