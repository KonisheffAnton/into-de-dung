extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CLASS SHOWCASE: " + label)

func _run() -> void:
	var old := HeroHubState.create(7781, 3)
	var fresh := HeroHubState.create(7781, 4)
	check(old.party == [1, 2, 3] and fresh.party == [3, 4, 5], "newest three only in new catalog")
	check(fresh.rng_state == old.rng_state and fresh.expedition_rng_state == old.expedition_rng_state, "catalog policy does not consume either RNG")
	for id: int in old.heroes: check(old.heroes[id].to_dict() == fresh.heroes[id].to_dict(), "same generated hero " + str(id))
	check(old.items == fresh.items and old.candidates.size() == fresh.candidates.size(), "same gear and candidate count")
	for index: int in old.candidates.size(): check(old.candidates[index].to_dict() == fresh.candidates[index].to_dict(), "same candidate " + str(index))
	for version: int in [1, 2, 3, 4]:
		var profile := HeroHubState.create(441, version)
		check(HeroHubState.from_dict(profile.to_dict()).to_dict() == profile.to_dict(), "roundtrip catalog " + str(version))
	check(ClassShowcaseRoster.enemies(fresh) == [&"shieldbearer", &"archer"], "only missing classes go to enemy without filler")
	check(ClassShowcaseRoster.enemies(old).is_empty(), "legacy enemy policy untouched")
	check(not HeroCatalog.class_ids(4).has(&"sick_hobgoblin"), "enemy archetype is excluded from the hero catalog")
	for version: int in [1, 2, 3]:
		var legacy := HeroHubState.create(441, version)
		check(legacy.start_battle(), "legacy battle starts without catalog migration")
		var saved := legacy.to_dict()
		var bundle := HeroHubBattleFactory.create(legacy)
		check(not bundle.is_empty(), "legacy battle factory remains available")
		if not bundle.is_empty():
			var legacy_session: BattleCoreReactionsSession = bundle.session
			for unit: UnitState in legacy_session.units:
				if unit.faction == Faction.Type.ENEMY:
					check(unit.stats.get_value(StatTypes.StatType.BALANCE_MAX) == float(ExpeditionCatalog.encounter("battle", 0).enemy_balance), "legacy authored enemy threshold remains unchanged")
			legacy_session.close()
		check(legacy.to_dict() == saved, "factory does not migrate catalog or saved profile")
	var authored: Array[Vector2i] = [Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3)]
	check(ClassShowcaseRoster.cells(authored, 2, {}, Vector2i(8, 8)) == authored.slice(0, 2), "unused old enemy cell removed")
	for mode: int in 3:
		var profile := HeroHubState.create(876, 4)
		if mode == 1:
			profile.party.assign([1])
		elif mode == 2:
			profile.party.assign([5])
		profile.enable_mage_deck()
		var transition := ExpeditionTransitions.apply(profile, "start")
		check(transition.is_ok(), "start deck showcase " + str(mode))
		if not transition.is_ok(): continue
		profile = transition.profile
		var before := profile.to_dict()
		var counter := UnitId.get_counter()
		var bundle := HeroHubBattleFactory.create(profile)
		check(not bundle.is_empty(), "build showcase " + str(mode))
		if bundle.is_empty(): continue
		var session: BattleCoreReactionsSession = bundle.session
		check(session.units.size() == 7 and session.actor_loadouts.size() == 7, "five hero classes and two named monster actors, without anonymous filler")
		check(session.living_ids(Faction.Type.ENEMY).size() == 7 - profile.party.size(), "enemy count follows absent classes and two named monsters")
		check(not "\n".join(session.flow_log).contains("Страж, Щит, Дозорный"), "opening text names actual class opponents")
		var classes: Array[StringName] = []
		var hobgoblin_count := 0
		var occupied: Array[Vector2i] = []
		for unit: UnitState in session.units:
			var class_id: StringName = session.actor_loadouts.get(unit.id, {}).get("class_id", &"")
			classes.append(class_id)
			check(not occupied.has(unit.cell) and session.board.get_terrain(unit.cell) == TerrainType.Type.FLOOR, "safe unique cell")
			occupied.append(unit.cell)
			if unit.faction == Faction.Type.PLAYER:
				for hero_id: int in bundle.hero_units:
					if bundle.hero_units[hero_id] == unit.id:
						var hero: HeroProgression = profile.heroes[hero_id]
						check(unit.stats.get_value(StatTypes.StatType.BALANCE_MAX) == float(hero.balance_max()), "player uses endurance threshold plus perk from saved progression")
			if unit.faction != Faction.Type.ENEMY: continue
			if class_id == &"sick_hobgoblin":
				hobgoblin_count += 1
				check(session.actor_loadouts[unit.id].attack_id == MageDeckRules.hero_attack_id(unit.id), "hobgoblin uses its own strike loadout")
				check(session.unit_visual_classes.get(unit.id) == &"sick_hobgoblin", "hobgoblin uses its own enemy visual class")
				continue
			if class_id == TroglodyteKit.ID: continue
			check(unit.stats.get_value(StatTypes.StatType.BALANCE_MAX) == 5.0, "current class enemy base balance is five")
			check(session.unit_visual_classes.get(unit.id) == class_id, "real enemy class matches visual")
			check(session.context.get_attack_rules().get_definition(session.actor_loadouts[unit.id].attack_id) != null, "enemy has actual attack loadout")
			if class_id == &"shieldbearer": check(unit.combat_perks.definition.passive_opportunist and not unit.armor.raised_shield.is_empty(), "enemy shieldbearer capabilities")
			if class_id == &"fighter": check(not unit.combat_perks.warrior.is_empty(), "enemy fighter capability")
			if class_id == &"rogue": check(unit.combat_perks.definition.sneak_attack, "enemy rogue capability")
			if class_id == &"archer": check(unit.stats.get_value(StatTypes.StatType.ATTACK_RANGE) == 4.0, "enemy archer range")
		for class_id: StringName in HeroCatalog.class_ids(4): check(classes.count(class_id) == 1, "exactly one of every class visible: " + String(class_id))
		check(hobgoblin_count == 1, "exactly one sick hobgoblin appears separately from hero classes")
		var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
		var rng := session.context.get_rng().to_dict()
		session.close()
		UnitId.set_counter(counter)
		var repeated := HeroHubBattleFactory.create(HeroHubState.from_dict(profile.to_dict()))
		check(not repeated.is_empty(), "restore same saved plan")
		if not repeated.is_empty():
			var restored: BattleCoreReactionsSession = repeated.session
			check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == snapshot and restored.context.get_rng().to_dict() == rng, "same checkpoint battle and RNG")
			restored.close()
		check(profile.to_dict() == before, "factory leaves stored plan and profile unchanged")
	_test_temporary_player_defeat()
	_test_showcase_bt()
	var crowded := ClassShowcaseRoster.cells([], 40, ExpeditionOpening.values(), BiomeShowcaseLayout.SIZE)
	check(crowded.size() == 40, "future class growth uses safe enemy cells")
	var terrain := BattleBoard.new(24, 16)
	for tile: Dictionary in ExpeditionOpening.values().terrain: terrain.set_terrain(ExpeditionOpening.cell(tile.cell), int(tile.type) as TerrainType.Type)
	BiomeShowcaseLayout.apply(terrain, true)
	for cell: Vector2i in crowded: check(terrain.get_terrain(cell) == TerrainType.Type.FLOOR, "extra cell avoids actual biome obstacles")
	print("CLASS SHOWCASE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _showcase_session() -> Dictionary:
	var profile := HeroHubState.create(8127, 4)
	profile.party.assign([3])
	check(profile.start_battle(), "catalog4 showcase enters battle")
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "catalog4 showcase factory creates action fixture")
	if bundle.is_empty(): return {}
	var session: BattleCoreReactionsSession = bundle.session
	check(session.start_battle(), "showcase starts real tactical session")
	for y: int in session.board.height:
		for x: int in session.board.width: session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	# Перекладываем всех участников в свободный ряд, чтобы команда проверяла именно
	# боевую способность, а не исходную расстановку или террейн конкретного плана.
	var park_x: int = 0
	for unit: UnitState in session.board.get_alive_units():
		var parking := Vector2i(park_x, session.board.height - 1)
		park_x += 1
		if unit.cell != parking:
			check(session.board.move_unit(unit, parking), "showcase fixture stages unit through board")
	return {"session": session, "bundle": bundle}

func _position_showcase_actor(session: BattleCoreReactionsSession, class_id: StringName) -> UnitState:
	var actor: UnitState = null
	for unit: UnitState in session.board.get_alive_units():
		if unit.faction == Faction.Type.ENEMY and session.actor_loadouts.get(unit.id, {}).get("class_id", &"") == class_id:
			actor = unit
			break
	var player: UnitState = null
	for unit: UnitState in session.board.get_alive_units():
		if unit.faction == Faction.Type.PLAYER: player = unit; break
	if actor == null or player == null: return null
	check(session.board.move_unit(player, Vector2i(2, 2)), "showcase target positioned through board")
	check(session.board.move_unit(actor, Vector2i(3, 2)), "showcase enemy positioned through board")
	session._enemy_ids = [actor.id]
	session._enemy_index = 0
	session._enemy_actions = 0
	return actor

func _test_temporary_player_defeat() -> void:
	var fixture := _showcase_session()
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var permanent: UnitState = null
	for unit: UnitState in session.board.get_alive_units():
		if unit.faction == Faction.Type.PLAYER and session.actor_loadouts.has(unit.id): permanent = unit
	if permanent == null:
		check(false, "fixture has permanent player loadout")
		session.close()
		return
	var temporary := UnitState.from_snapshot_dict(permanent.to_snapshot_dict())
	if temporary == null:
		check(false, "temporary player fixture clones valid unit snapshot")
		session.close()
		return
	temporary.id = UnitId.next()
	temporary.faction = Faction.Type.PLAYER
	temporary.debug_name = "Временный помощник без набора"
	temporary.cell = Vector2i(0, 1)
	check(session.board.add_unit(temporary), "temporary player joins through board without loadout")
	session.units.append(temporary)
	# set_hp используется загрузчиком и сам не меняет флаг жизни.
	permanent.vitals.apply_damage(permanent.vitals.get_hp())
	session._check_outcome()
	check(session.phase == BattleTacticalSession.Phase.DEFEAT, "living temporary player and enemy loadouts do not prevent permanent-party defeat")
	var live_enemy_loadouts := true
	for enemy_id: int in session.living_ids(Faction.Type.ENEMY):
		if not session.actor_loadouts.has(enemy_id): live_enemy_loadouts = false
	check(temporary.is_alive() and not session.actor_loadouts.has(temporary.id) and live_enemy_loadouts, "defeat fixture retains live temporary without loadout and live enemy loadouts")
	session.close()

func _test_showcase_bt() -> void:
	_test_showcase_attack(&"mage", &"mage-personal", false, false)
	_test_showcase_attack(&"fighter", WarriorKit.CLEAVE, false, false)
	_test_showcase_attack(&"fighter", &"fighter-cooldown-fallback", true, false)
	_test_showcase_raise_shields()
	_test_showcase_attack(&"archer", &"entangling_strike", false, false)
	_test_showcase_attack(&"archer", &"archer-immune-fallback", false, true)

func _test_showcase_attack(class_id: StringName, expected: StringName, cooldown: bool, immune: bool) -> void:
	var fixture := _showcase_session()
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actor := _position_showcase_actor(session, class_id)
	if actor == null:
		check(false, "showcase has " + String(class_id) + " actor")
		session.close()
		return
	var target: UnitState = session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[0])
	if expected == &"entangling_strike":
		# Контроль требует потери HP; броня и последующий push не должны скрыть эту проверку.
		target.stats.set_base_value(StatTypes.StatType.HP_MAX, 500.0)
		target.vitals.set_hp(500.0)
		target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1000.0)
		target.armor.natural.physical = 0
		for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
		actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	if immune: target.combat_perks.definition.entangle_immune = true
	if cooldown: actor.combat_perks.warrior.ready_turn = session.state.abilities.serials[Faction.Type.ENEMY] + 20
	var selected := BattleDemoBT.new().decide(session, actor)
	var expected_id: StringName = StringName(session.actor_loadouts[actor.id].attack_id)
	var label := String(class_id) + " BT "+ String(expected)
	if expected == &"mage-personal":
		var attack_id: StringName = session.actor_loadouts[actor.id].attack_id
		var definition := session.context.get_attack_rules().get_definition(attack_id)
		var contains_fire := false
		if definition != null:
			for component: Dictionary in definition.damage_components:
				if component.get("type", &"") == &"fire": contains_fire = true
		check(contains_fire, "mage personal loadout attack is the fire definition")
		check(selected.kind == BattleAIIntent.Kind.ATTACK and selected.attack_definition_id == attack_id, "mage chooses its personal attack id")
	elif expected == WarriorKit.CLEAVE:
		expected_id = WarriorKit.CLEAVE
		check(selected.kind == BattleAIIntent.Kind.ATTACK and selected.attack_definition_id == expected_id, "fighter chooses ready CLEAVE")
	elif expected == &"fighter-cooldown-fallback":
		check(selected.kind == BattleAIIntent.Kind.ATTACK and selected.attack_definition_id == StringName(session.actor_loadouts[actor.id].attack_id), "fighter cooldown falls back to ordinary attack")
	elif expected == &"entangling_strike":
		expected_id = &"entangling_strike"
		check(selected.kind == BattleAIIntent.Kind.ATTACK and selected.attack_definition_id == expected_id, "archer chooses valid entangling strike")
	else:
		check(selected.kind == BattleAIIntent.Kind.ATTACK and selected.attack_definition_id == StringName(session.actor_loadouts[actor.id].attack_id), "archer immunity falls back to ordinary attack")
	var receipt := session.step_enemy()
	check(receipt != null and receipt.status == ActionReceipt.APPLIED, label + " executes through step_enemy command")
	if receipt != null and expected == &"entangling_strike":
		check(target.control.entangled_turns > 0, "archer entangling command applies control")
	if receipt != null and expected == &"mage-personal":
		var found_personal := false
		for event: Dictionary in receipt.get_events():
			if event.get("kind", &"") == &"attacked" and event.get("attack_definition_id", &"") == expected_id: found_personal = true
		check(found_personal, "mage personal attack is the executed command")
	session.close()

func _test_showcase_raise_shields() -> void:
	var fixture := _showcase_session()
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actor := _position_showcase_actor(session, &"shieldbearer")
	if actor == null:
		check(false, "showcase has shieldbearer actor")
		session.close()
		return
	var intent := BattleDemoBT.new().decide(session, actor)
	check(session.round_number % 2 == 1 and intent.kind == BattleAIIntent.Kind.RAISE_SHIELDS, "shieldbearer chooses odd-round shield raise near enemy")
	var receipt := session.step_enemy()
	check(receipt != null and receipt.status == ActionReceipt.APPLIED and actor.armor.raised_shield.active, "shieldbearer intent executes raised-shields command")
	session.close()
