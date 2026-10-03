extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL DECK EXPEDITION: " + label)

func step(hub: HeroHubState, action: String, args: Dictionary = {}) -> HeroHubState:
	var before := hub.to_dict()
	var result := ExpeditionTransitions.apply(hub,action,args)
	check(result.is_ok(),action + " " + result.reason)
	check(hub.to_dict() == before,"isolated " + action)
	if result.is_ok():
		var path := "user://deck-barrier-%d.save" % Time.get_ticks_usec()
		check(HeroHubStore.write_run(path,hub).is_empty(),"before barrier " + action)
		check(not HeroHubStore.write_run(path + "/blocked",result.profile).is_empty(),"failed write " + action)
		check(HeroHubStore.read_run(path).run.to_dict() == before,"restart before commit " + action)
		check(HeroHubStore.write_run(path,result.profile).is_empty(),"retry exact candidate " + action)
		check(HeroHubStore.read_run(path).run.to_dict() == result.profile.to_dict(),"restart after commit " + action)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result.profile if result.is_ok() else hub

func receipt(hub: HeroHubState, victory: bool = true) -> Dictionary:
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for id: int in hub.party: hp[id] = float((hub.heroes[id] as HeroProgression).max_hp()) if victory else 0.0
	for item: Dictionary in hub.expedition.checkpoint.legacy_inputs.items: gear[item.id] = item.remaining
	return {"ruleset_id":ExpeditionRulesRegistry.DECK,"run_id":hub.run_serial,"node_id":hub.expedition.current_node().id,"serial":hub.expedition.battle_serial,"victory":victory,"hp":hp,"gear":gear}

func run() -> void:
	var hub := HeroHubState.create(443)
	var old := hub.to_dict()
	hub.enable_mage_deck()
	check(hub.to_dict().schema == 4 and HeroHubState.from_dict(hub.to_dict()) != null,"profile4")
	check(hub.rng_state == old.rng_state and hub.expedition_rng_state == old.expedition_rng_state,"upgrade preserves streams")
	check(hub.mage_deck.base_types.count("card.wet") == 2 and not hub.mage_deck.base_types.has("card.burning"),"D13 exact default")
	hub = step(hub,"start")
	if hub.expedition == null: quit(1); return
	check(hub.expedition.is_deck() and hub.expedition.cards.size() == 10,"deck start")
	var saved_plan := hub.expedition.plan.duplicate(true)
	for node: Dictionary in saved_plan.nodes:
		if node.kind in ["battle","elite","final"]: check(node.reward.size() == 3,"triple including final")
	for exit_kind: String in ["early","completed","defeat"]:
		var route := HeroHubState.from_dict(hub.to_dict())
		var safety: int = 0
		while route.expedition != null and safety < 30:
			safety += 1
			match route.expedition.phase:
				"route": route = step(route,"choose",{"node":route.expedition.available_nodes()[0]})
				"battle":
					var outcome := receipt(route,exit_kind != "defeat")
					route = step(route,"outcome",outcome)
					check(not ExpeditionTransitions.apply(route,"outcome",outcome).is_ok(),"outcome single use")
				"reward":
					check(not route.dismiss_battle_report(),"pending prevents Continue")
					route = step(route,"reward",{"index":0 if route.expedition.battle_serial % 2 else -1})
					check(not ExpeditionTransitions.apply(route,"reward",{"index":0}).is_ok(),"choice single use")
					if route.expedition != null: check(route.dismiss_battle_report(),"close nonfinal")
				"service": route = step(route,"service",{"kind":"heal"})
				"camp_departure":
					route = step(route,"deck_compose",{"active_ids":route.expedition.active_ids})
					route = step(route,"leave" if exit_kind == "early" else "continue")
		check(route.expedition == null,"terminates " + exit_kind)
		if route.expedition != null: continue
		var report := route.battle_report
		check(report.schema == 2 and report.open and report.return_reason == exit_kind,"open return report " + exit_kind)
		check(report.returned_cards.size() >= 10,"all copies historical")
		check(HeroHubState.from_dict(route.to_dict()) != null,"return reload " + exit_kind)
		var broken := route.to_dict(); broken.battle_report.schema = 2.0
		check(HeroHubState.from_dict(broken) == null,"report rejects float schema")
		broken = route.to_dict(); broken.battle_report.erase("source")
		check(HeroHubState.from_dict(broken) == null,"report rejects missing common field without exception")
		check(route.dismiss_battle_report() and not route.dismiss_battle_report(),"return Continue once")
		check(not HeroHubState.from_dict(route.to_dict()).battle_report.open,"closed report persists")
		if exit_kind == "defeat": check(route.essence == 0 and route.mage_deck.forge_discovered_types.is_empty(),"defeat no new resources")
	var legacy := step(HeroHubState.create(777),"start")
	legacy.enable_mage_deck()
	check(not legacy.expedition.is_deck() and HeroHubState.from_dict(legacy.to_dict()) != null,"upgrade keeps old run")
	var damaged := hub.to_dict(); damaged.expedition.ruleset_id = "future"
	check(HeroHubState.from_dict(damaged) == null,"unknown ruleset rejects")
	damaged = hub.to_dict(); damaged.expedition.cards[0].origin = "found"
	check(HeroHubState.from_dict(damaged) == null,"bad provenance rejects")
	_legacy_migration()
	print("MAGE DECK EXPEDITION RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _legacy_migration() -> void:
	var path := "user://deck-migration-%d.save" % Time.get_ticks_usec()
	for version: int in [1,2,3]:
		for battle: bool in [false,true]:
			var legacy := HeroHubState.create(808)
			if battle: check(legacy.start_battle(),"legacy H1 start")
			var raw := legacy.to_dict(); raw.schema = version
			if version < 3: raw.erase("achievements"); raw.erase("battle_report")
			if version < 2:
				for key: String in ["essence","expedition_rng_state","expedition"]: raw.erase(key)
			var payload := var_to_bytes(raw)
			var file := FileAccess.open(path,FileAccess.WRITE)
			file.store_buffer(var_to_bytes({"format":"hero-hub-v%d" % version,"payload":payload,"sha256":HeroHubStore._digest(payload)})); file.close()
			var loaded := HeroHubStore.read_run(path,true)
			check(loaded.run != null and loaded.migrated and loaded.run.to_dict().schema == 4,"v%d upgrade battle=%s" % [version,battle])
			check(HeroHubStore.read_run(path).run.to_dict().schema == 3,"old file untouched before upgrade commit")
			if loaded.run != null and battle:
				var bundle := HeroHubBattleFactory.create(loaded.run)
				check(not bundle.is_empty() and bundle.session.state.deck == null and bundle.session.state.abilities.schema_version == 1,"legacy H1 still legacy after upgrade")
				if not bundle.is_empty(): bundle.session.close()
	var route := step(HeroHubState.create(779),"start")
	var legacy_copies: int = 0
	for safety: int in 30:
		if route.expedition == null: break
		legacy_copies = route.expedition.artifacts.size()
		var upgraded := HeroHubState.from_dict(route.to_dict()); upgraded.enable_mage_deck()
		check(HeroHubState.from_dict(upgraded.to_dict()) != null and upgraded.expedition.to_dict() == route.expedition.to_dict(),"whole legacy phase preserved " + route.expedition.phase)
		match route.expedition.phase:
			"route": route = step(route,"choose",{"node":route.expedition.available_nodes()[0]})
			"battle":
				var hp: Dictionary = {}; var gear: Dictionary = {}
				for id: int in route.party: hp[id] = float(route.heroes[id].max_hp())
				for item: Dictionary in route.expedition.checkpoint.items: gear[item.id] = item.remaining
				route = step(upgraded,"outcome",{"run_id":route.run_serial,"node_id":route.expedition.current_node().id,"serial":route.expedition.battle_serial,"victory":true,"hp":hp,"gear":gear})
			"reward": route = step(upgraded,"reward",{"index":0})
			"service": route = step(upgraded,"service",{"kind":"heal"})
			"camp_departure": route = step(upgraded,"continue")
	check(route.expedition == null and route.essence == ExpeditionCatalog.FINAL_ESSENCE + legacy_copies * ExpeditionCatalog.COPY_ESSENCE,"old final essence remains legacy")
	if route.expedition == null:
		check(route.dismiss_battle_report(),"old final report Continue")
		route = step(route,"start")
		check(route.expedition.is_deck(),"only next run uses cards")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
