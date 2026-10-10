extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL BLEEDING: " + label)

func _run() -> void:
	_test_gate()
	_test_duration()
	_test_stacked_duration()
	_test_spatial()
	_test_faults()
	_test_turns()
	_test_edge_refresh_and_boundary()
	print("BLEEDING RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func fixture() -> BattleBleedingSession:
	var s := BattleBleedingSession.new()
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x,y),0)
			s.board.set_terrain(Vector2i(x,y),TerrainType.Type.FLOOR)
	s.board.move_unit(s.units[0], Vector2i(2,3))
	s.board.move_unit(s.units[1], Vector2i(3,3))
	s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
	return s

func fill(s: BattleBleedingSession, unit: UnitState, full: bool) -> void:
	for item: ItemInstance in s.state.get_owner(unit.id)._items.values():
		item.armor_remaining = item.get_definition().armor_max if full else 0

func no_heal(s: BattleBleedingSession) -> void:
	var target := s.units[1]
	for item: ItemInstance in s.state.get_owner(target.id)._items.values():
		if item.get_definition().id == &"demo_guard_amulet": s.state.get_inventory(target.id).remove_item(item)

func kinds(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for event: Dictionary in events: out.append(event["kind"])
	return out

func events_of_kind(events: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		if event["kind"] == kind: out.append(event)
	return out

func parity(s: BattleBleedingSession, label: String) -> AttackForecast:
	var before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var f := s.preview_attack(s.units[1].id)
	check(f.status == &"APPLIED", label + " preview " + String(f.reason))
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, label + " isolation")
	var repeat := s.preview_attack(s.units[1].id)
	check(repeat.events == f.events and repeat.steps == f.steps and repeat.snapshot_after == f.snapshot_after, label + " deterministic")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == f.status and receipt.reason == f.reason and receipt.get_events() == f.events and receipt.get_steps() == f.steps, label + " receipt parity")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == f.snapshot_after, label + " snapshot parity")
	check(s.context.get_rng().to_dict() == f.rng_after and s.context.simulation_counters() == f.counters_after, label + " RNG/counters parity")
	return f

func _test_gate() -> void:
	for mode: String in ["split", "armor_only", "overflow", "fire_only", "net_zero", "net_heal", "bypass", "immune", "bypass_immune", "no_source", "lethal"]:
		var s := fixture()
		var actor := s.units[0]; var target := s.units[1]
		if mode in ["armor_only", "bypass", "bypass_immune"]: fill(s,target,true)
		if mode in ["overflow", "net_zero", "net_heal", "lethal"]: fill(s,target,false)
		if mode in ["net_zero", "net_heal"]:
			target.vitals.set_hp(16.0)
			target.armor.natural["fire"] = 11000
			target.armor.perks = [{"id":"lim","type":"fire","branch":"both","bonus":3500}]
			s.context._attack_rules._definitions[0].damage_components[0]["numerator"] = 100 if mode == "net_zero" else 200
		if mode == "fire_only":
			actor.stats.set_base_value(StatTypes.StatType.STRENGTH,0.0)
			actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE,0.0)
		if mode in ["bypass", "bypass_immune"]: s.rune_selected = true
		if mode in ["immune", "bypass_immune"]: target.bleeding.immune = true
		if mode == "no_source": s.context._attack_rules._definitions[0].bleeding_policy = &""
		if mode == "lethal": target.vitals.set_hp(1.0)
		var f := parity(s,mode)
		var expected := mode in ["split", "overflow", "net_zero", "net_heal", "bypass"]
		check(target.bleeding.ticks_left == (2 if expected else 0), mode + " admission")
		check(actor.action_resources.get_main_left() == 0, mode + " cost one main")
		if expected:
			check(target.bleeding.source["instigator_unit_id"] == actor.id and target.bleeding.hit_id == f.events.filter(func(e: Dictionary) -> bool: return e["kind"] == &"hit_resolved")[0]["hit_id"], mode + " direct source")
		if mode in ["net_zero", "net_heal"]:
			check(target.vitals.get_hp() == (16.0 if mode == "net_zero" else 26.0) and &"damaged" not in kinds(f.events), mode + " gross gate independent of net HP")
		if mode == "split":
			var order := kinds(f.events)
			check(order.find(&"bleeding_changed") < order.find(&"healed"), "application before item healing")
		if mode == "lethal": check(not target.is_alive() and s.board.occupant_at(target.cell) == null and kinds(f.events).count(&"died") == 1, "direct death single event no state")
		s.close()

func turn(s: BattleBleedingSession, faction: Faction.Type) -> ActionReceipt:
	return s._queue.submit(BleedingTurnCommand.new(faction,s.context.get_revision()),s.context)

func turn_parity(s: BattleBleedingSession, faction: Faction.Type) -> ActionReceipt:
	var capture := ItemSimulationSnapshot.capture(s.state,[])
	var before := capture.snapshot.to_dict()
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK,"active state restores for turn")
	var rng_before := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var clone_context := s.context.copy_for_simulation(restored.state,s.context.get_rng().clone())
	var predicted := s._queue.copy_for_simulation().submit(BleedingTurnCommand.new(faction,clone_context.get_revision()),clone_context)
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before and s.context.get_rng().to_dict() == rng_before and s.context.simulation_counters() == counters,"tick simulation live isolation")
	var receipt := turn(s,faction)
	check(receipt.status == predicted.status and receipt.get_events() == predicted.get_events() and receipt.get_steps() == predicted.get_steps(),"tick receipt parity")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == ItemSimulationSnapshot.capture(restored.state,[]).snapshot.to_dict(),"tick snapshot parity")
	check(s.context.get_rng().to_dict() == clone_context.get_rng().to_dict() and s.context.simulation_counters() == clone_context.simulation_counters(),"tick counters/RNG parity")
	AttackForecast._close(restored.state)
	return receipt

func seed_status(actor: UnitState, target: UnitState) -> void:
	target.bleeding.ticks_left = 2
	target.bleeding.source = DamageSource.new(&"attack",0,actor.cell,actor.id,actor.id).to_dict()
	target.bleeding.hit_id = "1:%d" % target.id

func _test_duration() -> void:
	var s := fixture(); var target := s.units[1]
	no_heal(s)
	parity(s,"duration apply")
	var rng := s.context.get_rng().to_dict()
	var hp := target.vitals.get_hp()
	var armor := ArmorRuntime.capture(s.state.get_owner(target.id))
	var r := turn(s,Faction.Type.PLAYER)
	check(r.status == &"APPLIED" and target.bleeding.ticks_left == 2 and target.vitals.get_hp() == hp,"other team no tick")
	target.guard_stance = true
	r = turn_parity(s,Faction.Type.ENEMY)
	check(r.status == &"APPLIED" and target.bleeding.ticks_left == 1 and target.vitals.get_hp() == hp - 4,"first tick bypass armor and stance")
	check(ArmorRuntime.capture(s.state.get_owner(target.id)) == armor and s.context.get_rng().to_dict() == rng,"tick no armor/RNG")
	check(kinds(r.get_events()).count(&"hit_resolved") == 1 and kinds(r.get_events()).count(&"bleeding_changed") == 1,"tick not recursive")
	s.units[0].try_refill_turn_resources()
	parity(s,"refresh")
	check(target.bleeding.ticks_left == 3,"repeat adds two to one remaining tick")
	target.bleeding.immune = true
	target.vitals.set_hp(32.0)
	fill(s,target,true)
	s.units[0].try_refill_turn_resources()
	var preserved := target.bleeding.to_dict()
	parity(s,"immune preserves old")
	check(target.bleeding.to_dict() == preserved,"failed application does not clear or refresh old source")
	target.armor.natural["physical"] = 5000
	target.vitals.set_hp(16.0)
	hp = target.vitals.get_hp()
	r = turn(s,Faction.Type.ENEMY)
	check(r.status == &"APPLIED" and target.vitals.get_hp() == hp - 2 and target.bleeding.ticks_left == 2,"natural defense, immunity does not cure existing")
	r = turn(s,Faction.Type.ENEMY)
	check(r.status == &"APPLIED" and target.bleeding.ticks_left == 1 and target.vitals.get_hp() == hp - 4,"stack keeps third remaining tick")
	r = turn(s,Faction.Type.ENEMY)
	check(r.status == &"APPLIED" and target.bleeding.ticks_left == 0 and target.bleeding.source.is_empty() and target.bleeding.hit_id.is_empty() and target.vitals.get_hp() == hp - 6,"full accumulated duration expires")
	hp = target.vitals.get_hp()
	r = turn(s,Faction.Type.ENEMY)
	check(r.status == &"APPLIED" and r.get_events().is_empty() and target.vitals.get_hp() == hp,"expired no further tick")
	s.close()
	for defense: int in [0,-2500,11000]:
		s = fixture(); target = s.units[1]; no_heal(s)
		seed_status(s.units[0],target)
		target.armor.natural["physical"] = defense
		if defense == 11000: target.armor.perks = [{"id":"lim","type":"physical","branch":"natural","bonus":3500}]
		target.vitals.set_hp(2.0 if defense == 0 else 16.0)
		r = turn(s,Faction.Type.ENEMY)
		check(r.status == &"APPLIED", "tick defense valid %d" % defense)
		if defense == 0: check(not target.is_alive() and target.bleeding.ticks_left == 1 and kinds(r.get_events()).count(&"died") == 1 and s.board.occupant_at(target.cell) == null,"tick death retains status and frees cell")
		if defense == -2500: check(target.vitals.get_hp() == 11.0,"tick vulnerability")
		if defense == 11000: check(target.vitals.get_hp() == 16.0,"tick healing fractional floor no spurious damage")
		s.close()

func _test_spatial() -> void:
	for mode: String in ["wall", "collision_gate", "collision_order", "fall", "void"]:
		var s := fixture(); var target := s.units[1]; var actor := s.units[0]
		actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,5.0)
		var destination := target.cell + Vector2i.RIGHT
		if mode == "wall": s.board.set_terrain(destination,TerrainType.Type.WALL)
		if mode.begins_with("collision"):
			var blocker := s.units[3]
			s.board.move_unit(blocker,destination)
			fill(s,blocker,false); blocker.vitals.set_hp(10.0)
			if mode == "collision_gate":
				fill(s,target,false)
				# Direct при A=50 только броня; collision при A=30 уже пробивает HP.
				for item: ItemInstance in s.state.get_owner(target.id)._items.values():
					if item.get_definition().armor_max == 60: item.armor_remaining = 50
			else:
				s.board.set_height_steps(actor.cell,2); s.board.set_height_steps(target.cell,2)
		if mode == "fall":
			s.board.set_height_steps(actor.cell,2); s.board.set_height_steps(target.cell,2)
		if mode == "void": s.board.set_terrain(destination,TerrainType.Type.VOID)
		var f := parity(s,mode)
		var order := kinds(f.events)
		if mode == "void": check(not target.is_alive() and target.bleeding.ticks_left == 0,"mandatory spatial death suppresses bleeding")
		elif mode == "collision_gate":
			check(target.bleeding.ticks_left == 0 and s.units[3].bleeding.ticks_left == 0,"collision never provides original gate or secondary application")
			check(target.vitals.get_hp() < 32.0,"collision actually deals HP after armor-only original")
		else:
			check(target.bleeding.ticks_left == 2,"surviving spatial target receives status")
			check(order.find(&"bleeding_changed") > order.rfind(&"hit_resolved"),"all spatial hit results before application " + mode)
			check(order.find(&"healed") > order.find(&"bleeding_changed"),"all optional healing after application " + mode)
		s.close()

func _test_stacked_duration() -> void:
	var s := fixture()
	var actor := s.units[0]
	var target := s.units[1]
	no_heal(s)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX,128.0)
	target.vitals.set_hp(128.0)
	s.rune_selected = true
	for expected: int in [2,4,6]:
		fill(s,target,true)
		actor.try_refill_turn_resources()
		var forecast := parity(s,"successive application %d" % expected)
		check(target.bleeding.ticks_left == expected,"successive applications add two")
		var changed: Dictionary = events_of_kind(forecast.events,&"bleeding_changed")[0]
		check(changed["after"]["ticks_left"] == expected,"event reports accumulated duration")
		if expected > 2:
			# Проверяем draft, а не журнал с полями, добавленными очередью.
			var draft := {"kind": &"bleeding_changed", "actor_unit_id": actor.id, "target_unit_id": target.id, "reason": &"refreshed", "before": changed["before"], "after": changed["after"].duplicate(true)}
			check(ActionEventValidator._valid_bleeding_draft(draft),"queue accepts exact accumulated duration")
			draft["after"]["ticks_left"] = 2
			check(not ActionEventValidator._valid_bleeding_draft(draft),"queue rejects old refresh duration")
	var hp := target.vitals.get_hp()
	var rng := s.context.get_rng().to_dict()
	for elapsed: int in range(1,7):
		var receipt := turn_parity(s,Faction.Type.ENEMY)
		check(receipt.status == &"APPLIED" and target.bleeding.ticks_left == 6 - elapsed and target.vitals.get_hp() == hp - 4 * elapsed,"accumulated tick %d keeps fixed damage" % elapsed)
	check(target.bleeding.source.is_empty() and target.bleeding.hit_id.is_empty() and s.context.get_rng().to_dict() == rng,"all six ticks expire without RNG")
	var expired := turn(s,Faction.Type.ENEMY)
	check(expired.get_events().is_empty() and target.vitals.get_hp() == hp - 24,"no seventh tick")
	s.close()

	s = fixture(); actor = s.units[0]; target = s.units[1]
	seed_status(actor,target)
	target.bleeding.ticks_left = BleedingState.MAX_TICKS - 2
	s.rune_selected = true
	fill(s,target,true)
	parity(s,"last representable extension")
	check(target.bleeding.ticks_left == BleedingState.MAX_TICKS,"maximum duration reached exactly")
	actor.try_refill_turn_resources()
	fill(s,target,true)
	var preserved := target.bleeding.to_dict()
	var before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	var predicted := s.preview_attack(target.id)
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before,"overflow preview stays isolated")
	var overflow := s.attack_unit(target.id)
	check(overflow.status == &"FAULTED" and overflow.reason == &"bleeding/duration_exhausted" and overflow.get_events() == predicted.events and overflow.get_steps() == predicted.steps,"overflow fault has preview/live parity")
	check(target.bleeding.to_dict() == preserved and actor.action_resources.get_main_left() == 0 and kinds(overflow.get_events()).count(&"hit_resolved") == 1 and &"bleeding_changed" not in kinds(overflow.get_events()),"overflow preserves paid hit prefix and old status")
	check(ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == predicted.snapshot_after and s.context.get_rng().to_dict() == predicted.rng_after and s.context.simulation_counters() == predicted.counters_after,"overflow state RNG counters match forecast")
	s.close()

func _test_faults() -> void:
	for mode: String in ["apply", "extend", "tick", "hp"]:
		var s := fixture(); var target := s.units[1]
		if mode in ["tick", "extend"]: seed_status(s.units[0],target)
		var mutate := func() -> void: target.bleeding.immune = true
		var hp_mutate := func(_a: float,_b: float) -> void: target.bleeding.immune = true
		if mode == "hp": target.vitals.hp_changed.connect(hp_mutate)
		else: target.bleeding.changed.connect(mutate)
		var r := turn(s,Faction.Type.ENEMY) if mode == "tick" else s.attack_unit(target.id)
		check(r.status == &"FAULTED",mode + " hostile callback faults")
		if mode == "hp":
			check(target.bleeding.ticks_left == 0 and &"hit_resolved" not in kinds(r.get_events()),"HP callback no full hit or application")
			target.vitals.hp_changed.disconnect(hp_mutate)
		else:
			check(target.bleeding.ticks_left == (1 if mode == "tick" else (4 if mode == "extend" else 2)) and &"bleeding_changed" in kinds(r.get_events()),mode + " written status prefix retained")
			target.bleeding.changed.disconnect(mutate)
		s.close()
	for limit: int in [2,3]:
		var s := fixture()
		s._queue = ActionQueue.new(limit)
		var f := s.preview_attack(s.units[1].id)
		var r := s.attack_unit(s.units[1].id)
		check(r.status == &"FAULTED" and r.reason == &"command_limit" and r.get_events() == f.events and r.get_steps() == f.steps,"limit forecast prefix")
		check(s.units[1].bleeding.ticks_left == (0 if limit == 2 else 2),"limit preserves only executed application")
		s.close()
	var s := fixture()
	var before := ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict()
	var r := s._queue.submit(BleedingApplyCommand.new(),s.context)
	check(r.status == &"REJECTED" and r.reason == &"bleeding/internal_command" and ItemSimulationSnapshot.capture(s.state,[]).snapshot.to_dict() == before,"external forged application rejected")
	r = s._queue.submit(BleedingTickCommand.new(s.units[1]),s.context)
	check(r.status == &"REJECTED" and r.reason == &"bleeding/internal_command","external forged tick rejected")
	s.units[1].bleeding = null
	r = s.attack_unit(s.units[1].id)
	check(r.status == &"REJECTED" and s.units[0].action_resources.get_main_left() == 1,"missing capability rejects before payment")
	s.close()

func _test_turns() -> void:
	var s := fixture(); var actor := s.units[0]; var target := s.units[1]
	no_heal(s)
	seed_status(target,actor); seed_status(actor,target)
	actor.action_resources.try_spend_main(1)
	var actor_before := actor.to_snapshot_dict()
	s.select_unit(s.units[2].id); s.select_unit(actor.id)
	check(actor.to_snapshot_dict() == actor_before,"selection no refill or tick")
	check(s.end_player_turn() and target.bleeding.ticks_left == 1 and target.vitals.get_hp() == 28.0 and actor.bleeding.ticks_left == 2,"enemy boundary ticks enemy only")
	s._enemy_index = s._enemy_ids.size()
	s.step_enemy()
	check(s.phase == BattleTacticalSession.Phase.PLAYER_TURN and actor.bleeding.ticks_left == 1 and actor.vitals.get_hp() == 28.0 and actor.action_resources.get_main_left() == 1,"player boundary tick then refill")
	s.close()
	s = fixture(); actor = s.units[0]; target = s.units[1]; no_heal(s)
	seed_status(actor,target); target.vitals.set_hp(1.0)
	for enemy: UnitState in s.units:
		if enemy.faction == Faction.Type.ENEMY and enemy != target: s._queue.submit(DeathCommand.new(enemy.id,DamageSource.new(&"test",0,enemy.cell)),s.context)
	check(not s.end_player_turn() and s.phase == BattleTacticalSession.Phase.VICTORY,"last enemy tick ends battle before phase switch")
	check(not actor.armor.in_battle and target.bleeding.ticks_left == 1,"battle expiry does not clear status")
	s.close()

func _test_edge_refresh_and_boundary() -> void:
	var s := fixture()
	var second_actor := s.units[2]
	var target := s.units[1]
	no_heal(s)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX,128.0)
	target.vitals.set_hp(128.0)
	var first := parity(s,"edge initial application")
	var first_hit: Dictionary = first.events.filter(func(e: Dictionary) -> bool: return e["kind"] == &"hit_resolved")[0]
	var tick := turn_parity(s,Faction.Type.ENEMY)
	check(tick.status == &"APPLIED" and target.bleeding.ticks_left == 1,"edge refresh starts after first tick")
	s.board.move_unit(second_actor,target.cell + Vector2i.DOWN)
	check(s.select_unit(second_actor.id) and s.selected_unit() == second_actor,"edge switches to living ally")
	var refreshed := parity(s,"edge ally refresh")
	var hits := events_of_kind(refreshed.events,&"hit_resolved")
	var bleeding_events := events_of_kind(refreshed.events,&"bleeding_changed")
	check(hits.size() == 1 and bleeding_events.size() == 1,"edge refresh has one real hit and one status event")
	if hits.size() == 1 and bleeding_events.size() == 1:
		var hit: Dictionary = hits[0]
		var changed: Dictionary = bleeding_events[0]
		var source: Dictionary = target.bleeding.source
		check(source["instigator_unit_id"] == second_actor.id and source["credit_unit_id"] == second_actor.id and source["origin_cell"] == second_actor.cell,"edge refresh source is latest actor and origin")
		check(target.bleeding.hit_id == hit["hit_id"] and changed["after"]["hit_id"] == hit["hit_id"] and hit["hit_id"] != first_hit["hit_id"],"edge refresh links latest real hit id")
		check(changed["reason"] == &"refreshed" and changed["before"]["ticks_left"] == 1 and changed["after"]["ticks_left"] == 3,"edge repeat adds duration and replaces source")
	s.close()

	s = fixture()
	target = s.units[1]
	no_heal(s)
	seed_status(s.units[0],target)
	tick = turn_parity(s,Faction.Type.ENEMY)
	check(tick.status == &"APPLIED" and target.bleeding.ticks_left == 1,"edge armor-only starts after first tick")
	fill(s,target,true)
	var preserved := target.bleeding.to_dict()
	var armor_only := parity(s,"edge armor-only preserves active status")
	var armor_hits := events_of_kind(armor_only.events,&"hit_resolved")
	check(armor_only.status == &"APPLIED" and target.bleeding.to_dict() == preserved,"armor-only keeps all status fields")
	check(kinds(armor_only.events).count(&"bleeding_changed") == 0,"armor-only emits no bleeding change")
	if armor_hits.size() == 1:
		var bleeding_gate: Dictionary = armor_hits[0]["hit"]["bleeding"]
		check(bleeding_gate["eligible"] == false and bleeding_gate["physical_hp_damage"] == 0 and bleeding_gate["policy"] == &"physical_hp","armor-only records rejected physical HP gate")
	else:
		check(false,"armor-only has a real hit explanation")
	s.close()

	s = fixture()
	var last_player := s.units[0]
	no_heal(s)
	seed_status(s.units[1],last_player)
	last_player.vitals.set_hp(1.0)
	last_player.action_resources._set_for_refill(0,0)
	last_player.move_points_left = 0.0
	for player: UnitState in s.units:
		if player.faction == Faction.Type.PLAYER and player != last_player:
			s._queue.submit(DeathCommand.new(player.id,DamageSource.new(&"test",0,player.cell)),s.context)
	check(s.end_player_turn(),"edge boundary enters enemy turn")
	s._enemy_index = s._enemy_ids.size()
	var boundary_before := s.turn_events.size()
	s.step_enemy()
	var boundary_receipt := s.last_receipt
	var boundary_events: Array[Dictionary] = s.turn_events.slice(boundary_before)
	check(s.phase == BattleTacticalSession.Phase.DEFEAT,"bleeding defeat occurs before player refill")
	check(not last_player.is_alive() and s.board.occupant_at(last_player.cell) == null,"bleeding death frees last player cell")
	check(boundary_receipt != null and kinds(boundary_events).count(&"died") == 1 and kinds(boundary_receipt.get_events()).count(&"died") == 1,"bleeding boundary emits one death")
	check(last_player.bleeding.ticks_left == 1,"bleeding boundary preserves consumed tick state")
	check(last_player.action_resources.get_main_left() == 0 and last_player.action_resources.get_bonus_left() == 0 and last_player.move_points_left == 0.0,"defeat happens before resource refill")
	s.close()
