extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL COUNTERATTACK: " + label)

func fixture() -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for i: int in 6:
		var unit := s.units[i]
		s.board.move_unit(unit, Vector2i(i, 0))
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	s.board.move_unit(s.units[0], Vector2i(2, 3))
	s.board.move_unit(s.units[1], Vector2i(3, 3))
	s.select_unit(s.units[0].id)
	check(s._queue.submit(GuardCommand.new(s.units[1].id, s.context.get_revision(), CombatPerksState.Mode.COUNTERATTACK), s.context).status == ActionReceipt.APPLIED, "arm defender through paid command")
	return s

func command(s: BattleCoreReactionsSession, id: StringName = &"demo_strike") -> AttackCommand:
	var a := s.units[0]
	var b := s.units[1]
	return AttackCommand.new(a.id, b.id, a.cell, b.cell, id, s.context.get_revision())

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "capture " + capture.reason)
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func events(receipt: ActionReceipt, kind: StringName) -> Array[Dictionary]:
	return receipt.get_events().filter(func(e: Dictionary) -> bool: return e["kind"] == kind)

func parity(s: BattleCoreReactionsSession, attack: Command, label: String) -> ActionReceipt:
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(s.context, s._queue, attack)
	check(snapshot(s) == before and rng == s.context.get_rng().to_dict() and counters == s.context.simulation_counters() and ids == UnitId.get_counter(), label + " isolation")
	var receipt := s._queue.submit(attack, s.context)
	check(receipt.status == preview.status and receipt.reason == preview.reason and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, label + " receipt parity " + String(receipt.reason))
	check(snapshot(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after and s.context.simulation_counters() == preview.counters_after and SummonAdmission.values(s.context) == preview.admission_after, label + " final parity")
	return receipt

func run() -> void:
	normal()
	consequences()
	eligibility()
	resource_and_codec()
	unsupported_response()
	limits_and_callbacks()
	await workers()
	print("COUNTERATTACK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func normal() -> void:
	var s := fixture()
	var a := s.units[0]
	var b := s.units[1]
	a.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	a.guard_stance = true
	a.control.entangled_turns = 1
	b.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	var cell := a.cell
	var receipt := parity(s, command(s), "ordinary weapon answer")
	check(receipt.status == ActionReceipt.APPLIED and events(receipt, &"counterattacked").size() == 1, "exactly one answer")
	check(b.guard_stance and b.combat_perks.reaction_left == 0 and b.action_resources.get_main_left() == 0 and not b.has_attacked, "only charge spent and defender stance kept")
	check(not a.guard_stance and a.combat_perks.reaction_left == 1 and not a.combat_perks.movement_stopped and a.cell == cell, "no recursive answer, stop or push")
	var reply := events(receipt, &"counterattacked")[0]
	check(not reply["modifiers"]["critical"] and reply["main_cost"] == 0, "no critical on controlled original attacker")
	var last_source: int = 0
	for e: Dictionary in receipt.get_events():
		if e["event_seq"] >= reply["event_seq"]: break
		last_source = int(e["event_seq"])
	check(last_source > events(receipt, &"attacked")[0]["event_seq"], "reply follows original consequences")
	check(s._queue.submit(AttackCommand.counterattack(b, a, s.context.get_revision()), s.context).reason == &"reaction/internal_attack", "external free answer rejected")
	s.close()
	# Полностью поглощённое попадание всё равно является прямой атакой.
	s = fixture()
	for item: ItemInstance in s.state.get_owner(s.units[1].id)._items.values():
		item.armor_remaining = item.get_definition().armor_max
	receipt = parity(s, command(s), "armor only trigger")
	check(events(receipt, &"counterattacked").size() == 1 and s.units[1].vitals.get_hp() == 256, "no HP gate for response to a fully absorbed hit")
	s.close()
	# Контроль сначала разрешается, иммунитет позволяет живому защитнику ответить.
	s = fixture()
	s.units[1].combat_perks.definition.stun_immune = true
	receipt = parity(s, command(s, &"stunning_strike"), "immune control answer")
	check(events(receipt, &"counterattacked").size() == 1 and s.units[1].control.stunned_turns == 0, "immune defender answers")
	s.close()
	s = fixture()
	receipt = parity(s, command(s, &"entangling_strike"), "entangled answer")
	check(events(receipt, &"counterattacked").size() == 1 and s.units[1].control.entangled_turns == 1, "entanglement permits reply")
	s.close()

func eligibility() -> void:
	for condition: String in ["spent", "stance", "mode", "stun", "lethal", "pushed", "range", "no_admission"]:
		var s := fixture()
		var a := s.units[0]
		var b := s.units[1]
		match condition:
			"spent": b.combat_perks.reaction_left = 0
			"stance": b.guard_stance = false
			"mode": b.combat_perks.mode = CombatPerksState.Mode.NONE
			"lethal": b.vitals.set_hp(1)
			"pushed": a.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
			"range": b.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 0.0)
			"no_admission":
				var rules := s.context.get_attack_rules()
				var pairs: Array[Dictionary] = []
				for pair: Dictionary in rules._pairs:
					if pair["actor_unit_id"] != b.id or pair["target_unit_id"] != a.id: pairs.append(pair)
				s.context._attack_rules = AttackRules.new(rules._actors, pairs, rules._definitions)
		var before := b.combat_perks.reaction_left
		var receipt := parity(s, command(s, &"stunning_strike" if condition == "stun" else &"demo_strike"), condition)
		check(receipt.status == ActionReceipt.APPLIED and events(receipt, &"counterattacked").is_empty() and b.combat_perks.reaction_left == before, "ineligible keeps charge: " + condition + " / " + String(receipt.reason))
		s.close()

func consequences() -> void:
	var s := fixture()
	var b := s.units[1]
	b.vitals.set_hp(100)
	var item_def := ItemDef.new()
	item_def.id = &"counter_heal"
	var effect := HealOnDamageEffect.new()
	effect.heal_amount = 80
	item_def.effects.append(effect)
	var item := s.state.get_owner(b.id).create_item(item_def)
	s.state.get_inventory(b.id).add_item(item)
	var receipt := parity(s, command(s, &"blood_rune"), "bleeding and item heal before answer")
	var kinds: Array = receipt.get_events().map(func(e: Dictionary) -> StringName: return e["kind"])
	check(kinds.find(&"bleeding_changed") >= 0 and kinds.find(&"healed") > kinds.find(&"bleeding_changed") and kinds.find(&"counterattacked") > kinds.find(&"healed"), "source bleeding then item heal then response")
	check(b.vitals.get_hp() > 100, "healing was actually applied before response")
	s.close()
	s = fixture()
	var cover := s.units[2]
	s.board.move_unit(cover, Vector2i(2, 2))
	cover.combat_perks.definition.tank_reactions = true
	cover.combat_perks.mode = CombatPerksState.Mode.COVER
	cover.combat_perks.cover_target_id = s.units[0].id
	cover.combat_perks.reaction_left = 1
	cover.guard_stance = true
	receipt = parity(s, command(s), "cover protects original attacker from reply")
	var spent_modes: Array = events(receipt, &"reaction_used").map(func(e: Dictionary) -> int: return e["mode"])
	check(spent_modes == [CombatPerksState.Mode.COUNTERATTACK, CombatPerksState.Mode.COVER] and cover.combat_perks.reaction_left == 0 and cover.guard_stance, "two distinct owners spend their shared charges in one answer")
	s.close()
	s = fixture()
	var mover := s.units[0]
	mover.guard_stance = true
	mover.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	s.units[1].combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
	receipt = parity(s, MoveCommand.new(mover.id, [mover.cell, Vector2i(1, 3)], s.context.get_revision()), "opportunity cannot trigger answer")
	check(receipt.status == ActionReceipt.INTERRUPTED and events(receipt, &"counterattacked").is_empty() and mover.combat_perks.reaction_left == 1, "reaction strike never opens counterattack chain")
	s.close()
	s = fixture()
	# Прямой ответ может завершить бой; expiry брони следует за всем его каскадом.
	for unit: UnitState in s.board.get_alive_units():
		if unit.faction == Faction.Type.PLAYER and unit != s.units[0]: unit.vitals.apply_damage(unit.vitals.get_hp())
	s.units[0].vitals.set_hp(1)
	var forecast := AttackForecast.build(s.context, s._queue, command(s))
	receipt = s.attack_unit(s.units[1].id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == forecast.events and snapshot(s) == forecast.snapshot_after, "lethal reply forecast/live")
	check(s.phase == BattleTacticalSession.Phase.DEFEAT and not s.units[0].is_alive() and not events(receipt, &"corpse_created").is_empty(), "lethal response completes death, corpse and battle outcome")
	for unit: UnitState in s.units: check(not unit.armor.in_battle, "terminal armor expires after answer")
	check(not s.end_player_turn() and s.step_enemy() == null, "terminal answer cannot resume")
	s.close()

func resource_and_codec() -> void:
	var s := fixture()
	var b := s.units[1]
	b.combat_perks.definition.tank_reactions = false
	var data := snapshot(s)
	var decoded := ItemSimulationSnapshot.from_dict(data)
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = owner._definitions[id].duplicate(true)
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == data, "counter-only item snapshot exact, no refill")
	ForecastSimulation.close(restored.state)
	check(GuardCommand.new(b.id, s.context.get_revision(), CombatPerksState.Mode.COUNTERATTACK).validate(s.context) == &"guard/already_active", "same active stance rejected")
	var receipt := parity(s, command(s), "counter-only owner")
	check(events(receipt, &"counterattacked").size() == 1, "counter perk independent of tank")
	b.action_resources._set_for_refill(1, 1)
	check(s._queue.submit(GuardCommand.new(b.id, s.context.get_revision()), s.context).status == ActionReceipt.APPLIED and b.combat_perks.mode == CombatPerksState.Mode.NONE and b.combat_perks.reaction_left == 0, "ordinary guard leaves spent charge")
	b.action_resources._set_for_refill(1, 1)
	check(GuardCommand.new(b.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST).validate(s.context) == &"perks/not_owned", "counter-only cannot acquire tank modes")
	b.combat_perks.definition.tank_reactions = true
	check(s._queue.submit(GuardCommand.new(b.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), s.context).status == ActionReceipt.APPLIED and b.combat_perks.reaction_left == 0, "switch shares exhausted charge")
	check(s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.ENEMY), s.context.get_revision(), Faction.Type.ENEMY), s.context).status == ActionReceipt.APPLIED and b.combat_perks.reaction_left == 1 and not b.guard_stance, "own turn refill once, stance ends")
	s.round_number = 3
	var intent := BattleDemoBT.new().decide(s, b)
	check(intent.kind == BattleAIIntent.Kind.GUARD and intent.reaction_mode == CombatPerksState.Mode.COUNTERATTACK and not b.guard_stance, "BT chooses reply without mutation")
	s.close()

func limits_and_callbacks() -> void:
	var s := fixture()
	var baseline := s._queue.submit(command(s), s.context)
	var index: int = 0
	for step: Dictionary in baseline.get_steps():
		if step["kind"] == &"counterattack": break
		index += 1
	check(index > 0 and index < baseline.get_steps().size(), "reply step located for limits")
	var source_events: int = 0
	for event: Dictionary in baseline.get_events():
		if event["kind"] == &"counterattacked": break
		source_events += 1
	s.close()
	for maximum: int in [index, index + 1]:
		s = fixture()
		var hp := s.units[0].vitals.get_hp()
		s._queue._max_commands = maximum
		var receipt := parity(s, command(s), "tail command limit")
		check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"command_limit" and s.units[0].vitals.get_hp() == hp, "fault keeps source prefix without unexecuted reply HP")
		check(s.units[1].combat_perks.reaction_left == (1 if maximum == index else 0), "charge follows executed reply step")
		s.close()
	s = fixture()
	s._queue._max_events = source_events
	var initial_hp := s.units[0].vitals.get_hp()
	var limited := parity(s, command(s), "response event limit")
	check(limited.status == ActionReceipt.FAULTED and limited.reason == &"event_limit" and s.units[1].combat_perks.reaction_left == 0 and s.units[0].vitals.get_hp() == initial_hp and events(limited, &"counterattacked").size() == 1, "atomic response events and charge kept, unexecuted hit absent")
	s.close()
	s = fixture()
	s._queue._max_depth = 2
	limited = parity(s, command(s), "response child depth limit")
	check(limited.status == ActionReceipt.FAULTED and limited.reason == &"depth_limit" and s.units[1].combat_perks.reaction_left == 0 and s.units[0].vitals.get_hp() < initial_hp, "depth failure retains executed reply hit and charge")
	s.close()
	s = fixture()
	var defender := s.units[1]
	var restore_charge := func(_old: float, _new: float) -> void: defender.combat_perks.reaction_left = 1
	s.units[0].vitals.hp_changed.connect(restore_charge)
	var corrupt := s._queue.submit(command(s), s.context)
	check(corrupt.status == ActionReceipt.FAULTED and not events(corrupt, &"counterattacked").is_empty(), "callback cannot restore spent charge silently")
	s.units[0].vitals.hp_changed.disconnect(restore_charge)
	s.close()
	s = fixture()
	defender = s.units[1]
	var remove_perk := func(_old: float, _new: float) -> void: defender.combat_perks.definition.counterattack = false
	defender.vitals.hp_changed.connect(remove_perk)
	corrupt = s._queue.submit(command(s), s.context)
	check(corrupt.status == ActionReceipt.FAULTED and events(corrupt, &"counterattacked").is_empty(), "source callback corruption faults before response")
	defender.vitals.hp_changed.disconnect(remove_perk)
	s.close()

func unsupported_response() -> void:
	for missing: bool in [true, false]:
		var s := fixture()
		var rules := s.context.get_attack_rules()
		var definitions: Array[AttackDefinition] = []
		for source: AttackDefinition in rules._definitions:
			var definition := AttackRules._copy_definition(source)
			if definition.id == &"counter_strike":
				if missing: continue
				definition.reaction_strike = false
			definitions.append(definition)
		s.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
		check(s.context.get_attack_rules().validate() == &"", "ordinary same-name definition is a valid configuration")
		var receipt := parity(s, command(s), "unsupported response capability")
		check(receipt.status == ActionReceipt.APPLIED and not s.context.is_faulted() and events(receipt, &"counterattacked").is_empty() and s.units[1].combat_perks.reaction_left == 1, "missing reaction capability preserves source attack and charge")
		s.close()

func workers() -> void:
	var s := fixture()
	var before := snapshot(s)
	var forecast := AttackForecast.build(s.context, s._queue, command(s))
	var worker := AttackForecastWorker.new()
	worker.start(s.prepare_attack_forecast(s.units[1].id))
	var result: AttackForecast
	for iteration: int in 500:
		result = worker.take_finished()
		if result != null: break
		await create_timer(0.01).timeout
	worker.close()
	check(result != null and result.events == forecast.events and result.steps == forecast.steps and result.snapshot_after == forecast.snapshot_after and result.rng_after == forecast.rng_after and result.counters_after == forecast.counters_after, "detached forecast worker exact tail")
	check(snapshot(s) == before, "forecast leaves live untouched")
	var live := BattleExecutionWorker.new()
	check(BattleExecutionWorker.can_transfer(s) and live.start(s, &"attack_unit", [s.units[1].id], 1), "live graph safely transferable")
	var completed := live.take_finished(true)
	var receipt := completed.get("result") as ActionReceipt
	check(receipt != null and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "exclusive live worker parity")
	s.close()
