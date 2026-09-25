extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CORE REACTIONS: " + label)

func _run() -> void:
	_sneak()
	_cover()
	_opportunity()
	_limits_and_callbacks()
	_transit_and_ai()
	_helpers_restore_and_geometry()
	_lethal_and_forced()
	_full_battle(false)
	_full_battle(true)
	print("CORE REACTIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _session() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s.state.environment.fires.clear()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in 6:
		var unit := s.units[index]
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		check(s.board.move_unit(unit, Vector2i(index, 0)), "park fixture %d" % index)
	return s

func _put(s: BattleCoreReactionsSession, index: int, cell: Vector2i) -> UnitState:
	var unit := s.units[index]
	check(s.board.move_unit(unit, cell), "place fixture %d" % index)
	return unit

func _snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "capture: " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func _events(events: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event.get("kind") == kind)

func _parity(s: BattleCoreReactionsSession, command: Command, label: String) -> ActionReceipt:
	var before := _snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(s.context, s._queue, command)
	check(preview.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], label + " preview: " + String(preview.reason))
	check(_snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and UnitId.get_counter() == ids, label + " isolation")
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == preview.status and receipt.reason == preview.reason and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, label + " receipt parity: " + String(receipt.reason))
	check(_snapshot(s) == preview.snapshot_after and s.context.simulation_counters() == preview.counters_after and s.context.get_rng().to_dict() == preview.rng_after and SummonAdmission.values(s.context) == preview.admission_after, label + " full state parity")
	return receipt

func _attack(s: BattleCoreReactionsSession, actor: UnitState, target: UnitState) -> AttackCommand:
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", s.context.get_revision())

func _sneak() -> void:
	var s := _session()
	var ally := _put(s, 0, Vector2i(2, 2))
	var target := _put(s, 3, Vector2i(3, 2))
	var actor := _put(s, 2, Vector2i(4, 2))
	check(MeleeThreat.has_sneak(actor) and not MeleeThreat.has_sneak(ally) and not MeleeThreat.has_tank(actor), "perks belong to authored owners only")
	check(s.context.get_attack_rules().get_definition(&"demo_strike").backstab_bonus_percent == 0, "new battle removes facing bonus")
	ally.action_resources.try_spend_main(1)
	check(MeleeThreat.participants(s.context, target) == [ally.id, actor.id], "spent main still threatens; attacker counts")
	ally.control.stunned_turns = 1
	check(MeleeThreat.participants(s.context, target) == [actor.id], "stunned excluded")
	ally.control.stunned_turns = 0
	ally.control.entangled_turns = 1
	check(MeleeThreat.participants(s.context, target).size() == 2, "entangled still threatens")
	var preview := ForecastSimulation.run(s.context, s._queue, _attack(s, actor, target))
	var attacks := _events(preview.events, &"attacked")
	check(not attacks.is_empty() and attacks[0]["modifiers"]["sneak_percent"] == 50 and attacks[0]["modifiers"]["backstab_percent"] == 0, "sneak replaces rear bonus")
	_parity(s, _attack(s, actor, target), "sneak armor/piercing/spatial")
	s.close()
	s = _session()
	actor = _put(s, 0, Vector2i(2, 2))
	target = _put(s, 3, Vector2i(3, 2))
	_put(s, 2, Vector2i(4, 2))
	preview = ForecastSimulation.run(s.context, s._queue, _attack(s, actor, target))
	attacks = _events(preview.events, &"attacked")
	check(not attacks.is_empty() and attacks[0]["modifiers"]["sneak_percent"] == 0, "nonowner gets no passive bonus")
	var raw := ArmorAttack.components(6.0, 4.0, 2, false, [], 50, 2, 50, 30)
	var total := 0.0
	for row: Dictionary in raw: total += float(row["numerator"]) / float(row["denominator"])
	check(is_equal_approx(total, 23.8), "height + base bonus then crit and cover before armor rounding")
	s.close()

func _cover() -> void:
	var s := _session()
	var tank := _put(s, 0, Vector2i(2, 2))
	var target := _put(s, 2, Vector2i(3, 2))
	var enemy := _put(s, 5, Vector2i(4, 2))
	s.selected_id = tank.id
	_parity(s, GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.COVER, target.id), "cover stance")
	check(tank.action_resources.get_main_left() == 0 and tank.combat_perks.reaction_left == 1 and tank.guard_stance, "stance pays main not reaction")
	var before := _snapshot(s)
	check(s.set_reaction_guard(CombatPerksState.Mode.OPPORTUNIST).status == ActionReceipt.REJECTED and _snapshot(s) == before, "cannot switch free")
	var second := _put(s, 4, Vector2i(3, 1))
	second.combat_perks = CombatPerksState.new()
	second.combat_perks.definition.tank_reactions = true
	second.combat_perks.mode = CombatPerksState.Mode.COVER
	second.combat_perks.cover_target_id = target.id
	second.combat_perks.reaction_left = 1
	second.guard_stance = true
	var receipt := _parity(s, _attack(s, enemy, target), "covered direct attack")
	var reactions := _events(receipt.get_events(), &"reaction_used")
	check(reactions.size() == 1 and reactions[0]["actor_unit_id"] == tank.id and tank.combat_perks.reaction_left == 0 and second.combat_perks.reaction_left == 1, "lowest eligible ID only; common charge spent")
	check(tank.guard_stance, "cover preserves tank stance")
	tank.action_resources._set_for_refill(1, 1)
	check(s.set_reaction_guard(CombatPerksState.Mode.OPPORTUNIST).status == ActionReceipt.APPLIED and tank.combat_perks.reaction_left == 0, "paid mode switch never replenishes charge")
	tank.action_resources._set_for_refill(1, 1)
	_parity(s, GuardCommand.new(tank.id, s.context.get_revision()), "paid active reaction to ordinary guard")
	check(tank.combat_perks.mode == CombatPerksState.Mode.NONE and tank.combat_perks.cover_target_id == 0 and tank.combat_perks.reaction_left == 0 and tank.guard_stance and tank.action_resources.get_main_left() == 0, "ordinary guard disables mode without refilling charge")
	check(GuardCommand.new(tank.id, s.context.get_revision()).validate(s.context) == &"guard/already_active", "same ordinary stance remains rejected")
	check(s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context).status == ActionReceipt.APPLIED and tank.combat_perks.reaction_left == 1 and not tank.guard_stance, "own team refills reaction and expires stance")
	check(GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.COVER, tank.id).validate(s.context) == &"perks/invalid_cover_target", "self cover refused")
	s.close()

func _opportunity() -> void:
	var s := _session()
	var tank := _put(s, 1, Vector2i(2, 2))
	var mover := _put(s, 2, Vector2i(3, 2))
	mover.combat_perks = null
	mover.control = null
	check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), s.context).status == ActionReceipt.APPLIED, "enemy arms opportunity")
	var main := mover.action_resources.get_main_left()
	var move := mover.move_points_left
	var balance := mover.vitals.get_balance()
	var path: Array[Vector2i] = [mover.cell, Vector2i(4, 2)]
	var receipt := _parity(s, MoveCommand.new(mover.id, path, s.context.get_revision()), "opportunity movement")
	check(receipt.status == ActionReceipt.INTERRUPTED and receipt.reason == &"perks/opportunist_stopped", "movement interrupted after reaction")
	check(mover.cell == path[0] and mover.move_points_left == move and mover.action_resources.get_main_left() == main and mover.vitals.get_balance() == balance, "stop before paying/moving; no main or balance damage")
	check(tank.guard_stance and tank.action_resources.get_main_left() == 0 and tank.combat_perks.reaction_left == 0, "reaction uses charge and preserves stance")
	check(mover.combat_perks != null and mover.combat_perks.movement_stopped and mover.control == null and not ControlRules.critical_target(mover), "stop not stun or entangle; nullable control preserved")
	var stopped := _snapshot(s)
	check(s._queue.submit(MoveCommand.new(mover.id, path, s.context.get_revision()), s.context).reason == &"perks/movement_stopped" and _snapshot(s) == stopped, "repeat click cannot bypass stop")
	check(ControlRules.action_reason(mover) == &"", "other voluntary actions remain allowed")
	check(s._queue.submit(AttackCommand.opportunity(tank, mover, s.context.get_revision()), s.context).reason == &"reaction/internal_attack", "external free reaction refused")
	check(s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context).status == ActionReceipt.APPLIED and not mover.combat_perks.movement_stopped and tank.combat_perks.reaction_left == 0, "victim team unlocks move, enemy charge not refilled")
	s.close()

func _limits_and_callbacks() -> void:
	for callback: bool in [false, true]:
		var s := _session()
		var tank := _put(s, 1, Vector2i(2, 2))
		var mover := _put(s, 2, Vector2i(3, 2))
		tank.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 100.0)
		check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), 1), s.context).status == ActionReceipt.APPLIED, "arm fault fixture")
		var hp := mover.vitals.get_hp()
		if callback:
			mover.vitals.hp_changed.connect(func(_old: float, _new: float) -> void: tank.combat_perks.reaction_left = 1)
		else: s._queue = ActionQueue.new(2)
		var receipt := s._queue.submit(MoveCommand.new(mover.id, [mover.cell, Vector2i(4, 2)], s.context.get_revision()), s.context)
		check(receipt.status == ActionReceipt.FAULTED and mover.cell == Vector2i(3, 2) and mover.combat_perks.movement_stopped, "fault retains stop/payment before unfinished hit")
		if callback: check(mover.vitals.get_hp() < hp and not _events(receipt.get_events(), &"damaged").is_empty(), "callback fault retains HP prefix")
		else: check(mover.vitals.get_hp() == hp and tank.combat_perks.reaction_left == 0 and receipt.reason == &"command_limit", "command limit retains charge but no unexecuted HP")
		s.close()

func _transit_and_ai() -> void:
	var s := _session()
	var tank := _put(s, 1, Vector2i(2, 2))
	var mover := _put(s, 2, Vector2i(0, 1))
	_put(s, 0, Vector2i(1, 1))
	_put(s, 4, Vector2i(1, 2))
	var ally := _put(s, 3, Vector2i(1, 3))
	ally.faction = Faction.Type.PLAYER
	check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), 1), s.context).status == ActionReceipt.APPLIED, "arm transit fixture")
	var path: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(0, 3)]
	var receipt := _parity(s, MoveCommand.new(mover.id, path, s.context.get_revision()), "allied transit crosses threat")
	check(receipt.status == ActionReceipt.APPLIED and mover.cell == path[-1] and tank.combat_perks.reaction_left == 1, "transit-only encounter does not provoke")
	s.close()
	s = _session()
	tank = _put(s, 1, Vector2i(2, 2))
	_put(s, 5, Vector2i(3, 2))
	var intent := BattleDemoBT.new().decide(s, tank)
	check(intent != null and intent.kind == BattleAIIntent.Kind.GUARD and intent.reaction_mode == CombatPerksState.Mode.COVER, "BT selects cover intention, not mutation")
	check(not tank.guard_stance and tank.combat_perks.reaction_left == 1, "BT leaves live state")
	s.close()

func _helpers_restore_and_geometry() -> void:
	var s := _session()
	var owner := _put(s, 0, Vector2i(2, 2))
	var target := _put(s, 3, Vector2i(4, 2))
	var actor := _put(s, 2, Vector2i(5, 2))
	s.selected_id = owner.id
	check(s.use_summoning_item(Vector2i(3, 2)).status == ActionReceipt.APPLIED, "summon in perk battle")
	var helper := s.board.occupant_at(Vector2i(3, 2))
	check(helper != null and helper.combat_perks == null and helper.control == null and not MeleeThreat.participants(s.context, target).has(helper.id), "pending helper inherits no perks and no threat")
	check(s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context).status == ActionReceipt.APPLIED, "helper enters next team turn")
	check(MeleeThreat.participants(s.context, target) == [actor.id, helper.id], "ready helper supplies second threat")
	var data := _snapshot(s)
	var decoded := ItemSimulationSnapshot.from_dict(data)
	var definitions: Dictionary = {}
	for inventory_owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in inventory_owner._definitions: definitions[id] = inventory_owner._definitions[id].duplicate(true)
	var restored := decoded.snapshot.instantiate(definitions) if decoded.code == ItemSnapshotResult.Code.OK else ItemSnapshotResult.new()
	check(restored.code == ItemSnapshotResult.Code.OK, "mixed perks/helpers item snapshot restores")
	if restored.state != null:
		check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == data, "restored snapshot is exact and no refill")
		restored.state.get_board().get_unit_by_id(actor.id).combat_perks.definition.sneak_attack = false
		check(actor.combat_perks.definition.sneak_attack and _snapshot(s) == data, "restored resource definition isolated")
		ForecastSimulation.close(restored.state)
	var bad := data.duplicate(true)
	for unit_data: Dictionary in bad["board_snapshot"]["board"]["units"]:
		if unit_data["id"] == actor.id: unit_data["schema_version"] = 6
	check(ItemSimulationSnapshot.from_dict(bad).code != ItemSnapshotResult.Code.OK, "no downgrade of perk capability")
	check(UnitState.from_dict(actor.to_snapshot_dict()) == null, "legacy decoder cannot silently discard perks")
	s.board.set_height_steps(actor.cell, 2)
	check(not MeleeThreat.threatens(s.context, actor, target), "height surcharge removes out-of-reach threat")
	s.board.set_height_steps(actor.cell, 1)
	check(MeleeThreat.threatens(s.context, actor, target), "half step retains valid melee geometry")
	s.close()
	s = _session()
	actor = _put(s, 2, Vector2i(1, 2))
	target = _put(s, 3, Vector2i(3, 2))
	actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 2.0)
	s.board.set_terrain(Vector2i(2, 2), TerrainType.Type.WALL)
	check(not MeleeThreat.threatens(s.context, actor, target), "wall blocks melee threat")
	s.board.set_terrain(Vector2i(2, 2), TerrainType.Type.FLOOR)
	check(MeleeThreat.threatens(s.context, actor, target), "reach geometry reused after opening line")
	s.close()

func _lethal_and_forced() -> void:
	var s := _session()
	var tank := _put(s, 1, Vector2i(2, 2))
	var mover := _put(s, 2, Vector2i(3, 2))
	tank.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 100.0)
	mover.vitals.apply_damage(mover.vitals.get_hp() - 1.0)
	check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), 1), s.context).status == ActionReceipt.APPLIED, "arm lethal opportunity")
	var receipt := _parity(s, MoveCommand.new(mover.id, [mover.cell, Vector2i(4, 2)], s.context.get_revision()), "lethal opportunity")
	check(not mover.is_alive() and s.board.occupant_at(Vector2i(3, 2)) == null and not _events(receipt.get_events(), &"corpse_created").is_empty(), "lethal reaction completes death and corpse before stop")
	s.close()
	s = _session()
	tank = _put(s, 5, Vector2i(3, 1))
	tank.combat_perks.definition.tank_reactions = true
	tank.combat_perks.reaction_left = 1
	mover = _put(s, 2, Vector2i(3, 2))
	var enemy := _put(s, 1, Vector2i(4, 2))
	enemy.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), 1), s.context).status == ActionReceipt.APPLIED, "arm forced fixture")
	receipt = _parity(s, _attack(s, enemy, mover), "forced push through reaction zone")
	check(mover.cell == Vector2i(2, 2) and tank.combat_perks.reaction_left == 1 and _events(receipt.get_events(), &"reaction_used").is_empty(), "forced exit does not provoke")
	s.close()

# Общий командный бой проверяет завершение и BT после новых перехватов/стоек.
func _full_battle(passive: bool) -> void:
	var s := BattleCoreReactionsSession.new()
	check(s.begin_deployment() and s.start_battle(), "K10 full battle starts through deployment")
	var resolved := 0
	for turn: int in 80:
		if not s.can_player_act(): break
		if not passive:
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
						BattleAIIntent.Kind.GUARD: command = GuardCommand.new(id, s.context.get_revision(), intent.reaction_mode, intent.target_id)
					var receipt := s._submit(command)
					check(receipt.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], "K10 active battle admissible action: " + String(receipt.reason))
					resolved += 1
					if intent.kind != BattleAIIntent.Kind.MOVE or receipt.status != ActionReceipt.APPLIED: break
		if s.can_player_act(): s.end_player_turn()
		for step: int in 100:
			if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
			var receipt := s.step_enemy()
			if receipt != null:
				check(receipt.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], "K10 real enemy resolves action: " + String(receipt.reason))
				resolved += 1
	check(resolved > 0 and s.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION], "K10 full battle reaches outcome: passive=%s round=%d phase=%s" % [passive, s.round_number, s.phase_text()])
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.OK and not s.context.is_busy() and not s.context.is_faulted(), "K10 terminal state is serializable and drained")
	check(not s.end_player_turn() and s.step_enemy() == null and not s.start_battle(), "K10 terminal battle cannot resume")
	print("K10 BATTLE passive=%s round=%d phase=%s" % [passive, s.round_number, s.phase_text()])
	s.close()
