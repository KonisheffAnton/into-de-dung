extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL CONTROL PACKAGE: " + label)

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
	return s

func command(s: BattleCoreReactionsSession, id: StringName = &"stunning_strike") -> AttackCommand:
	var actor := s.units[0]
	var target := s.units[1]
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, id, s.context.get_revision())

func snapshot(s: BattleDemoSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK, "snapshot accepted " + capture.reason)
	return capture.snapshot.to_dict() if capture.snapshot != null else {}

func parity(s: BattleCoreReactionsSession, attack: AttackCommand, label: String) -> ActionReceipt:
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var ids := UnitId.get_counter()
	var forecast := AttackForecast.build(s.context, s._queue, attack)
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and UnitId.get_counter() == ids, label + " forecast isolates live")
	var actual := s._queue.submit(attack, s.context)
	check(actual.status == forecast.status and actual.reason == forecast.reason and actual.get_events() == forecast.events and actual.get_steps() == forecast.steps, label + " complete receipt parity")
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, label + " final snapshot RNG counters parity")
	return actual

func has_step(receipt: ActionReceipt, kind: StringName, reason: StringName = &"") -> bool:
	for step: Dictionary in receipt.get_steps():
		if step["kind"] == kind and step["reason"] == reason: return true
	return false

func states(receipt: ActionReceipt) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event["kind"] == &"control_changed": result.append(event)
	return result

func run() -> void:
	_admission()
	await _worker_restore()
	_immunities_and_expiry()
	_gate_spatial_healing()
	_reactions_and_ai()
	_combined_order_and_critical()
	_faults_and_events()
	print("CONTROL PACKAGE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _admission() -> void:
	var s := fixture()
	var rules := s.context.get_attack_rules()
	var invalid := rules.get_definition(&"stunning_strike")
	invalid.profile = AttackRules.SPATIAL_PROFILE
	check(AttackRules.new(rules._actors, rules._pairs, [invalid]).validate() != &"", "stun requires armor profile")
	invalid = rules.get_definition(&"opportunity_strike")
	invalid.stun_on_physical_hp = true
	check(AttackRules.new(rules._actors, rules._pairs, [invalid]).validate() != &"", "reaction definition cannot apply stun")
	var before := snapshot(s)
	var refused := s._queue.submit(StunApplyCommand.new(), s.context)
	check(refused.status == ActionReceipt.REJECTED and refused.reason == &"control/internal_command" and snapshot(s) == before, "internal application cannot be submitted as root")
	s.units[0].combat_perks.definition.stunning_strike = false
	before = snapshot(s)
	refused = s._queue.submit(command(s), s.context)
	check(refused.status == ActionReceipt.REJECTED and refused.reason == &"perks/stunning_strike_required" and snapshot(s) == before, "non-owner refused before payment")
	s.units[0].combat_perks.definition.stunning_strike = true
	s.units[1].control = null
	before = snapshot(s)
	refused = s._queue.submit(command(s), s.context)
	check(refused.status == ActionReceipt.REJECTED and refused.reason == &"control/capability_required" and snapshot(s) == before, "nullable target refused without creating capability")
	s.close()

func _worker_restore() -> void:
	var s := fixture()
	s.units[1].control.entangled_turns = 1
	var before := snapshot(s)
	var expected := AttackForecast.build(s.context, s._queue, command(s))
	var worker := preload("res://scripts/demo/attack_forecast_worker.gd").new()
	worker.start(ForecastSimulation.prepare(s.context, s._queue, command(s)))
	var deadline := Time.get_ticks_msec() + 5000
	var actual: AttackForecast
	while actual == null and Time.get_ticks_msec() < deadline:
		actual = worker.take_finished()
		if actual == null: await create_timer(0.002).timeout
	worker.close()
	check(actual != null and actual.events == expected.events and actual.steps == expected.steps and actual.snapshot_after == expected.snapshot_after and actual.rng_after == expected.rng_after and actual.counters_after == expected.counters_after, "worker executes exact combined-control forecast")
	check(snapshot(s) == before, "worker preserves complete live snapshot")
	var receipt := parity(s, command(s), "stun beside entangle")
	check(receipt.status == ActionReceipt.APPLIED and s.units[1].control.stunned_turns == 1 and s.units[1].control.entangled_turns == 1, "stun coexists with entangle")
	check(states(receipt).size() == 1 and states(receipt)[0]["reason"] == &"stunned" and s.units[0].action_resources.get_main_left() == 0, "stun pays one main and emits exact application")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var decoded := ItemSimulationSnapshot.from_dict(snapshot(s))
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == snapshot(s), "item restore preserves perk v2 and both controls")
	if restored.state != null: ForecastSimulation.close(restored.state)
	s.units[0].try_refill_turn_resources()
	receipt = parity(s, command(s), "repeat stun")
	check(states(receipt).size() == 1 and states(receipt)[0]["reason"] == &"stun_refreshed" and s.units[1].control.stunned_turns == 1, "repeat does not stack duration")
	s.close()

func _immunities_and_expiry() -> void:
	for mask: int in 4:
		for ability: StringName in [&"stunning_strike", &"entangling_strike"]:
			var s := fixture()
			var target := s.units[1]
			target.combat_perks.definition.stun_immune = (mask & 1) != 0
			target.combat_perks.definition.entangle_immune = (mask & 2) != 0
			var receipt := parity(s, command(s, ability), "immunity %d %s" % [mask, ability])
			var stun := ability == &"stunning_strike"
			var immune := (mask & (1 if stun else 2)) != 0
			check(receipt.status == ActionReceipt.APPLIED and target.vitals.get_hp() < 256 and s.units[0].action_resources.get_main_left() == 0, "immunity preserves paid hit")
			check(target.control.stunned_turns == (1 if stun and not immune else 0) and target.control.entangled_turns == (1 if not stun and not immune else 0), "independent immunity blocks only matching control")
			if immune: check(has_step(receipt, &"stun_apply" if stun else &"entangle_apply", &"control/stun_immune" if stun else &"control/entangle_immune") and states(receipt).is_empty(), "immune skip is explicit without control event")
			s.close()
	var s := fixture()
	var target := s.units[1]
	target.control.stunned_turns = 1
	target.control.entangled_turns = 1
	target.combat_perks.definition.stun_immune = true
	target.combat_perks.definition.entangle_immune = true
	parity(s, command(s), "already controlled immune target")
	check(target.control.stunned_turns == 1 and target.control.entangled_turns == 1 and ControlRules.critical_target(target), "immunity does not remove old control or critical eligibility")
	s._queue.submit(ControlTurnEndCommand.new(Faction.Type.PLAYER, s.context.get_revision()), s.context)
	check(target.control.stunned_turns == 1 and target.control.entangled_turns == 1, "other team end preserves both")
	s._queue.submit(ControlTurnEndCommand.new(Faction.Type.ENEMY, s.context.get_revision()), s.context)
	check(target.control.stunned_turns == 0 and target.control.entangled_turns == 0, "own team end expires both normally under immunity")
	s.close()

func _gate_spatial_healing() -> void:
	var s := fixture()
	var target := s.units[1]
	for item: ItemInstance in s.state.get_owner(target.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	var receipt := parity(s, command(s), "armor only")
	check(target.control.stunned_turns == 0 and has_step(receipt, &"stun_apply", &"control/hp_gate"), "armor-only hit cannot stun")
	s.close()
	s = fixture(); target = s.units[1]
	target.vitals.set_hp(1)
	receipt = parity(s, command(s), "lethal hit")
	check(not target.is_alive() and target.control.stunned_turns == 0 and has_step(receipt, &"stun_apply", &"control/dead_target"), "dead target skips stun")
	s.close()
	s = fixture(); target = s.units[1]
	target.control.entangled_turns = 1
	target.combat_perks.definition.entangle_immune = true
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	receipt = parity(s, command(s), "push before stun")
	check(target.cell == Vector2i(4, 3) and target.control.entangled_turns == 0 and target.control.stunned_turns == 1, "push still clears old immune entangle before stun")
	check(states(receipt).size() == 2 and states(receipt)[0]["reason"] == &"push" and states(receipt)[1]["reason"] == &"stunned", "spatial control event precedes new stun")
	s.close()
	s = fixture(); target = s.units[1]
	target.vitals.set_hp(100)
	target.armor.natural["fire"] = 11000
	target.armor.perks = [{"id": "limit", "type": "fire", "branch": "both", "bonus": 3500}]
	var rules := s.context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for definition: AttackDefinition in rules._definitions:
		var copy := AttackRules._copy_definition(definition)
		if copy.id == &"stunning_strike": copy.damage_components = [{"type": "fire", "policy": "standard", "numerator": 1000, "denominator": 1, "source": "control_net_heal", "factor_num": 1, "factor_den": 1}]
		definitions.append(copy)
	s.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	receipt = parity(s, command(s), "physical gate before net healing")
	check(receipt.status == ActionReceipt.APPLIED and target.vitals.get_hp() > 100 and target.control.stunned_turns == 1, "same-hit net healing cannot suppress physical gate")
	s.close()
	s = fixture(); target = s.units[1]
	target.vitals.set_hp(100)
	var item_def := ItemDef.new()
	item_def.id = &"stun_heal"
	var effect := HealOnDamageEffect.new(); effect.heal_amount = 80
	item_def.effects.append(effect)
	var item := s.state.get_owner(target.id).create_item(item_def)
	s.state.get_inventory(target.id).add_item(item)
	receipt = parity(s, command(s), "healing item after stun")
	var kinds: Array = receipt.get_events().map(func(e: Dictionary) -> StringName: return e["kind"])
	check(kinds.find(&"control_changed") >= 0 and kinds.find(&"healed") > kinds.find(&"control_changed") and target.control.stunned_turns == 1, "item reaction follows mandatory stun")
	s.close()

func _reactions_and_ai() -> void:
	var s := fixture()
	var tank := s.units[1]
	var actor := s.units[0]
	s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), s.context)
	parity(s, command(s), "stun opportunist")
	check(tank.guard_stance and tank.action_resources.get_bonus_left() == 1 and not MeleeThreat.threatens(s.context, tank, actor), "stun removes threat without consuming guard charge")
	var path: Array[Vector2i] = [actor.cell, Vector2i(1, 3)]
	var moved := s._queue.submit(MoveCommand.new(actor.id, path, s.context.get_revision()), s.context)
	check(moved.status == ActionReceipt.APPLIED and actor.cell == path[-1] and tank.action_resources.get_bonus_left() == 1, "stunned opportunist permits departure without charge use")
	s.close()
	s = fixture(); tank = s.units[1]
	var ally := s.units[5]
	s.board.move_unit(ally, Vector2i(3, 2))
	s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.COVER, ally.id), s.context)
	parity(s, command(s), "stun cover tank")
	s.units[0].try_refill_turn_resources()
	s.board.move_unit(s.units[0], Vector2i(2, 2))
	var hit := AttackCommand.new(s.units[0].id, ally.id, s.units[0].cell, ally.cell, &"demo_strike", s.context.get_revision())
	var receipt := s._queue.submit(hit, s.context)
	check(receipt.status == ActionReceipt.APPLIED and tank.action_resources.get_bonus_left() == 1 and receipt.get_events().all(func(e: Dictionary) -> bool: return e.get("kind") != &"reaction_used"), "stunned cover tank cannot protect or spend charge")
	s.close()
	s = fixture(); tank = s.units[1]
	s.round_number = 2
	var intent := BattleDemoBT.new().decide(s, tank)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.attack_definition_id == &"stunning_strike", "BT selects owned active stun")
	s.units[0].combat_perks.definition.stun_immune = true
	intent = BattleDemoBT.new().decide(s, tank)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.attack_definition_id == &"demo_strike", "BT falls back for immune target")
	tank.control.stunned_turns = 1
	intent = BattleDemoBT.new().decide(s, tank)
	check(intent.kind == BattleAIIntent.Kind.WAIT, "stunned actor cannot act through BT")
	s.close()

func _faults_and_events() -> void:
	var s := fixture()
	var target := s.units[1]
	var mutate := func(_a: float, _b: float) -> void: target.combat_perks.definition.stun_immune = true
	target.vitals.hp_changed.connect(mutate)
	var receipt := s._queue.submit(command(s), s.context)
	target.vitals.hp_changed.disconnect(mutate)
	check(receipt.status == ActionReceipt.FAULTED and target.vitals.get_hp() < 256 and s.units[0].action_resources.get_main_left() == 0 and target.control.stunned_turns == 0, "callback mutation faults with paid HP prefix before stun")
	s.close()
	s = fixture(); s._queue = ActionQueue.new(2)
	receipt = parity(s, command(s), "command limit")
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"command_limit" and s.units[1].control.stunned_turns == 0, "command limit leaves no unexecuted stun")
	s.close()
	s = fixture(); s._queue = ActionQueue.new(256, 3)
	receipt = parity(s, command(s), "event limit")
	check(receipt.status == ActionReceipt.FAULTED and s.units[1].control.stunned_turns == 1 and states(receipt).size() == 1, "event limit retains executed stun and event")
	s.close()
	var before := ControlState.new().to_dict()
	var after := before.duplicate(true); after["stunned_turns"] = 1
	var event := {"kind": &"control_changed", "target_unit_id": 1, "before": before, "after": after, "reason": &"stunned"}
	check(ActionQueue._valid_control_draft(event), "new exact stun delta accepted")
	after["entangled_turns"] = 1
	check(not ActionQueue._valid_control_draft(event), "stun event cannot forge additional entangle")
	after["entangled_turns"] = 0; event["reason"] = &"stun_refreshed"
	check(not ActionQueue._valid_control_draft(event), "refresh cannot forge first application")

func _combined_order_and_critical() -> void:
	var s := fixture()
	var receipt := parity(s, command(s), "first stun is not retroactive critical")
	var attacks: Array = receipt.get_events().filter(func(e: Dictionary) -> bool: return e["kind"] == &"attacked")
	check(attacks.size() == 1 and not attacks[0]["modifiers"]["critical"], "first application cannot make its own hit critical")
	s.close()
	var losses: Array[float] = []
	for both: bool in [false, true]:
		s = fixture()
		s.units[1].control.stunned_turns = 1
		s.units[1].control.entangled_turns = 1 if both else 0
		receipt = parity(s, command(s), "critical single or combined control")
		losses.append(256.0 - s.units[1].vitals.get_hp())
		s.close()
	check(losses[0] > 0 and losses[0] == losses[1], "both control states produce one critical multiplier")
	s = fixture()
	var rules := s.context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for definition: AttackDefinition in rules._definitions:
		var copy := AttackRules._copy_definition(definition)
		if copy.id == &"stunning_strike": copy.entangle_on_physical_hp = true
		definitions.append(copy)
	s.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	receipt = parity(s, command(s), "both application siblings")
	var changes := states(receipt)
	check(changes.size() == 2 and changes[0]["reason"] == &"entangled" and changes[1]["reason"] == &"stunned", "shared command applies entangle then stun with exact independent deltas")
	s.close()
	s = fixture()
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	s.board.set_terrain(Vector2i(4, 3), TerrainType.Type.VOID)
	receipt = parity(s, command(s), "spatial death before stun")
	check(not s.units[1].is_alive() and s.units[1].control.stunned_turns == 0 and has_step(receipt, &"stun_apply", &"control/dead_target"), "fall death skips pending stun")
	s.close()
	s = fixture()
	s.round_number = 1
	check(s.end_player_turn(), "enter enemy turn for active perk")
	check(s.round_number == 2, "successful player boundary advances round before enemy AI")
	receipt = s.step_enemy()
	check(receipt != null and receipt.status == ActionReceipt.APPLIED and s.units[0].control.stunned_turns == 1 and s.units[1].action_resources.get_main_left() == 0, "session executes BT-selected stun for one main")
	s.close()
