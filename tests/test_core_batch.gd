extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CORE BATCH: " + label)

func snapshot(s: BattleCoreCombinationSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()

func run() -> void:
	deployment()
	armor_forecast()
	for layout: int in 2: full_battle(layout)
	print("CORE BATCH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func deployment() -> void:
	var s := BattleCoreCombinationSession.new()
	check(s.begin_deployment() and s.is_deploying(), "explicit prebattle entry")
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	check(not s.can_player_act() and not s.end_player_turn() and s.step_enemy() == null, "no turn or AI during deployment")
	check(s.move_to(Vector2i(0, 4)).status == ActionReceipt.REJECTED and s.attack_unit(s.units[1].id).status == ActionReceipt.REJECTED, "no combat move or attack")
	check(s.guard_selected().status == ActionReceipt.REJECTED and s.use_healing_item().status == ActionReceipt.REJECTED and s.restore_selected_armor().status == ActionReceipt.REJECTED and s.raise_corpse(Vector2i(0, 3)).status == ActionReceipt.REJECTED and s.use_summoning_item(Vector2i(0, 3)).status == ActionReceipt.REJECTED, "no prebattle abilities or item payment")
	check(s.preview_move(Vector2i(0, 4)).status == ActionReceipt.REJECTED and s.preview_attack(s.units[1].id).status == ActionReceipt.REJECTED and s.preview_restore_armor().status == ActionReceipt.REJECTED, "no prebattle combat forecast")
	check(snapshot(s) == before, "rejections do not mutate full state")
	check(not s.select_unit(s.units[1].id), "cannot deploy enemy")
	check(not s.place_selected(Vector2i(2, 3)) and not s.place_selected(Vector2i(6, 3)) and not s.place_selected(s.units[2].cell), "spikes, outside and occupied placements rejected")
	check(s.select_unit(s.units[4].id), "stunned ally can be deployed")
	var ray := s.selected_unit()
	var vitals := ray.vitals.to_dict()
	var resources := ray.action_resources.to_snapshot_dict()
	var control := ray.control.to_dict()
	check(s.place_selected(Vector2i(1, 4)) and s.place_selected(Vector2i(2, 4)), "multiple free placements without path")
	check(ray.cell == Vector2i(2, 4) and s.board.occupant_at(ray.cell) == ray and s.board.occupant_at(Vector2i(5, 5)) == null, "board owns deployment occupancy")
	check(ray.vitals.to_dict() == vitals and ray.action_resources.to_snapshot_dict() == resources and ray.control.to_dict() == control, "placement preserves HP, actions and status duration")
	check(s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and s.state.environment.to_dict() == before["environment"], "placement has no queue, RNG or environment effects")
	var placed := snapshot(s)
	check(s.start_battle() and not s.start_battle() and not s.begin_deployment(), "start is one way and once")
	check(snapshot(s) == placed and not s.place_selected(Vector2i(1, 4)), "start preserves battle state and disables placement")
	s.reset()
	check(s.is_deploying() and s.units[4].cell == Vector2i(5, 5) and s.units[4].control.stunned_turns == 1, "reset returns original prebattle setup")
	s.close()

func armor_forecast() -> void:
	for damaged: bool in [false, true]:
		var s := BattleCoreCombinationSession.new()
		var actor := s.selected_unit()
		if damaged:
			for item: ItemInstance in s.state.get_owner(actor.id)._items.values():
				if item.get_definition().armor_max > 0: item.armor_remaining = 0
		var before := snapshot(s)
		var counters := s.context.simulation_counters()
		var rng := s.context.get_rng().to_dict().duplicate(true)
		var admission := SummonAdmission.values(s.context)
		var first := s.preview_restore_armor()
		var second := s.preview_restore_armor()
		check(first.status == ActionReceipt.APPLIED and first.snapshot_after == second.snapshot_after and first.events == second.events, "repeated armor forecast")
		check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and SummonAdmission.values(s.context) == admission, "armor preview full isolation")
		var receipt := s.restore_selected_armor()
		check(receipt.status == first.status and receipt.get_events() == first.events and receipt.get_steps() == first.steps and snapshot(s) == first.snapshot_after, "armor preview/live full parity")
		check(s.context.simulation_counters() == first.counters_after and s.context.get_rng().to_dict() == first.rng_after and SummonAdmission.values(s.context) == first.admission_after, "armor preview counters/RNG/admission")
		check((not actor.armor.grants.is_empty()) != damaged, "undamaged set gets temporary armor; damaged set repairs items")
		var after := snapshot(s)
		check(s.preview_restore_armor().reason == &"attack/insufficient_main" and snapshot(s) == after, "no-main preview refusal")
		s.select_unit(s.units[4].id)
		check(s.preview_restore_armor().reason == &"control/stunned", "stunned restore refuses")
		s.close()
	# Лимит публикации после мутации: прогноз хранит prefix, но не готовые полосы.
	var s := BattleCoreCombinationSession.new()
	for enemy: UnitState in s.board.get_all_units():
		if enemy.faction == Faction.Type.ENEMY and enemy.is_alive():
			s._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test", 0, enemy.cell)), s.context)
	s.selected_unit().armor = ArmorState.new()
	s.selected_unit().armor.in_battle = true
	s._queue = ActionQueue.new(1, 512, 32)
	var forecast := s.preview_restore_armor()
	check(forecast.status == ActionReceipt.FAULTED and forecast.units_after.is_empty(), "faulted restore does not advertise ready DTO")
	var receipt := s.restore_selected_armor()
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_steps() == forecast.steps and receipt.get_events() == forecast.events and snapshot(s) == forecast.snapshot_after, "restore FAULTED prefix parity")
	s.close()

func full_battle(layout: int) -> void:
	var s := BattleCoreCombinationSession.new()
	s.begin_deployment()
	if layout == 1:
		s.select_unit(s.units[0].id); s.place_selected(Vector2i(2, 2))
		s.select_unit(s.units[4].id); s.place_selected(Vector2i(3, 4))
	check(s.start_battle(), "layout %d begins battle" % layout)
	var applied: int = 0
	for turn: int in 80:
		if s.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		for id: int in s.living_ids(Faction.Type.PLAYER):
			if not s.can_player_act(): break
			s.select_unit(id)
			for action: int in 2:
				if not s.can_player_act(): break
				var actor := s.board.get_unit_by_id(id)
				var intent := BattleDemoBT.new().decide(s, actor)
				if intent == null or intent.kind == BattleAIIntent.Kind.WAIT: break
				var command: Command
				match intent.kind:
					BattleAIIntent.Kind.ATTACK:
						var target := s.board.get_unit_by_id(intent.target_id)
						command = AttackCommand.new(id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision())
					BattleAIIntent.Kind.MOVE: command = MoveCommand.new(id, intent.path, s.context.get_revision())
					BattleAIIntent.Kind.SUMMON: command = s.item_command(id, intent.item_id, intent.cell)
				var receipt := s._submit(command)
				if receipt.status != ActionReceipt.APPLIED:
					check(false, "layout %d BT command refused: %s" % [layout, receipt.reason])
					break
				applied += 1
				if intent.kind != BattleAIIntent.Kind.MOVE: break
		if s.can_player_act(): s.end_player_turn()
		for step: int in 100:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			var receipt := s.step_enemy()
			if receipt != null: check(receipt.status == ActionReceipt.APPLIED, "enemy command remains admissible: " + String(receipt.reason))
	check(applied > 0 and s.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION], "layout %d reaches drained outcome after %d rounds" % [layout, s.round_number])
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.OK and not s.context.is_busy() and not s.context.is_faulted(), "terminal state remains serializable and queue drained")
	check(not s.end_player_turn() and s.step_enemy() == null and not s.start_battle(), "terminal battle cannot resume")
	s.close()
