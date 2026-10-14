extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SURROUND: " + label)

func _fixture(count: int = 1, enemy: bool = false) -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	s.state.environment.fires.clear()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for i: int in s.units.size():
		var u := s.units[i]
		if not u.is_alive(): continue
		check(s.board.move_unit(u, Vector2i(i, 0)), "park unit")
		u.faction = Faction.Type.ENEMY if enemy else Faction.Type.PLAYER
		u.control.stunned_turns = 0
		u.control.entangled_turns = 0
		u.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		u.vitals.set_hp(256.0)
		u.stats.set_base_value(StatTypes.StatType.STRENGTH, 10.0)
		u.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		# Экипировка fixture сохраняет свои модификаторы; эталону нужна суммарная база ровно 10.
		var total := u.get_stat(StatTypes.StatType.STRENGTH) + u.get_stat(StatTypes.StatType.WEAPON_DAMAGE)
		u.stats.set_base_value(StatTypes.StatType.STRENGTH, 20.0 - total)
		u.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 0.0)
		u.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		if u.combat_perks != null: u.combat_perks.definition.sneak_attack = false
		u.armor.natural = {"physical": 0, "fire": 0}
		for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = 0
	var target := s.units[3]
	target.faction = Faction.Type.PLAYER if enemy else Faction.Type.ENEMY
	check(s.board.move_unit(target, Vector2i(3, 3)), "target placed")
	check(s.board.move_unit(s.units[0], Vector2i(2, 3)), "actor placed")
	var cells: Array[Vector2i] = [Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4)]
	var indices: Array[int] = [2, 4, 5]
	for i: int in count: check(s.board.move_unit(s.units[indices[i]], cells[i]), "ally placed")
	var rules := s.context.get_attack_rules()
	var ids: Array[int] = []
	var pairs: Array[Dictionary] = []
	for u: UnitState in s.units:
		ids.append(u.id)
		for v: UnitState in s.units:
			if u.is_hostile_to(v): pairs.append({"actor_unit_id": u.id, "target_unit_id": v.id})
	s.context._attack_rules = AttackRules.new(ids, pairs, rules._definitions)
	s.selected_id = s.units[0].id
	return s

func _command(s: BattleCoreReactionsSession) -> AttackCommand:
	var a := s.units[0]
	var t := s.units[3]
	return AttackCommand.new(a.id, t.id, a.cell, t.cell, &"demo_strike", s.context.get_revision())

func _snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "snapshot " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func _parity(s: BattleCoreReactionsSession, command: Command) -> ActionReceipt:
	var before := _snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var ids := UnitId.get_counter()
	var forecast := ForecastSimulation.run(s.context, s._queue, command)
	check(forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], "preview applied " + String(forecast.reason))
	check(_snapshot(s) == before and rng == s.context.get_rng().to_dict() and counters == s.context.simulation_counters() and ids == UnitId.get_counter(), "preview isolated")
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "full receipt parity " + String(receipt.reason))
	check(_snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after and SummonAdmission.values(s.context) == forecast.admission_after, "snapshot RNG counters admission parity")
	return receipt

func _attack_event(events: Array[Dictionary], kind: StringName = &"attacked") -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind: return event
	return {}

func _run() -> void:
	_counts_and_types()
	_eligibility()
	_periodic()
	_ignite()
	_reactions()
	await _workers()
	print("SURROUND DAMAGE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _counts_and_types() -> void:
	for enemy: bool in [false, true]:
		for count: int in 4:
			var s := _fixture(count, enemy)
			var actor := s.units[0]
			var target := s.units[3]
			var allies := MeleeThreat.surrounding_allies(s.context, actor, target)
			check(allies.size() == count and not allies.has(actor.id), "self excluded on both sides")
			for id: int in allies:
				check(MeleeThreat.surrounding_allies(s.context, s.board.get_unit_by_id(id), target).size() == count, "each participant gets same count")
			var receipt := _parity(s, _command(s))
			# demo_strike fixture содержит ещё 10 огня руны; обе компоненты усиливаются одинаково.
			check(target.vitals.get_hp() == 236.0 - 2 * count, "physical + fire damage 20/22/24/26: count=%d hp=%s" % [count, target.vitals.get_hp()])
			var event := _attack_event(receipt.get_events())
			check(event.get("modifiers", {}).get("surround_percent", 0) == 10 * count, "event percent")
			s.close()
	var s := _fixture(1)
	var actor := s.units[0]
	var target := s.units[3]
	actor.combat_perks.definition.sneak_attack = true
	s.board.set_height_steps(actor.cell, 1)
	# Один полушаг допустим для ближней угрозы и даёт высоту x1.1.
	s.context._attack_rules._definitions[0].damage_components = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "test:fire", "factor_num": 1, "factor_den": 1}]
	var forecast := AttackForecast.build(s.context, s._queue, _command(s))
	var names: Dictionary[int, String] = {actor.id: "Вор", target.id: "Цель", s.units[2].id: "Союзник"}
	var event_lines: PackedStringArray = []
	for entry: Dictionary in forecast.events: event_lines.append(BattleEventText.format_event(entry, names, true, false, ""))
	var text := BattleForecastText.attack(forecast, "Вор", "Цель", target.id, names, event_lines, true, true)
	check(text.contains("Окружение +10% всего прямого урона") and text.contains("Скрытая атака +50% физической базы"), "forecast distinguishes common rule and rogue perk")
	var event := _attack_event(forecast.events)
	check(BattleEventText.format_event(event, names, true, false, "").contains("Окружение +10%"), "journal explains bonus")
	_event_validation(s, event)
	_parity(s, _command(s))
	# Физический (10*1.1 +5)*1.1=17.6; огонь 10*1.1*1.1=12.1; D0:17+12.
	check(target.vitals.get_hp() == 227.0, "height, rogue and all direct damage types combine before floor")
	s.close()

func _event_validation(s: BattleCoreReactionsSession, event: Dictionary) -> void:
	var draft := event.duplicate(true)
	for key: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: draft.erase(key)
	check(ActionEventValidator.valid_draft(draft, s.context), "new draft accepted")
	for field: String in ["self", "target", "duplicate", "count", "missing", "unknown"]:
		var bad := draft.duplicate(true)
		match field:
			"self": bad.modifiers.surround_ally_ids = [s.units[0].id]
			"target": bad.modifiers.surround_ally_ids = [s.units[3].id]
			"duplicate":
				bad.modifiers.surround_ally_ids = [s.units[2].id, s.units[2].id]
				bad.modifiers.surround_percent = 20
			"count": bad.modifiers.surround_percent = 20
			"missing": bad.modifiers.erase("surround_ally_ids")
			"unknown": bad.modifiers["unknown"] = 0
		check(not ActionEventValidator.valid_draft(bad, s.context), "reject malformed surround " + field)

func _eligibility() -> void:
	for condition: String in ["spent", "entangled", "stunned", "frozen", "dead", "neutral", "distant", "diagonal", "height", "no_admission", "actor_distant"]:
		var s := _fixture(1)
		var a := s.units[0]
		var ally := s.units[2]
		var t := s.units[3]
		match condition:
			"spent": ally.action_resources.try_spend_main(1)
			"entangled": ally.control.entangled_turns = 1
			"stunned": ally.control.stunned_turns = 1
			"frozen": ally.elemental.frozen_turns = 1
			"dead":
				ally.vitals.set_hp(0)
				ally.vitals._is_alive = false
			"neutral": ally.faction = Faction.Type.NEUTRAL
			"distant":
				s.board.move_unit(ally, Vector2i(5, 3))
				ally.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 3.0)
			"diagonal":
				s.board.move_unit(ally, Vector2i(4, 4))
				ally.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 3.0)
			"height":
				s.board.set_height_steps(ally.cell, 2)
				ally.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 3.0)
			"no_admission":
				var rules := s.context._attack_rules
				rules._pairs = rules._pairs.filter(func(pair: Dictionary) -> bool: return pair.actor_unit_id != ally.id)
			"actor_distant":
				s.board.move_unit(a, Vector2i(1, 3))
				a.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 3.0)
		check(MeleeThreat.surrounding_allies(s.context, a, t).size() == (1 if condition in ["spent", "entangled"] else 0), "eligibility " + condition)
		s.close()
	var s := _fixture(1)
	var ally := s.units[2]
	var original := ally.cell
	check(MeleeThreat.surrounding_allies(s.context, s.units[0], s.units[3]).size() == 1, "initial live participation")
	s.board.move_unit(ally, Vector2i(6, 5))
	check(MeleeThreat.surrounding_allies(s.context, s.units[0], s.units[3]).is_empty(), "movement removes participation")
	s.board.move_unit(ally, original)
	check(MeleeThreat.surrounding_allies(s.context, s.units[0], s.units[3]).size() == 1, "return recomputes participation")
	s.close()

func _periodic() -> void:
	for burning: bool in [false, true]:
		var s := _fixture(3)
		var target := s.units[3]
		var source := DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
		if burning:
			target.elemental.burning_stacks = 10
			target.elemental.burning_ticks = 2
			target.elemental.burning_source = source
		else:
			target.bleeding.stacks = 10
			target.bleeding.ticks_left = 2
			target.bleeding.source = source
			target.bleeding.hit_id = "surround-test"
		var tick := s._queue.submit(BleedingTurnCommand.new(target.faction, s.context.get_revision()), s.context)
		check(tick.status == ActionReceipt.APPLIED, "periodic turn applied " + String(tick.reason))
		check(target.vitals.get_hp() == 246.0, "ten stacks periodic damage stays ten despite x1.3 surround")
		s.close()

func _reactions() -> void:
	var s := _fixture(1)
	var actor := s.units[0]
	var target := s.units[3]
	check(s._queue.submit(GuardCommand.new(actor.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), s.context).status == ActionReceipt.APPLIED, "arm opportunity")
	var receipt := _parity(s, MoveCommand.new(target.id, [target.cell, Vector2i(3, 4)], s.context.get_revision()))
	check(_attack_event(receipt.get_events(), &"opportunity_attacked").get("modifiers", {}).get("surround_percent", 0) == 10, "opportunity gets common bonus")
	s.close()
	s = _fixture(1)
	actor = s.units[0]
	target = s.units[3]
	check(s._queue.submit(GuardCommand.new(actor.id, s.context.get_revision(), CombatPerksState.Mode.COUNTERATTACK), s.context).status == ActionReceipt.APPLIED, "arm counter")
	receipt = _parity(s, AttackCommand.new(target.id, actor.id, target.cell, actor.cell, &"demo_strike", s.context.get_revision()))
	check(_attack_event(receipt.get_events(), &"counterattacked").get("modifiers", {}).get("surround_percent", 0) == 10, "counter gets common bonus")
	s.close()

func _ignite() -> void:
	var s := _fixture(3)
	var actor := s.units[0]
	var target := s.units[3]
	var receipt := _parity(s, ElementalCastCommand.new(actor.id, target.id, &"burning", s.context.get_revision()))
	check(target.vitals.get_hp() == 251.0, "initial ignite direct damage floor(4 * 1.3) = 5")
	var event := _attack_event(receipt.get_events(), &"elemental_cast")
	check(event.get("modifiers", {}).get("surround_percent", 0) == 30, "ignite explains surround")
	_event_validation(s, event)
	var tick := s._queue.submit(BleedingTurnCommand.new(target.faction, s.context.get_revision()), s.context)
	check(tick.status == ActionReceipt.APPLIED and target.vitals.get_hp() == 250.0, "later burning tick remains one")
	s.close()

func _workers() -> void:
	var s := _fixture(2)
	var before := _snapshot(s)
	var forecast := AttackForecast.build(s.context, s._queue, _command(s))
	var worker := AttackForecastWorker.new()
	worker.start(s.prepare_attack_forecast(s.units[3].id))
	var result: AttackForecast
	for iteration: int in 500:
		result = worker.take_finished()
		if result != null: break
		await create_timer(0.01).timeout
	worker.close()
	check(result != null and result.events == forecast.events and result.steps == forecast.steps and result.snapshot_after == forecast.snapshot_after and result.rng_after == forecast.rng_after and result.counters_after == forecast.counters_after, "forecast worker full parity")
	check(_snapshot(s) == before, "worker source unchanged")
	var live := BattleExecutionWorker.new()
	check(BattleExecutionWorker.can_transfer(s) and live.start(s, &"attack_unit", [s.units[3].id], 1), "live worker start")
	var completed := live.take_finished(true)
	var receipt := completed.get("result") as ActionReceipt
	check(receipt != null and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and _snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, "live worker full parity")
	s.close()
