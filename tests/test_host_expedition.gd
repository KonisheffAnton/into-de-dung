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
	var missing_flag := _receipt(hub,host_id,true)
	missing_flag.erase("host_has_died")
	_check(not ExpeditionTransitions.apply(hub,"outcome",missing_flag).is_ok(),"missing death history cannot bypass reselection")
	var lying := _receipt(hub, host_id, false)
	_check(not ExpeditionTransitions.apply(hub, "outcome", lying).is_ok() and hub.to_dict() == stale_before, "surviving party cannot claim defeat")
	var victory_receipt := _receipt(hub,host_id,false)
	victory_receipt.victory = true; victory_receipt["host_has_died"] = true
	var victory := ExpeditionTransitions.apply(hub,"outcome",victory_receipt)
	_check(victory.is_ok(),"victory with dead carrier accepted: " + victory.reason)
	if victory.is_ok():
		var continued: HeroHubState = victory.profile
		_check(continued.expedition != null and continued.expedition.phase == "reward" and continued.expedition.host_hero_id == 0 and continued.mage_deck.host_hero_id == 0,"host death keeps run and requires new carrier after reward")
		_check(not continued.heroes.has(host_id) and continued.items.size() == hub.items.size(),"dead permanent host removed; gear follows ordinary victory policy")
		_check(HeroHubState.from_dict(continued.to_dict()) != null,"hostless reward save reloads")
		continued = ExpeditionTransitions.apply(continued,"reward",{"index":-1}).profile
		_check(continued != null and continued.expedition != null,"reward resolves with no host")
		if continued != null and continued.expedition != null:
			var node: int = continued.expedition.available_nodes()[0]
			_check(not ExpeditionTransitions.apply(continued,"choose",{"node":node}).is_ok(),"new room requires host")
			var selected := ExpeditionTransitions.apply(continued,"select_host",{"hero":continued.party[0]})
			_check(selected.is_ok() and HeroHubState.from_dict(selected.profile.to_dict()) != null,"new host persists")
			if selected.is_ok(): _check(ExpeditionTransitions.apply(selected.profile,"choose",{"node":node}).is_ok(),"new host admits next room")
	var revived_receipt := _receipt(hub,host_id,true)
	revived_receipt["host_has_died"] = true; revived_receipt.hp[host_id] = 12.0
	var revived := ExpeditionTransitions.apply(hub,"outcome",revived_receipt)
	_check(revived.is_ok() and revived.profile.heroes.has(host_id) and revived.profile.expedition.host_hero_id == 0,"living resurrection preserves permanent hero but reselect required: " + revived.reason)
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
	return {"ruleset_id":ExpeditionRulesRegistry.DECK,"run_id":hub.run_serial,"node_id":hub.expedition.current_node().id,"serial":hub.expedition.battle_serial,"victory":victory,"hp":hp,"gear":gear,"host_has_died":not victory}

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
