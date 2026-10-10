extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL POSTBATTLE: " + label)

func step(hub: HeroHubState, action: String, args: Dictionary = {}) -> HeroHubState:
	var before := hub.to_dict()
	var result := ExpeditionTransitions.apply(hub,action,args)
	check(result.is_ok(),"transition " + action + " " + result.reason)
	check(hub.to_dict() == before,"transition isolates source " + action)
	if not result.is_ok(): return hub
	var restored := HeroHubState.from_dict(result.profile.to_dict())
	check(restored != null and restored.to_dict() == result.profile.to_dict(),"roundtrip " + action)
	return result.profile

func receipt(hub: HeroHubState, victory: bool = true, dead_id: int = 0) -> Dictionary:
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for id: int in hub.party:
		hp[id] = float((hub.heroes[id] as HeroProgression).max_hp() - 10) if victory and id != dead_id else 0.0
	for item: Dictionary in hub.expedition.checkpoint.items:
		gear[item.id] = maxi(0,HeroGearCatalog.definition(item.definition).armor_max - 12)
	return {"run_id":hub.run_serial,"node_id":hub.expedition.current_node().id,"serial":hub.expedition.battle_serial,"victory":victory,"hp":hp,"gear":gear}

func first_battle(seed_value: int) -> HeroHubState:
	var hub := step(HeroHubState.create(seed_value),"start")
	return step(hub,"choose",{"node":hub.expedition.available_nodes()[0]})

func run() -> void:
	var hub := first_battle(88123)
	var battle_start := hub.to_dict()
	var outcome := receipt(hub)
	hub = step(hub,"outcome",outcome)
	check(hub.battle_report.open and hub.expedition.phase == "reward", "saved report opens before reward choice")
	check(hub.achievements.total_points == 10 and hub.achievements.available_points == 10, "first victory and no casualties give points once")
	check(hub.achievements.count_for("first_victory") == 1, "profile progress counts one victory")
	for row: Dictionary in hub.battle_report.heroes:
		if row.participated:
			check(row.xp_after - row.xp_before == 1000 and row.hp_restored == floorf(row.hp_max * 0.1), "participant XP and ten percent actual restoration")
			check(is_equal_approx((hub.heroes[row.id] as HeroProgression).hp_current,row.hp_after_recovery),"report matches restored live profile HP")
		else: check(row.xp_after - row.xp_before == 100 and row.hp_restored == 0.0,"reserve XP and no reserve restoration")
	var saved := hub.to_dict()
	check(not ExpeditionTransitions.apply(hub,"outcome",outcome).is_ok() and hub.to_dict() == saved,"duplicate outcome cannot heal or award again")
	var hero_id: int = hub.party[0]
	var quote := PostBattleRules.repair_quote(hub,hero_id)
	check(quote.amount == 10 and quote.cost == 20 and quote.affordable,"repair quotes ten armor at two gold each")
	check(hub.repair_after_battle(hero_id),"paid repair accepted")
	check(hub.expedition.gold == 20 and hub.expedition.repair_spent == 20 and hub.items[quote.item_id].remaining == quote.after,"repair updates item and expense ledger")
	quote = PostBattleRules.repair_quote(hub,hero_id)
	check(quote.amount == 2 and quote.cost == 4 and hub.repair_after_battle(hero_id),"near-full armor charges only restored amount")
	saved = hub.to_dict()
	check(not hub.repair_after_battle(hero_id) and hub.to_dict() == saved,"full armor refusal does not spend")
	check(not hub.repair_after_battle(hub.party[1]) and hub.to_dict() == saved,"unaffordable repair does not mutate")
	check(not hub.dismiss_battle_report(),"reward choice required before Continue")
	var roundtrip := HeroHubState.from_dict(saved)
	check(roundtrip != null and roundtrip.to_dict() == saved,"paid ledger survives restore")
	var corrupt := saved.duplicate(true); corrupt.expedition.gold += 1
	check(HeroHubState.from_dict(corrupt) == null,"unexplained gold rejected even with repair ledger")
	corrupt = saved.duplicate(true); corrupt.expedition.repair_spent = -1
	check(HeroHubState.from_dict(corrupt) == null,"negative repair expense rejected")
	corrupt = saved.duplicate(true); corrupt.achievements.total_points += 1
	check(HeroHubState.from_dict(corrupt) == null,"invented achievement points rejected")
	corrupt = saved.duplicate(true); corrupt.achievements.unlocked.append("first_victory")
	check(HeroHubState.from_dict(corrupt) == null,"duplicate achievement rejected")
	corrupt = saved.duplicate(true); corrupt.battle_report.heroes[0].hp_restored = NAN
	check(HeroHubState.from_dict(corrupt) == null,"nonfinite report rejected")
	hub = step(hub,"reward",{"index":0})
	check(hub.battle_report.open and not hub.battle_report.artifact_selected.is_empty(),"artifact recorded with report still open")
	check(hub.dismiss_battle_report() and not hub.dismiss_battle_report(),"Continue is one-time and leaves rewards unchanged")
	check(not hub.repair_after_battle(hub.party[1]),"repair not available after leaving result")
	var disk := "user://postbattle/roundtrip.save"
	check(HeroHubStore.write_run(disk,hub).is_empty(),"save report and achievement profile")
	var loaded := HeroHubStore.read_run(disk)
	check(loaded.error.is_empty() and not loaded.migrated and loaded.run.to_dict() == hub.to_dict(),"reload current schema without reawarding")
	check(not HeroHubStore.write_run("user://postbattle/roundtrip.save/blocked",hub).is_empty(),"failed save reports failure")
	check(HeroHubStore.read_run(disk).run.to_dict() == hub.to_dict(),"failed write leaves committed result intact")
	_migration(battle_start)
	_losses_and_final()
	_legacy()
	print("EXPEDITION POSTBATTLE RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _migration(current: Dictionary) -> void:
	var old := current.duplicate(true)
	old.schema = 2; old.erase("achievements"); old.erase("battle_report")
	old.expedition.schema = 1; old.expedition.erase("repair_spent")
	check(HeroHubState.from_dict(old) == null,"schema2 profile is refused without migration")
	var path := "user://postbattle/v2.save"
	var payload := var_to_bytes(old)
	var bytes := var_to_bytes({"format":"hero-hub-v2","payload":payload,"sha256":HeroHubStore._digest(payload)})
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
	var loaded := HeroHubStore.read_run(path)
	check(loaded.run == null and not loaded.error.is_empty(),"v2 envelope is explicitly refused")
	check(FileAccess.get_file_as_bytes(path) == bytes,"refused v2 file remains byte-exact")

func _losses_and_final() -> void:
	var hub := first_battle(88124)
	var dead_id: int = hub.party[0]
	hub = step(hub,"outcome",receipt(hub,true,dead_id))
	check(hub.achievements.total_points == 5 and not hub.heroes.has(dead_id),"casualty is not revived and prevents no-loss achievement")
	var dead: Dictionary = hub.battle_report.heroes[0]
	check(not dead.alive and dead.hp_restored == 0.0 and dead.xp_after == dead.xp_before,"dead hero gets neither recovery nor XP")
	hub = step(hub,"reward",{"index":0})
	while hub.expedition.phase != "battle":
		if hub.expedition.phase == "route": hub = step(hub,"choose",{"node":hub.expedition.available_nodes()[0]})
		elif hub.expedition.phase == "service": hub = step(hub,"service",{"kind":"heal"})
		else: hub = step(hub,"continue")
	var gold_lost := hub.expedition.gold
	hub = step(hub,"outcome",receipt(hub,false))
	check(hub.phase == "hub" and hub.battle_report.open and not hub.battle_report.victory,"defeat shows persistent summary in hub")
	check(hub.battle_report.gold_lost == gold_lost and hub.achievements.total_points == 5 and hub.battle_report.points_awarded == 0,"defeat loses run gold but keeps prior achievement points")
	check(not hub.repair_after_battle(dead_id),"defeat cannot repair or resurrect")
	hub = HeroHubState.create(88125)
	hub = step(hub,"start")
	var guard: int = 30
	while hub.phase == "expedition" and guard > 0:
		guard -= 1
		match hub.expedition.phase:
			"route": hub = step(hub,"choose",{"node":hub.expedition.available_nodes()[0]})
			"battle": hub = step(hub,"outcome",receipt(hub))
			"reward": hub = step(hub,"reward",{"index":0})
			"service": hub = step(hub,"service",{"kind":"repair"})
			"camp_departure": hub = step(hub,"continue")
	check(hub.phase == "hub" and hub.battle_report.completed and hub.battle_report.open,"final win has summary after automatic return")
	check(hub.achievements.unlocked.has("first_expedition") and hub.battle_report.achievements.has("first_expedition"),"first expedition grants permanent achievement")
	check(hub.battle_report.gold_scope == "hub" and hub.battle_report.gold_awarded == 180 and hub.battle_report.essence_awarded >= 10,"final summary distinguishes banked rewards and essence")
	var progress := ProfileAchievements.new()
	for index: int in 5: progress.record(true,false,false)
	check(progress.unlocked.has("five_victories") and progress.total_points == 15,"fifth victory threshold grants exactly once")
	progress.record(true,false,false)
	check(progress.total_points == 15 and ProfileAchievements.from_dict(progress.to_dict()) != null,"later wins do not repeat rewards")

func _legacy() -> void:
	var hub := HeroHubState.create(88126)
	check(hub.start_battle(),"legacy battle starts")
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for id: int in hub.party: hp[id] = float((hub.heroes[id] as HeroProgression).max_hp() - 1)
	for id: int in hub.battle_items(): gear[id] = maxi(0,HeroGearCatalog.definition(hub.items[id].definition).armor_max - 2)
	check(hub.finish_battle(hub.run_serial,true,hp,gear),"legacy battle uses postbattle result")
	for row: Dictionary in hub.battle_report.heroes:
		if row.participated: check(row.hp_restored == 1.0 and row.hp_after_recovery == row.hp_max,"recovery caps at max HP")
	check(hub.achievements.total_points == 10 and hub.battle_report.source == "legacy","same profile achievement subsystem in legacy H1")
	check(hub.repair_after_battle(hub.party[0]) and hub.gold == 136,"legacy repair pays bank gold")
	check(HeroHubState.from_dict(hub.to_dict()) != null,"legacy postbattle profile validates")
