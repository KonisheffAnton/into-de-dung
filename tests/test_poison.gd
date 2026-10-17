extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL POISON: " + label)

func fixture(keep_healing: bool = false) -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s._enemy_index = s._enemy_ids.size()
	s.step_enemy()
	s.state.environment.fires.clear()
	if s.state.environment.hazards.has("acid"): s.state.environment.hazards.acid.clear()
	for unit: UnitState in s.units:
		unit.control.stunned_turns = 0; unit.control.entangled_turns = 0
		unit.guard_stance = false
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0); unit.vitals.set_hp(80.0)
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values():
			item.armor_remaining = 0
			# Амулет лечит ответом на урон; отдельные проверки ниже измеряют сам тик.
			if not keep_healing and item.get_definition().id == &"demo_guard_amulet": s.state.get_inventory(unit.id).remove_item(item)
	return s

func target(s: BattleCoreReactionsSession) -> UnitState:
	return s.board.get_unit_by_id(s.living_ids(Faction.Type.ENEMY)[0])

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "capture: " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func cast(s: BattleCoreReactionsSession, unit: UnitState) -> ActionReceipt:
	return s.cast_mage_spell(&"mage.test_poison", unit.id)

func run() -> void:
	models()
	gates_and_ticks()
	faults_and_limits()
	await parity()
	healing_and_authored()
	print("POISON RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func models() -> void:
	var source := DamageSource.new(&"mage", 26, Vector2i(-1, -1)).to_dict()
	var empty := ElementalState.new().to_dict()
	var burn := ElementalRules.transition(empty, &"burning", 50, source).after as Dictionary
	check(burn.burning_stacks == 1 and burn.burning_ticks == 2, "first burn always lasts two ticks")
	burn.burning_ticks = ElementalState.MAX_VALUE
	burn = ElementalRules.transition(burn, &"burning", 1, source).after
	check(burn.burning_stacks == 2 and burn.burning_ticks == 2, "burn refreshes long old duration without overflow")
	burn = ElementalRules.transition(burn, &"burn_tick", 1, {}).after
	burn = ElementalRules.transition(burn, &"burning", 1, source).after
	check(burn.burning_stacks == 3 and burn.burning_ticks == 2, "burn refresh after tick retains all potency")
	var state := ElementalState.new(); state.authored = true
	var poison := ElementalRules.transition(state.to_dict(), &"poison", 1, source).after as Dictionary
	poison = ElementalRules.transition(poison, &"poison", 1, source).after
	check(poison.poison_stacks == 2 and poison.poison_ticks == 2 and StatusContributions.total(poison.poison_contributions).numerator == 2, "poison accumulates potency duration and authored damage")
	var restored := ElementalState.from_dict(poison)
	check(restored != null and restored.to_dict() == poison, "poison codec roundtrip")
	restored.poison_contributions[0].source.source_instance_id = 25
	check(poison.poison_contributions[0].source.source_instance_id == 26, "restored poison contributions detached")
	for field: String in ["poison_stacks", "poison_ticks", "poison_source", "poison_contributions"]:
		var missing := poison.duplicate(true); missing.erase(field)
		check(not ElementalState.valid(missing), "reject missing " + field)
	var bad := poison.duplicate(true); bad.poison_ticks = true
	check(not ElementalState.valid(bad), "reject bool duration")
	bad = poison.duplicate(true); bad.poison_stacks = 0
	check(not ElementalState.valid(bad), "reject active duration without potency")
	bad = poison.duplicate(true); bad.poison_contributions.clear()
	check(not ElementalState.valid(bad), "reject contribution count mismatch")
	bad = empty.duplicate(true); bad.schema_version = 3
	check(not ElementalState.valid(bad), "old elemental schema refused")
	poison = ElementalRules.transition(poison, &"poison_tick", 1, {}).after
	check(poison.poison_stacks == 2 and poison.poison_ticks == 1, "tick spends duration but retains potency")
	poison = ElementalRules.transition(poison, &"poison", 1, source).after
	check(poison.poison_stacks == 3 and poison.poison_ticks == 2, "reapply adds one tick to remaining duration")
	for effect: StringName in [&"wet", &"freeze", &"burning"]:
		var after := ElementalRules.transition(poison, effect, 1, source, true).after as Dictionary
		check(after.poison_stacks == 3 and after.poison_ticks == 2, "poison independent of " + String(effect))

func gates_and_ticks() -> void:
	var s := fixture(); var u := target(s)
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	var hp := u.vitals.get_hp()
	var receipt := cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp and u.elemental.poison_stacks == 0, "armor-only direct hit cannot poison: " + String(receipt.reason))
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = 0
	u.armor.shield = SpellShield.make(&"mage.shield", 6, 1)
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp and u.elemental.poison_stacks == 0, "shield absorbs direct hit and prevents poison")
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() < hp and u.elemental.poison_stacks == 1 and u.elemental.poison_ticks == 1, "direct HP hit applies first poison: %s hp=%s status=%s" % [receipt.reason, u.vitals.get_hp(), u.elemental.to_dict()])
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.elemental.poison_stacks == 2 and u.elemental.poison_ticks == 2, "second direct hit adds potency and duration")
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	u.armor.natural = {"physical": 7500, "fire": 7500}
	var armor := ArmorRuntime.capture(s.state.get_owner(u.id))
	hp = u.vitals.get_hp()
	receipt = s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp - 2 and u.elemental.poison_ticks == 1 and u.elemental.poison_stacks == 2, "own-turn poison tick bypasses armor and natural resistance: %s hp=%s status=%s" % [receipt.reason, u.vitals.get_hp(), u.elemental.to_dict()])
	check(ArmorRuntime.capture(s.state.get_owner(u.id)) == armor, "poison never damages armor")
	receipt = s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp - 4 and u.elemental.poison_ticks == 0 and u.elemental.poison_stacks == 0 and u.elemental.poison_source.is_empty(), "last tick deals full damage and clears poison")
	s.close()
	s = fixture(); u = target(s); u.vitals.set_hp(1.0)
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and not u.is_alive() and u.elemental.poison_stacks == 0, "lethal direct hit does not apply poison to corpse")
	s.close()
	s = fixture(); u = target(s)
	cast(s, u); u.vitals.set_hp(1.0)
	receipt = s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	var deaths := 0
	for event: Dictionary in receipt.get_events():
		if event.kind == &"died": deaths += 1
	check(receipt.status == ActionReceipt.APPLIED and not u.is_alive() and deaths == 1, "lethal poison tick records one death: %s hp=%s deaths=%d" % [receipt.reason, u.vitals.get_hp(), deaths])
	s.close()

func faults_and_limits() -> void:
	var s := fixture(); var u := target(s)
	u.elemental.poison_stacks = 1; u.elemental.poison_ticks = ElementalState.MAX_VALUE
	u.elemental.poison_source = DamageSource.new(&"mage", 26, Vector2i(-1, -1)).to_dict()
	var before := snapshot(s)
	check(cast(s, u).status == ActionReceipt.REJECTED and snapshot(s) == before, "poison overflow rejected before mana damage or status")
	u.vitals.set_hp(1.0)
	check(cast(s, u).status == ActionReceipt.APPLIED and not u.is_alive(), "lethal direct hit ignores unnecessary poison overflow")
	s.close()

func healing_and_authored() -> void:
	var s := fixture(true); var u := target(s)
	u.guard_stance = true
	var hp := u.vitals.get_hp()
	var receipt := cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp and u.elemental.poison_stacks == 1, "gross HP hit still poisons when item reaction heals all damage")
	s.close()
	s = fixture(); u = target(s)
	u.armor.fractional = true; u.elemental.authored = true
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.APPLIED and u.elemental.poison_contributions.size() == 1, "fractional target records mage contribution")
	var before := snapshot(s)
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = owner._definitions[id]
	var restored := ItemSimulationSnapshot.from_dict(before).snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK, "authored poison full restore")
	if restored.state != null:
		var copy := restored.state.get_board().get_unit_by_id(u.id)
		copy.elemental.poison_contributions[0].source.source_instance_id = 25
		check(u.elemental.poison_contributions[0].source.source_instance_id == 26, "restored full poison branch detached")
		ForecastSimulation.close(restored.state)
	var without_deck := before.duplicate(true)
	for row: Dictionary in without_deck.board_snapshot.board.units:
		if row.id == u.id:
			row.elemental.poison_source.source_instance_id = 25
			row.elemental.poison_contributions[0].source.source_instance_id = 25
	check(ItemSimulationSnapshot.from_dict(without_deck).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "card poison source requires deck even inside historical contribution")
	u.elemental.poison_contributions[0].numerator = 3
	u.elemental.poison_contributions[0].denominator = 2
	hp = u.vitals.get_hp()
	receipt = s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == hp - 1.5 and u.elemental.poison_contributions.is_empty(), "fractional poison is exact and last tick clears contribution")
	s.close()
	s = fixture(); u = target(s)
	var mutate := func(_old: float, _new: float) -> void: u.elemental.wet_turns = 1
	u.vitals.hp_changed.connect(mutate)
	receipt = cast(s, u)
	check(receipt.status == ActionReceipt.FAULTED and s.state.abilities.mana == 5 and u.vitals.get_hp() == 76 and u.elemental.poison_stacks == 0, "HP callback mutation faults after paid hit before poison")
	u.vitals.hp_changed.disconnect(mutate)
	s.close()

func parity() -> void:
	var s := fixture(); var u := target(s)
	var before := snapshot(s)
	var forecast := ForecastSimulation.run_prepared(s.prepare_mage_forecast(&"mage.test_poison", u.id))
	check(forecast.status == ActionReceipt.APPLIED and snapshot(s) == before, "poison forecast succeeds without touching live")
	var worker := ActionForecastWorker.new()
	worker.start(s.prepare_mage_forecast(&"mage.test_poison", u.id))
	var threaded: ForecastSimulation
	while threaded == null:
		threaded = worker.take_finished()
		if threaded == null: await process_frame
	check(threaded.snapshot_after == forecast.snapshot_after and threaded.events == forecast.events and threaded.steps == forecast.steps and threaded.rng_after == forecast.rng_after and threaded.counters_after == forecast.counters_after and threaded.admission_after == forecast.admission_after, "forecast worker full parity")
	worker.close()
	var live := BattleExecutionWorker.new()
	check(live.start(s, &"cast_mage_spell", [&"mage.test_poison", u.id], true), "live worker starts poison")
	var completed := live.take_finished(true)
	var receipt: ActionReceipt = completed.result
	check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after and SummonAdmission.values(s.context) == forecast.admission_after, "live worker full poison parity")
	var turn := TurnForecast.run_prepared(TurnForecast.prepare(s))
	check(turn.status == ActionReceipt.APPLIED, "end turn forecast with active poison")
	s.close()
