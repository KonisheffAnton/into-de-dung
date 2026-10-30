extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL WARRIOR: " + label)

func _fixture() -> Dictionary:
	var hub := HeroHubState.create(3010, 3)
	hub.party.assign([5, 1, 2])
	check(hub.start_battle(), "v3 fighter party starts")
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(), "factory accepts fighter")
	if bundle.is_empty(): return {}
	var session: BattleCoreReactionsSession = bundle.session
	check(session.start_battle(), "battle begins")
	var steps := 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		session.step_enemy(); steps += 1
	check(session.can_player_act(), "player turn opens")
	var actor := session.board.get_unit_by_id(bundle.hero_units[5])
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	# Изолируем формулу от окружения: бой остаётся production factory/queue/clock.
	for other: UnitState in session.units:
		if other == actor or other == target: continue
		other.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 0.0)
	check(session.board.move_unit(target, actor.cell + Vector2i.RIGHT), "target placed adjacent through board")
	actor.stats.set_base_value(StatTypes.StatType.POWER, 11.0)
	actor.stats.set_base_value(StatTypes.StatType.MASTERY, 10.0)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 500.0)
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
	target.vitals.set_hp(500.0)
	target.vitals.set_balance(0.0)
	target.guard_stance = false
	target.armor.natural.physical = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	check(session.select_unit(actor.id), "fighter selected")
	return {"session": session, "actor": actor, "target": target, "hub": hub}

func _run() -> void:
	await _skills_and_parity()
	await _ui_selection()
	_permissions_and_clock()
	_codec()
	print("WARRIOR CLASS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _ui_selection() -> void:
	var f := _fixture()
	if f.is_empty(): return
	var session: BattleCoreReactionsSession = f.session
	var actor: UnitState = f.actor
	actor.action_resources.try_spend_main(1)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	root.add_child(viewport)
	var demo := (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	demo.supplied_session = session
	viewport.add_child(demo)
	await process_frame
	await process_frame
	demo._action_bar_requested(WarriorKit.KICK)
	check(demo.attack_mode and session.warrior_selected == WarriorKit.KICK and demo._attack_variant() == WarriorKit.KICK, "UI selects kick after main spent")
	check(demo._status.text.contains("1 дополнительное") and not demo._status.text.contains("1 основное"), "status displays actual bonus price")
	check(not demo._instructions.text.contains("1 основное"), "compact instructions do not contradict bonus price")
	demo.set_attack_mode(true)
	check(session.warrior_selected == &"" and demo._attack_variant() == &"ordinary", "ordinary attack clears skill selection")
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame

func _skills_and_parity() -> void:
	var f := _fixture()
	if f.is_empty(): return
	var session: BattleCoreReactionsSession = f.session
	var actor: UnitState = f.actor
	var target: UnitState = f.target
	check(WarriorKit.enabled(actor) and session.unit_visual_classes[actor.id] == &"fighter", "owned kit and model route")
	var descriptors := BattleActionDescriptors.build(session, session, false, false, func(reason: StringName) -> String: return String(reason))
	var visible := session.visible_action_descriptors(descriptors)
	check(visible.size() == 2 and visible[0].action_id == WarriorKit.CLEAVE and visible[1].action_id == WarriorKit.KICK, "two class slots")
	for skill: StringName in [WarriorKit.CLEAVE, WarriorKit.KICK]:
		session.warrior_selected = skill
		var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
		var forecast := session.preview_attack(target.id)
		check(forecast.status == ActionReceipt.APPLIED, "preview skill " + String(skill) + " " + String(forecast.reason))
		var worker := AttackForecastWorker.new()
		worker.start(session.prepare_attack_forecast(target.id))
		var threaded: AttackForecast = null
		var deadline := Time.get_ticks_msec() + 10000
		while threaded == null and Time.get_ticks_msec() < deadline:
			threaded = worker.take_finished()
			if threaded == null: await create_timer(0.001).timeout
		worker.close()
		check(threaded != null and threaded.events == forecast.events and threaded.snapshot_after == forecast.snapshot_after, "worker forecast agrees " + String(skill))
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "preview isolated " + String(skill))
		var hp_before := target.vitals.get_hp()
		var balance_before := target.vitals.get_balance()
		var execution := BattleExecutionWorker.new()
		var started := execution.start(session, &"click_attack" if skill == WarriorKit.KICK else &"attack_unit", [target.id], false, true)
		check(started, "live worker starts")
		if not started: break
		var completed := execution.take_finished(true)
		var receipt: ActionReceipt = completed.result
		check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, "live equals preview " + String(skill) + " " + String(receipt.reason))
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, "state RNG counters agree")
		if skill == WarriorKit.CLEAVE:
			check(actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 1, "cleave costs main only")
			check(target.bleeding.stacks == 1, "cleave adds exactly one stack")
			check(actor.combat_perks.warrior.ready_turn == session.state.abilities.serials[actor.faction] + 2, "cooldown belongs to warrior")
		else:
			check(is_equal_approx(hp_before - target.vitals.get_hp(), 22.0), "kick damage exactly 2P without weapon or repeated power factor")
			check(is_equal_approx(target.vitals.get_balance() - balance_before, 2.75), "kick balance P/4 preserves fraction")
			check(actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 0, "kick works after main spent and costs bonus only")
			check(session.warrior_reason(WarriorKit.KICK) == &"attack/insufficient_bonus", "no second kick without bonus")
	session.close()

func _permissions_and_clock() -> void:
	var f := _fixture()
	if f.is_empty(): return
	var session: BattleCoreReactionsSession = f.session
	var actor: UnitState = f.actor
	var target: UnitState = f.target
	var ordinary := session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	var invalid := AttackCommand.new(ordinary.id, target.id, ordinary.cell, target.cell, WarriorKit.KICK, session.context.get_revision())
	check(invalid.validate(session.context) == &"warrior/capability_required", "other class cannot use kick")
	session.warrior_selected = WarriorKit.CLEAVE
	check(session.attack_unit(target.id).status == ActionReceipt.APPLIED, "cleave commits")
	actor.try_refill_turn_resources()
	check(session.warrior_reason(WarriorKit.CLEAVE) == &"warrior/cooldown", "refill cannot clear cooldown")
	var clock := session.state.abilities
	# Границы проходят тот же codec clock; смена выделения не участвует.
	for turn: int in 2:
		for side: int in 2:
			for operation: StringName in [&"close", &"end", &"begin", &"open"]:
				var after := clock.boundary(operation, clock.team, clock.serials[clock.team])
				check(not after.is_empty(), "clock boundary " + String(operation))
				if not after.is_empty(): clock.apply_values(after)
		check(session.warrior_reason(WarriorKit.CLEAVE) == (&"warrior/cooldown" if turn == 0 else &""), "CD1 skips next own turn")
	session.close()

func _codec() -> void:
	var perks := CombatPerksState.new()
	perks.uses_bonus_actions = true
	perks.warrior = {"ready_turn": 5}
	var copied := perks.copy()
	check(copied != null and copied.to_dict() == perks.to_dict(), "warrior state roundtrip")
	copied.warrior.ready_turn = 9
	check(perks.warrior.ready_turn == 5, "cooldown dictionaries not aliased")
	var bad := perks.to_dict()
	bad.warrior.ready_turn = -1
	check(not CombatPerksState.valid(bad), "negative cooldown rejected")
