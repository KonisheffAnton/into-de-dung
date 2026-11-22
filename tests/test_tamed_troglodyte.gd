extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL TAMED TROGLODYTE: " + label)

func _run() -> void:
	var profile := HeroHubState.create(772301, 4)
	check(profile != null and profile.start_battle(), "version 4 test profile enters the battle run")
	if profile == null or profile.phase != "battle":
		_finish_early()
		return
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "factory builds a battle for the run phase")
	if bundle.is_empty():
		_finish_early()
		return
	var session := bundle.session as BattleCoreReactionsSession
	var trog: UnitState = null
	var hob: UnitState = null
	var players: Array[UnitState] = []
	var enemy_humans: Array[UnitState] = []
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.PLAYER: players.append(unit)
		if unit.archetype_id == TroglodyteKit.ID: trog = unit
		if session.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"sick_hobgoblin": hob = unit
		if unit.faction == Faction.Type.ENEMY and unit != trog and unit != hob \
			and session.actor_loadouts.get(unit.id, {}).has("class_id"):
			enemy_humans.append(unit)
	check(players.size() == profile.party.size() and trog != null and hob != null,
		"factory keeps the run party, hobgoblin and tamed troglodyte distinct")
	if trog == null or hob == null or players.size() < 2 or enemy_humans.size() < 2:
		session.close()
		_finish_early()
		return
	check(TroglodyteKit.owns(trog) and trog.creature_kind == &"living" and trog.faction == Faction.Type.ENEMY,
		"kit uses durable archetype identity independently of creature kind and faction")
	check(trog.vitals.get_hp() == 24.0 and trog.get_stat(StatTypes.StatType.STRENGTH) == 3.0
		and trog.get_stat(StatTypes.StatType.WEAPON_DAMAGE) == 2.0
		and trog.get_stat(StatTypes.StatType.MOVE_RANGE) == 3.0
		and trog.armor.natural.physical == 0, "factory gives expected health, attributes, movement and no armor")
	if session.state.abilities != null:
		session.state.abilities.team = int(Faction.Type.ENEMY)
		session.state.abilities.stage = "active"
		session.state.abilities.serials[Faction.Type.ENEMY] = 1
		session.state.abilities.mage_allowed = false
	var attacker := players[0]
	for candidate: UnitState in players:
		var class_id: StringName = session.actor_loadouts.get(candidate.id, {}).get("class_id", &"")
		if class_id == &"fighter": attacker = candidate; break
	check(_park_all(session, [Vector2i(3, 3), Vector2i(3, 2)]), "factory units park on floor for attack fixture")
	check(session.board.move_unit(trog, Vector2i(3, 3)) and session.board.move_unit(attacker, Vector2i(3, 2)),
		"personal attacker and troglodyte are adjacent on equal height")
	attacker.stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	attacker.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	attacker.stats.set_base_value(StatTypes.StatType.POWER, 10.0)
	attacker.stats.set_base_value(StatTypes.StatType.MASTERY, 10.0)
	attacker.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	if attacker.combat_perks != null: attacker.combat_perks.definition.sneak_attack = false
	trog.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
	trog.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1000.0)
	trog.vitals.set_hp(100.0)
	trog.vitals.set_balance(0.0)
	trog.armor.natural.physical = 0
	trog.armor.natural.fire = 0
	var attack_id: StringName = session.actor_loadouts.get(attacker.id, {}).get("attack_id", &"")
	var attack := AttackCommand.new(attacker.id, trog.id, attacker.cell, trog.cell, attack_id, session.context.get_revision())
	var attack_capture := ItemSimulationSnapshot.capture(session.state, [])
	check(attack_capture.code == ItemSnapshotResult.Code.OK, "attack fixture snapshot: " + attack_capture.reason)
	if attack_capture.code != ItemSnapshotResult.Code.OK: session.close(); _finish_early(); return
	var attack_before := attack_capture.snapshot.to_dict()
	var attack_rng := session.context.get_rng().to_dict().duplicate(true)
	var attack_counters := session.context.simulation_counters()
	var attack_admission := SummonAdmission.values(session.context)
	var attack_preview := ForecastSimulation.run(session.context, session._queue, attack)
	check(attack_preview.status == ActionReceipt.APPLIED
		and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == attack_before
		and session.context.get_rng().to_dict() == attack_rng and session.context.simulation_counters() == attack_counters
		and SummonAdmission.values(session.context) == attack_admission,
		"ordinary personal attack preview leaves full live state, RNG, counters and admission unchanged")
	var attack_receipt := session._queue.submit(attack, session.context)
	var after_attack := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	check(attack_receipt.status == ActionReceipt.APPLIED and attack_receipt.get_events() == attack_preview.events
		and attack_receipt.get_steps() == attack_preview.steps and after_attack == attack_preview.snapshot_after
		and session.context.get_rng().to_dict() == attack_preview.rng_after
		and session.context.simulation_counters() == attack_preview.counters_after
		and SummonAdmission.values(session.context) == attack_preview.admission_after,
		"live ordinary attack matches preview full snapshot, RNG, counters, admission and receipt")
	check(is_equal_approx(trog.vitals.get_hp(), 95.0), "personal 7-point attack is reduced once to five HP damage")
	attacker.action_resources._set_for_refill(1, 0)
	trog.action_resources._set_for_refill(1, 0)
	var owner := session.state.get_owner(trog.id)
	var armor_view := ArmorRuntime.capture(owner)
	check(not armor_view.is_empty(), "factory troglodyte has a valid armor view")
	if not armor_view.is_empty():
		var split: Array[Dictionary] = [
			{"type": "physical", "policy": "standard", "source": "first", "numerator": 7, "denominator": 1},
			{"type": "physical", "policy": "standard", "source": "second", "numerator": 3, "denominator": 1}
		]
		var plan := _prepare_hit(session, trog, attacker, armor_view, &"attack", split)
		var after: Array = plan.get("thick_skin", {}).get("raw_after", [])
		check(plan.get("reason", &"") == &"" and after.size() == 2
			and int(after[0].numerator) + int(after[1].numerator) == 8,
			"direct attack spends one reduction across split 7+3 damage")
		var one: Array[Dictionary] = [{"type": "physical", "policy": "standard", "source": "tiny", "numerator": 1, "denominator": 1}]
		plan = _prepare_hit(session, trog, attacker, armor_view, &"attack", one)
		after = plan.get("thick_skin", {}).get("raw_after", [])
		check(after.size() == 1 and int(after[0].numerator) == 0, "direct one-point attack becomes zero")
		var mage_raw: Array[Dictionary] = [{"type": "physical", "policy": "standard", "source": "spell", "numerator": 3, "denominator": 1}]
		plan = _prepare_hit(session, trog, attacker, armor_view, &"mage", mage_raw)
		after = plan.get("thick_skin", {}).get("raw_after", [])
		check(after.size() == 1 and int(after[0].numerator) == 1, "direct mage hit receives the same one-time reduction")
		for excluded: StringName in [&"status", &"cell", &"fall", &"collision"]:
			plan = _prepare_hit(session, trog, attacker, armor_view, excluded, one)
			after = plan.get("thick_skin", {}).get("raw_after", [])
			var untouched: Array = plan.get("raw", [])
			check(plan.get("reason", &"") == &"" and after.is_empty()
				and untouched.size() == 1 and int(untouched[0].numerator) == 1,
				"non-direct source bypasses skin reduction: " + String(excluded))
	var initial := ItemSimulationSnapshot.capture(session.state, [])
	check(initial.code == ItemSnapshotResult.Code.OK, "battle snapshot accepts the tamed identity")
	if initial.code == ItemSnapshotResult.Code.OK:
		var imported := ItemSimulationSnapshot.from_dict(initial.snapshot.to_dict())
		var catalogue: Dictionary = {}
		for item_owner: ItemOwnerState in session.state.get_owners(): catalogue.merge(item_owner._definitions, true)
		var restored := imported.snapshot.instantiate(catalogue) if imported.snapshot != null else ItemSnapshotResult.new()
		check(imported.code == ItemSnapshotResult.Code.OK and restored.code == ItemSnapshotResult.Code.OK
			and restored.state != null and TroglodyteKit.owns(restored.state.get_board().get_unit_by_id(trog.id)),
			"snapshot roundtrip and instantiate retain the kit identity")
	var victim := attacker
	var victim_receipt := _kill_adjacent(session, trog, victim, false)
	var fresh := _corpse_event(victim_receipt)
	check(fresh.get("remains") == "fresh" and fresh.get("fresh_turns_left") == 3,
		"queued death of a registered living unit creates an adjacent fresh body")
	if fresh.is_empty():
		session.close(); _finish_early(); return
	trog.stats.set_base_value(StatTypes.StatType.HP_MAX, 24.0)
	trog.vitals.set_hp(20.0)
	trog.armor.fractional = false
	check(CannibalizeCommand.new(trog.id, int(fresh.id), session.context.get_revision()).validate(session.context) == &"cannibalize/fractional_hp_required", "legacy integer HP cannot admit fractional healing")
	trog.armor.fractional = true
	trog.vitals.set_hp(20.5)
	var intent := BattleDemoBT.new().decide(session, trog)
	check(intent.kind == BattleAIIntent.Kind.CANNIBALIZE and intent.corpse_id == int(fresh.id),
		"hungry BT selects a nearby fresh corpse before other behavior")
	var command := CannibalizeCommand.new(trog.id, int(fresh.id), session.context.get_revision())
	var snapshot_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters()
	var admission_before := SummonAdmission.values(session.context)
	var preview := ForecastSimulation.run(session.context, session._queue, command)
	check(preview.status == ActionReceipt.APPLIED and preview.snapshot_before == snapshot_before
		and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == snapshot_before
		and rng_before == session.context.get_rng().to_dict() and counters_before == session.context.simulation_counters()
		and admission_before == SummonAdmission.values(session.context),
		"cannibalism preview is isolated over full snapshot, RNG, counters and admission")
	var receipt := session._queue.submit(command, session.context)
	var consumed_snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	check(receipt.status == ActionReceipt.APPLIED and receipt.status == preview.status
		and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps
		and consumed_snapshot == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after
		and session.context.simulation_counters() == preview.counters_after
		and SummonAdmission.values(session.context) == preview.admission_after,
		"live cannibalism matches preview full snapshot, RNG, counters, admission and receipt")
	check(is_equal_approx(trog.vitals.get_hp(), 22.25) and trog.action_resources.get_main_left() == 0
		and session.state.environment.corpses.is_empty(), "half missing fractional HP is restored and one main action consumes the corpse")
	var consumed := false
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"corpse_consumed":
			consumed = event.actor_unit_id == trog.id and event.target_unit_id == trog.id
	check(consumed, "self-target corpse-consumed event is published for buff routing")
	trog.action_resources._set_for_refill(1, 0)
	var no_food_intent := BattleDemoBT.new().decide(session, trog)
	check(no_food_intent.kind != BattleAIIntent.Kind.CANNIBALIZE,
		"BT does not hunt or target a corpse after fresh food is gone")
	var rejected_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var reject_counters := session.context.simulation_counters()
	var doubled := CannibalizeCommand.new(trog.id, int(fresh.id), session.context.get_revision())
	check(doubled.validate(session.context) == &"cannibalize/no_fresh_corpse"
		and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == rejected_before
		and session.context.simulation_counters() == reject_counters, "a second consume is denied without mutation")
	var undead_victim := enemy_humans[0]
	var bones_receipt := _kill_adjacent(session, trog, undead_victim, true)
	var bones := _corpse_event(bones_receipt)
	check(bones.get("remains") == "bones" and bones.get("fresh_turns_left") == 0,
		"queued undead death leaves bones immediately")
	trog.vitals.set_hp(18.0)
	trog.action_resources._set_for_refill(1, 0)
	check(CannibalizeCommand.new(trog.id, int(bones.get("id", 0)), session.context.get_revision()).validate(session.context)
		== &"cannibalize/no_fresh_corpse", "bones cannot be eaten")
	var full_receipt := _kill_adjacent(session, trog, hob, false)
	var full_corpse := _corpse_event(full_receipt)
	trog.vitals.set_hp(trog.get_stat(StatTypes.StatType.HP_MAX))
	check(CannibalizeCommand.new(trog.id, int(full_corpse.get("id", 0)), session.context.get_revision()).validate(session.context)
		== &"cannibalize/full_hp", "full-health actor cannot eat")
	trog.vitals.set_hp(18.0)
	trog.control.stunned_turns = 1
	var control_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	check(CannibalizeCommand.new(trog.id, int(full_corpse.get("id", 0)), session.context.get_revision()).validate(session.context)
		== &"control/stunned" and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == control_before,
		"stunned actor is denied without state mutation")
	trog.control.stunned_turns = 0
	var distant_receipt := _kill_distant(session, trog, enemy_humans[1])
	var distant := _corpse_event(distant_receipt)
	trog.action_resources._set_for_refill(1, 0)
	check(CannibalizeCommand.new(trog.id, int(distant.get("id", 0)), session.context.get_revision()).validate(session.context)
		== &"cannibalize/out_of_reach", "distant body cannot be eaten")
	var stale := CannibalizeCommand.new(trog.id, int(distant.get("id", 0)), maxi(0, session.context.get_revision() - 1))
	check(stale.validate(session.context) == &"cannibalize/stale_revision", "old command revision is rejected")
	var live_targets: Array[UnitState] = []
	for player: UnitState in players:
		if player.is_alive(): live_targets.append(player)
	_troglodyte_ai_target_order(session, trog, live_targets)
	trog.creature_kind = &"undead"
	var undead_death := _kill_unit(session, trog)
	var undead_corpse := _corpse_event(undead_death)
	check(undead_corpse.get("remains") == "bones" and undead_corpse.get("fresh_turns_left") == 0,
		"queued death of an undead troglodyte leaves bones immediately")
	session.close()
	for mutation: String in ["identity", "admission", "rng"]: _test_cannibal_callback(mutation)
	print("TAMED TROGLODYTE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _prepare_hit(session: BattleCoreReactionsSession, target: UnitState, attacker: UnitState,
		armor_view: Dictionary, kind: StringName, raw: Array[Dictionary]) -> Dictionary:
	var source := DamageSource.new(kind, 1 if kind == &"mage" else 0,
		Vector2i(-1, -1) if kind == &"mage" else attacker.cell,
		0 if kind == &"mage" else attacker.id, 0 if kind == &"mage" else attacker.id)
	var request := ArmorAttack.request(target.id, raw, source)
	return ArmorHitExecutor.prepare(request, armor_view, target.vitals.get_hp(),
		target.get_stat(StatTypes.StatType.HP_MAX), session.context.get_rng(), false, session.context)

func _kill_adjacent(session: BattleCoreReactionsSession, actor: UnitState, victim: UnitState, undead: bool) -> ActionReceipt:
	for direction: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell := actor.cell + direction
		if not session.board.is_in_bounds(cell) or session.board.occupant_at(cell) != null: continue
		session.board.set_terrain(cell, TerrainType.Type.FLOOR)
		session.board.set_height_steps(cell, session.board.get_height_steps(actor.cell))
		if not session.board.move_unit(victim, cell): continue
		victim.creature_kind = &"undead" if undead else &"living"
		return session._queue.submit(DeathCommand.new(victim.id, DamageSource.new(&"test", 0, cell)), session.context)
	return ActionReceipt.new()

func _kill_distant(session: BattleCoreReactionsSession, actor: UnitState, victim: UnitState) -> ActionReceipt:
	for y: int in session.board.height:
		for x: int in session.board.width:
			var cell := Vector2i(x, y)
			if absi(cell.x - actor.cell.x) + absi(cell.y - actor.cell.y) != 2 or session.board.occupant_at(cell) != null: continue
			session.board.set_terrain(cell, TerrainType.Type.FLOOR)
			session.board.set_height_steps(cell, session.board.get_height_steps(actor.cell))
			if not session.board.move_unit(victim, cell): continue
			return session._queue.submit(DeathCommand.new(victim.id, DamageSource.new(&"test", 0, cell)), session.context)
	return ActionReceipt.new()

func _kill_unit(session: BattleCoreReactionsSession, unit: UnitState) -> ActionReceipt:
	return session._queue.submit(DeathCommand.new(unit.id, DamageSource.new(&"test", 0, unit.cell)), session.context)

func _corpse_event(receipt: ActionReceipt) -> Dictionary:
	check(receipt.status == ActionReceipt.APPLIED, "queued death command is applied: " + String(receipt.status) + "/" + String(receipt.reason))
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"corpse_created": return event.get("corpse", {})
	return {}

func _park_all(session: BattleCoreReactionsSession, reserved: Array[Vector2i]) -> bool:
	for y: int in session.board.height:
		for x: int in session.board.width:
			var cell := Vector2i(x, y)
			session.board.set_terrain(cell, TerrainType.Type.FLOOR)
			session.board.set_height_steps(cell, 0)
	for unit: UnitState in session.board.get_alive_units():
		var parked := false
		for y: int in session.board.height:
			for x: int in session.board.width:
				var cell := Vector2i(x, y)
				if reserved.has(cell) or session.board.occupant_at(cell) != null: continue
				if session.board.move_unit(unit, cell):
					parked = true
					break
			if parked: break
		if not parked: return false
	return true

func _troglodyte_ai_target_order(session: BattleCoreReactionsSession, trog: UnitState, targets: Array[UnitState]) -> void:
	if targets.size() < 2: check(false, "AI targeting has two live hostile units"); return
	var center := Vector2i(3, 3)
	var left := Vector2i(2, 3)
	var right := Vector2i(4, 3)
	check(_park_all(session, [center, left, right]), "AI fixture parks all living units outside target geometry")
	check(session.board.move_unit(trog, center) and session.board.move_unit(targets[0], left)
		and session.board.move_unit(targets[1], Vector2i(4, 4)), "AI target fixture starts with a nearer high-health hostile")
	trog.action_resources._set_for_refill(1, 0)
	trog.vitals.set_hp(trog.get_stat(StatTypes.StatType.HP_MAX))
	targets[0].vitals.set_hp(20.0); targets[1].vitals.set_hp(1.0)
	var intent := BattleDemoBT.new().decide(session, trog)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.target_id == targets[0].id,
		"BT ranks Manhattan distance before a farther low-HP target")
	check(session.board.move_unit(targets[1], right), "second hostile moves to the same Manhattan range")
	targets[0].vitals.set_hp(20.0); targets[1].vitals.set_hp(10.0)
	intent = BattleDemoBT.new().decide(session, trog)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.target_id == targets[1].id,
		"equal-distance BT tie selects lower current HP")
	targets[0].vitals.set_hp(10.0); targets[1].vitals.set_hp(10.0)
	intent = BattleDemoBT.new().decide(session, trog)
	check(intent.kind == BattleAIIntent.Kind.ATTACK and intent.target_id == mini(targets[0].id, targets[1].id),
		"equal-distance and equal-HP BT tie selects lower unit ID")

func _finish_early() -> void:
	print("TAMED TROGLODYTE RESULTS: %d passed, %d failed" % [passed, failed + 1])
	quit(1)

func _test_cannibal_callback(mutation: String) -> void:
	var profile := HeroHubState.create(772302, 4)
	profile.start_battle()
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "callback fixture builds")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	session.state.abilities = null
	var actor: UnitState = null
	var victim: UnitState = null
	for unit: UnitState in session.units:
		if TroglodyteKit.owns(unit): actor = unit
		elif unit.faction == Faction.Type.ENEMY: victim = unit
	if actor == null or victim == null: check(false, "callback fixture has actors"); session.close(); return
	var corpse := _corpse_event(_kill_adjacent(session, actor, victim, false))
	if corpse.is_empty(): check(false, "callback fixture has real corpse"); session.close(); return
	actor.vitals.set_hp(18.0)
	actor.action_resources._set_for_refill(1, 0)
	var mutate := func(_before: float, _after: float) -> void:
		match mutation:
			"identity": actor.archetype_id = &"changed_during_heal"
			"admission": session.context._move_rules._admitted_unit_ids.erase(actor.id)
			"rng": session.context.get_rng().next_int(&"combat", 100)
	actor.vitals.hp_changed.connect(mutate)
	var receipt := session._queue.submit(CannibalizeCommand.new(actor.id, int(corpse.id), session.context.get_revision()), session.context)
	check(receipt.status == ActionReceipt.FAULTED and actor.vitals.get_hp() == 21.0 and actor.action_resources.get_main_left() == 0 and session.state.environment.corpses_at(corpse.cell).is_empty(), "heal callback faults and retains paid completed prefix: " + mutation)
	actor.vitals.hp_changed.disconnect(mutate)
	session.close()
