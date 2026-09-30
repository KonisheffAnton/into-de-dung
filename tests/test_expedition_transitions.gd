extends SceneTree

var passed: int = 0
var failed: int = 0
var profile: HeroHubState

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL EXPEDITION TRANSITIONS: " + label)

func step(action: String, args: Dictionary = {}) -> bool:
	var before := profile.to_dict()
	var result := ExpeditionTransitions.apply(profile,action,args)
	check(profile.to_dict() == before,"transition is copy-on-write " + action)
	check(result.is_ok(),"accept " + action + ": " + result.reason)
	if result.is_ok():
		profile = result.profile
		var restored := HeroHubState.from_dict(profile.to_dict())
		check(restored != null and restored.to_dict() == profile.to_dict(),"restore phase " + (profile.expedition.phase if profile.expedition != null else profile.phase))
	return result.is_ok()

func reject(action: String, args: Dictionary = {}) -> void:
	var before := profile.to_dict()
	check(not ExpeditionTransitions.apply(profile,action,args).is_ok() and profile.to_dict() == before,"atomic reject " + action)

func receipt(dead: Array[int] = []) -> Dictionary:
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for id: int in profile.party: hp[id] = 0.0 if dead.has(id) else minf(12.0,(profile.heroes[id] as HeroProgression).max_hp())
	for item: Dictionary in profile.expedition.checkpoint.items: gear[item.id] = mini(7,int(item.remaining))
	return {"run_id":profile.run_serial,"node_id":profile.expedition.current_node().id,"serial":profile.expedition.battle_serial,"victory":dead.size() < profile.party.size(),"hp":hp,"gear":gear}

func _run() -> void:
	profile = HeroHubState.create(919)
	var initial := profile.to_dict(); var hire_rng := profile.rng_state
	(profile.heroes[profile.party[0]] as HeroProgression).hp_current = 1.0
	step("start")
	check(profile.rng_state == hire_rng,"independent hire RNG")
	check((profile.heroes[profile.party[0]] as HeroProgression).hp_current == (profile.heroes[profile.party[0]] as HeroProgression).max_hp(),"hub heals once")
	var original_plan := profile.expedition.plan.duplicate(true)
	reject("choose",{"node":14}); reject("choose",{"node":true}); reject("leave")
	step("choose",{"node":profile.expedition.available_nodes()[0]})
	var first := receipt(); var bad := first.duplicate(true); bad.serial += 1
	reject("outcome",bad); bad = first.duplicate(true); bad.hp.erase(profile.party[0]); reject("outcome",bad)
	step("outcome",first); reject("outcome",first); reject("choose",{"node":3})
	var xp_after: int = (profile.heroes[profile.party[0]] as HeroProgression).xp_tenths
	check(xp_after == 1000,"victory XP immediate")
	step("reward",{"index":0}); reject("reward",{"index":0})
	check(profile.expedition.plan == original_plan,"all choices pre-generated, no reroll")
	var artifact_id: int = profile.expedition.artifacts[0].id
	step("artifact_equip",{"item":artifact_id,"hero":profile.party[0],"slot":1})
	step("artifact_unequip",{"item":artifact_id,"hero":0,"slot":0})
	var worn := profile.equipped(profile.party[0],"armor"); var armor_id: int = worn.id
	step("unequip",{"item":armor_id,"hero":0})
	check(profile.items[armor_id].remaining == 7,"unequip does not repair")
	var reserve_id: int = int(initial.heroes[3].id)
	reject("equip",{"item":armor_id,"hero":reserve_id})
	_walk_to_camp()
	var copies := profile.expedition.next_artifact_id - 1
	var loot := profile.expedition.gold
	step("leave")
	check(profile.phase == "hub" and profile.gold == 100 + loot and profile.essence == copies * 10,"camp banks gold and copies exactly once")
	reject("leave")
	check(profile.items.has(armor_id),"unequipped run gear survives exit")
	_merge_rules()
	_death_and_defeat()
	_migration()
	_content_restore()
	print("EXPEDITION TRANSITIONS RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _content_restore() -> void:
	var started := ExpeditionTransitions.apply(HeroHubState.create(77),"start").profile
	var raw := started.to_dict()
	raw.expedition.plan.content.encounters[0].enemy_hp += 1
	check(HeroHubState.from_dict(raw) == null,"profile refuses different saved content")
	var path := "user://u14-content-%d.save" % Time.get_ticks_usec()
	var payload := var_to_bytes(raw)
	var bytes := var_to_bytes({"format":"hero-hub-v2","payload":payload,"sha256":HeroHubStore._digest(payload)})
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(bytes); file.close()
	var restored := HeroHubStore.read_run(path)
	check(restored.run == null and restored.error.contains("каталога"),"store returns explicit content refusal")
	check(FileAccess.get_file_as_bytes(path) == bytes,"refused content file remains byte-exact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _walk_to_camp() -> void:
	for unused: int in 10:
		if profile.expedition.phase == "camp_departure": return
		match profile.expedition.phase:
			"route": step("choose",{"node":profile.expedition.available_nodes()[0]})
			"battle": step("outcome",receipt())
			"reward": step("reward",{"index":0})
			"service":
				step("service",{"kind":"repair"})
				reject("service",{"kind":"repair"})
	check(false,"reach camp")

func _merge_rules() -> void:
	profile = HeroHubState.create(914)
	step("start")
	# Выбираем законный маршрут с четырьмя победами; награды заменены допустимым детерминированным каталогом fixture.
	for node: Dictionary in profile.expedition.plan.nodes:
		if node.kind in ["battle","elite"]: node.reward = ["spark","blood","ice"]
	for unused: int in 16:
		if profile.expedition.next_artifact_id == 5: break
		match profile.expedition.phase:
			"route":
				var choice: int = profile.expedition.available_nodes()[0]
				for id: int in profile.expedition.available_nodes():
					if profile.expedition.plan.nodes[id - 1].kind in ["battle","elite"]: choice = id; break
				step("choose",{"node":choice})
			"battle": step("outcome",receipt())
			"reward": step("reward",{"index":0})
			"service": step("service",{"kind":"heal"})
			"camp_departure": step("continue")
	check(profile.expedition.next_artifact_id == 5,"four copies earned")
	var four_copies := profile.to_dict()
	step("artifact_merge",{"item":2,"target":1})
	step("artifact_merge",{"item":3,"target":1})
	check(profile.expedition.artifact(1).stacks == 3,"1+1 then 2+1 yields cap three")
	reject("artifact_merge",{"item":4,"target":1})
	profile = HeroHubState.from_dict(four_copies)
	step("artifact_merge",{"item":2,"target":1})
	step("artifact_merge",{"item":4,"target":3})
	reject("artifact_merge",{"item":3,"target":1})
	step("artifact_equip",{"item":1,"hero":profile.party[0],"slot":1})
	reject("artifact_equip",{"item":3,"hero":profile.party[0],"slot":2})
	step("artifact_equip",{"item":1,"hero":profile.party[1],"slot":2})
	check(profile.expedition.artifact(1).stacks == 2 and profile.expedition.artifact(1).hero_id == profile.party[1],"whole merged item transfers")
	var invalid := profile.to_dict(); invalid.expedition.artifacts[0].stacks = 4
	check(HeroHubState.from_dict(invalid) == null,"cap enforced on load")
	invalid = profile.to_dict(); invalid.expedition.gold += 1
	check(HeroHubState.from_dict(invalid) == null,"loot matches resolved route")

func _death_and_defeat() -> void:
	profile = HeroHubState.create(719)
	step("start"); step("choose",{"node":1})
	var dead: int = profile.party[0]; var protected_id: int = profile.equipped(dead,"armor").id
	step("outcome",receipt([dead])); step("reward",{"index":0})
	check(profile.items[protected_id].hero_id == 0 and not profile.expedition.ordinary_item_ids.has(protected_id),"fallen winner gear protected in warehouse")
	var lost_id: int = profile.equipped(profile.party[0],"armor").id
	step("unequip",{"item":lost_id,"hero":0})
	reject("equip",{"item":protected_id,"hero":profile.party[0]})
	for unused: int in 4:
		step("choose",{"node":profile.expedition.available_nodes()[0]})
		if profile.expedition.phase == "battle": break
		if profile.expedition.phase == "service": step("service",{"kind":"heal"})
		if profile.expedition.phase == "camp_departure": step("continue")
	step("outcome",receipt(profile.party.duplicate()))
	check(profile.phase == "hub" and profile.gold == 100 and profile.essence == 0,"defeat loses unbanked loot")
	check(profile.items.has(protected_id) and not profile.items.has(lost_id),"warehouse safe, unequipped expedition gear lost")
	check(profile.party.is_empty() and profile.heroes.size() == 1,"reserve survives")
	check((profile.heroes.values()[0] as HeroProgression).xp_tenths == 100,"earlier reserve XP retained")

func _migration() -> void:
	var legacy := HeroHubState.create(87)
	for battle: bool in [false,true]:
		if battle: legacy.start_battle()
		var data := legacy.to_dict(); data.schema = 1
		for key: String in ["essence","expedition_rng_state","expedition"]: data.erase(key)
		var migrated := HeroHubState.from_dict(data)
		check(migrated != null and migrated.phase == legacy.phase and migrated.expedition == null and migrated.essence == 0 and migrated.rng_state == legacy.rng_state,"schema1 hub/battle migration preserves checkpoint")
		var path := "user://u14-migration-%d.save" % Time.get_ticks_usec()
		var payload := var_to_bytes(data)
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(var_to_bytes({"format":"hero-hub-v1","payload":payload,"sha256":HeroHubStore._digest(payload)})); file.close()
		var loaded := HeroHubStore.read_run(path)
		check(loaded.get("migrated",false) and loaded.run != null,"store reads legacy")
		check(HeroHubStore.write_run(path,loaded.run).is_empty() and not HeroHubStore.read_run(path).get("migrated",true),"store persists v2")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
