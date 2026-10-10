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
		var loaded := HeroHubStore.read_run(path)
		check(loaded.run != null and loaded.run.to_dict() == result.profile.to_dict(),"restart after commit " + action + " " + loaded.error)
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
	check(hub.to_dict().schema == 6 and HeroHubState.from_dict(hub.to_dict()) != null,"profile6")
	check(hub.rng_state == old.rng_state and hub.expedition_rng_state == old.expedition_rng_state,"upgrade preserves streams")
	check(hub.mage_deck.base_types.count("card.wet") == 2 and not hub.mage_deck.base_types.has("card.burning"),"D13 exact default")
	hub = step(hub,"start")
	if hub.expedition == null: quit(1); return
	var strict_run := hub.expedition.to_dict()
	var invalid_run: Dictionary
	for version: int in [2, 3, 5]:
		invalid_run = strict_run.duplicate(true); invalid_run.schema = version
		check(ExpeditionRunState.from_dict(invalid_run) == null,"reject old/future run schema %d" % version)
	invalid_run = strict_run.duplicate(true); invalid_run.erase("ruleset_id")
	check(ExpeditionRunState.from_dict(invalid_run) == null,"run requires ruleset")
	invalid_run = strict_run.duplicate(true); invalid_run.ruleset_id = ExpeditionRulesRegistry.LEGACY
	check(ExpeditionRunState.from_dict(invalid_run) == null,"deck capability requires deck ruleset")
	invalid_run = strict_run.duplicate(true); invalid_run.erase("repair_spent")
	check(ExpeditionRunState.from_dict(invalid_run) == null,"run requires repair ledger")
	var invalid_plan := strict_run.duplicate(true); invalid_plan.plan.ruleset_id = ExpeditionRulesRegistry.LEGACY
	check(ExpeditionRunState.from_dict(invalid_plan) == null and hub.expedition.to_dict() == strict_run,"run rejects mismatched plan without mutating source")
	check(hub.expedition.is_deck() and hub.expedition.cards.size() == 10,"deck start")
	_opening(hub)
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
		check(report.schema == 3 and report.open and report.return_reason == exit_kind,"open return report " + exit_kind)
		check(report.returned_cards.size() >= 10,"all copies historical")
		check(HeroHubState.from_dict(route.to_dict()) != null,"return reload " + exit_kind)
		if exit_kind == "early":
			check(report.node_id == 7, "new layout returns from camp seven")
			var wrong_camp := route.to_dict(); wrong_camp.battle_report.node_id = 6
			check(HeroHubState.from_dict(wrong_camp) == null, "early report rejects non-camp node")
		var broken := route.to_dict(); broken.battle_report.schema = 3.0
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

func _opening(hub: HeroHubState) -> void:
	check(hub.expedition.phase == "battle" and hub.expedition.route == [1] and hub.expedition.battle_serial == 1, "start atomically enters first battle")
	check(not ExpeditionTransitions.apply(hub, "choose", {"node":1}).is_ok(), "first room cannot be entered twice")
	var next_id := UnitId.get_counter()
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(), "opening battle constructed")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict()
	var enemies: Array[UnitState] = []
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.ENEMY: enemies.append(unit)
	check(enemies.size() == 3 and enemies[0].debug_name == "Страж" and enemies[1].debug_name == "Щит" and enemies[2].debug_name == "Дозорный", "three existing enemy archetypes")
	check(enemies[0].combat_perks.definition.counterattack and enemies[0].combat_perks.definition.tank_reactions and enemies[0].combat_perks.definition.stunning_strike, "guard capabilities")
	check(enemies[1].bleeding.immune and enemies[1].combat_perks.definition.stun_immune and enemies[2].combat_perks.definition.sneak_attack, "shield and sneak capabilities")
	check(session.state.environment.fire_at(Vector2i(3,2)).effect == "bleeding" and session.state.environment.fire_at(Vector2i(4,4)).effect == "burning", "both existing cell hazards")
	check(session.board.get_terrain(Vector2i(3,0)) == TerrainType.Type.WALL and session.board.get_terrain(Vector2i(5,6)) == TerrainType.Type.HAZARD and session.board.get_terrain(Vector2i(6,7)) == TerrainType.Type.VOID, "wall and both lethal terrain forms")
	check(session.board.get_height_steps(Vector2i(3,3)) == 1 and session.board.get_height_steps(Vector2i(4,3)) == 2 and not session.state.environment.collapse.is_empty(), "half/full height steps and collapse enabled")
	check(session.is_deploying() and session.state.deck.hand_ids.size() == 5, "opening keeps deployment and mulligan")
	session.close()
	UnitId.set_counter(next_id)
	var restored := HeroHubState.from_dict(hub.to_dict())
	bundle = HeroHubBattleFactory.create(restored)
	session = bundle.session
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == snapshot and session.context.get_rng().to_dict() == rng, "restart restores exact opening battle and RNG")
	session.close()
	var old := hub.to_dict()
	old.expedition.plan = ExpeditionRulesRegistry.generate_plan(hub.expedition.plan.seed, false)
	var old_hub := HeroHubState.from_dict(old)
	check(old_hub != null and old_hub.to_dict() == old and not old_hub.expedition.plan.opening and old_hub.expedition.plan.start == [1,2], "current two-start deck graph roundtrips without migration")
	if old_hub != null:
		bundle = HeroHubBattleFactory.create(old_hub)
		check(not bundle.is_empty(), "old deck encounter still constructs")
		if not bundle.is_empty():
			session = bundle.session
			check(session.board.get_terrain(Vector2i(3,0)) == TerrainType.Type.FLOOR, "old first encounter is not replaced by test room")
			session.close()

func _legacy_migration() -> void:
	var path := "user://deck-migration-%d.save" % Time.get_ticks_usec()
	for version: int in [1,2,3]:
		var payload := var_to_bytes({"schema":version})
		var bytes := var_to_bytes({"format":"hero-hub-v%d" % version,"payload":payload,"sha256":HeroHubStore._digest(payload)})
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(bytes); file.close()
		var loaded := HeroHubStore.read_run(path,true)
		check(loaded.run == null and not loaded.error.is_empty(),"v%d profile refused even in deck mode" % version)
		check(FileAccess.get_file_as_bytes(path) == bytes,"v%d old profile left unchanged" % version)
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
