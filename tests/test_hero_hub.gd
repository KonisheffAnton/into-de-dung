extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HERO HUB: " + label)

func _run() -> void:
	_roster()
	_full_warehouse()
	_saving()
	_battle()
	print("HERO HUB RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _roster() -> void:
	var hub := HeroHubState.create()
	check(HeroHubState.from_dict(hub.to_dict()) != null, "initial valid profile")
	var candidate := hub.candidates[0].to_dict()
	var gold := hub.gold
	check(hub.hire(0), "free hire")
	check((hub.heroes[candidate.id] as HeroProgression).to_dict() == candidate and hub.gold == gold, "displayed candidate unchanged and free")
	check(hub.candidates[0].id != candidate.id and hub.candidates[0].base_attributes == candidate.base_attributes and hub.candidates[0].perk == StringName(candidate.perk), "always available novice without free reroll")
	var id: int = hub.party[0]
	var hero: HeroProgression = hub.heroes[id]
	hero.award_experience_tenths(1000)
	hero.hp_current = 10.0
	check(hub.allocate(id, [0,0,1,0]) and hero.hp_current == 12.0, "allocated endurance grows current health")
	check(hub.respec(id) and hero.available_points() == 1 and hub.gold == gold - HeroHubState.RESPEC_PRICE, "paid respec returns earned points")
	var before := hub.to_dict()
	check(not hub.respec(id) and hub.to_dict() == before, "empty respec cannot charge")
	var reserve_id: int = hub.heroes.keys().filter(func(value: int) -> bool: return not hub.party.has(value))[0]
	check(hub.start_battle() and hero.hp_current == hero.max_hp(), "start heals living and creates checkpoint")
	var checkpoint := hub.to_dict()
	check(not hub.hire(0) and not hub.respec(id) and not hub.allocate(id,[1,0,0,0]) and hub.to_dict() == checkpoint, "hub mutations locked during battle")
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for actor_id: int in hub.party: hp[actor_id] = float((hub.heroes[actor_id] as HeroProgression).max_hp())
	var dead_id: int = hub.party[1]
	hp[dead_id] = 0.0
	for item_id: int in hub.battle_items(): gear[item_id] = 0
	var malformed := hp.duplicate(); malformed[id] = INF
	check(not hub.finish_battle(hub.run_serial, true, malformed, gear) and hub.to_dict() == checkpoint, "invalid result leaves checkpoint unchanged")
	check(hub.finish_battle(hub.run_serial, true, hp, gear), "commit victory")
	check(not hub.heroes.has(dead_id) and (hub.heroes[reserve_id] as HeroProgression).xp_tenths == 100, "permadeath and reserve share per hero")
	check(hero.xp_tenths == 2000, "survivor receives full encounter reward")
	check(hub.items.values().filter(func(item: Dictionary) -> bool: return item.hero_id == 0).size() == 2, "victory salvages dead hero gear")
	before = hub.to_dict()
	check(not hub.finish_battle(hub.run_serial, true, hp, gear) and hub.to_dict() == before, "outcome cannot award twice")
	check(HeroHubState.from_dict(hub.to_dict()) != null, "post-victory profile reloads")
	check(hub.start_battle(), "second expedition")
	hp.clear(); gear.clear()
	for actor_id: int in hub.party: hp[actor_id] = 0.0
	for item_id: int in hub.battle_items(): gear[item_id] = 0
	var reserved_xp: int = (hub.heroes[reserve_id] as HeroProgression).xp_tenths
	check(hub.finish_battle(hub.run_serial, false, hp, gear), "defeat commits")
	check(hub.party.is_empty() and hub.heroes.has(reserve_id) and (hub.heroes[reserve_id] as HeroProgression).xp_tenths == reserved_xp, "defeat preserves reserve without XP")
	check(hub.items.values().filter(func(item: Dictionary) -> bool: return item.hero_id == 0).size() == 2, "defeat leaves warehouse intact")
	hub.gold = 0
	check(hub.hire(1), "new expedition remains possible with no gold")
	var bad := hub.to_dict(); bad.heroes.append(bad.heroes[0].duplicate(true))
	check(HeroHubState.from_dict(bad) == null, "duplicate hero ID rejected")
	bad = hub.to_dict(); bad.party = [true]
	check(HeroHubState.from_dict(bad) == null, "bool is not a party ID")
	bad = hub.to_dict(); bad.items[0].hero_id = -1
	check(HeroHubState.from_dict(bad) == null, "orphan equipment rejected")
	var copy := HeroHubState.from_dict(hub.to_dict())
	(copy.heroes.values()[0] as HeroProgression).base_attributes[0] += 1
	check(copy.to_dict() != hub.to_dict(), "deep isolated clone")

func _saving() -> void:
	var path := "user://hero-hub-tests-%d.save" % Time.get_ticks_usec()
	var fresh := HeroHubStore.read_run(path).run as HeroHubState
	var another := HeroHubStore.read_run(path + "-new").run as HeroHubState
	check(fresh != null and another != null and fresh.rng_state != another.rng_state, "new production profiles receive independent generation seeds")
	var hub := HeroHubState.create()
	check(HeroHubStore.write_run(path,hub).is_empty(), "atomic initial save")
	var loaded := HeroHubStore.read_run(path)
	check(loaded.error.is_empty() and loaded.run.to_dict() == hub.to_dict(), "profile exact disk round trip")
	check(not HeroHubStore.write_run(path + "/cannot-write",hub).is_empty(), "failed write is reported")
	check(HeroHubStore.read_run(path).run.to_dict() == hub.to_dict(), "failed write preserves prior file")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(var_to_bytes({"format":"hero-hub-v1","payload":PackedByteArray([1]),"sha256":"corrupt"})); file.close()
	loaded = HeroHubStore.read_run(path)
	check(loaded.run == null and not loaded.error.is_empty(), "corruption does not silently create a new roster")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_rejected_files_are_untouched()
	for catalog: int in [1, 2]:
		for with_deck: bool in [false, true]:
			var profile := HeroHubState.create(8120 + catalog, catalog)
			if with_deck: profile.enable_mage_deck()
			var roundtrip_path := "user://hero-hub-v6-%d-%s.save" % [catalog, str(with_deck)]
			check(HeroHubStore.write_run(roundtrip_path, profile).is_empty(), "schema6 saves catalog/deck combination")
			var envelope_file := FileAccess.open(roundtrip_path, FileAccess.READ)
			var envelope: Variant = bytes_to_var(envelope_file.get_buffer(envelope_file.get_length()))
			envelope_file.close()
			check(envelope.format == "hero-hub-v6" and envelope.payload is PackedByteArray and envelope.sha256 == HeroHubStore._digest(envelope.payload), "schema6 envelope and checksum")
			var profile_loaded := HeroHubStore.read_run(roundtrip_path, not with_deck)
			check(profile_loaded.error.is_empty() and not profile_loaded.migrated and profile_loaded.run.to_dict() == profile.to_dict(), "schema6 roundtrip ignores read deck mode")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(roundtrip_path))

func _rejected_files_are_untouched() -> void:
	var path := "user://hero-hub-reject-%d.save" % Time.get_ticks_usec()
	var schema6 := HeroHubState.create(991).to_dict()
	var old_payload := var_to_bytes({"schema":5})
	var cases: Array[Dictionary] = []
	for version: int in range(1, 6):
		cases.append({"format":"hero-hub-v%d" % version,"payload":old_payload,"sha256":HeroHubStore._digest(old_payload)})
	cases.append({"format":"hero-hub-v7","payload":var_to_bytes(schema6),"sha256":HeroHubStore._digest(var_to_bytes(schema6))})
	var mismatch := var_to_bytes(schema6); schema6.schema = 5
	cases.append({"format":"hero-hub-v6","payload":var_to_bytes(schema6),"sha256":HeroHubStore._digest(var_to_bytes(schema6))})
	var valid_payload := var_to_bytes(HeroHubState.create(992).to_dict())
	cases.append({"format":"hero-hub-v6","payload":valid_payload,"sha256":"bad-checksum"})
	for index: int in cases.size():
		var bytes := var_to_bytes(cases[index])
		var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()
		var backup := FileAccess.open(path + ".bak", FileAccess.WRITE); backup.store_buffer(PackedByteArray([7,8,9])); backup.close()
		var temp := FileAccess.open(path + ".tmp", FileAccess.WRITE); temp.store_buffer(PackedByteArray([4,5,6])); temp.close()
		var result := HeroHubStore.read_run(path, true)
		check(result.run == null and not result.error.is_empty(), "reject old/future/mismatch/checksum envelope %d" % index)
		check(FileAccess.get_file_as_bytes(path) == bytes and FileAccess.get_file_as_bytes(path + ".bak") == PackedByteArray([7,8,9]) and FileAccess.get_file_as_bytes(path + ".tmp") == PackedByteArray([4,5,6]), "rejection preserves save and sentinels %d" % index)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))

func _full_warehouse() -> void:
	var hub := HeroHubState.create()
	check(not hub.discard_item(int(hub.items.keys()[0])), "equipped item cannot be discarded")
	hub.heroes.clear(); hub.party.clear(); hub.items.clear(); hub.gold = 0
	for id: int in range(1, HeroHubState.MAX_ITEMS + 1):
		hub.items[id] = {"id":id,"definition":"armor:warrior","hero_id":0,"remaining":0}
	hub.next_item_id = HeroHubState.MAX_ITEMS + 1
	check(HeroHubState.from_dict(hub.to_dict()) != null and not hub.hire(0), "full warehouse with no heroes remains a valid profile")
	check(hub.discard_item(1) and hub.discard_item(2) and hub.hire(0) and hub.gold == 0, "discarding warehouse items restores free hire at capacity")
	check(HeroHubState.from_dict(hub.to_dict()) != null, "capacity recovery preserves stable item IDs")

func _battle() -> void:
	var hub := HeroHubState.create()
	hub.party = [1,2,4]
	check(hub.start_battle(), "mixed party starts")
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(), "build real battle from permanent roster")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	check(session.is_deploying() and session.living_ids(Faction.Type.PLAYER).size() == 3, "real deployment and selected party")
	check(BattleExecutionWorker.can_transfer(session), "battle runtime owns no hub references")
	check(HeroHubBattleFactory.outcome(bundle).is_empty(), "no early award during deployment")
	var mage_id: int = bundle.hero_units[4]
	var archer_id: int = bundle.hero_units[2]
	var mage := session.board.get_unit_by_id(mage_id)
	check(mage.armor.natural.fire == (hub.heroes[4] as HeroProgression).fire_resistance(), "intellect projected as natural fire resistance")
	check(session.board.get_unit_by_id(archer_id).get_stat(StatTypes.StatType.ATTACK_RANGE) == 4.0, "archer uses existing ranged geometry")
	check(session.start_battle(), "deployment starts enemy turn")
	var guard: int = 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and guard < 20:
		session.step_enemy(); guard += 1
	check(session.can_player_act(), "real enemy phase reaches player")
	if session.can_player_act():
		session.select_unit(mage_id)
		check(session.healing_item() != null, "hero-specific might-scaled healing item")
		check(session.cast_reason(&"wet") == &"", "mage elemental ability available")
		var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
		# Test setup only: put a real target within range before comparing real commands.
		session.board.move_unit(target, mage.cell + Vector2i(1,0))
		var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
		var preview := session.preview_attack(target.id)
		check(preview.status == ActionReceipt.APPLIED, "mage fire attack forecasts")
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before, "preview isolated from live")
		var receipt := session.attack_unit(target.id)
		check(receipt.status == ActionReceipt.APPLIED, "mage fire attack executes")
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == preview.snapshot_after and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps and session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after, "mage attack full preview/live parity")
		session.select_unit(archer_id)
		check(session.cast_reason(&"wet") != &"", "archer cannot cast mage class spell")
		var archer := session.selected_unit()
		archer.vitals.set_hp(1.0)
		var healing := session.preview_healing_item()
		check(healing.status == ActionReceipt.APPLIED and archer.vitals.get_hp() == 1.0, "hero flask preview isolated")
		var healing_receipt := session.use_healing_item()
		check(healing_receipt.status == ActionReceipt.APPLIED and archer.vitals.get_hp() == 5.0 + (hub.heroes[2] as HeroProgression).attributes()[0], "hero flask heals exactly 4 plus Might")
		check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == healing.snapshot_after and healing_receipt.get_events() == healing.events and healing_receipt.get_steps() == healing.steps and session.context.get_rng().to_dict() == healing.rng_after and session.context.simulation_counters() == healing.counters_after, "hero flask full preview/live parity")
		var forecast := TurnForecast.build(session)
		check(forecast.status == ActionReceipt.APPLIED and not session.actor_loadouts.is_empty(), "turn forecast supports class loadouts")
		check(session.end_player_turn() and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == forecast.snapshot_after and session.context.get_rng().to_dict() == forecast.rng_after and session.context.simulation_counters() == forecast.counters_after, "H1 turn boundary full preview/live parity")
	# Finish through commands, then consume the actual battle outcome.
	for id: int in session.living_ids(Faction.Type.ENEMY):
		session._submit(DeathCommand.new(id, DamageSource.new(&"test",0,Vector2i.ZERO)))
	var outcome := HeroHubBattleFactory.outcome(bundle)
	check(not outcome.is_empty() and outcome.victory, "complete outcome after command queue")
	if not outcome.is_empty(): check(hub.finish_battle(outcome.serial,outcome.victory,outcome.hp,outcome.gear), "actual outcome accepted by persistent model")
	session.close()
