extends SceneTree

var passed: int = 0
var failed: int = 0
var profile: HeroHubState
var actual_attacks: int = 0
var actual_moves: int = 0
var deck_mode: bool = false
var actual_cards: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL EXPEDITION PLAYTHROUGH: " + label)

func transition(action: String, args: Dictionary = {}) -> bool:
	var result := ExpeditionTransitions.apply(profile,action,args)
	check(result.is_ok(),action + " " + result.reason)
	if not result.is_ok(): return false
	profile = result.profile
	return true

func _run() -> void:
	deck_mode = OS.get_cmdline_user_args().has("--deck")
	_journey(false)
	_journey(true)
	_defeat()
	if deck_mode: check(actual_cards > 0,"real cards executed during connected journey")
	print(("MAGE DECK PLAYTHROUGH RESULTS:" if deck_mode else "EXPEDITION PLAYTHROUGH RESULTS:") + " %d passed, %d failed; attacks %d, moves %d, cards %d" % [passed,failed,actual_attacks,actual_moves,actual_cards])
	quit(0 if failed == 0 else 1)

func _journey(leave: bool) -> void:
	profile = HeroHubState.create(4280)
	if deck_mode: profile.enable_mage_deck()
	# Полная победа проверяет цикл на допустимом отряде ветеранов; баланс новичков не является утверждением этого runner.
	if not leave:
		for hero: HeroProgression in profile.heroes.values():
			hero.award_experience_tenths(45000); hero.apply_allocation([9,0,0,0])
		if deck_mode:
			# Для полного маршрута полигон с бронёй проходит допустимый смешанный отряд.
			check(profile.toggle_party(2) and profile.toggle_party(4), "veteran party includes mage against opening armor")
	transition("start")
	var battles: int = 0
	var path := "user://u14-playthrough-%d.save" % Time.get_ticks_usec()
	for unused: int in 30:
		if profile.phase == "hub": break
		check(HeroHubStore.write_run(path,profile).is_empty(),"save every phase")
		var loaded := HeroHubStore.read_run(path)
		check(loaded.run != null and loaded.run.to_dict() == profile.to_dict(),"reload same phase/plan")
		profile = loaded.run
		match profile.expedition.phase:
			"route":
				_prepare_party()
				var node: int = profile.expedition.available_nodes()[0]
				for candidate: int in profile.expedition.available_nodes():
					var kind: String = profile.expedition.plan.nodes[candidate - 1].kind
					if kind in ["rest","cache","battle"]: node = candidate
					if kind == "rest": break
				transition("choose",{"node":node})
			"service": transition("service",{"kind":"heal"})
			"camp_departure":
				if deck_mode:
					var active := profile.expedition.active_ids.duplicate()
					if active.size() > 10: active.pop_front()
					transition("deck_compose",{"active_ids":active})
				transition("leave" if leave else "continue")
			"reward":
				var reward: Array = profile.expedition.current_node().reward
				var choice := reward.find("spark")
				if choice < 0: choice = 0
				transition("reward",{"index":choice})
				if deck_mode:
					if not leave and profile.expedition != null:
						for id: int in profile.party:
							var quote := PostBattleRules.repair_quote(profile,id)
							if not quote.is_empty() and quote.affordable:
								check(profile.repair_after_battle(id), "pilot buys quoted armor repair")
					check(profile.dismiss_battle_report(),"reward Continue")
			"battle":
				var outcome := _battle(false)
				if outcome.is_empty(): break
				check(outcome.victory,"real victory room %d" % outcome.node_id)
				if not transition("outcome",outcome): break
				battles += 1
	check(profile.phase == "hub" and profile.expedition == null,"returns hub")
	check(profile.last_result.begins_with("Досрочное" if leave else "Поход завершён"),"correct successful exit " + profile.last_result)
	check(battles >= (2 if leave else 3) and profile.gold > 100 and profile.essence >= 20,"banks real rewards")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _prepare_party() -> void:
	for id: int in profile.party:
		var hero: HeroProgression = profile.heroes[id]
		if hero.available_points() > 0: transition("allocate",{"hero":id,"delta":[0,0,hero.available_points(),0]})
	var ids: Array[int] = []
	for item: Dictionary in profile.expedition.artifacts: ids.append(item.id)
	for id: int in ids:
		var item := profile.expedition.artifact(id)
		if item.is_empty() or item.hero_id != 0: continue
		var equipped := false
		for hero: int in profile.party:
			for slot: int in range(1,4):
				var result := ExpeditionTransitions.apply(profile,"artifact_equip",{"item":id,"hero":hero,"slot":slot})
				if result.is_ok(): profile = result.profile; equipped = true; break
			if equipped: break

func _battle(passive: bool) -> Dictionary:
	var starting_party: Array = []
	for id: int in profile.party:
		var hero: HeroProgression = profile.heroes[id]
		starting_party.append({"name":hero.name,"hp":hero.hp_current,"attributes":hero.attributes()})
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(),"real factory")
	if bundle.is_empty(): return {}
	var s: BattleCoreReactionsSession = bundle.session
	if deck_mode:
		s.mage_deployment_confirmed = true
		check(s.confirm_mage_mulligan([]).status == ActionReceipt.APPLIED,"explicit no-mulligan")
	check(s.start_battle(),"deployment completes")
	for unused: int in 2400:
		if s.phase in [BattleTacticalSession.Phase.VICTORY,BattleTacticalSession.Phase.DEFEAT,BattleTacticalSession.Phase.MUTUAL_DESTRUCTION,BattleTacticalSession.Phase.FAULTED]: break
		if s.phase == BattleTacticalSession.Phase.ENEMY_TURN: s.step_enemy(); continue
		if s.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if not passive:
			if deck_mode: _play_cards(s)
			for id: int in profile.party:
				if not s.can_player_act(): break
				var unit := s.board.get_unit_by_id(bundle.hero_units[id])
				if unit == null or not unit.is_alive() or not s.select_unit(unit.id): continue
				if unit.vitals.get_hp() < ActionHpExecutor._stat_value(unit,StatTypes.StatType.HP_MAX) - 8.0:
					if not deck_mode and s.mage_reason(&"mage.heal") == &"": s.cast_mage_spell(&"mage.heal",unit.id)
					var flask := s.healing_item()
					if flask != null and flask.get_charges_left() > 0: s.use_healing_item()
				for attempt: int in 4:
					if not s.can_player_act() or not unit.is_alive(): break
					var attacked := false
					if unit.action_resources.get_main_left() > 0:
						for target_id: int in s.living_ids(Faction.Type.ENEMY):
							var target := s.board.get_unit_by_id(target_id)
							var command := AttackCommand.new(unit.id,target_id,unit.cell,target.cell,s.actor_loadouts[unit.id].attack_id,s.context.get_revision())
							if command.validate(s.context) == &"":
								var receipt := s.attack_unit(target_id)
								if receipt.status == ActionReceipt.APPLIED: actual_attacks += 1; attacked = true
								break
					if attacked: continue
					var cell := _approach(s,unit)
					if cell.x < 0: break
					var movement := s.move_to(cell)
					if movement.status == ActionReceipt.APPLIED: actual_moves += 1
					else: break
		if s.can_player_act(): s.end_player_turn()
	check(s.phase != BattleTacticalSession.Phase.FAULTED and not s.context.is_faulted(),"real battle no fault " + (String(s.last_receipt.reason) if s.last_receipt != null else ""))
	var outcome := HeroHubBattleFactory.outcome(bundle)
	check(not outcome.is_empty(),"real terminal receipt")
	if not passive and not outcome.is_empty() and not outcome.victory:
		printerr("JOURNEY DIAGNOSTIC: node %s party %s outcome %s; %s" % [outcome.node_id, starting_party, outcome.hp, s.flow_log.slice(-8)])
	s.close()
	return outcome

func _approach(s: BattleCoreReactionsSession, actor: UnitState) -> Vector2i:
	var best := Vector2i(-1,-1); var score := _distance(s,actor.cell)
	for cell: Vector2i in s.reachable_cells():
		var path := s.path_to(cell)
		if path.size() < 2: continue
		# Полигон содержит опасности: пилот не сокращает путь через шипы, огонь и провалы.
		var safe := true
		for step: Vector2i in path.slice(1):
			if s.board.is_lethal(step) or not s.state.environment.fire_at(step).is_empty(): safe = false; break
		if not safe: continue
		var value := _distance(s,cell)
		if value < score: score = value; best = cell
	return best

func _distance(s: BattleCoreReactionsSession, cell: Vector2i) -> int:
	var score: int = 1000
	for id: int in s.living_ids(Faction.Type.ENEMY):
		var delta := s.board.get_unit_by_id(id).cell - cell
		score = mini(score,absi(delta.x) + absi(delta.y))
	return score

func _defeat() -> void:
	profile = HeroHubState.create(4280)
	if deck_mode: profile.enable_mage_deck()
	transition("start")
	if not deck_mode: transition("choose",{"node":1})
	var outcome := _battle(true)
	if outcome.is_empty(): return
	check(not outcome.victory,"passive party reaches actual defeat")
	transition("outcome",outcome)
	check(profile.phase == "hub" and profile.party.is_empty() and profile.gold == 100 and profile.essence == 0,"defeat settles loss")

func _play_cards(s: BattleCoreReactionsSession) -> void:
	var hand := s.state.deck.hand_ids.duplicate()
	for id: int in hand:
		if not s.can_player_act() or s.mage_card_reason(id) != &"": continue
		var type: String = s.state.deck.card(id).type_id
		var target_ids := s.living_ids(Faction.Type.ENEMY if type == "card.fire" else Faction.Type.PLAYER)
		if type not in ["card.fire","card.heal","card.shield","card.wet"]: continue
		if type == "card.heal":
			# Лечение первого полного бойца впустую оставляло раненого без помощи перед финалом.
			target_ids.sort_custom(func(a: int, b: int) -> bool: return _missing_hp(s,a) > _missing_hp(s,b))
		for target: int in target_ids:
			if type == "card.heal" and _missing_hp(s,target) <= 0.0: continue
			if type == "card.wet" and s.board.get_unit_by_id(target).elemental.burning_stacks == 0: continue
			var result := s.play_mage_card(id,target,Vector2i(-1,-1))
			if result.status == ActionReceipt.APPLIED: actual_cards += 1; break

func _missing_hp(s: BattleCoreReactionsSession, id: int) -> float:
	var unit := s.board.get_unit_by_id(id)
	return ActionHpExecutor._stat_value(unit,StatTypes.StatType.HP_MAX) - unit.vitals.get_hp()
