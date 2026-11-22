extends "res://tests/test_mage_deck_battle.gd"

class TerminalDeaths extends Command:
	var ids: Array[int] = []
	func _init(value: Array[int]) -> void: ids = value.duplicate()
	func get_kind() -> StringName: return &"test_terminal_deaths"
	func copy_for_queue() -> Command: return TerminalDeaths.new(ids)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(context: ActionContext) -> CommandStepResult:
		var children: Array[Command] = []
		for id: int in ids:
			children.append(DeathCommand.new(id,DamageSource.new(&"test",0,context.get_state().get_board().get_unit_by_id(id).cell)))
		return CommandStepResult.applied([],children)

func arranged() -> BattleCoreReactionsSession:
	var session := fixture()
	var players := session.living_ids(Faction.Type.PLAYER)
	var enemies := session.living_ids(Faction.Type.ENEMY)
	session.state.card_effects.host_unit_id = players[0]
	var index := 0
	for unit: UnitState in session.units:
		if not unit.is_alive(): continue
		var spare := Vector2i(index, 7)
		session.board.set_terrain(spare, TerrainType.Type.FLOOR)
		session.board.set_height_steps(spare, 0)
		check(session.board.move_unit(unit, spare), "stage unit")
		index += 1
	for x: int in range(4):
		session.board.set_terrain(Vector2i(x, 0), TerrainType.Type.FLOOR)
		session.board.set_height_steps(Vector2i(x, 0), 0)
	check(session.board.move_unit(session.board.get_unit_by_id(players[0]), Vector2i(0,0)), "host position")
	check(session.board.move_unit(session.board.get_unit_by_id(players[1]), Vector2i(3,0)), "ally position")
	for n: int in mini(2, enemies.size()):
		var enemy := session.board.get_unit_by_id(enemies[n])
		check(session.board.move_unit(enemy, Vector2i(n+1,0)), "enemy position")
		for item: ItemInstance in session.state.get_owner(enemy.id)._items.values(): item.armor_remaining = 0
	return session

func parity(session: BattleCoreReactionsSession, id: int, target: int) -> ActionReceipt:
	var before := snapshot(session)
	var rng := session.context.get_rng().to_dict()
	var command := PlayMageCardCommand.new(id,target,Vector2i(-1,-1),session.context.get_revision())
	var forecast := ForecastSimulation.run_prepared(ForecastSimulation.prepare(session.context,session._queue,command))
	check(forecast.status == ActionReceipt.APPLIED, "forecast " + String(forecast.reason))
	check(snapshot(session) == before and session.context.get_rng().to_dict() == rng, "forecast isolation")
	var worker := ActionForecastWorker.new()
	worker.start(ForecastSimulation.prepare(session.context,session._queue,command))
	var background: ForecastSimulation = worker.take_finished()
	while background == null:
		await process_frame
		background = worker.take_finished()
	check(background.snapshot_after == forecast.snapshot_after and background.events == forecast.events, "worker parity")
	var receipt := session.play_mage_card(id,target,Vector2i(-1,-1))
	check(receipt.status == ActionReceipt.APPLIED, "live " + String(receipt.reason))
	check(snapshot(session) == forecast.snapshot_after and receipt.get_events() == forecast.events, "live full parity")
	return receipt

func run() -> void:
	death_before_mulligan()
	var session := arranged()
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var ally := session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	host.move_points_left = 1.0
	host.action_resources._main_left = 0
	host.action_resources._bonus_left = 0
	host.control.entangled_turns = 1
	var id := card_in_hand(session, "card.light_step")
	var before := snapshot(session)
	check(session.play_mage_card(id,ally.id,Vector2i(-1,-1)).status == ActionReceipt.REJECTED and snapshot(session) == before, "wrong carrier atomic refusal")
	await parity(session,id,host.id)
	check(host.move_points_left == 3.0 and host.action_resources.get_main_left() == 0 and host.action_resources.get_bonus_left() == 0 and host.control.entangled_turns == 1, "adds movement only; no refill or roots removal")
	var copy_id := session.state.deck.cards.size() + 1
	session.state.deck.cards.append({"id":copy_id,"type_id":"card.light_step","origin":"found"})
	session.state.deck.hand_ids.append(copy_id)
	before = snapshot(session)
	check(session.play_mage_card(copy_id,host.id,Vector2i(-1,-1)).reason == &"host_card/already_used" and snapshot(session) == before, "second copy refused without cost")
	var closed := session._queue.submit(AbilityBoundaryCommand.new(&"close",0,session.state.abilities.serials[0],session.context.get_revision()),session.context)
	check(closed.status == ActionReceipt.APPLIED,"close step turn")
	var ended := session._queue.submit(AbilityBoundaryCommand.new(&"end",0,session.state.abilities.serials[0],session.context.get_revision()),session.context)
	check(ended.status == ActionReceipt.APPLIED and host.move_points_left == 1.0,"unused bonus expires at end")
	session.close()
	session = arranged()
	host = session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	ally = session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	id = card_in_hand(session,"card.binding_thread")
	var enemies := session.living_ids(Faction.Type.ENEMY)
	var hp: Dictionary = {}
	for enemy_id: int in enemies: hp[enemy_id] = session.board.get_unit_by_id(enemy_id).vitals.get_hp()
	var host_hp := host.vitals.get_hp()
	var ally_hp := ally.vitals.get_hp()
	var thread_receipt := await parity(session,id,ally.id)
	for n: int in mini(2,enemies.size()):
		var enemy := session.board.get_unit_by_id(enemies[n])
		var direct_four := thread_receipt.get_events().any(func(event: Dictionary) -> bool: return event.kind == &"damaged" and event.target_unit_id == enemy.id and event.amount == 4.0)
		check(direct_four and enemy.vitals.get_hp() < hp[enemy.id] and enemy.elemental.burning_stacks == 0,"four direct damage before item reactions, without burning")
	check(host.vitals.get_hp() == host_hp and ally.vitals.get_hp() == ally_hp,"endpoints unharmed")
	check(session.state.abilities.mana == 0,"thread costs two mana")
	session.close()
	session = arranged()
	host = session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	ally = session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	id = card_in_hand(session,"card.binding_thread")
	session.board.set_terrain(Vector2i(1,0),TerrainType.Type.WALL)
	before = snapshot(session)
	check(session.play_mage_card(id,ally.id,Vector2i(-1,-1)).status == ActionReceipt.REJECTED and snapshot(session) == before,"wall rejection atomic")
	session.board.set_terrain(Vector2i(1,0),TerrainType.Type.FLOOR)
	var death := session._queue.submit(DeathCommand.new(host.id,DamageSource.new(&"test",0,host.cell)),session.context)
	check(death.status == ActionReceipt.APPLIED,"host death queue")
	session._check_outcome()
	check(session.phase == BattleTacticalSession.Phase.DEFEAT and ally.is_alive() and session.state.abilities.stage == "terminal","host death ends battle with living allies")
	session.close()
	session = arranged()
	host = session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var deaths: Array[int] = [host.id]
	deaths.append_array(session.living_ids(Faction.Type.ENEMY))
	var terminal := session._queue.submit(TerminalDeaths.new(deaths),session.context)
	session._check_outcome()
	check(terminal.status == ActionReceipt.APPLIED and session.living_ids(Faction.Type.ENEMY).is_empty() and session.phase == BattleTacticalSession.Phase.DEFEAT,"full queue finishes after host death; simultaneous last enemy is defeat")
	session.close()
	session = arranged()
	ally = session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[1])
	enemies = session.living_ids(Faction.Type.ENEMY)
	var first := session.board.get_unit_by_id(enemies[0])
	var second := session.board.get_unit_by_id(enemies[1])
	var second_hp := second.vitals.get_hp()
	first.vitals.hp_changed.connect(func(_old: float, _new: float) -> void: ally.move_points_left += 1.0)
	id = card_in_hand(session,"card.binding_thread")
	var fault := session.play_mage_card(id,ally.id,Vector2i(-1,-1))
	check(fault.status == ActionReceipt.FAULTED and session.state.deck.spent_ids.has(id) and session.state.abilities.mana == 0,"mutating callback retains paid faulted prefix")
	check(second.vitals.get_hp() == second_hp,"fault blocks later thread targets")
	session.close()
	print("HOST CARDS RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func death_before_mulligan() -> void:
	var hub := HeroHubState.create(443)
	hub.enable_mage_deck()
	check(hub.select_mage_host(hub.party[0]), "setup host selected")
	var started := ExpeditionTransitions.apply(hub, "start")
	check(started.is_ok(), "setup expedition starts")
	if not started.is_ok(): return
	var bundle := HeroHubBattleFactory.create(started.profile)
	check(not bundle.is_empty(), "setup session created")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var host := session.board.get_unit_by_id(session.state.card_effects.host_unit_id)
	var deck_before := session.state.deck.to_dict()
	var rng_before := session.context.get_rng().to_dict()
	check(not session.state.deck.mulligan_done and session.state.abilities.stage == "setup", "regression starts before mulligan")
	var receipt := session._queue.submit(DeathCommand.new(host.id, DamageSource.new(&"test", 0, host.cell)), session.context)
	session._check_outcome()
	check(receipt.status == ActionReceipt.APPLIED and session.phase == BattleTacticalSession.Phase.DEFEAT
		and session.state.abilities.stage == "terminal", "setup death applies and terminates after queue")
	check(session.state.deck.to_dict() == deck_before and session.context.get_rng().to_dict() == rng_before,
		"setup death neither confirms mulligan nor draws or consumes RNG")
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "terminal before mulligan captures: " + captured.reason)
	if captured.snapshot != null:
		var catalogue := ForecastDefinitionCopy.copy_catalog(session.state)
		var restored := captured.snapshot.instantiate(catalogue.definitions)
		check(restored.code == ItemSnapshotResult.Code.OK, "terminal before mulligan restores: " + restored.reason)
		if restored.state != null:
			var recaptured := ItemSimulationSnapshot.capture(restored.state, [])
			check(recaptured.snapshot != null and recaptured.snapshot.to_dict() == captured.snapshot.to_dict(),
				"terminal restore preserves complete snapshot without replay")
			ForecastSimulation.close(restored.state)
	var after := snapshot(session)
	check(session.confirm_mage_mulligan([]).status == ActionReceipt.REJECTED and not session.start_battle()
		and snapshot(session) == after, "terminal setup cannot reopen or confirm hand")
	session.close()
