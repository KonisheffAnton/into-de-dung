extends "res://tests/test_host_cards.gd"

func prepared() -> BattleCoreReactionsSession:
	var session := arranged()
	power(session)
	return session

func power(session: BattleCoreReactionsSession) -> void:
	session.state.abilities.serials.assign([8,8])
	session.state.abilities.ended.assign([7,8])
	session.state.abilities.maximum = 9
	session.state.abilities.mana = 9

func grant(session: BattleCoreReactionsSession, type_id: String) -> int:
	var deck := session.state.deck
	var id := deck.cards.size() + 1
	if deck.hand_ids.size() >= 6: deck.draw_ids.append(deck.hand_ids.pop_back())
	deck.cards.append({"id":id,"type_id":type_id,"origin":"found"})
	deck.hand_ids.append(id)
	return id

func kill(session: BattleCoreReactionsSession, unit: UnitState) -> void:
	var receipt := session._queue.submit(DeathCommand.new(unit.id,DamageSource.new(&"test",0,unit.cell)),session.context)
	check(receipt.status == ActionReceipt.APPLIED,"death " + String(receipt.reason))

func exact(session: BattleCoreReactionsSession, id: int, target: int, cell: Vector2i, detached: bool = false) -> ActionReceipt:
	var before := snapshot(session)
	var rng := session.context.get_rng().to_dict()
	var counters := session.context.simulation_counters()
	var admission := SummonAdmission.values(session.context)
	var command := PlayMageCardCommand.new(id,target,cell,session.context.get_revision())
	var request := ForecastSimulation.prepare(session.context,session._queue,command)
	var forecast := ForecastSimulation.run_prepared(request)
	check(forecast.status == ActionReceipt.APPLIED,"return forecast " + String(forecast.reason))
	var worker := ActionForecastWorker.new()
	worker.start(ForecastSimulation.prepare(session.context,session._queue,command))
	var background: ForecastSimulation = worker.take_finished()
	while background == null:
		await process_frame
		background = worker.take_finished()
	check(background.snapshot_after == forecast.snapshot_after and background.events == forecast.events and background.admission_after == forecast.admission_after and background.rng_after == forecast.rng_after,"return forecast worker exact parity")
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and SummonAdmission.values(session.context) == admission,"return forecast isolation")
	var receipt: ActionReceipt
	if detached:
		var live := BattleExecutionWorker.new()
		var accepted := live.start(session,&"play_mage_card",[id,target,cell])
		check(accepted,"return execution worker accepted")
		receipt = live.take_finished(true).result if accepted else session.play_mage_card(id,target,cell)
	else: receipt = session.play_mage_card(id,target,cell)
	check(receipt.status == ActionReceipt.APPLIED,"return live " + String(receipt.reason))
	check(receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps and snapshot(session) == forecast.snapshot_after and SummonAdmission.values(session.context) == forecast.admission_after,"return full live parity")
	return receipt

func run() -> void:
	await living_return()
	await corpse_cards()
	await raise_cycle()
	await spirit_cards()
	enemy_raise()
	refusals()
	callback_fault()
	await production_return()
	anchor_bounds_and_fall()
	print("MAGE RETURN RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func living_return() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var stats := host.stats.to_dict()
	var owner := session.state.get_owner(host.id)
	var inventory := session.state.get_inventory(host.id)
	host.control.stunned_turns = 1; host.elemental.wet_turns = 2
	kill(session,host)
	check(host.control.stunned_turns == 0 and host.elemental.wet_turns == 0,"death clears control and elemental")
	session._check_outcome()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and session.state.card_effects.host_has_died and HostBinding.anchor(session.state).kind == "fresh","death keeps fight with fresh corpse origin")
	var id := grant(session,"card.return_to_life")
	await exact(session,id,0,host.cell,true)
	check(host.is_alive() and host.vitals.get_hp() == 12.0 and host.stats.to_dict() == stats and session.state.get_owner(host.id) == owner and session.state.get_inventory(host.id) == inventory,"living return preserves hero identity stats and equipment with12HP")
	check(session.state.abilities.mana == 5 and session.state.is_summon_pending(host.id) and host.move_points_left == 0.0 and host.action_resources.get_main_left() == 0 and host.action_resources.get_bonus_left() == 0,"return costs4; no current-turn actions")
	check(not session.context.get_move_rules().allows(host.id) and HostBinding.corpse(session.state,host.id).is_empty() and not session.state.environment.processed_deaths.has(host.id),"body consumed, actor pending and repeat death enabled")
	var saved := snapshot(session)
	var restored := ItemSimulationSnapshot.from_dict(saved)
	check(restored.code == ItemSnapshotResult.Code.OK,"pending resurrection serializes")
	var invalid := saved.duplicate(true)
	for row: Dictionary in invalid.board_snapshot.board.units:
		if row.id == host.id: row.action_resources.main_left = 1
	check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK,"pending resurrection cannot inject main action")
	var refill := session._queue.submit(BattleTurnRefill.new(session.living_ids(Faction.Type.PLAYER),session.context.get_revision(),Faction.Type.PLAYER),session.context)
	check(refill.status == ActionReceipt.APPLIED and not session.state.is_summon_pending(host.id) and host.action_resources.get_main_left() == 1 and session.context.get_move_rules().allows(host.id),"next own-team boundary enables resurrected hero: " + String(refill.reason))
	kill(session,host)
	power(session)
	await exact(session,grant(session,"card.return_to_life"),0,host.cell)
	check(host.is_alive() and host.vitals.get_hp() == 12.0,"repeat resurrection has no count limit")
	session.close()

func corpse_cards() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	kill(session,host)
	await exact(session,grant(session,"card.light_step"),host.id,Vector2i(-1,-1))
	check(not host.is_alive() and session.state.card_effects.light_step_serial == 8,"corpse step spends card and normal serial without moving corpse")
	await exact(session,grant(session,"card.fire_imbue"),host.id,Vector2i(-1,-1))
	check(session.state.card_effects.fire_imbues.size() == 1,"corpse accepts fire imbue")
	await exact(session,grant(session,"card.shield"),host.id,Vector2i(-1,-1))
	check(not host.armor.shield.is_empty(),"corpse accepts shield")
	power(session)
	await exact(session,grant(session,"card.return_to_life"),0,host.cell)
	check(session.state.card_effects.fire_imbues.is_empty() and host.armor.shield.is_empty(),"return clears corpse buffs")
	session.close()

func raise_cycle() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	kill(session,host)
	await exact(session,grant(session,"card.raise"),0,host.cell,true)
	var raised := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	check(raised != host and raised.faction == Faction.Type.PLAYER and raised.creature_kind == &"undead" and session.state.is_summon(raised.id),"raised body carries binding under player control")
	check(raised.vitals.get_hp() == 16.0 and raised.stats.get_value(StatTypes.StatType.MOVE_RANGE) == 4.0 and raised.combat_perks == null and session.state.abilities.mana == 7,"spell helper stats and2mana")
	check(session.state.is_summon_pending(raised.id) and not host.is_alive(),"undead pending, original hero remains dead")
	kill(session,raised)
	check(HostBinding.anchor(session.state).kind == "bones","dead raised carrier leaves bones")
	await exact(session,grant(session,"card.raise"),0,raised.cell)
	check(session.state.card_effects.host_unit_id != raised.id,"bones can be raised again")
	# Второй труп рядом с живой поднятой опорой: нет лимита активной нежити.
	var foe := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	kill(session,foe)
	await exact(session,grant(session,"card.raise"),0,foe.cell)
	var alive_helpers: int = 0
	for record: Dictionary in session.state.get_summons():
		if session.board.get_unit_by_id(record.unit_id).is_alive(): alive_helpers += 1
	check(alive_helpers == 2,"two simultaneous raised helpers allowed")
	var permanent := session.living_ids(Faction.Type.PLAYER)
	for unit_id: int in permanent:
		if not session.state.is_summon(unit_id): kill(session,session.board.get_unit_by_id(unit_id))
	session._check_outcome()
	check(HostBinding.party_dead(session.state) and session.phase == BattleTacticalSession.Phase.DEFEAT and session.state.abilities.stage == "terminal","undead cannot prevent permanent-party defeat")
	session.close()

func spirit_cards() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var ally: int = session.living_ids(Faction.Type.PLAYER)[1]
	kill(session,host)
	session.state.environment.consume_corpse(HostBinding.corpse(session.state,host.id).id)
	session.board.set_terrain(host.cell,TerrainType.Type.VOID)
	check(HostBinding.anchor(session.state).kind == "spirit" and session.board.occupant_at(host.cell) == null,"no remains yields nonoccupying spirit on pit")
	await exact(session,grant(session,"card.binding_thread"),ally,Vector2i(-1,-1))
	var id := grant(session,"card.light_step")
	var before := snapshot(session)
	check(session.play_mage_card(id,host.id,Vector2i(-1,-1)).status == ActionReceipt.REJECTED and snapshot(session) == before,"spirit has no body for buffs")
	id = grant(session,"card.raise"); before = snapshot(session)
	check(session.play_mage_card(id,0,host.cell).status == ActionReceipt.REJECTED and snapshot(session) == before,"spirit itself cannot be raised")
	session.close()

func enemy_raise() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var enemy := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	kill(session,host)
	var command := RaiseCorpseCommand.new(enemy.id,HostBinding.corpse(session.state,host.id).id,session.context.get_revision())
	var before := snapshot(session)
	var preview := ForecastSimulation.run_prepared(ForecastSimulation.prepare(session.context,session._queue,command))
	check(preview.status == ActionReceipt.APPLIED and snapshot(session) == before,"enemy raise forecast isolated: " + String(preview.reason))
	var receipt := session._queue.submit(command,session.context)
	var raised := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	check(receipt.status == ActionReceipt.APPLIED and raised.faction == Faction.Type.PLAYER and raised != host and snapshot(session) == preview.snapshot_after,"enemy raising carrier grants player helper: " + String(receipt.reason))
	session.close()

func refusals() -> void:
	for mode: String in ["bones","occupied","far","height","wall","mana","enemy","gone"]:
		var session := prepared()
		var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
		kill(session,host)
		var cell := host.cell
		match mode:
			"bones":
				for body: Dictionary in session.state.environment.corpses: body.remains = "bones"; body.fresh_turns_left = 0; body.fresh_round_pending = false
			"occupied": session.board.move_unit(session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0]),cell)
			"far": cell = Vector2i(5,0)
			"height":
				var other := session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[0])
				cell = Vector2i(0,1); session.board.set_terrain(cell,TerrainType.Type.FLOOR); session.board.set_height(cell,1)
				session.board.move_unit(other,cell); kill(session,other)
			"wall": cell = Vector2i(0,1); session.board.set_terrain(cell,TerrainType.Type.WALL)
			"mana": session.state.abilities.mana = 3
			"enemy":
				var enemy := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0]); kill(session,enemy); cell = enemy.cell
			"gone": session.state.environment.consume_corpse(HostBinding.corpse(session.state,host.id).id)
		var id := grant(session,"card.return_to_life")
		var before := snapshot(session)
		var receipt := session.play_mage_card(id,0,cell)
		check(receipt.status == ActionReceipt.REJECTED and snapshot(session) == before,"invalid return atomic " + mode + ": " + String(receipt.reason))
		session.close()

func callback_fault() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var other := session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	kill(session,host)
	host.vitals.hp_changed.connect(func(_old:float,_new:float)->void: other.move_points_left += 1.0)
	var id := grant(session,"card.return_to_life")
	var receipt := session.play_mage_card(id,0,host.cell)
	check(receipt.status == ActionReceipt.FAULTED and host.is_alive() and session.state.deck.spent_ids.has(id) and session.state.abilities.mana == 5,"hostile return callback faults after paid actual prefix: " + String(receipt.reason))
	session.close()

func production_return() -> void:
	for undead: bool in [false,true]:
		var hub := HeroHubState.create(12041,4)
		hub.enable_mage_deck(); hub.select_mage_host(hub.party[0])
		hub = ExpeditionTransitions.apply(hub,"start").profile
		var bundle := HeroHubBattleFactory.create(hub)
		check(not bundle.is_empty(),"production return factory")
		if bundle.is_empty(): continue
		var session: BattleCoreReactionsSession = bundle.session
		check(session.confirm_mage_deployment() and session.confirm_mage_mulligan([]).status == ActionReceipt.APPLIED and session.start_battle(),"production enters battle")
		session._enemy_index = session._enemy_ids.size(); session.step_enemy()
		power(session)
		var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
		var host_hero_id: int = hub.expedition.host_hero_id
		var stats := host.stats.to_dict()
		var gear := session.state.get_owner(host.id)._items.duplicate()
		kill(session,host)
		await exact(session,grant(session,"card.raise" if undead else "card.return_to_life"),0,host.cell)
		var returned := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
		if undead:
			check(returned != host and returned.combat_perks == null,"production undead has no inherited class")
			var definition := session.context.get_attack_rules().get_definition(MageDeckRules.RAISED_ATTACK)
			check(definition != null and definition.damage_components.is_empty(),"production raised attack has no demo fire")
			var refill := session._queue.submit(BattleTurnRefill.new(session.living_ids(Faction.Type.PLAYER),session.context.get_revision()),session.context)
			check(refill.status == ActionReceipt.APPLIED,"production raised unit joins next team turn")
			session.select_unit(returned.id)
			var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
			var command := session._command_for(target.id)
			check(command != null and command.get_attack_definition_id() == MageDeckRules.RAISED_ATTACK,"actual player attack chooses raised definition")
		else: check(returned == host and host.stats.to_dict() == stats and session.state.get_owner(host.id)._items == gear,"production living return keeps original stats and gear")
		for id: int in session.living_ids(Faction.Type.ENEMY): kill(session,session.board.get_unit_by_id(id))
		session._check_outcome()
		var receipt := HeroHubBattleFactory.outcome(bundle)
		check(receipt.get("host_has_died",false) and receipt.get("victory",false),"factory exports death history despite victory")
		var transition := ExpeditionTransitions.apply(hub,"outcome",receipt)
		check(transition.is_ok(),"production outcome accepts factory receipt: " + transition.reason)
		if transition.is_ok():
			check(transition.profile.expedition.host_hero_id == 0 and transition.profile.mage_deck.host_hero_id == 0,"production outcome requires explicit reselect")
			check(transition.profile.heroes.has(host_hero_id) == not undead,"only living resurrected hero persists")
			check(HeroHubState.from_dict(transition.profile.to_dict()) != null,"production returned outcome reloads")
		session.close()

func anchor_bounds_and_fall() -> void:
	var session := prepared()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var source := DamageSource.new(&"mage",29,Vector2i(-1,-1))
	check(source.validate(session.context) == &"" and DamageSource.is_card_source(29),"return source29 recognized with deck")
	var no_deck := BattleCoreReactionsSession.new()
	check(source.validate(no_deck.context) == &"source/deck_required","return source29 requires deck capability")
	no_deck.close()
	session.board.set_terrain(Vector2i(0,1),TerrainType.Type.VOID)
	var death := session._queue.submit(DeathCommand.new(host.id,DamageSource.new(&"fall",0,Vector2i(0,1))),session.context)
	check(death.status == ActionReceipt.APPLIED and HostBinding.corpse(session.state,host.id).is_empty() and HostBinding.anchor(session.state).cell == Vector2i(0,1),"fall without body binds at lethal destination")
	var saved := snapshot(session)
	var bad := saved.duplicate(true); bad.card_effects.host_death_cell = Vector2i(session.board.width,0)
	check(ItemSimulationSnapshot.from_dict(bad).code != ItemSnapshotResult.Code.OK,"out-of-board spirit snapshot rejected")
	session.state.card_effects.host_death_cell = Vector2i(0,session.board.height)
	check(ItemSimulationSnapshot.capture(session.state,[]).code != ItemSnapshotResult.Code.OK,"out-of-board live spirit rejected")
	session.close()
	session = prepared(); host = session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	session.state.environment.collapse = {"turn":1,"marked":[host.cell]}
	var collapse := session._queue.submit(CollapsePhaseCommand.new(session.context.get_revision()),session.context)
	check(collapse.status == ActionReceipt.APPLIED and HostBinding.anchor(session.state).kind == "spirit" and not host.is_alive(),"collapsed carrier creates spirit through real queue")
	session.close()
