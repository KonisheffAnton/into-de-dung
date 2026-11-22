extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST EXPEDITION: " + label)

func _run() -> void:
	var hub := HeroHubState.create(9021)
	hub.enable_mage_deck()
	var host_id: int = hub.party[1]
	_check(hub.select_mage_host(host_id), "selected host saved before start")
	var start := ExpeditionTransitions.apply(hub, "start", {"host_hero_id":host_id})
	_check(start.is_ok(), "explicit party host starts expedition")
	if not start.is_ok():
		quit(1); return
	hub = start.profile
	hub = _earn_cache_gold(hub)
	_check(hub.expedition != null and hub.expedition.gold > 0, "run can carry acquired room gold into host defeat")
	if hub.expedition == null or hub.expedition.gold <= 0:
		quit(1); return
	var run_data := hub.expedition.to_dict()
	_check(run_data.schema == 5 and run_data.host_hero_id == host_id and run_data.checkpoint.schema == 2 and run_data.checkpoint.host_hero_id == host_id, "host persists in run and checkpoint")
	_check(ExpeditionRunState.from_dict(run_data) != null, "host run roundtrip")
	var bad_checkpoint := run_data.duplicate(true)
	bad_checkpoint.checkpoint.host_hero_id = int(hub.party[0])
	_check(ExpeditionRunState.from_dict(bad_checkpoint) == null, "checkpoint host must match run host")
	var damaged := hub.to_dict()
	damaged.expedition.host_hero_id = 999999
	_check(HeroHubState.from_dict(damaged) == null, "run host must remain party member")
	var bad_start := ExpeditionTransitions.apply(hub, "start", {"host_hero_id":999999})
	_check(not bad_start.is_ok() and hub.expedition.host_hero_id == host_id, "invalid host start rejects without source mutation")
	var stale := _receipt(hub, host_id, true)
	stale.serial += 1
	var stale_before := hub.to_dict()
	_check(not ExpeditionTransitions.apply(hub, "outcome", stale).is_ok() and hub.to_dict() == stale_before, "stale receipt rejected without source mutation")
	var lying := _receipt(hub, host_id, false)
	lying.victory = true
	_check(not ExpeditionTransitions.apply(hub, "outcome", lying).is_ok() and hub.to_dict() == stale_before, "host death cannot claim victory and source stays unchanged")
	var salvage_receipt := _receipt(hub, host_id, false)
	for id: int in hub.party:
		if id != host_id: salvage_receipt.hp[id] = float((hub.heroes[id] as HeroProgression).max_hp())
	var salvage := ExpeditionTransitions.apply(hub, "outcome", salvage_receipt)
	_check(salvage.is_ok(), "host defeat with survivors is accepted")
	if salvage.is_ok():
		var returned: HeroHubState = salvage.profile
		_check(returned.expedition == null and returned.phase == "hub" and returned.party.size() > 0, "host defeat returns surviving party")
		_check(returned.battle_report.return_reason == "host_defeat" and not returned.battle_report.victory and returned.battle_report.gold_lost == 0 and returned.battle_report.lost_items.is_empty(), "salvage report retains defeat narrative without losses")
		_check(returned.gold == hub.gold + hub.expedition.gold and returned.battle_report.gold_awarded == hub.expedition.gold, "host defeat retains run gold")
		var found_recycled: bool = false
		for card: Dictionary in returned.battle_report.returned_cards:
			if card.origin == "found" and card.disposition == "recycled": found_recycled = true
		_check(returned.battle_report.returned_cards.size() > 10 and found_recycled and returned.battle_report.recycled_count > 0, "found cards recycle after host defeat")
		var lost_host_gear: bool = true
		for item: Dictionary in returned.items.values():
			if int(item.hero_id) == host_id: lost_host_gear = false
		_check(lost_host_gear and returned.items.size() == hub.items.size() and returned.items.size() > 0, "all gear is preserved and dead host gear enters hub storage")
		_check(HeroHubState.from_dict(returned.to_dict()) != null, "host defeat report reloads")
	var full_defeat := ExpeditionTransitions.apply(hub, "outcome", _receipt(hub, host_id, false, true))
	_check(full_defeat.is_ok(), "all party dead remains full defeat")
	if full_defeat.is_ok():
		var found_lost: bool = false
		for card: Dictionary in full_defeat.profile.battle_report.returned_cards:
			if card.disposition == "lost": found_lost = true
		var carried_lost := true
		for item_id: int in hub.expedition.ordinary_item_ids:
			if full_defeat.profile.items.has(item_id): carried_lost = false
		_check(full_defeat.profile.expedition == null and full_defeat.profile.battle_report.return_reason == "defeat" and found_lost and carried_lost, "full defeat loses carried items and preserves hub storage")
	print("HOST EXPEDITION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _receipt(hub: HeroHubState, host_id: int, victory: bool, all_dead: bool = false) -> Dictionary:
	var hp: Dictionary = {}
	var gear: Dictionary = {}
	for id: int in hub.party:
		hp[id] = float((hub.heroes[id] as HeroProgression).max_hp()) if victory or (id != host_id and not all_dead) else 0.0
	for item: Dictionary in hub.expedition.checkpoint.legacy_inputs.items:
		gear[item.id] = item.remaining
	return {"ruleset_id":ExpeditionRulesRegistry.DECK,"run_id":hub.run_serial,"node_id":hub.expedition.current_node().id,"serial":hub.expedition.battle_serial,"victory":victory,"hp":hp,"gear":gear}

func _earn_cache_gold(source: HeroHubState) -> HeroHubState:
	var hub := source
	var chose_found_card: bool = false
	for _i: int in range(24):
		if hub.expedition == null: return hub
		if hub.expedition.gold > 0 and chose_found_card and hub.expedition.phase == "battle": return hub
		var result: ExpeditionTransitionResult
		match hub.expedition.phase:
			"battle": result = ExpeditionTransitions.apply(hub, "outcome", _receipt(hub, hub.expedition.host_hero_id, true))
			"reward":
				var index: int = 0 if not chose_found_card else -1
				result = ExpeditionTransitions.apply(hub, "reward", {"index":index})
				if index == 0: chose_found_card = true
			"route":
				var choices: Array[int] = hub.expedition.available_nodes()
				var chosen: int = choices[0]
				for node_id: int in choices:
					if hub.expedition.plan.nodes[node_id - 1].kind == "cache": chosen = node_id; break
				result = ExpeditionTransitions.apply(hub, "choose", {"node":chosen})
			"service": result = ExpeditionTransitions.apply(hub, "service", {"kind":"heal"})
			"camp_departure": result = ExpeditionTransitions.apply(hub, "continue")
		if result == null or not result.is_ok(): return hub
		hub = result.profile
	return hub
