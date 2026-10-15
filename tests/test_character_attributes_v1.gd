extends SceneTree

class InternalStatusParent extends Command:
	var child: Command
	func _init(p_child: Command) -> void: child = p_child
	func get_kind() -> StringName: return &"character_attributes_status_parent"
	func copy_for_queue() -> Command: return InternalStatusParent.new(child.copy_for_queue())
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(_context: ActionContext) -> CommandStepResult: return CommandStepResult.applied([], [child])

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL CHARACTER ATTRIBUTES V1: " + label)

func _run() -> void:
	_test_generated_attributes()
	_test_attack_formulas()
	_test_attribute_text_formatting()
	await _test_production_attack_snapshot_parity(false)
	await _test_production_attack_snapshot_parity(true)
	_test_authored_bleeding()
	_test_authored_burning()
	_test_summon_capabilities()
	_test_absent_author_and_fractional_heal()
	print("CHARACTER ATTRIBUTES V1 RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_generated_attributes() -> void:
	for seed_value: int in range(30, 54):
		var first := HeroHubState.create(seed_value)
		var second := HeroHubState.create(seed_value)
		_check(first != null and second != null and first.candidates.size() == second.candidates.size(), "seed creates matching candidate rosters")
		if first == null or second == null: continue
		for index: int in first.candidates.size():
			var a: HeroProgression = first.candidates[index]
			var b: HeroProgression = second.candidates[index]
			_check(a.base_attributes.size() == 5 and a.base_attributes == b.base_attributes, "five candidate attributes are deterministic")
			var total := 0
			for value: int in a.base_attributes:
				_check(value >= 3, "generated attribute meets minimum")
				total += value
			_check(total == 50, "generated attributes sum to 50")
			_check(a.attributes().size() == 5, "runtime hero exposes five attributes")

func _component_total(components: Array[Dictionary]) -> ArmorFraction:
	var result := ArmorFraction.make(0)
	for component: Dictionary in components:
		result = result.add(ArmorFraction.make(component.numerator, component.denominator))
	return result

func _test_attack_formulas() -> void:
	var neutral := {"power": 10.0, "mastery": 10.0}
	var positioned := CharacterAttack.components(10.0, 0.0, 1, false, [], 0, true, 0, 0, 2, neutral)
	_check(not positioned.is_empty() and absf(float(positioned[0].numerator) / float(positioned[0].denominator) - 23.0) <= 0.000000000001, "critical, one height and two surround allies total 23")
	var mastery := CharacterAttack.components(10.0, 0.0, 1, false, [], 0, true, 0, 0, 2, {"power":10.0,"mastery":11.0})
	_check(not mastery.is_empty() and absf(float(mastery[0].numerator) / float(mastery[0].denominator) - 24.18) <= 0.000000000001, "mastery 11 gives direct attack 24.18")
	var power := CharacterAttack.components(10.0, 0.0, 0, false, [], 0, false, 0, 0, 0, {"power":11.0,"mastery":10.0})
	_check(not power.is_empty() and absf(float(power[0].numerator) / float(power[0].denominator) - 10.2) <= 0.000000000001, "power 11 multiplies direct damage by 1.02")
	var rogue := CharacterAttack.components(10.0, 0.0, 0, false, [], 50, false, 0, 0, 0, neutral)
	_check(rogue.size() == 1 and float(rogue[0].numerator) / float(rogue[0].denominator) == 15.0, "rogue sneak is a separate 1.5 physical multiplier")
	var extra: Array[Dictionary] = [{"type":"fire","policy":"standard","numerator":2,"denominator":1,"source":"fixture","factor_num":1,"factor_den":1}]
	var rogue_with_extra := CharacterAttack.components(10.0, 0.0, 0, false, extra, 50, false, 0, 0, 0, neutral)
	_check(rogue_with_extra.size() == 2 and float(rogue_with_extra[0].numerator) / float(rogue_with_extra[0].denominator) == 15.0 and float(rogue_with_extra[1].numerator) / float(rogue_with_extra[1].denominator) == 2.0, "rogue multiplier does not boost an extra damage component")
	var lower := CharacterAttack.components(10.0, 0.0, -1, false, [], 0, false, 0, 0, 0, neutral)
	_check(not lower.is_empty() and float(lower[0].numerator) / float(lower[0].denominator) == 9.0, "negative height keeps its separate previous factor")
	var pierced := CharacterAttack.components(10.0, 0.0, 0, false, [], 0, false, 35, 0, 0, neutral)
	var split := _component_total(pierced)
	_check(pierced.size() == 2 and split.valid and split.numerator == 10 and split.denominator == 1, "physical piercing branches conserve the exact amount")

func _test_attribute_text_formatting() -> void:
	var names: Dictionary[int, String] = {1: "Герой", 2: "Цель", 3: "Союзник А", 4: "Союзник Б"}
	var v1_event := {"kind": &"attacked", "actor_unit_id": 1, "target_unit_id": 2, "modifiers": {
		"critical": true, "surround_percent": 20, "surround_ally_ids": [3, 4],
		"character_attributes": {"power": 10.0, "mastery": 11.0},
	}}
	var event_text := BattleEventText.format_event(v1_event, names, false, false, "")
	_check(event_text.contains("Крит ×2.1") and event_text.contains("+110% к сумме"), "mastery 11 displays its critical multiplier and total-sum bonus")
	_check(event_text.contains("Окружение +21.2% к сумме бонусов") and event_text.contains("база 20%"), "mastery 11 scales two surround bonuses to 21.2 percent")
	var source_a := DamageSource.new(&"attack", 0, Vector2i.ZERO, 1, 1).to_dict()
	var source_b := DamageSource.new(&"attack", 0, Vector2i.ONE, 2, 2).to_dict()
	var authored_bleeding := {"stacked": true, "stacks": 2, "ticks_left": 2, "contributions": [
		StatusContributions.make(source_a, 10.0), StatusContributions.make(source_b, 20.0),
	]}
	var bleeding_text := BattleEventText.bleeding_summary(authored_bleeding)
	_check(bleeding_text.contains("2.3/тик") and bleeding_text.contains("4.6/клетку"), "authored bleeding summary shows frozen total and doubled movement damage")
	var hit_event := {"kind": &"hit_resolved", "actor_unit_id": 1, "target_unit_id": 2, "hit": {"hp_before": 10.5, "hp_after": 9.573}}
	_check(BattleEventText.format_event(hit_event, names, false, false, "").contains("HP 10.5 → 9.6"), "fractional event HP is shown to one decimal without integer truncation")
	var forecast := AttackForecast.new()
	forecast.status = ActionReceipt.APPLIED
	forecast.events = [v1_event, {"kind": &"hit_resolved", "target_unit_id": 2, "hit": {
		"armor_spent": 0.25, "p_num": 0.927, "p_den": 1.0, "total_damage": 0.927, "total_healing": 0.0,
		"rows": [{"type": &"fire", "policy": &"standard", "D": 0.927, "armor_spent": 0.25, "hp_damage": 0.927, "healing": 0.0}],
	}}]
	forecast.units = {2: {
		"before": {"hp": 10.5, "alive": true, "balance": 0.0, "balance_max": 0.0, "armor_current": 0.25, "armor_max": 5.0, "bleeding": authored_bleeding, "main": 1},
		"after": {"hp": 9.573, "alive": true, "balance": 0.0, "balance_max": 0.0, "armor_current": 0.0, "armor_max": 5.0, "bleeding": authored_bleeding, "main": 1},
	}}
	var forecast_text := BattleForecastText.attack(forecast, "Герой", "Цель", 2, names, PackedStringArray(["attack", "hit"]), false, true)
	_check(forecast_text.contains("броня 0.3 → 0 / 5") and forecast_text.contains("броня −0.3"), "fractional armor forecast values round for display without truncation")
	_check(forecast_text.contains("вход 0.9 → броня 0.3 / HP 0.9 / лечение 0") and forecast_text.contains("4.6/клетку"), "fractional hit row and authored movement damage retain decimal display")
	var legacy_event := {"kind": &"attacked", "actor_unit_id": 1, "target_unit_id": 2, "modifiers": {"critical": true, "surround_percent": 20, "surround_ally_ids": [3, 4]}}
	_check(BattleEventText.format_event(legacy_event, names, false, false, "") == "Герой атакует Цель. Окружение +20% всего прямого урона (союзники: Союзник А, Союзник Б). Крит ×2.", "legacy event wording remains byte-exact without character metadata")

func _test_production_attack_snapshot_parity(use_workers: bool) -> void:
	var hub := HeroHubState.create(92401)
	var hero_id: int = hub.party[0]
	var armor := hub.equipped(hero_id, "armor")
	var armor_max: int = HeroGearCatalog.definition(armor.definition).armor_max
	armor.remaining = float(armor_max) - 0.25
	_check(hub.start_battle(), "production hub enters battle with fractional HP and gear")
	var hero: HeroProgression = hub.heroes[hero_id]
	hero.hp_current = hero.max_hp() - 0.25
	var source_before := hub.to_dict()
	var bundle := HeroHubBattleFactory.create(hub)
	_check(not bundle.is_empty(), "production battle factory creates the combat")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var actor_id: int = bundle.hero_units[hero_id]
	var actor := session.board.get_unit_by_id(actor_id)
	_check(session.start_battle(), "production encounter opens its enemy turn")
	var enemy_steps: int = 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and enemy_steps < 30:
		session.step_enemy()
		enemy_steps += 1
	_check(session.can_player_act(), "production turn reaches player through commands")
	if not session.can_player_act():
		session.close()
		return
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	var free_cell := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate := actor.cell + offset
		if session.board.is_in_bounds(candidate) and session.board.occupant_at(candidate) == null:
			free_cell = candidate
			break
	_check(free_cell.x >= 0 and session.board.move_unit(target, free_cell), "target moves through BattleBoard into attack range")
	if free_cell.x < 0:
		session.close()
		return
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	target.armor.natural.physical = 0
	_check(session.select_unit(actor_id), "production hero can be selected")
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	_check(capture.code == ItemSnapshotResult.Code.OK, "fractional battle state snapshots")
	if capture.code == ItemSnapshotResult.Code.OK:
		var definitions: Dictionary = {}
		for owner: ItemOwnerState in session.state.get_owners(): definitions.merge(owner._definitions, true)
		var restored := capture.snapshot.instantiate(definitions)
		_check(restored.code == ItemSnapshotResult.Code.OK, "full battle snapshot restores")
		if restored.code == ItemSnapshotResult.Code.OK:
			var restored_hero := restored.state.get_board().get_unit_by_id(actor_id)
			var gear_mapping: Dictionary = bundle.gear_items[armor.id]
			var restored_item: ItemInstance = restored.state.get_owner(actor_id)._items[gear_mapping.item_id]
			_check(is_equal_approx(restored_hero.vitals.get_hp(), actor.vitals.get_hp()) and is_equal_approx(restored_item.armor_remaining, armor.remaining), "snapshot restore retains fractional HP and armor")
			ForecastSimulation.close(restored.state)
	var live_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var forecast := session.preview_attack(target.id)
	_check(forecast.status == ActionReceipt.APPLIED, "production attack creates a forecast")
	if use_workers:
		var preview_worker := AttackForecastWorker.new()
		preview_worker.start(session.prepare_attack_forecast(target.id))
		var threaded: AttackForecast = null
		var deadline := Time.get_ticks_msec() + 10000
		while threaded == null and Time.get_ticks_msec() < deadline:
			threaded = preview_worker.take_finished()
			if threaded == null: await create_timer(0.001).timeout
		preview_worker.close()
		_check(threaded != null and threaded.status == forecast.status and threaded.events == forecast.events and threaded.steps == forecast.steps and threaded.snapshot_after == forecast.snapshot_after and threaded.rng_after == forecast.rng_after and threaded.counters_after == forecast.counters_after, "production fractional attack forecast worker matches synchronous forecast")
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == live_before and hub.to_dict() == source_before, "forecast leaves live battle and source profile unchanged")
	if forecast.status == ActionReceipt.APPLIED:
		var receipt: ActionReceipt
		if use_workers:
			var execution_worker := BattleExecutionWorker.new()
			var started := execution_worker.start(session, &"attack_unit", [target.id], false, true)
			_check(started, "production fractional battle graph transfers to live execution worker")
			if not started:
				session.close()
				return
			_check(not execution_worker.take_presentation_before().is_empty(), "worker captures fractional presentation before execution")
			var completed := execution_worker.take_finished(true)
			receipt = completed.result
			_check(not session.take_presentation_capture().is_empty(), "fractional live worker publishes presentation packets")
		else:
			receipt = session.attack_unit(target.id)
		var after := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
		_check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "real attack matches forecast receipt")
		_check(after == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, "real attack matches forecast snapshot, RNG and counters")
	session.close()

func _new_status_session(seed_value: int) -> Dictionary:
	var hub := HeroHubState.create(seed_value)
	var start := hub.start_battle()
	if not start: return {}
	var bundle := HeroHubBattleFactory.create(hub)
	if bundle.is_empty(): return {}
	var session: BattleCoreReactionsSession = bundle.session
	var actors: Array[UnitState] = []
	for hero_id: int in hub.party:
		actors.append(session.board.get_unit_by_id(bundle.hero_units[hero_id]))
	if actors.size() < 2: session.close(); return {}
	actors[0].stats.set_base_value(StatTypes.StatType.INTELLECT, 10.0)
	actors[1].stats.set_base_value(StatTypes.StatType.INTELLECT, 20.0)
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	target.vitals.set_hp(target.get_stat(StatTypes.StatType.HP_MAX))
	target.armor.natural.physical = 1000
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	var definition := AttackDefinition.new()
	definition.id = &"authored_bleed_test"
	definition.profile = AttackRules.ARMOR_PROFILE
	definition.bleeding_policy = &"physical_hp"
	var ids := session._unit_ids()
	var pairs: Array[Dictionary] = []
	for actor_id: int in ids:
		for target_id: int in ids:
			if actor_id != target_id: pairs.append({"actor_unit_id":actor_id,"target_unit_id":target_id})
	var definitions := session.context.get_attack_rules().get_definitions()
	definitions.append(definition)
	var rules := AttackRules.new(ids, pairs, definitions)
	# Fixture добавляет собственную внутреннюю атаку вне каталога активных способностей.
	session.state.abilities = null
	session.context = ActionContext.new(session.state, session.context.get_rng(), ActionEventSink.new(), [], session.context.get_move_rules(), rules)
	return {"session":session,"actors":actors,"target":target}

func _submit_internal(session: BattleCoreReactionsSession, child: Command) -> ActionReceipt:
	return session._submit(InternalStatusParent.new(child))

func _apply_bleed(session: BattleCoreReactionsSession, actor: UnitState, target: UnitState, hit_id: String) -> ActionReceipt:
	var source := DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	var receipt := _submit_internal(session, BleedingApplyCommand.new(actor, target, source, hit_id, &"authored_bleed_test", &"physical_hp", true))
	if receipt.status != ActionReceipt.APPLIED: printerr("bleeding apply fixture rejected: " + String(receipt.reason))
	return receipt

func _test_authored_bleeding() -> void:
	var fixture := _new_status_session(92402)
	_check(not fixture.is_empty(), "production factory creates authored status fixture")
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actors: Array = fixture.actors
	var target: UnitState = fixture.target
	var actor_a: UnitState = actors[0]
	var actor_b: UnitState = actors[1]
	var start_hp := target.vitals.get_hp()
	_check(_apply_bleed(session, actor_a, target, "a-first").status == ActionReceipt.APPLIED, "first actor applies a frozen bleed contribution")
	_check(_apply_bleed(session, actor_b, target, "b-first").status == ActionReceipt.APPLIED, "second actor adds a frozen bleed contribution")
	_check(target.bleeding.contributions.size() == 2 and StatusContributions.total(target.bleeding.contributions).numerator == 23 and StatusContributions.total(target.bleeding.contributions).denominator == 10, "I10 and I20 stack as 2.3 pre-defense")
	actor_a.stats.set_base_value(StatTypes.StatType.INTELLECT, 50.0)
	var first_tick := _submit_internal(session, BleedingTickCommand.new(target))
	_check(first_tick.status == ActionReceipt.APPLIED and absf(start_hp - target.vitals.get_hp() - 2.07) <= 0.000000000001, "tick applies target defense once and ignores later intellect changes")
	actor_a.stats.set_base_value(StatTypes.StatType.INTELLECT, 30.0)
	_check(_apply_bleed(session, actor_a, target, "a-third").status == ActionReceipt.APPLIED, "third same-author stack records current intellect")
	var credited := StatusContributions.credited_source(target.bleeding.contributions)
	_check(target.bleeding.contributions.size() == 3 and not credited.is_empty() and int(credited.get("credit_unit_id", 0)) == actor_a.id and credited.get("origin_cell", Vector2i(-1, -1)) == actor_a.cell, "greatest accumulated actor receives credit with earliest representative")
	# Равные суммы оставляют кредит за автором первой активной записи.
	actor_a.stats.set_base_value(StatTypes.StatType.INTELLECT, 10.0)
	actor_b.stats.set_base_value(StatTypes.StatType.INTELLECT, 10.0)
	var other := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[1])
	_check(_apply_bleed(session, actor_a, other, "tie-a").status == ActionReceipt.APPLIED and _apply_bleed(session, actor_b, other, "tie-b").status == ActionReceipt.APPLIED, "two equal authors apply to a second target")
	var tie_credit := StatusContributions.credited_source(other.bleeding.contributions)
	_check(not tie_credit.is_empty() and int(tie_credit.get("credit_unit_id", 0)) == actor_a.id, "equal author credit breaks ties by earliest active contribution")
	other.armor.natural.physical = 0
	other.vitals.set_hp(1.0)
	var lethal := _submit_internal(session, BleedingTickCommand.new(other))
	var died_events: Array = lethal.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind", &"") == &"died")
	_check(lethal.status == ActionReceipt.APPLIED and died_events.size() == 1 and died_events[0].source.credit_unit_id == actor_a.id, "lethal bleeding tick credits the earliest author in a greatest-sum tie")
	var snapshot := ItemSimulationSnapshot.capture(session.state, [])
	_check(snapshot.code == ItemSnapshotResult.Code.OK, "authored contributions survive full battle snapshot capture")
	if snapshot.code == ItemSnapshotResult.Code.OK:
		var definitions: Dictionary = {}
		for owner: ItemOwnerState in session.state.get_owners(): definitions.merge(owner._definitions, true)
		var restored := snapshot.snapshot.instantiate(definitions)
		_check(restored.code == ItemSnapshotResult.Code.OK, "authored contribution snapshot restores")
		if restored.code == ItemSnapshotResult.Code.OK:
			var restored_target := restored.state.get_board().get_unit_by_id(target.id)
			_check(restored_target.bleeding.to_dict() == target.bleeding.to_dict() and is_equal_approx(restored_target.vitals.get_hp(), target.vitals.get_hp()), "snapshot restores frozen contributions and target HP")
			ForecastSimulation.close(restored.state)
	actor_a.vitals.set_hp(0.0)
	var second_hp := target.vitals.get_hp()
	var second_tick := _submit_internal(session, BleedingTickCommand.new(target))
	_check(second_tick.status == ActionReceipt.APPLIED and absf(second_hp - target.vitals.get_hp() - 3.51) <= 0.000000000001, "third coefficient is frozen and dead source author still ticks")
	var external_target := target
	var external_mage := DamageSource.new(&"mage", 3, Vector2i(-1, -1), 0, 0).to_dict()
	external_target.bleeding.authored = true
	external_target.bleeding.stacked = true
	external_target.bleeding.stacks = 1
	external_target.bleeding.ticks_left = 1
	external_target.bleeding.source = external_mage.duplicate(true)
	external_target.bleeding.hit_id = "external-mage-bleed"
	external_target.bleeding.contributions.assign([StatusContributions.make(external_mage, 10.0)])
	external_target.armor.natural.physical = 0
	external_target.vitals.set_hp(0.5)
	var external_tick := _submit_internal(session, BleedingTickCommand.new(external_target))
	var external_deaths: Array = external_tick.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind", &"") == &"died")
	_check(external_tick.status == ActionReceipt.APPLIED and external_deaths.size() == 1 and external_deaths[0].source.credit_unit_id == 0 and session.board.get_unit_by_id(0) == null, "external mage author with no board unit retains lethal tick credit")
	session.close()

func _authored_source(actor: UnitState) -> Dictionary:
	return DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id).to_dict()

func _test_authored_burning() -> void:
	var fixture := _new_status_session(92403)
	_check(not fixture.is_empty(), "production factory creates authored burning fixture")
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actors: Array = fixture.actors
	var actor_a: UnitState = actors[0]
	var actor_b: UnitState = actors[1]
	var target: UnitState = fixture.target
	target.elemental.authored = true
	target.elemental.burning_stacks = 2
	target.elemental.burning_ticks = 2
	target.elemental.burning_source = _authored_source(actor_a)
	target.elemental.burning_contributions.assign([
		StatusContributions.make(_authored_source(actor_a), 10.0),
		StatusContributions.make(_authored_source(actor_b), 20.0),
	])
	target.armor.natural.fire = 1000
	target.vitals.set_hp(target.get_stat(StatTypes.StatType.HP_MAX))
	var hp_before := target.vitals.get_hp()
	actor_a.stats.set_base_value(StatTypes.StatType.INTELLECT, 50.0)
	var first_tick := _submit_internal(session, ElementalTickCommand.new(target))
	_check(first_tick.status == ActionReceipt.APPLIED and absf(hp_before - target.vitals.get_hp() - 2.07) <= 0.000000000001, "I10 and I20 burning sum to 2.3 before one 10 percent fire defense")
	_check(target.elemental.burning_contributions.size() == 2, "one burning tick preserves both frozen contributions")
	var second_hp := target.vitals.get_hp()
	var second_tick := _submit_internal(session, ElementalTickCommand.new(target))
	_check(second_tick.status == ActionReceipt.APPLIED and absf(second_hp - target.vitals.get_hp() - 2.07) <= 0.000000000001, "later intellect changes do not alter frozen burning damage")
	_check(target.elemental.burning_stacks == 0 and target.elemental.burning_contributions.is_empty(), "burning expiry clears authored contributions")
	var state := ElementalState.new()
	state.authored = true
	state.burning_stacks = 2
	state.burning_ticks = 2
	state.burning_source = _authored_source(actor_b)
	state.burning_contributions.assign([
		StatusContributions.make(_authored_source(actor_a), 10.0),
		StatusContributions.make(_authored_source(actor_b), 20.0),
	])
	var wet := ElementalRules.transition(state.to_dict(), &"wet", 1, {})
	_check(wet.reason == &"" and wet.after.burning_contributions.is_empty(), "wet transition clears authored burning records")
	var freeze_clear := ElementalRules.transition(state.to_dict(), &"freeze", 1, {})
	_check(freeze_clear.reason == &"" and freeze_clear.after.burning_contributions.is_empty(), "freeze transition clears authored burning records before freezing")
	var frozen := ElementalRules.transition(freeze_clear.after, &"freeze", 1, {}, true)
	_check(frozen.reason == &"" and frozen.after.frozen_turns == 1 and frozen.after.burning_contributions.is_empty(), "cleared burning state accepts a following freeze transition")
	session.close()

func _test_summon_capabilities() -> void:
	var fixture := _new_status_session(92404)
	_check(not fixture.is_empty(), "production factory creates summon capability fixture")
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actor: UnitState = fixture.actors[0]
	actor.stats.set_base_value(StatTypes.StatType.INTELLECT, 50.0)
	actor.armor.fractional = true
	actor.bleeding.authored = true
	actor.elemental.authored = true
	var owner: ItemOwnerState = session.state.get_owner(actor.id)
	var definition := ItemDef.new()
	definition.id = &"test_authored_summon"
	definition.display_name = "Тестовый призыв"
	definition.use_summon = true
	definition.max_charges = 1
	var item := owner.create_item(definition)
	_check(item != null, "fixture owner creates a summon-capable item")
	if item == null:
		session.close()
		return
	var command := UseSummoningItemCommand.new(actor.id, item.get_item_instance_id(), actor.cell + Vector2i.RIGHT, session.context.get_revision())
	var helper := command._new_helper(session.context, 900001)
	_check(helper != null, "production summon helper builder accepts the capability fixture")
	if helper != null:
		_check(helper.armor != null and helper.armor.fractional and helper.bleeding.authored and helper.elemental.authored, "helper inherits fractional and authored-status capabilities")
		_check(helper.bleeding.contributions.is_empty() and helper.elemental.burning_contributions.is_empty(), "helper does not inherit the source author's live contributions")
		_check(helper.stats.get_value(StatTypes.StatType.INTELLECT) != actor.stats.get_value(StatTypes.StatType.INTELLECT), "helper uses its template stats instead of source intellect")
	session.close()

func _test_absent_author_and_fractional_heal() -> void:
	var fixture := _new_status_session(92405)
	_check(not fixture.is_empty(), "absent-author fixture builds")
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actor: UnitState = fixture.actors[0]
	var target: UnitState = fixture.target
	var guard := SpatialRules.capture_guard(session.context, [actor], [actor.cell], {})
	_check(guard != null and guard.check(session.context), "fractional participant guard captures attribute values")
	actor.stats.set_base_value(StatTypes.StatType.POWER, actor.get_stat(StatTypes.StatType.POWER) + 1.0)
	_check(guard != null and not guard.check(session.context), "attribute mutation invalidates the action checkpoint even without explicitly selected stats")
	var absent_source := DamageSource.new(&"attack", 0, Vector2i.ZERO, 900001, 900001).to_dict()
	target.bleeding.stacks = 1
	target.bleeding.ticks_left = 2
	target.bleeding.source = absent_source
	target.bleeding.hit_id = "departed-author"
	target.bleeding.contributions.assign([StatusContributions.make(absent_source, 20.0)])
	var snapshot := ItemSimulationSnapshot.capture(session.state, [])
	_check(snapshot.code == ItemSnapshotResult.Code.OK and session.board.get_unit_by_id(900001) == null, "historical absent author's contribution captures without a live reference")
	if snapshot.code == ItemSnapshotResult.Code.OK:
		var definitions: Dictionary = {}
		for owner: ItemOwnerState in session.state.get_owners(): definitions.merge(owner._definitions, true)
		var restored := snapshot.snapshot.instantiate(definitions)
		_check(restored.code == ItemSnapshotResult.Code.OK, "historical absent author's contribution restores")
		if restored.code == ItemSnapshotResult.Code.OK: ForecastSimulation.close(restored.state)
	target.armor.natural.physical = 0
	target.vitals.set_hp(2.0)
	var healed := _submit_internal(session, HealCommand.new(target.id, 0.25, DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)))
	_check(healed.status == ActionReceipt.APPLIED and target.vitals.get_hp() == 2.25, "fractional healing restores exactly one quarter HP")
	var tick := _submit_internal(session, BleedingTickCommand.new(target))
	_check(tick.status == ActionReceipt.APPLIED and absf(target.vitals.get_hp() - 0.95) < 1e-12, "absent author's frozen coefficient still deals 1.3 HP")
	var lethal := _submit_internal(session, BleedingTickCommand.new(target))
	var deaths: Array = lethal.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind", &"") == &"died")
	_check(lethal.status == ActionReceipt.APPLIED and deaths.size() == 1 and deaths[0].source.credit_unit_id == 900001, "absent author retains lethal tick credit")
	session.close()
