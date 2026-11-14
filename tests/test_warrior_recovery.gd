extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL WARRIOR RECOVERY: " + label)

func battle_fixture(seed_value: int, catalog_version: int) -> Dictionary:
	var run := HeroHubState.create(seed_value, catalog_version)
	if run == null: return {}
	if catalog_version == 3: run.party = [5, 1, 2]
	if not run.start_battle(): return {}
	return HeroHubBattleFactory.create(run)

func battle_unit(bundle: Dictionary, hero_id: int) -> UnitState:
	if bundle.is_empty(): return null
	var session: BattleCoreReactionsSession = bundle.session
	return session.board.get_unit_by_id(bundle.hero_units[hero_id])

func healing_item(owner: ItemOwnerState) -> ItemInstance:
	for item: ItemInstance in owner.get_items_for(ItemOwnerState.INVENTORY_PLACEMENT):
		if String(item.get_definition_id()).begins_with("hero_flask_"): return item
	return null

func _run() -> void:
	_test_combat_healing()
	_test_mage_card_healing()
	_test_resistance_absorption_healing()
	_test_item_healing_and_armor()
	_test_hub_recovery()
	print("WARRIOR RECOVERY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_combat_healing() -> void:
	var fighter_bundle := battle_fixture(76101, 3)
	var legacy_bundle := battle_fixture(76102, 1)
	check(not fighter_bundle.is_empty() and not legacy_bundle.is_empty(), "fighter and legacy battle fixtures create")
	if fighter_bundle.is_empty() or legacy_bundle.is_empty(): return
	var fighter_session: BattleCoreReactionsSession = fighter_bundle.session
	var fighter := battle_unit(fighter_bundle, 5)
	var fighter_max := ActionHpExecutor._stat_value(fighter, StatTypes.StatType.HP_MAX)
	fighter.vitals.set_hp(fighter_max - 10.0)
	var source := DamageSource.new(&"test", 0, fighter.cell, fighter.id, fighter.id)
	var boosted := ActionHpExecutor.heal(fighter.id, 5.0, source, fighter_session.context)
	check(boosted.status == &"APPLIED" and is_equal_approx(fighter.vitals.get_hp(), fighter_max - 4.0), "fighter receives 20 percent once before the HP cap")
	check(boosted.events.size() == 1 and is_equal_approx(boosted.events[0].amount, 6.0), "heal event reports actual boosted recovery")
	fighter.vitals.set_hp(fighter_max - 2.0)
	var capped := ActionHpExecutor.heal(fighter.id, 5.0, source, fighter_session.context)
	check(capped.status == &"APPLIED" and is_equal_approx(fighter.vitals.get_hp(), fighter_max), "fighter heal caps at missing HP")
	check(capped.events.size() == 1 and is_equal_approx(capped.events[0].amount, 2.0), "capped event reports actual recovery")
	var legacy_session: BattleCoreReactionsSession = legacy_bundle.session
	var legacy := battle_unit(legacy_bundle, 1)
	var legacy_max := ActionHpExecutor._stat_value(legacy, StatTypes.StatType.HP_MAX)
	legacy.vitals.set_hp(legacy_max - 10.0)
	var legacy_source := DamageSource.new(&"test", 0, legacy.cell, legacy.id, legacy.id)
	var unchanged := ActionHpExecutor.heal(legacy.id, 5.0, legacy_source, legacy_session.context)
	check(unchanged.status == &"APPLIED" and is_equal_approx(legacy.vitals.get_hp(), legacy_max - 5.0), "legacy warrior healing remains unchanged")
	fighter_session.close(); legacy_session.close()

func _test_mage_card_healing() -> void:
	var bundle := battle_fixture(76106, 3)
	check(not bundle.is_empty(), "mage recovery battle fixture creates")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var fighter := battle_unit(bundle, 5)
	var maximum := ActionHpExecutor._stat_value(fighter, StatTypes.StatType.HP_MAX)
	fighter.vitals.set_hp(maximum - 10.0)
	var source := DamageSource.new(&"mage", 1, Vector2i(-1, -1), 0, 0)
	var plan := MageEffectExecutor.prepare(session.context, fighter.id, fighter.cell, &"mage.heal", 5, 0, source, {}, &"mage.heal")
	check(plan.get("reason", &"invalid") == &"" and is_equal_approx(float(plan.get("hp_after", 0.0)), maximum - 4.0), "mage card heal plan applies fighter recovery factor once: %s hp %s expected %s" % [plan.get("reason", &"missing"), plan.get("hp_after", -1.0), maximum - 4.0])
	if plan.get("reason", &"invalid") == &"":
		var result := MageEffectExecutor.apply(session.context, plan, plan.guard, func() -> bool: return true)
		check(result.status == &"APPLIED" and is_equal_approx(fighter.vitals.get_hp(), maximum - 4.0), "mage card heal applies boosted recovery")
		check(result.events.size() == 1 and is_equal_approx(float(result.events[0].get("amount", 0.0)), 6.0), "mage card heal event reports actual boosted amount")
	fighter.vitals.set_hp(maximum - 2.0)
	var capped_plan := MageEffectExecutor.prepare(session.context, fighter.id, fighter.cell, &"mage.heal", 5, 0, source, {}, &"mage.heal")
	check(capped_plan.get("reason", &"invalid") == &"" and is_equal_approx(float(capped_plan.get("hp_after", 0.0)), maximum), "mage card heal caps at missing HP after boost: %s hp %s max %s" % [capped_plan.get("reason", &"missing"), capped_plan.get("hp_after", -1.0), maximum])
	session.close()

func _test_resistance_absorption_healing() -> void:
	var bundle := battle_fixture(76107, 3)
	check(not bundle.is_empty(), "resistance recovery battle fixture creates")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var fighter := battle_unit(bundle, 5)
	var owner := session.state.get_owner(fighter.id)
	var view := ArmorRuntime.capture(owner)
	check(not view.is_empty(), "fighter armor view captures for resistance healing")
	if view.is_empty():
		session.close(); return
	view.state.natural.physical = 11000
	view.state.perks.append({"id": "test_absorption", "type": "physical", "branch": "natural", "bonus": 4000})
	var maximum := ActionHpExecutor._stat_value(fighter, StatTypes.StatType.HP_MAX)
	fighter.vitals.set_hp(maximum - 1.0)
	var request := ArmorAttack.request(fighter.id, ArmorAttack.components(10.0, 0.0, 0, false, [], 0, 1, 100), DamageSource.new(&"test", 0, fighter.cell, fighter.id, fighter.id))
	var baseline := ArmorHitExecutor.prepare(request, view, fighter.vitals.get_hp(), maximum, session.context.get_rng())
	var boosted := ArmorHitExecutor.prepare(request, view, fighter.vitals.get_hp(), maximum, session.context.get_rng(), false, session.context)
	check(baseline.get("reason", &"invalid") == &"" and boosted.get("reason", &"invalid") == &"", "resistance absorption plans prepare with and without warrior factor")
	if baseline.get("reason", &"invalid") == "" and boosted.get("reason", &"invalid") == "":
		check(float(baseline.total_healing) > 0.0 and is_equal_approx(float(boosted.total_healing), float(baseline.total_healing) * 1.2), "resistance absorption healing receives fighter factor exactly once: base %s boosted %s rows %s" % [baseline.total_healing, boosted.total_healing, baseline.rows])
		check(is_equal_approx(float(boosted.hp_after), maximum) and is_equal_approx(float(boosted.hp_gain), 1.0), "resistance absorption healing caps at missing HP: after %s gain %s max %s rows %s" % [boosted.hp_after, boosted.hp_gain, maximum, boosted.rows])
	session.close()

func _test_item_healing_and_armor() -> void:
	var bundle := battle_fixture(76103, 3)
	check(not bundle.is_empty(), "battle recovery fixture creates")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var fighter := battle_unit(bundle, 5)
	var owner := session.state.get_owner(fighter.id)
	var potion_item := healing_item(owner)
	check(potion_item != null, "fighter factory provides its registered healing potion")
	if potion_item == null:
		session.close(); return
	potion_item.get_definition().use_heal_amount = 5.0
	var maximum := ActionHpExecutor._stat_value(fighter, StatTypes.StatType.HP_MAX)
	fighter.vitals.set_hp(maximum - 10.0)
	var main_before := fighter.action_resources.get_main_left()
	var applied := session._queue.submit(UseHealingItemCommand.new(fighter.id, potion_item.get_item_instance_id(), session.context.get_revision()), session.context)
	var event_amount := 0.0
	for event: Dictionary in applied.get_events():
		if event.get("kind") == &"healed": event_amount = float(event.amount)
	check(applied.status == ActionReceipt.APPLIED and is_equal_approx(fighter.vitals.get_hp(), maximum - 4.0), "fighter potion applies boosted healing through its command: %s/%s HP %s" % [applied.status, applied.reason, fighter.vitals.get_hp()])
	check(is_equal_approx(event_amount, 6.0) and potion_item.get_charges_left() == 0 and fighter.action_resources.get_main_left() == main_before - 1, "potion event, charge and main payment match the actual heal: amount %s charges %s main %s" % [event_amount, potion_item.get_charges_left(), fighter.action_resources.get_main_left()])

	fighter.armor.in_battle = true
	fighter.try_refill_turn_resources()
	var armor_item: ItemInstance = null
	for item: ItemInstance in owner._items.values():
		if item.get_definition().armor_max > 0: armor_item = item; break
	check(armor_item != null, "fighter fixture has armor to restore")
	if armor_item == null:
		session.close(); return
	var armor_max: int = armor_item.get_definition().armor_max
	armor_item.armor_remaining = armor_max - 20
	var restored := session._queue.submit(RestoreArmorCommand.new(fighter.id, 20, session.context.get_revision()), session.context)
	check(restored.status == ActionReceipt.APPLIED and armor_item.armor_remaining == armor_max, "fighter armor volume 20 restores 20 missing armor: %s/%s armor %s" % [restored.status, restored.reason, armor_item.armor_remaining])
	check(fighter.armor.grants.size() == 1 and is_equal_approx(float(fighter.armor.grants[0].remaining), 4.0), "boosted armor volume 24 grants its exact overflow: " + str(fighter.armor.grants))

	fighter.try_refill_turn_resources()
	armor_item.armor_remaining = float(armor_max) - 2.0
	var before_fractional := float(armor_item.armor_remaining)
	var fractional_restore := session._queue.submit(RestoreArmorCommand.new(fighter.id, 1, session.context.get_revision()), session.context)
	check(fractional_restore.status == ActionReceipt.APPLIED and is_equal_approx(float(armor_item.armor_remaining) - before_fractional, 1.2), "fighter armor volume 1 restores 1.2 fractional armor: %s/%s after %s" % [fractional_restore.status, fractional_restore.reason, armor_item.armor_remaining])
	var view := ArmorRuntime.capture(owner)
	check(not view.is_empty(), "fractional armor view captures")
	if view.is_empty():
		session.close(); return
	view["state"]["fractional"] = true
	var unchanged_view := view.duplicate(true)
	check(ArmorRecovery.restore(view, NAN, "test").reason == &"armor/overflow" and view == unchanged_view, "non-finite repair volume is rejected without view mutation")
	armor_item.armor_remaining = armor_max - 3
	var integer_view := view.duplicate(true)
	integer_view["state"]["fractional"] = false
	integer_view["state"]["grants"] = []
	for item_record: Dictionary in integer_view["items"]:
		item_record["remaining"] = int(item_record["remaining"])
	check(ArmorRecovery.restore(integer_view, 1.2, "test").reason == &"armor/overflow", "legacy integer armor path rejects fractional volume")

	session.close()
	_test_item_preflight_and_callback()

func _test_item_preflight_and_callback() -> void:
	var bundle := battle_fixture(76105, 3)
	check(not bundle.is_empty(), "callback-guard battle fixture creates")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var fighter := battle_unit(bundle, 5)
	var potion_item := healing_item(session.state.get_owner(fighter.id))
	check(potion_item != null, "callback-guard fixture has its registered potion")
	if potion_item == null:
		session.close(); return
	potion_item.get_definition().use_heal_amount = 1.0
	var maximum := ActionHpExecutor._stat_value(fighter, StatTypes.StatType.HP_MAX)
	fighter.vitals.set_hp(maximum - 10.0)
	fighter.armor.fractional = false
	var charges_before := potion_item.get_charges_left()
	var main_before := fighter.action_resources.get_main_left()
	# Проверяем preflight непосредственно: полный snapshot закономерно отвергает
	# синтетически противоречивый runtime, где дробная пассивка помечена integer.
	var fraction_reason := UseHealingItemCommand.new(fighter.id, potion_item.get_item_instance_id(), session.context.get_revision())._availability(session.context, false)
	check(fraction_reason == &"armor/fractional_heal" and potion_item.get_charges_left() == charges_before and fighter.action_resources.get_main_left() == main_before, "integer HP recipient rejects fractional boosted potion before payment: " + String(fraction_reason))
	fighter.armor.fractional = true
	fighter.try_refill_turn_resources()
	var callback_used := [false]
	var callback := func(_before: float, _after: float) -> void:
		if not callback_used[0]:
			callback_used[0] = true
			fighter.action_resources.try_spend_bonus(1)
	fighter.vitals.hp_changed.connect(callback)
	var guarded := session._queue.submit(UseHealingItemCommand.new(fighter.id, potion_item.get_item_instance_id(), session.context.get_revision()), session.context)
	fighter.vitals.hp_changed.disconnect(callback)
	check(callback_used[0] and guarded.status == ActionReceipt.FAULTED and guarded.reason == &"item/invalid_mutation", "potion callback mutation trips the pinned snapshot guard: called %s receipt %s/%s" % [callback_used[0], guarded.status, guarded.reason])
	session.close()

func _hub_battle_receipt(hub: HeroHubState, fighter_armor_remaining: float) -> Dictionary:
	var hp: Dictionary = {}
	for id: int in hub.party:
		var hero: HeroProgression = hub.heroes[id]
		hp[id] = maxf(1.0, float(hero.max_hp()) - 10.0)
	var gear: Dictionary = {}
	for id: int in hub.battle_items():
		gear[id] = hub.items[id].remaining
	var fighter_armor := hub.equipped(5, "armor")
	gear[fighter_armor.id] = fighter_armor_remaining
	return {"hp":hp,"gear":gear}

func _finish_hub_battle(hub: HeroHubState, fighter_armor_remaining: float) -> bool:
	if not hub.start_battle(): return false
	var receipt := _hub_battle_receipt(hub, fighter_armor_remaining)
	return hub.finish_battle(hub.run_serial, true, receipt.hp, receipt.gear)

func _test_hub_recovery() -> void:
	var hub := HeroHubState.create(76104, 3)
	hub.party = [5, 1, 2]
	var fighter: HeroProgression = hub.heroes[5]
	var armor := hub.equipped(5, "armor")
	var maximum: int = HeroGearCatalog.definition(armor.definition).armor_max
	check(_finish_hub_battle(hub, float(maximum - 20)), "fighter hub battle finishes for recovery report")
	var row: Dictionary = {}
	for result: Dictionary in hub.battle_report.heroes:
		if result.id == 5: row = result; break
	var battle_hp: float = float(row.hp_after_battle)
	var base_recovery := floorf(float(row.hp_max) * 0.1)
	var expected_hp := minf(float(row.hp_max), battle_hp + base_recovery * 1.2)
	check(is_equal_approx(float(row.hp_after_recovery), expected_hp) and is_equal_approx(fighter.hp_current, expected_hp), "post-victory report and live fighter receive boosted recovery")
	check(float(hub.equipped(5, "armor").remaining) == maximum and PostBattleRules.repair_quote(hub, 5).is_empty(), "hub return restores warrior armor freely")
	# Бонус платного ремонта проверяется внутри похода, где сохраняется износ.
	hub = _step_expedition(hub, "start")
	hub = _step_expedition(hub, "choose", {"node":hub.expedition.available_nodes()[0]})
	var outcome := _expedition_receipt(hub)
	outcome.gear[hub.equipped(5, "armor").id] = maximum - 20
	hub = _step_expedition(hub, "outcome", outcome)
	var quote := PostBattleRules.repair_quote(hub, 5)
	check(not quote.is_empty() and is_equal_approx(float(quote.amount), 12.0) and quote.cost == 20 and quote.affordable, "paid fighter repair restores 12 armor for 20 gold")
	check(hub.repair_after_battle(5), "full fighter repair accepts quoted payment")
	var partial := PostBattleRules.repair_quote(hub, 5)
	check(not partial.is_empty() and is_equal_approx(float(partial.amount), 8.0) and partial.cost == ceili(8.0 / 1.2 * 2.0), "partial repair caps at the remaining 8 and scales the fee by recovery factor")
	check(hub.repair_after_battle(5), "partial fighter repair succeeds")
	var restored := HeroHubState.from_dict(hub.to_dict())
	check(restored != null and restored.to_dict() == hub.to_dict(), "fighter recovery report validates after profile roundtrip")
	var path := "user://warrior-recovery-%d.save" % Time.get_ticks_usec()
	check(HeroHubStore.write_run(path, hub).is_empty(), "fighter recovery profile saves")
	var loaded := HeroHubStore.read_run(path)
	check(loaded.run != null and loaded.run.to_dict() == hub.to_dict(), "fighter recovery and repair report survive store roundtrip")
	for target: String in [path, path + ".bak", path + ".tmp"]:
		var absolute := ProjectSettings.globalize_path(target)
		if FileAccess.file_exists(target): DirAccess.remove_absolute(absolute)
	_test_camp_recovery()

func _step_expedition(hub: HeroHubState, action: String, args: Dictionary = {}) -> HeroHubState:
	var result := ExpeditionTransitions.apply(hub, action, args)
	check(result.is_ok(), "expedition step " + action + ": " + result.reason)
	return result.profile if result.is_ok() else hub

func _expedition_receipt(hub: HeroHubState) -> Dictionary:
	var hp: Dictionary = {}
	for id: int in hub.party:
		var hero: HeroProgression = hub.heroes[id]
		hp[id] = maxf(1.0, float(hero.max_hp()) - 10.0)
	var gear: Dictionary = {}
	for item: Dictionary in hub.expedition.checkpoint.items:
		gear[item.id] = maxf(0.0, float(item.remaining) - 2.0)
	return {"run_id":hub.expedition.run_id,"node_id":hub.expedition.current_node().id,"serial":hub.expedition.battle_serial,"victory":true,"hp":hp,"gear":gear}

func _test_camp_recovery() -> void:
	var hub := HeroHubState.create(919, 3)
	hub.party = [5, 1, 2]
	var started := ExpeditionTransitions.apply(hub, "start")
	check(started.is_ok(), "fighter profile starts an expedition")
	if not started.is_ok(): return
	hub = started.profile
	var camp_found := false
	for unused: int in 32:
		match hub.expedition.phase:
			"route":
				var choice: int = hub.expedition.available_nodes()[0]
				for id: int in hub.expedition.available_nodes():
					if hub.expedition.plan.nodes[id - 1].kind == "camp": choice = id; break
				hub = _step_expedition(hub, "choose", {"node":choice})
			"battle":
				hub = _step_expedition(hub, "outcome", _expedition_receipt(hub))
			"reward": hub = _step_expedition(hub, "reward", {"index":0})
			"service":
				if hub.expedition.current_node().kind == "camp": camp_found = true; break
				hub = _step_expedition(hub, "service", {"kind":"heal"})
			"camp_departure": hub = _step_expedition(hub, "continue")
		if hub.phase != "expedition" or hub.expedition == null: break
	check(camp_found, "deterministic route reaches a camp service")
	if not camp_found: return
	var camp := HeroHubState.from_dict(hub.to_dict())
	check(camp != null, "camp checkpoint clones for independent service choices")
	if camp == null: return
	var hero: HeroProgression = camp.heroes[5]
	var hp_max: int = hero.max_hp()
	var hp_before := maxf(1.0, float(hp_max) - 20.0)
	hero.hp_current = hp_before
	var modifier: String = camp.expedition.current_node().modifier
	var heal_percent: int = ExpeditionCatalog.BOOSTED_SERVICE_PERCENT if modifier == "healing" else ExpeditionCatalog.SERVICE_PERCENT
	var expected_hp := minf(float(hp_max), hp_before + floorf(float(hp_max) * heal_percent / 100.0) * 1.2)
	var healed := ExpeditionTransitions.apply(camp, "service", {"kind":"heal"})
	check(healed.is_ok() and is_equal_approx(float(healed.profile.heroes[5].hp_current), expected_hp), "camp heal applies fighter factor before missing HP cap")
	var repair_profile := HeroHubState.from_dict(hub.to_dict())
	var armor := repair_profile.equipped(5, "armor")
	var armor_max: int = HeroGearCatalog.definition(armor.definition).armor_max
	armor.remaining = float(armor_max - 20)
	var repair_percent: int = ExpeditionCatalog.BOOSTED_SERVICE_PERCENT if repair_profile.expedition.current_node().modifier == "repair" else ExpeditionCatalog.SERVICE_PERCENT
	var expected_armor := minf(float(armor_max), float(armor.remaining) + floorf(float(armor_max) * repair_percent / 100.0) * 1.2)
	var repaired := ExpeditionTransitions.apply(repair_profile, "service", {"kind":"repair"})
	check(repaired.is_ok() and is_equal_approx(float(repaired.profile.items[armor.id].remaining), expected_armor), "camp repair applies fighter factor before armor cap")
