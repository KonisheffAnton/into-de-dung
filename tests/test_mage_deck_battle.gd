extends SceneTree

var passed: int = 0
var failed: int = 0

class MutatingSink extends ActionEventSink:
	var deck: BattleDeckState
	func publish(_event: Dictionary) -> void: deck.replaced_serial += 1

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL DECK BATTLE: " + label)

func snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(session.state,[])
	check(captured.code == ItemSnapshotResult.Code.OK,"capture " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	var values: Array = []
	for card: MageCardDefinition in MageCardCatalog.all(): values.append({"id":values.size()+1,"type_id":card.id,"origin":"base" if values.size() < 10 else "found"})
	session.state.deck = BattleDeckState.create(values,88)
	session.state.card_effects = BattleCardEffectState.new()
	for unit: UnitState in session.units:
		session.state.card_effects.ordinary_attacks.append({"unit_id":unit.id,"attack_id":"demo_strike"})
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX,100.0); unit.vitals.set_hp(80.0)
		unit.control.stunned_turns = 0; unit.control.entangled_turns = 0; unit.elemental.frozen_turns = 0
	session.state.abilities = BattleAbilityState.create_deck(session.state.abilities.catalog,Faction.Type.ENEMY)
	var confirm := session._queue.submit(ConfirmMageMulliganCommand.new([],session.context.get_revision()),session.context)
	check(confirm.status == ActionReceipt.APPLIED,"mulligan " + String(confirm.reason))
	var start := session._queue.submit(AbilityBoundaryCommand.new(&"start",1,0,session.context.get_revision()),session.context)
	check(start.status == ActionReceipt.APPLIED,"start " + String(start.reason))
	session._enemy_index = session._enemy_ids.size(); session.step_enemy()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN,"player first window")
	session.selected_id = session.living_ids(Faction.Type.PLAYER)[0]
	return session

func card_in_hand(session: BattleCoreReactionsSession, type_id: String) -> int:
	var deck := session.state.deck
	for card: Dictionary in deck.cards:
		if card.type_id != type_id: continue
		if not deck.hand_ids.has(card.id):
			var index := deck.draw_ids.find(card.id)
			var old: int = deck.hand_ids[0]; deck.hand_ids[0] = card.id; deck.draw_ids[index] = old
		return card.id
	return 0

func safe_cell(session: BattleCoreReactionsSession, owner: UnitState) -> Vector2i:
	for delta: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var cell := owner.cell+delta
		if UseSummoningItemCommand.valid_cell(session.board,owner.cell,cell) and session.state.environment.fire_at(cell).is_empty(): return cell
	return Vector2i(-1,-1)

func run() -> void:
	for card: MageCardDefinition in MageCardCatalog.all():
		var session := fixture()
		if session.phase != BattleTacticalSession.Phase.PLAYER_TURN: session.close(); continue
		var id := card_in_hand(session,card.id)
		var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0] if card.target_policy in ["enemy_unit","living_unit"] else session.selected_id)
		var cell := Vector2i(-1,-1)
		if card.target_policy in ["valid_cell","corpse_cell"]:
			cell = safe_cell(session,session.selected_unit())
			if card.id == "card.raise":
				var fallen := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
				check(session.board.move_unit(fallen,cell),"corpse placement")
				check(session._queue.submit(DeathCommand.new(fallen.id,DamageSource.new(&"test",0,cell)),session.context).status == ActionReceipt.APPLIED,"corpse creation")
		var before := snapshot(session)
		var rng := session.context.get_rng().to_dict(); var counters := session.context.simulation_counters(); var admission := SummonAdmission.values(session.context)
		var target_id: int = 0 if card.target_policy in ["valid_cell","corpse_cell"] else target.id
		var command := PlayMageCardCommand.new(id,target_id,cell,session.context.get_revision())
		var preview := ForecastSimulation.run_prepared(ForecastSimulation.prepare(session.context,session._queue,command))
		check(preview.status == ActionReceipt.APPLIED,card.id + " preview " + String(preview.reason))
		var forecast_worker := ActionForecastWorker.new()
		forecast_worker.start(ForecastSimulation.prepare(session.context,session._queue,command))
		var background: ForecastSimulation = forecast_worker.take_finished()
		while background == null:
			await process_frame; background = forecast_worker.take_finished()
		check(background.status == preview.status and background.snapshot_after == preview.snapshot_after and background.events == preview.events and background.steps == preview.steps and background.rng_after == preview.rng_after and background.counters_after == preview.counters_after and background.admission_after == preview.admission_after,"forecast worker exact parity " + card.id)
		check(snapshot(session) == before and rng == session.context.get_rng().to_dict() and counters == session.context.simulation_counters() and admission == SummonAdmission.values(session.context),"hover isolated " + card.id)
		var live_worker := BattleExecutionWorker.new()
		var transferred := live_worker.start(session,&"play_mage_card",[id,target_id,cell])
		check(transferred,"detached execution worker " + card.id)
		var receipt: ActionReceipt = live_worker.take_finished(true).result if transferred else session._queue.submit(command,session.context)
		check(receipt.status == ActionReceipt.APPLIED,card.id + " live " + String(receipt.reason))
		check(preview.events == receipt.get_events() and preview.steps == receipt.get_steps() and preview.snapshot_after == snapshot(session) and preview.rng_after == session.context.get_rng().to_dict() and preview.counters_after == session.context.simulation_counters() and preview.admission_after == SummonAdmission.values(session.context),"full parity " + card.id)
		check(session.state.deck.spent_ids.has(id) and session.state.abilities.mana == 2-card.mana_cost,"one card and mana cost " + card.id)
		var saved := snapshot(session)
		check(session._queue.submit(PlayMageCardCommand.new(id,target.id,cell,session.context.get_revision()),session.context).status == ActionReceipt.REJECTED and snapshot(session) == saved,"repeat refused " + card.id)
		session.close()
	var hub := HeroHubState.create(997); hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub,"start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(),"production factory schema10")
	if not bundle.is_empty():
		check(snapshot(bundle.session).schema_version == ItemSimulationSnapshot.SCHEMA_VERSION,"production snapshot11")
		check(BattleExecutionWorker.can_transfer(bundle.session),"detached worker capability")
		bundle.session.close()
	var invalid_session := fixture()
	var invalid := snapshot(invalid_session); invalid.abilities.schema_version = 1
	check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK,"hybrid rejected")
	invalid = snapshot(invalid_session); invalid["artifacts"] = {}
	check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK,"artifact hybrid rejected")
	invalid = snapshot(invalid_session); invalid.board_snapshot.board.units = [null]
	check(ItemSimulationSnapshot.from_dict(invalid).code != ItemSnapshotResult.Code.OK,"malformed board rejected before card references")
	invalid_session.close()
	_invalid_effect_owners()
	_invalid_hero_attack_binding()
	_buff_and_faults()
	_helpers_and_callbacks()
	_death_attack()
	print("MAGE DECK BATTLE RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _apply_imbue(session: BattleCoreReactionsSession, unit_id: int) -> Dictionary:
	var card_id := card_in_hand(session,"card.fire_imbue")
	var receipt := session.play_mage_card(card_id,unit_id,Vector2i(-1,-1))
	check(receipt.status == ActionReceipt.APPLIED,"owner regression fixture imbue " + String(receipt.reason))
	return session.state.card_effects.fire_imbues[0].duplicate(true) if not session.state.card_effects.fire_imbues.is_empty() else {}

func _invalid_effect_owners() -> void:
	for owner_kind: String in ["enemy","dead","pending"]:
		var session := fixture()
		var actor := session.selected_unit()
		var effect := _apply_imbue(session,actor.id)
		var owner_id: int = 0
		if owner_kind == "enemy":
			owner_id = session.living_ids(Faction.Type.ENEMY)[0]
		elif owner_kind == "dead":
			for ally_id: int in session.living_ids(Faction.Type.PLAYER):
				if ally_id != actor.id: owner_id = ally_id; break
			var corpse := session.board.get_unit_by_id(owner_id)
			var death := session._queue.submit(DeathCommand.new(owner_id,DamageSource.new(&"test",0,corpse.cell)),session.context)
			check(death.status == ActionReceipt.APPLIED,"dead owner regression setup")
		else:
			var summon_id := card_in_hand(session,"card.summon")
			var cell := safe_cell(session,session.units[0])
			var summon := session.play_mage_card(summon_id,0,cell)
			check(summon.status == ActionReceipt.APPLIED,"pending owner regression setup")
			var helper := session.board.occupant_at(cell)
			owner_id = helper.id if helper != null else 0
			check(helper != null and session.state.is_summon_pending(owner_id),"pending owner exists")
		var valid_data := snapshot(session)
		check(ItemSimulationSnapshot.from_dict(valid_data).code == ItemSnapshotResult.Code.OK,"post-imbue owner snapshot baseline " + owner_kind)
		var copied: Dictionary = valid_data.duplicate(true)
		if not copied.card_effects.fire_imbues.is_empty(): copied.card_effects.fire_imbues[0].unit_id = owner_id
		check(ItemSimulationSnapshot.from_dict(copied).code != ItemSnapshotResult.Code.OK,"snapshot rejects " + owner_kind + " imbue owner")
		if not effect.is_empty():
			effect.unit_id = owner_id
			session.state.card_effects.fire_imbues[0] = effect
		var command_id := card_in_hand(session,"card.heal")
		var mana_before := session.state.abilities.mana
		var deck_before := session.state.deck.to_dict()
		check(ItemSimulationSnapshot.capture(session.state,[]).code != ItemSnapshotResult.Code.OK,"capture rejects " + owner_kind + " imbue owner")
		var command := PlayMageCardCommand.new(command_id,actor.id,Vector2i(-1,-1),session.context.get_revision())
		var receipt := session._queue.submit(command,session.context)
		check(receipt.status == ActionReceipt.REJECTED and String(receipt.reason).begins_with("deck/") and session.state.deck.to_dict() == deck_before and session.state.abilities.mana == mana_before,"command rejects " + owner_kind + " imbue owner before payment: " + String(receipt.reason))
		session.close()

func _invalid_hero_attack_binding() -> void:
	var hub := HeroHubState.create(1997)
	hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub,"start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(),"hero binding production fixture")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var hero_id: int = bundle.hero_units.values()[0]
	var binding: Dictionary = {}
	var other_attack_id: String = ""
	for candidate: Dictionary in session.state.card_effects.ordinary_attacks:
		if candidate.unit_id == hero_id: binding = candidate
		elif other_attack_id.is_empty(): other_attack_id = String(candidate.attack_id)
	check(not binding.is_empty() and String(binding.attack_id).begins_with("hero_attack_"),"production hero default binding")
	var valid_data := snapshot(session)
	check(ItemSimulationSnapshot.from_dict(valid_data).code == ItemSnapshotResult.Code.OK,"hero default snapshot baseline")
	if not binding.is_empty(): binding.attack_id = "entangling_strike"
	var tampered: Dictionary = valid_data.duplicate(true)
	for row: Dictionary in tampered.card_effects.ordinary_attacks:
		if row.unit_id == hero_id: row.attack_id = "entangling_strike"
	check(ItemSimulationSnapshot.from_dict(tampered).code != ItemSnapshotResult.Code.OK,"snapshot rejects substituted hero ordinary attack")
	var card_id := card_in_hand(session,"card.heal")
	var mana_before := session.state.abilities.mana
	var deck_before := session.state.deck.to_dict()
	check(ItemSimulationSnapshot.capture(session.state,[]).code != ItemSnapshotResult.Code.OK,"capture rejects substituted hero ordinary attack")
	var receipt := session._queue.submit(PlayMageCardCommand.new(card_id,hero_id,Vector2i(-1,-1),session.context.get_revision()),session.context)
	check(receipt.status == ActionReceipt.REJECTED and String(receipt.reason).begins_with("deck/") and session.state.deck.to_dict() == deck_before and session.state.abilities.mana == mana_before,"command rejects substituted hero ordinary attack before payment: " + String(receipt.reason))
	if not other_attack_id.is_empty():
		if not binding.is_empty(): binding.attack_id = other_attack_id
		var other_tampered: Dictionary = valid_data.duplicate(true)
		for row: Dictionary in other_tampered.card_effects.ordinary_attacks:
			if row.unit_id == hero_id: row.attack_id = other_attack_id
		check(ItemSimulationSnapshot.from_dict(other_tampered).code != ItemSnapshotResult.Code.OK,"snapshot rejects another hero personal ordinary attack")
		check(other_attack_id.begins_with("hero_attack_"),"substituted attack is another personal hero default")
		card_id = card_in_hand(session,"card.heal")
		mana_before = session.state.abilities.mana
		deck_before = session.state.deck.to_dict()
		check(ItemSimulationSnapshot.capture(session.state,[]).code != ItemSnapshotResult.Code.OK,"capture rejects another hero personal ordinary attack")
		check(not BattleExecutionWorker.can_transfer(session),"worker admission rejects another hero personal ordinary attack")
		receipt = session._queue.submit(PlayMageCardCommand.new(card_id,hero_id,Vector2i(-1,-1),session.context.get_revision()),session.context)
		check(receipt.status == ActionReceipt.REJECTED and String(receipt.reason).begins_with("deck/") and session.state.deck.to_dict() == deck_before and session.state.abilities.mana == mana_before,"command rejects another hero personal ordinary attack before payment: " + String(receipt.reason))
	else:
		check(false,"second production hero has a personal ordinary attack")
	session.close()

func _buff_and_faults() -> void:
	var session := fixture()
	var actor := session.selected_unit()
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	var cell := safe_cell(session,actor)
	check(session.board.move_unit(target,cell),"attack fixture adjacent")
	var card_id := card_in_hand(session,"card.fire_imbue")
	var played := session._queue.submit(PlayMageCardCommand.new(card_id,actor.id,Vector2i(-1,-1),session.context.get_revision()),session.context)
	check(played.status == ActionReceipt.APPLIED and session.state.card_effects.fire_imbues.size() == 1,"imbue active immediately")
	var attack := AttackCommand.new(actor.id,target.id,actor.cell,target.cell,&"demo_strike",session.context.get_revision())
	var prepared := attack._prepare(session.context)
	check(prepared.get("reason",&"") == &"","buff attack prepare")
	if prepared.has("request"):
		check(prepared.request.armor_components.any(func(part: Dictionary) -> bool: return part.get("source") == "card:fire_imbue"),"fire component inside single hit")
	var before := snapshot(session)
	var preview := ForecastSimulation.run_prepared(ForecastSimulation.prepare(session.context,session._queue,attack))
	check(snapshot(session) == before,"imbued attack preview isolated")
	var live := session._queue.submit(attack,session.context)
	check(live.status == ActionReceipt.APPLIED and preview.events == live.get_events() and preview.steps == live.get_steps() and preview.snapshot_after == snapshot(session),"imbued normal attack P07 parity " + String(live.reason))
	for serial: int in range(1,4):
		var turn := TurnForecast.run_prepared(TurnForecast.prepare(session))
		session.end_player_turn()
		check(turn.status == ActionReceipt.APPLIED and turn.snapshot_after == snapshot(session),"end forecast parity " + str(serial))
		check(session.state.card_effects.fire_imbues.is_empty() == (serial == 3),"expires at end s+2 " + str(serial))
		if serial < 3:
			session._enemy_index = session._enemy_ids.size(); session.step_enemy()
	session.close()
	var faulted := fixture()
	var fire_id := card_in_hand(faulted,"card.fire")
	var victim := faulted.board.get_unit_by_id(faulted.living_ids(Faction.Type.ENEMY)[0])
	var callback := func(_before: float,_after: float) -> void: faulted.state.deck.draw_rng._draws += 1
	victim.vitals.hp_changed.connect(callback)
	check(not BattleExecutionWorker.can_transfer(faulted),"foreign callback synchronous fallback")
	var fault := faulted._queue.submit(PlayMageCardCommand.new(fire_id,victim.id,Vector2i(-1,-1),faulted.context.get_revision()),faulted.context)
	check(fault.status == ActionReceipt.FAULTED and faulted.state.deck.spent_ids.has(fire_id) and faulted.state.abilities.mana == 0,"fault keeps paid prefix")
	check(fault.get_events().any(func(event: Dictionary) -> bool: return event.kind == &"mage_card_played") and fault.get_events().any(func(event: Dictionary) -> bool: return event.kind == &"damaged"),"fault receipts keep actual payment and HP")
	victim.vitals.hp_changed.disconnect(callback); faulted.close()

func _helpers_and_callbacks() -> void:
	var session := fixture()
	var summon_id := card_in_hand(session,"card.summon")
	var cell := safe_cell(session,session.selected_unit())
	var summoned := session.play_mage_card(summon_id,0,cell)
	check(summoned.status == ActionReceipt.APPLIED,"helper summon")
	var helper := session.board.occupant_at(cell)
	var imbue_id := card_in_hand(session,"card.fire_imbue")
	var original := snapshot(session)
	check(helper != null and session.play_mage_card(imbue_id,helper.id,Vector2i(-1,-1)).status == ActionReceipt.REJECTED and snapshot(session) == original,"pending helper cannot receive buff or spend card")
	session.end_player_turn(); session._enemy_index = session._enemy_ids.size(); session.step_enemy()
	check(helper != null and not session.state.is_summon_pending(helper.id),"helper activates next player turn")
	if helper != null:
		check(session.play_mage_card(imbue_id,helper.id,Vector2i(-1,-1)).status == ActionReceipt.APPLIED and MageDeckRules.ordinary_bonus(session.state,helper.id,&"demo_strike"),"active helper ordinary binding and buff")
		check(not MageDeckRules.ordinary_bonus(session.state,helper.id,&"entangle_strike"),"ability does not inherit ordinary buff")
		var death := session._queue.submit(DeathCommand.new(helper.id,DamageSource.new(&"test",0,helper.cell)),session.context)
		check(death.status == ActionReceipt.APPLIED and session.state.card_effects.fire_imbues.is_empty(),"death cleans buff within executed root")
	session.close()
	for type_id: String in ["card.heal","card.shield"]:
		var faulted := fixture()
		var id := card_in_hand(faulted,type_id)
		var target := faulted.selected_unit()
		var hp_callback := func(_before: float,_after: float) -> void: faulted.state.card_effects.ordinary_attacks[0].attack_id = "wrong"
		var shield_callback := func(_kind: StringName,_item: int,_before: int,_after: int) -> void: faulted.state.deck.draw_rng = CombatRng.new(42)
		if type_id == "card.heal": target.vitals.hp_changed.connect(hp_callback)
		else: target.armor.changed.connect(shield_callback)
		var outcome := faulted.play_mage_card(id,target.id,Vector2i(-1,-1))
		check(outcome.status == ActionReceipt.FAULTED and faulted.state.deck.spent_ids.has(id) and faulted.state.abilities.mana == 1,"foreign callback guard paid prefix " + type_id)
		if type_id == "card.heal": target.vitals.hp_changed.disconnect(hp_callback)
		else: target.armor.changed.disconnect(shield_callback)
		faulted.close()
	var sink_session := fixture()
	var sink := MutatingSink.new(); sink.deck = sink_session.state.deck; sink_session.context._sink = sink
	var id := card_in_hand(sink_session,"card.fire_imbue")
	check(sink_session.play_mage_card(id,sink_session.selected_id,Vector2i(-1,-1)).status == ActionReceipt.FAULTED,"publication cannot mutate deck unnoticed")
	sink_session.close()
	var exhausted := fixture()
	var fire_id := card_in_hand(exhausted,"card.fire")
	exhausted.context._next_event_seq = ActionContext.MAX_ID - 1
	var saved := snapshot(exhausted)
	check(exhausted.play_mage_card(fire_id,exhausted.living_ids(Faction.Type.ENEMY)[0],Vector2i(-1,-1)).status == ActionReceipt.REJECTED and snapshot(exhausted) == saved,"sequence overflow before either payment")
	exhausted.close()

func _death_attack() -> void:
	var session := fixture()
	var victim := session.selected_unit()
	var attacker := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	check(session.board.move_unit(attacker,safe_cell(session,victim)),"lethal enemy attack position")
	var id := card_in_hand(session,"card.fire_imbue")
	check(session.play_mage_card(id,victim.id,Vector2i(-1,-1)).status == ActionReceipt.APPLIED,"buff before lethal P07 attack")
	attacker.stats.set_base_value(StatTypes.StatType.STRENGTH,1000.0)
	var command := AttackCommand.new(attacker.id,victim.id,attacker.cell,victim.cell,&"demo_strike",session.context.get_revision())
	var preview := ForecastSimulation.run_prepared(ForecastSimulation.prepare(session.context,session._queue,command))
	var receipt := session._queue.submit(command,session.context)
	check(receipt.status == ActionReceipt.APPLIED and not victim.is_alive() and session.state.card_effects.fire_imbues.is_empty(),"lethal attack removes target buff without invalidating remaining P07 prefix " + String(receipt.reason))
	check(preview.status == receipt.status and preview.events == receipt.get_events() and preview.steps == receipt.get_steps() and preview.snapshot_after == snapshot(session),"lethal buff cleanup full parity")
	session.close()
