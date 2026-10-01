extends RefCounted
class_name ExpeditionTransitions

static func apply(source: HeroHubState, action: String, args: Dictionary = {}) -> ExpeditionTransitionResult:
	var result := ExpeditionTransitionResult.new()
	if source == null:
		result.reason = "expedition/invalid_profile"; return result
	var hub := HeroHubState.from_dict(source.to_dict())
	if hub == null:
		result.reason = "expedition/invalid_profile"; return result
	var reason := _apply(hub, action, args)
	if not reason.is_empty():
		result.reason = reason; return result
	if HeroHubState.from_dict(hub.to_dict()) == null:
		result.reason = "expedition/invalid_result"; return result
	result.profile = hub
	return result

static func _apply(hub: HeroHubState, action: String, args: Dictionary) -> String:
	if action == "start":
		if not args.is_empty() or hub.phase != "hub" or hub.party.is_empty() or hub.run_serial >= ExpeditionRunState.MAX_VALUE: return "expedition/cannot_start"
		hub.run_serial += 1
		if not hub.battle_report.is_empty(): hub.battle_report.open = false
		var run := ExpeditionRunState.new()
		run.run_id = hub.run_serial
		var rng := RandomNumberGenerator.new(); rng.state = hub.expedition_rng_state
		run.plan = ExpeditionGenerator.generate(int(rng.randi()))
		hub.expedition_rng_state = rng.state
		for id: int in hub.party:
			var hero: HeroProgression = hub.heroes[id]
			hero.hp_current = hero.max_hp()
		run.ordinary_item_ids = hub.battle_items()
		hub.expedition = run; hub.phase = "expedition"
		return ""
	var run := hub.expedition
	if hub.phase != "expedition" or run == null: return "expedition/not_active"
	if action == "outcome": return _outcome(hub,args)
	if action == "choose":
		if not _ints(args,["node"]) or run.phase != "route" or not run.available_nodes().has(args.node): return "expedition/node_unavailable"
		if not hub.battle_report.is_empty(): hub.battle_report.open = false
		run.route.append(args.node)
		var node := run.current_node()
		if node.kind in ["battle","elite","final"]:
			run.phase = "battle"; run.battle_serial += 1
			run.checkpoint = ExpeditionRunState.make_checkpoint(hub, node.battle_seed)
		elif node.kind == "cache":
			var amount := ExpeditionCatalog.RICH_CACHE_GOLD if node.modifier == "rich" else ExpeditionCatalog.CACHE_GOLD
			if run.gold > ExpeditionRunState.MAX_VALUE - amount: return "expedition/overflow"
			run.gold += amount; run.resolved.append(args.node)
		else: run.phase = "service"
		return ""
	if action == "service":
		if run.phase != "service" or not ItemSimulationSnapshot._shape(args,{"kind":TYPE_STRING}) or args.kind not in ["heal","repair"]: return "expedition/service_unavailable"
		var modifier: String = run.current_node().modifier
		var percent := ExpeditionCatalog.BOOSTED_SERVICE_PERCENT if (args.kind == "heal" and modifier == "healing") or (args.kind == "repair" and modifier == "repair") else ExpeditionCatalog.SERVICE_PERCENT
		for id: int in hub.party:
			var hero: HeroProgression = hub.heroes[id]
			if args.kind == "heal": hero.hp_current = minf(hero.max_hp(),hero.hp_current + floorf(hero.max_hp() * percent / 100.0))
			else:
				var armor := hub.equipped(id,"armor")
				if not armor.is_empty():
					var maximum: int = HeroGearCatalog.definition(armor.definition).armor_max
					armor.remaining = mini(maximum, int(armor.remaining) + floori(maximum * percent / 100.0))
		if run.current_node().kind == "camp": run.phase = "camp_departure"
		else: _resolve(run)
		return ""
	if action == "continue" or action == "leave":
		if run.phase != "camp_departure" or not args.is_empty(): return "expedition/exit_unavailable"
		_resolve(run)
		return _finish(hub,false,false) if action == "leave" else ""
	if action == "reward":
		if run.phase != "reward" or not _ints(args,["index"]) or args.index < 0 or args.index > 2: return "expedition/reward_unavailable"
		run.artifacts.append({"id":run.next_artifact_id,"definition":String(run.current_node().reward[args.index]),"stacks":1,"hero_id":0,"slot":0})
		if not hub.battle_report.is_empty() and hub.battle_report.open:
			hub.battle_report.artifact_selected = String(run.current_node().reward[args.index])
			hub.battle_report.items.append(ExpeditionCatalog.artifact_name(hub.battle_report.artifact_selected))
		run.next_artifact_id += 1; _resolve(run)
		return ""
	if run.phase != "route": return "expedition/map_required"
	if action == "allocate":
		if not ItemSimulationSnapshot._shape(args,{"hero":TYPE_INT,"delta":TYPE_ARRAY}) or not hub.party.has(args.hero): return "expedition/invalid_allocation"
		var delta: Array[int] = []
		for value: Variant in args.delta:
			if typeof(value) != TYPE_INT: return "expedition/invalid_allocation"
			delta.append(value)
		return "" if (hub.heroes[args.hero] as HeroProgression).apply_allocation(delta) else "expedition/invalid_allocation"
	if action in ["equip","unequip"]:
		if not _ints(args,["item","hero"]) or not run.ordinary_item_ids.has(args.item): return "expedition/item_unavailable"
		var item: Dictionary = hub.items[args.item]
		if action == "unequip": item.hero_id = 0; return ""
		if not hub.party.has(args.hero) or not HeroGearCatalog.allowed(item.definition,(hub.heroes[args.hero] as HeroProgression).class_id): return "expedition/item_unavailable"
		var old := hub.equipped(args.hero,HeroGearCatalog.slot(item.definition))
		if not old.is_empty(): old.hero_id = 0
		item.hero_id = args.hero
		return ""
	if action in ["artifact_equip","artifact_unequip","artifact_merge"]: return _artifact(run,hub.party,action,args)
	return "expedition/unknown_action"

static func _artifact(run: ExpeditionRunState, party: Array[int], action: String, args: Dictionary) -> String:
	if action == "artifact_merge":
		if not _ints(args,["item","target"]) or args.item == args.target: return "expedition/invalid_merge"
		var source := run.artifact(args.item); var destination := run.artifact(args.target)
		if source.is_empty() or destination.is_empty() or source.definition != "spark" or destination.definition != "spark" or int(source.stacks) + int(destination.stacks) > 3: return "expedition/invalid_merge"
		destination.stacks += source.stacks; run.artifacts.erase(source)
		return ""
	if not _ints(args,["item","hero","slot"]): return "expedition/invalid_artifact"
	var item := run.artifact(args.item)
	if item.is_empty(): return "expedition/invalid_artifact"
	if action == "artifact_unequip": item.hero_id = 0; item.slot = 0; return ""
	if not party.has(args.hero) or args.slot < 1 or args.slot > 3: return "expedition/invalid_artifact"
	for other: Dictionary in run.artifacts:
		if other.id == item.id or other.hero_id != args.hero: continue
		if other.definition == item.definition:
			if item.definition != "spark" or int(item.stacks) + int(other.stacks) > 3: return "expedition/duplicate_artifact"
			other.stacks += item.stacks; run.artifacts.erase(item); return ""
	for other: Dictionary in run.artifacts:
		if other.id == item.id or other.hero_id != args.hero: continue
		if other.slot == args.slot: return "expedition/occupied_artifact_slot"
	item.hero_id = args.hero; item.slot = args.slot
	return ""

static func _outcome(hub: HeroHubState, receipt: Dictionary) -> String:
	var run := hub.expedition
	if run.phase != "battle" or not ItemSimulationSnapshot._shape(receipt,{"run_id":TYPE_INT,"node_id":TYPE_INT,"serial":TYPE_INT,"victory":TYPE_BOOL,"hp":TYPE_DICTIONARY,"gear":TYPE_DICTIONARY}): return "expedition/invalid_receipt"
	if receipt.run_id != run.run_id or receipt.node_id != run.current_node().id or receipt.serial != run.battle_serial: return "expedition/stale_receipt"
	if receipt.hp.size() != hub.party.size() or receipt.gear.size() != run.checkpoint.items.size(): return "expedition/incomplete_receipt"
	var living: int = 0
	for id: Variant in receipt.hp:
		if typeof(id) != TYPE_INT or not hub.party.has(id) or typeof(receipt.hp[id]) not in [TYPE_FLOAT,TYPE_INT]: return "expedition/invalid_hp"
		var value := float(receipt.hp[id])
		if not is_finite(value) or value < 0.0 or value > (hub.heroes[id] as HeroProgression).max_hp(): return "expedition/invalid_hp"
		if value > 0.0: living += 1
	if receipt.victory != (living > 0): return "expedition/invalid_victory"
	var expected_gear: Array[int] = []
	for row: Dictionary in run.checkpoint.items: expected_gear.append(row.id)
	for id: Variant in receipt.gear:
		if typeof(id) != TYPE_INT or not expected_gear.has(id) or typeof(receipt.gear[id]) != TYPE_INT: return "expedition/invalid_gear"
		if receipt.gear[id] < 0 or receipt.gear[id] > HeroGearCatalog.definition(hub.items[id].definition).armor_max: return "expedition/invalid_gear"
	var report := PostBattleRules.begin(hub,"expedition",run.current_node().id,run.battle_serial,ExpeditionCatalog.room_name(run.current_node().kind),receipt.victory,receipt.victory and run.current_node().kind == "final")
	if not receipt.victory:
		for id: int in run.ordinary_item_ids: report.lost_items.append(String(HeroGearCatalog.definition(hub.items[id].definition).display_name))
	var deployed: Array[int] = hub.party.duplicate()
	var dead: Array[int] = []
	for id: int in deployed:
		var hero: HeroProgression = hub.heroes[id]
		hero.hp_current = float(receipt.hp[id])
		if hero.hp_current <= 0.0: dead.append(id); run.fallen.append(hero.name)
	for id: int in receipt.gear:
		var item: Dictionary = hub.items[id]
		item.remaining = receipt.gear[id]
		if receipt.victory and dead.has(item.hero_id):
			report.items.append(String(HeroGearCatalog.definition(item.definition).display_name) + " · на склад")
			item.hero_id = 0; run.ordinary_item_ids.erase(id)
	for item: Dictionary in run.artifacts:
		if dead.has(item.hero_id): item.hero_id = 0; item.slot = 0
	for id: int in dead: hub.party.erase(id); hub.heroes.erase(id)
	run.checkpoint.clear()
	if not receipt.victory:
		PostBattleRules.finish(hub,report,receipt.hp)
		return _finish(hub,true,false)
	var room := ExpeditionCatalog.room(run.current_node().kind)
	if run.gold > ExpeditionRunState.MAX_VALUE - room.gold: return "expedition/overflow"
	run.gold += room.gold
	report.gold_awarded = room.gold
	for id: int in hub.heroes:
		if not (hub.heroes[id] as HeroProgression).award_experience_tenths(room.xp * (10 if deployed.has(id) else 1)): return "expedition/overflow"
	PostBattleRules.finish(hub,report,receipt.hp)
	if run.current_node().kind == "final": _resolve(run); return _finish(hub,false,true)
	run.phase = "reward"
	return ""

static func _finish(hub: HeroHubState, defeat: bool, completed: bool) -> String:
	var run := hub.expedition
	var copies: int = 0
	for item: Dictionary in run.artifacts: copies += int(item.stacks)
	var essence: int = 0 if defeat else copies * ExpeditionCatalog.COPY_ESSENCE + (ExpeditionCatalog.FINAL_ESSENCE if completed else 0)
	var gold: int = 0 if defeat else run.gold + (ExpeditionCatalog.FINAL_GOLD if completed else 0)
	if hub.gold > ExpeditionRunState.MAX_VALUE - gold or hub.essence > ExpeditionRunState.MAX_VALUE - essence: return "expedition/overflow"
	if defeat:
		for id: int in run.ordinary_item_ids: hub.items.erase(id)
	hub.gold += gold; hub.essence += essence
	if not hub.battle_report.is_empty() and hub.battle_report.open:
		hub.battle_report.gold_scope = "hub"
		hub.battle_report.gold_lost = run.gold if defeat else 0
		hub.battle_report.essence_awarded = essence
		if completed: hub.battle_report.gold_awarded += ExpeditionCatalog.FINAL_GOLD
	hub.last_result = "%s · комнат %d. Золото +%d, эссенция +%d. %s\nОпыт прошлых побед сохранён; артефакты %s." % ["Поражение" if defeat else ("Поход завершён" if completed else "Досрочное возвращение"),run.route.size(),gold,essence,"Погибли: " + ", ".join(run.fallen) if not run.fallen.is_empty() else "Все герои вернулись.","потеряны" if defeat else "переработаны"]
	hub.expedition = null; hub.phase = "hub"; hub._refresh_candidates()
	return ""

static func _resolve(run: ExpeditionRunState) -> void:
	run.resolved.append(run.route.back()); run.phase = "route"

static func _ints(args: Dictionary, keys: Array[String]) -> bool:
	if args.size() != keys.size(): return false
	for key: String in keys:
		if not args.has(key) or typeof(args[key]) != TYPE_INT: return false
	return true
