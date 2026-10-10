extends SceneTree

var passed: int = 0
var failed: int = 0

class HitCommand extends DamageCommand:
	var id: int
	var raw: Array[Dictionary]
	var kind: StringName
	func _init(target: int, parts: Array[Dictionary], source_kind: StringName = &"test") -> void:
		id = target; raw = parts.duplicate(true); kind = source_kind
		request = ArmorAttack.request(id, raw, DamageSource.new(kind, 0, Vector2i.ZERO))
	func get_kind() -> StringName: return &"status_test_hit"
	func copy_for_queue() -> Command: return HitCommand.new(id, raw, kind)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(context: ActionContext) -> CommandStepResult:
		var target := context.get_state().get_board().get_unit_by_id(id)
		var guard := SpatialRules.capture_guard(context, [target], [target.cell], {id: [StatTypes.StatType.HP_MAX]})
		return ArmorHitExecutor.execute(ArmorAttack.request(id, raw, DamageSource.new(kind, 0, target.cell)), guard, context)["result"]

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	_transitions()
	_freeze_gate()
	_shatter()
	_movement()
	_turn_order()
	_parity_and_faults()
	_helpers()
	_forced_chain_and_critical()
	_perk_and_transit()
	print("STATUS EFFECTS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_height_steps(Vector2i(x, y), 0)
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	# Старый fixture проверяет прежний срез без capability K18.
	session.state.abilities = null
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	session.state.environment.fires.clear()
	for unit: UnitState in session.units:
		if unit.control != null:
			unit.control.stunned_turns = 0; unit.control.entangled_turns = 0
		unit.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in session.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
		if unit.is_alive():
			unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
			unit.vitals._hp = 100.0
			unit.action_resources._main_left = 10
			unit.move_points_left = 20.0
	session.board.move_unit(session.units[1], Vector2i(2, 2))
	return session

func _cast(s: BattleCoreReactionsSession, effect: StringName, ticks: int = 1) -> ActionReceipt:
	return s._queue.submit(ElementalCastCommand.new(s.units[0].id, s.units[1].id, effect, s.context.get_revision(), ticks), s.context)

func _bleed(s: BattleCoreReactionsSession, unit: UnitState, stacks: int = 1, ticks: int = 3) -> void:
	unit.bleeding.stacks = stacks; unit.bleeding.ticks_left = ticks
	unit.bleeding.source = DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
	unit.bleeding.hit_id = "fixture"

func _transitions() -> void:
	var s := _fixture()
	var u := s.units[1]
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.wet_turns == 3 and u.elemental.frozen_turns == 0, "dry freeze becomes wet")
	_check(_cast(s, &"freeze", 2).status == ActionReceipt.APPLIED and u.elemental.wet_turns == 0 and u.elemental.frozen_turns == 2, "wet converts to frozen, configured duration")
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 3, "frozen extends without wet")
	_check(ControlRules.action_reason(u) == &"control/frozen" and ControlRules.action_reason(u, true) == &"control/frozen", "frozen blocks voluntary actions and movement")
	u.control.stunned_turns = 1
	_check(_cast(s, &"burning").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 0 and u.elemental.wet_turns == 3 and u.elemental.burning_ticks == 0, "first fire thaws only")
	_check(u.control.stunned_turns == 1, "thaw preserves ordinary stun")
	_bleed(s, u, 2)
	_check(_cast(s, &"burning").status == ActionReceipt.APPLIED and u.elemental.wet_turns == 0 and u.elemental.burning_ticks == 0 and u.bleeding.stacks == 2, "second fire consumes wet and preserves bleed")
	_check(_cast(s, &"burning", 2).status == ActionReceipt.APPLIED and u.elemental.burning_ticks == 2 and u.elemental.burning_stacks == 1 and u.bleeding.stacks == 0, "third fire ignites and clears all bleed")
	_check(_cast(s, &"burning", 3).status == ActionReceipt.APPLIED and u.elemental.burning_ticks == 5 and u.elemental.burning_stacks == 2, "burning adds stacks and source duration")
	_check(_cast(s, &"wet").status == ActionReceipt.APPLIED and u.elemental.burning_ticks == 0 and u.elemental.wet_turns == 3, "wet extinguishes")
	u.elemental.wet_turns = 1
	_check(_cast(s, &"wet").status == ActionReceipt.APPLIED and u.elemental.wet_turns == 3, "wet refreshes")
	s.close()

func _freeze_gate() -> void:
	var s := _fixture()
	var u := s.units[1]
	var equipment: Array[ItemInstance] = []
	for item: ItemInstance in s.state.get_owner(u.id)._items.values():
		if item.get_definition().armor_max > 0 and item._placement >= ItemOwnerState.EQUIPMENT_BASE: equipment.append(item)
	_check(not equipment.is_empty(), "freeze fixture has armor")
	for item: ItemInstance in equipment: item.armor_remaining = item.get_definition().armor_max
	_check(_cast(s, &"wet").status == ActionReceipt.APPLIED and u.elemental.wet_turns == 3, "wet ignores full armor")
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 0 and u.elemental.wet_turns == 3, "failed armor gate keeps wet")
	_check(_cast(s, &"burning").status == ActionReceipt.APPLIED and u.elemental.wet_turns == 3, "character fire cannot apply through full armor")
	var maximum: int = ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(u.id)))["maximum"]
	var remainder := maximum / 2
	for item: ItemInstance in equipment:
		item.armor_remaining = mini(remainder, item.get_definition().armor_max)
		remainder -= item.armor_remaining
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 0, "exact 50 percent rejects freeze")
	for item: ItemInstance in equipment:
		if item.armor_remaining > 0:
			item.armor_remaining -= 1
			break
	u.combat_perks.definition.stun_immune = true
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 1, "below 50 percent allows freeze despite stun immunity")
	u.elemental.frozen_turns = 0; u.elemental.wet_turns = 3; u.elemental.freeze_immune = true
	_check(_cast(s, &"freeze").status == ActionReceipt.APPLIED and u.elemental.frozen_turns == 0 and u.elemental.wet_turns == 3, "separate freeze immunity preserves wet")
	s.close()

func _shatter() -> void:
	for source: StringName in [&"attack", &"status", &"collision", &"fall"]:
		for damage: int in [10, 11]:
			var s := _fixture()
			var u := s.units[1]
			u.elemental.frozen_turns = 1; u.vitals._hp = 20.0
			var raw: Array[Dictionary] = [{"type": "physical", "policy": "hp_only_natural", "source": "test", "numerator": damage, "denominator": 1}]
			var receipt := s._queue.submit(HitCommand.new(u.id, raw, source), s.context)
			_check(receipt.status == ActionReceipt.APPLIED, "individual %s damage applies: %s" % [source, receipt.reason])
			var hit_after := -1
			for event: Dictionary in receipt.get_events():
				if event["kind"] == &"hit_resolved": hit_after = event["hit"]["hp_after"]
			_check(u.is_alive() == (damage == 10) and hit_after == (10 if damage == 10 else 0), "%s strict shatter boundary %d" % [source, damage])
			_check(s.state.environment.corpses_at(u.cell).size() == (0 if damage == 10 else 1), "shatter creates one body")
			s.close()
	var s := _fixture()
	var u := s.units[1]
	u.elemental.frozen_turns = 1; u.vitals._hp = 20.0
	# Уязвимость/сопротивление fire >100% даёт лечащую часть того же hit.
	u.armor.natural["fire"] = 20000
	u.armor.perks.append({"id": "heal_fire", "type": "fire", "branch": "natural", "bonus": 15000})
	var raw: Array[Dictionary] = [{"type": "physical", "policy": "hp_only_natural", "source": "test", "numerator": 12, "denominator": 1}, {"type": "fire", "policy": "standard", "source": "test", "numerator": 4, "denominator": 1}]
	var receipt := s._queue.submit(HitCommand.new(u.id, raw), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and not u.is_alive(), "gross damage 12 before healing 4 shatters 20 HP: " + String(receipt.reason))
	s.close()

func _movement() -> void:
	var s := _fixture()
	var u := s.units[0]
	_bleed(s, u, 2)
	var path: Array[Vector2i] = [u.cell, Vector2i(0, 1), Vector2i(0, 0)]
	var receipt := s._queue.submit(MoveCommand.new(u.id, path, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == 92.0 and u.bleeding.ticks_left == 3, "two cells cost 2 damage per stack each without consuming ticks")
	s.close()
	s = _fixture(); u = s.units[0]
	_bleed(s, u)
	s.state.environment.ignite(Vector2i(0, 1), "burning")
	path = [u.cell, Vector2i(0, 1)]
	receipt = s._queue.submit(MoveCommand.new(u.id, path, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.vitals.get_hp() == 98.0 and u.bleeding.stacks == 0 and u.elemental.burning_stacks == 1, "movement bleed precedes burning entry and cure")
	s.close()
	s = _fixture(); u = s.units[0]
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	s.state.environment.ignite(Vector2i(0, 1))
	path = [u.cell, Vector2i(0, 1)]
	receipt = s._queue.submit(MoveCommand.new(u.id, path, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.bleeding.stacks == 1 and u.bleeding.ticks_left == 3, "spikes apply bleed ignoring armor")
	s.close()
	s = _fixture(); u = s.units[0]
	_bleed(s, u, 1, 1); u.vitals._hp = 2.0
	path = [u.cell, Vector2i(0, 1), Vector2i(0, 0)]
	receipt = s._queue.submit(MoveCommand.new(u.id, path, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.INTERRUPTED and not u.is_alive() and u.cell == Vector2i(0, 1), "movement death stops next edge")
	s.close()

func _turn_order() -> void:
	var s := _fixture()
	var u := s.units[1]
	_bleed(s, u, 3, 1)
	s.state.environment.ignite(u.cell, "burning")
	var receipt := s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.bleeding.stacks == 0 and u.elemental.burning_ticks == 0 and _raw_damage(receipt) == 1, "turn cell applies then one burn tick, no cured bleed tick: " + String(receipt.reason))
	_bleed(s, u, 2, 3)
	u.elemental.wet_turns = 3
	receipt = s._queue.submit(BleedingTurnCommand.new(u.faction, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.bleeding.ticks_left == 2 and u.elemental.wet_turns == 0 and _raw_damage(receipt) == 2, "wet consumes floor application then remaining bleed ticks: " + String(receipt.reason))
	u.elemental.wet_turns = 3; u.elemental.frozen_turns = 2
	receipt = s._queue.submit(ControlTurnEndCommand.new(u.faction, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and u.elemental.wet_turns == 2 and u.elemental.frozen_turns == 1, "wet and freeze expire at own team end")
	s.close()

func _parity_and_faults() -> void:
	var s := _fixture()
	var u := s.units[1]
	_bleed(s, u, 2)
	s.elemental_selected = &"burning"
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var forecast := ForecastSimulation.run_prepared(s.prepare_cast_forecast(u.id))
	_check(forecast.status == ActionReceipt.APPLIED, "cast real forecast applies: " + String(forecast.reason))
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before, "cast forecast isolated")
	var worker := ActionForecastWorker.new()
	worker.start(s.prepare_cast_forecast(u.id))
	var background: ForecastSimulation
	while background == null:
		background = worker.take_finished()
		OS.delay_msec(1)
	_check(background.snapshot_after == forecast.snapshot_after and background.events == forecast.events and background.steps == forecast.steps and background.rng_after == forecast.rng_after, "forecast worker full parity")
	var live := BattleExecutionWorker.new()
	_check(live.start(s, &"cast_unit", [u.id], true), "live worker accepts cast")
	var completed := live.take_finished(true)
	var receipt: ActionReceipt = completed["result"]
	_check(receipt.status == forecast.status and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "cast live events/steps parity")
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "cast snapshot RNG counters parity")
	s.close()
	s = _fixture(); u = s.units[1]
	var mutate := func() -> void: u.bleeding.immune = true
	u.elemental.changed.connect(mutate)
	receipt = _cast(s, &"wet")
	_check(receipt.status == ActionReceipt.FAULTED and u.elemental.wet_turns == 3 and s.units[0].action_resources.get_main_left() == 9, "callback mutation faults after paid status prefix")
	u.elemental.changed.disconnect(mutate)
	s.close()
	s = _fixture(); u = s.units[1]
	u.elemental.burning_ticks = ElementalState.MAX_VALUE; u.elemental.burning_stacks = 1
	u.elemental.burning_source = DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
	before = ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	receipt = _cast(s, &"burning")
	_check(receipt.status == ActionReceipt.REJECTED and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before, "overflow rejects before payment/damage")
	s.close()

func _helpers() -> void:
	var s := _fixture()
	var actor := s.units[0]
	var corpse: Dictionary = s.state.environment.corpses[0]
	var command := RaiseCorpseCommand.new(actor.id, corpse["id"], s.context.get_revision())
	var helper := command._new_helper(s.context, UseSummoningItemCommand.next_id(s.board), corpse)
	_check(helper.elemental != null and helper.bleeding.stacked and helper.to_snapshot_dict().get("schema_version") == UnitState.SNAPSHOT_SCHEMA_VERSION, "raised helper inherits new empty status capability")
	s.close()

func _forced_chain_and_critical() -> void:
	var s := _fixture()
	for i: int in 6:
		var unit := s.units[i]
		s.board.move_unit(unit, Vector2i(i, 0))
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	for pair: Array in [[0, Vector2i(1, 3)], [1, Vector2i(2, 3)], [2, Vector2i(3, 3)], [5, Vector2i(4, 3)]]: s.board.move_unit(s.units[pair[0]], pair[1])
	for i: int in [1, 2, 5]: _bleed(s, s.units[i])
	s.units[5].elemental.frozen_turns = 2
	var forecast := s.preview_attack(s.units[1].id)
	var receipt := s.attack_unit(s.units[1].id)
	_check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after, "K16 frozen chain live/preview parity")
	var movement_victims: Array[int] = []
	for event: Dictionary in receipt.get_events():
		if event["kind"] != &"hit_resolved": continue
		for row: Dictionary in event["hit"]["raw"]:
			if row["source"] == "bleeding_move": movement_victims.append(event["target_unit_id"])
	_check(movement_victims == [s.units[5].id] and s.units[5].cell == Vector2i(5, 3), "only moved last link bleeds; frozen accepts forced push")
	_check(s.units[1].bleeding.stacks == 2 and s.units[1].bleeding.ticks_left == 3, "new weapon bleed follows complete push and refreshes duration")
	s.close()
	s = _fixture()
	var a := s.units[0]
	var u := s.units[1]
	s.board.move_unit(u, Vector2i(1, 2))
	u.elemental.frozen_turns = 2; u.control.stunned_turns = 1; u.control.entangled_turns = 1
	var attack := AttackCommand.new(a.id, u.id, a.cell, u.cell, &"demo_strike", s.context.get_revision())
	var prepared := attack._prepare(s.context)
	_check(prepared.get("reason", &"") == &"" and prepared.get("modifiers", {}).get("critical", false), "frozen and normal control produce one critical")
	a.guard_stance = true; a.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	var reaction := AttackCommand.counterattack(a, u, s.context.get_revision())
	var reaction_plan := reaction._prepare(s.context)
	_check(reaction_plan.get("reason", &"") == &"" and reaction_plan.get("modifiers", {}).get("critical", false), "reaction strike is critical against frozen despite legacy reaction exception")
	_check(not MeleeThreat.threatens(s.context, u, a) and not MeleeThreat.reaction_ready(s.context, u, CombatPerksState.Mode.COUNTERATTACK), "frozen cannot threaten or react")
	s.close()

func _perk_and_transit() -> void:
	var s := _fixture()
	var a := s.units[0]
	var u := s.units[1]
	a.combat_perks.definition.burning_bypass_hp_gate = true
	for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	var dto := a.combat_perks.to_dict()
	_check(dto.get("schema_version") == 7 and dto.has("reaction_left") and dto.reaction_left == 0 and dto.definition.size() == 8 and CombatPerksState.from_dict(dto).to_dict() == dto, "modern bypass perk uses current complete schema with zero legacy reserve")
	var legacy_perks := CombatPerksState.new()
	legacy_perks.definition.burning_bypass_hp_gate = true
	var legacy_dto := legacy_perks.to_dict()
	_check(legacy_dto.get("schema_version") == 7 and legacy_dto.has("reaction_left") and legacy_dto.definition.size() == 8 and CombatPerksState.from_dict(legacy_dto).to_dict() == legacy_dto, "standalone legacy resource mode uses the current complete codec")
	var old_perks := legacy_dto.duplicate(true); old_perks.schema_version = 6
	_check(not CombatPerksState.valid(old_perks), "old perk reader format is refused")
	var forecast := ForecastSimulation.run(s.context, s._queue, ElementalCastCommand.new(a.id, u.id, &"burning", s.context.get_revision()))
	var receipt := _cast(s, &"burning")
	_check(receipt.status == ActionReceipt.APPLIED and u.elemental.burning_stacks == 1 and receipt.get_events() == forecast.events and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == forecast.snapshot_after, "owned bypass perk applies through armor with forecast parity")
	s.close()
	s = _fixture(); a = s.units[0]; u = s.units[1]
	s.board.move_unit(u, Vector2i(2, 0))
	s.board.move_unit(s.units[2], Vector2i(1, 2))
	_bleed(s, a)
	s.state.environment.ignite(Vector2i(1, 2))
	var path: Array[Vector2i] = [a.cell, Vector2i(1, 2), Vector2i(2, 2)]
	receipt = s._queue.submit(MoveCommand.new(a.id, path, s.context.get_revision()), s.context)
	_check(receipt.status == ActionReceipt.APPLIED and a.cell == Vector2i(2, 2) and a.bleeding.stacks == 2 and a.vitals.get_hp() == 86.0, "atomic ally transit processes bleed2, spikes8/new stack, bleed4 in cell order")
	_check(s.board.occupant_at(Vector2i(1, 2)) == s.units[2], "transit never overwrites ally occupancy")
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var turn := TurnForecast.build(s)
	_check(turn.status == ActionReceipt.APPLIED and ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before, "status end-turn forecast isolated")
	s.end_player_turn()
	_check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == turn.snapshot_after and s.context.get_rng().to_dict() == turn.rng_after and s.context.simulation_counters() == turn.counters_after, "status end-turn preview matches actual full boundary")
	s.close()

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL: " + label)

func _raw_damage(receipt: ActionReceipt) -> int:
	var total := 0
	for event: Dictionary in receipt.get_events():
		if event["kind"] == &"hit_resolved": total += int(event["hit"]["total_damage"])
	return total
