extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SHIELDBEARER PROFILE: " + label)

func _run() -> void:
	_test_catalog_and_gear()
	_test_profile_codec()
	_test_store_dispatch()
	_test_factory_dispatch()
	print("SHIELDBEARER PROFILE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_catalog_and_gear() -> void:
	check(HeroCatalog.class_ids(1) == [&"warrior", &"archer", &"rogue", &"mage"], "catalog version one remains unchanged")
	check(HeroCatalog.class_ids(2) == [&"shieldbearer", &"archer", &"rogue", &"mage"], "catalog version two replaces only the warrior slot")
	check(HeroCatalog.class_ids(3) == [&"shieldbearer", &"archer", &"rogue", &"mage", &"fighter"], "catalog version three appends fighter after existing version two classes")
	var warrior := HeroCatalog.class_definition(&"warrior")
	var shieldbearer := HeroCatalog.class_definition(&"shieldbearer")
	var fighter := HeroCatalog.class_definition(&"fighter")
	check(warrior.display_name == "Воин" and warrior.base_attributes == [10, 10, 10, 10, 10] and warrior.attack_range == 1 and warrior.weapon_damage == 4 and warrior.armor_max == 40, "class templates use neutral five-attribute defaults")
	check(shieldbearer.display_name == "Щитоносец" and shieldbearer.base_attributes == warrior.base_attributes and shieldbearer.attack_range == warrior.attack_range and shieldbearer.weapon_damage == warrior.weapon_damage and shieldbearer.armor_max == warrior.armor_max, "shieldbearer keeps warrior combat values")
	check(fighter.display_name == "Воин" and fighter.base_attributes == warrior.base_attributes and fighter.attack_range == warrior.attack_range and fighter.weapon_damage == warrior.weapon_damage and fighter.armor_max == warrior.armor_max, "fighter uses legacy warrior template values")
	check(fighter.abilities_text.contains("+20%") and fighter.abilities_text.contains("лечению") and fighter.abilities_text.contains("броне") and fighter.abilities_text.contains("Рассекающий удар") and fighter.abilities_text.contains("Пинок ногой"), "fighter description lists passive and both active abilities")
	check(shieldbearer.abilities_text.contains("Оппортунист (пассивный)") and shieldbearer.abilities_text.contains("90% первой атаки") and shieldbearer.abilities_text.contains("1 основное действие") and shieldbearer.abilities_text.contains("перезарядка 1"), "shieldbearer profile describes its bounded abilities")
	var weapon := HeroGearCatalog.definition("weapon:shieldbearer")
	var armor := HeroGearCatalog.definition("armor:shieldbearer")
	check(weapon != null and armor != null and weapon.effects.size() == HeroGearCatalog.definition("weapon:warrior").effects.size() and armor.armor_max == HeroGearCatalog.definition("armor:warrior").armor_max, "class gear reuses warrior equipment values")
	check(HeroGearCatalog.allowed("weapon:shieldbearer", &"shieldbearer") and not HeroGearCatalog.allowed("weapon:shieldbearer", &"warrior") and HeroGearCatalog.allowed("armor:shieldbearer", &"shieldbearer"), "new gear accepts shieldbearer class")
	var fighter_weapon := HeroGearCatalog.definition("weapon:fighter")
	var fighter_armor := HeroGearCatalog.definition("armor:fighter")
	check(fighter_weapon != null and fighter_armor != null and fighter_weapon.effects.size() == HeroGearCatalog.definition("weapon:warrior").effects.size() and fighter_armor.armor_max == 40, "fighter gear uses legacy warrior numeric values")
	check(HeroGearCatalog.allowed("weapon:fighter", &"fighter") and not HeroGearCatalog.allowed("weapon:fighter", &"mage") and HeroGearCatalog.allowed("armor:fighter", &"fighter"), "fighter equipment accepts its owner class")

func _test_profile_codec() -> void:
	var legacy := HeroHubState.create(7101)
	var legacy_v7 := legacy.to_dict()
	check(legacy.hero_catalog_version == 1 and legacy_v7.schema == 7 and legacy_v7.hero_catalog_version == 1 and legacy_v7.heroes[0].class_id == "warrior" and HeroHubState.from_dict(legacy_v7).to_dict() == legacy_v7, "catalog one encodes in schema seven")
	legacy._refresh_candidates()
	check(legacy.candidates[0].class_id == &"warrior", "legacy refresh remains on warrior catalog")
	legacy.enable_mage_deck()
	var legacy_deck_v7 := legacy.to_dict()
	var restored_legacy_deck := HeroHubState.from_dict(legacy_deck_v7)
	check(legacy_deck_v7.schema == 7 and restored_legacy_deck != null and restored_legacy_deck.to_dict() == legacy_deck_v7 and restored_legacy_deck.hero_catalog_version == 1, "catalog one deck profile uses schema seven")
	var fresh := HeroHubState.create(7101, 2)
	var v7 := fresh.to_dict()
	check(fresh.hero_catalog_version == 2 and v7.schema == 7 and v7.hero_catalog_version == 2 and v7.mage_deck.is_empty() and v7.h1_ruleset == "", "catalog version two writes schema seven before deck enable")
	check(fresh.heroes[1].class_id == &"shieldbearer" and fresh.candidates[0].class_id == &"shieldbearer", "version two creates shieldbearer first in roster and candidates")
	var hire_profile := HeroHubState.create(7104, 2)
	var hired_id: int = hire_profile.candidates[0].id
	check(hire_profile.hire(0), "version two can hire shieldbearer candidate")
	var hired: HeroProgression = hire_profile.heroes[hired_id]
	check(hired.class_id == &"shieldbearer" and hire_profile.equipped(hired.id, "weapon").definition == "weapon:shieldbearer" and hire_profile.equipped(hired.id, "armor").definition == "armor:shieldbearer", "hired shieldbearer receives valid class gear")
	var restored := HeroHubState.from_dict(v7)
	check(restored != null and restored.to_dict() == v7 and restored.hero_catalog_version == 2, "schema seven profile roundtrip")
	if restored != null:
		restored._refresh_candidates()
		check(restored.candidates[0].class_id == &"shieldbearer", "schema seven refresh uses stored catalog")
	var deck_profile := HeroHubState.create(7102, 2)
	deck_profile.enable_mage_deck()
	var deck_v7 := deck_profile.to_dict()
	check(deck_v7.schema == 7 and deck_v7.mage_deck.schema == 2 and MageDeckProfile.valid(deck_v7.mage_deck) and HeroHubState.from_dict(deck_v7) != null, "schema seven stores strict mage deck schema two")
	var old_deck := deck_v7.duplicate(true); old_deck.mage_deck.schema = 1
	check(HeroHubState.from_dict(old_deck) == null, "schema seven rejects old mage deck profile schema")
	var bad := v7.duplicate(true)
	bad.hero_catalog_version = 1
	check(HeroHubState.from_dict(bad) == null, "schema seven rejects class list inconsistent with catalog")
	bad = v7.duplicate(true)
	bad.hero_catalog_version = "2"
	check(HeroHubState.from_dict(bad) == null, "schema seven rejects wrong catalog version type")
	bad = v7.duplicate(true)
	bad.heroes[0].class_id = "warrior"
	check(HeroHubState.from_dict(bad) == null, "schema seven rejects legacy hero class")
	bad = v7.duplicate(true)
	bad.candidates[0].class_id = "warrior"
	check(HeroHubState.from_dict(bad) == null, "schema seven rejects legacy candidate class")
	var fighter_profile := HeroHubState.create(7105, 3)
	var fighter_v7 := fighter_profile.to_dict()
	check(fighter_profile.hero_catalog_version == 3 and fighter_profile.heroes[5].class_id == &"fighter" and fighter_profile.candidates[4].class_id == &"fighter", "catalog version three adds fighter to roster and candidate pool")
	check(fighter_profile.equipped(5, "weapon").definition == "weapon:fighter" and fighter_profile.equipped(5, "armor").definition == "armor:fighter", "new fighter receives class gear")
	var restored_fighter := HeroHubState.from_dict(fighter_v7)
	check(restored_fighter != null and restored_fighter.to_dict() == fighter_v7 and restored_fighter.hero_catalog_version == 3, "catalog three profile roundtrip preserves schema seven data")
	bad = fighter_v7.duplicate(true)
	bad.hero_catalog_version = 5
	check(HeroHubState.from_dict(bad) == null and HeroHubState.create(7101, 5) == null, "profile and create reject unsupported catalog version five")
	var showcase := HeroHubState.create(7106, 4)
	var showcase_data := showcase.to_dict()
	check(showcase.hero_catalog_version == 4 and showcase.party.size() == 3
		and showcase.heroes[showcase.party[0]].class_id == &"rogue"
		and showcase.heroes[showcase.party[1]].class_id == &"mage"
		and showcase.heroes[showcase.party[2]].class_id == &"fighter",
		"catalog version four starts with Rogue, Mage and Fighter party")
	var restored_showcase := HeroHubState.from_dict(showcase_data)
	check(restored_showcase != null and restored_showcase.to_dict() == showcase_data
		and restored_showcase.hero_catalog_version == 4,
		"catalog four profile roundtrip preserves schema seven data")

func _test_store_dispatch() -> void:
	var path := "user://shieldbearer-profile-%d.save" % Time.get_ticks_usec()
	var fresh := HeroHubStore.read_run(path, true)
	var run: HeroHubState = fresh.run
	check(run != null and run.hero_catalog_version == 4 and run.party.size() == 3
		and run.heroes[run.party[0]].class_id == &"rogue"
		and run.heroes[run.party[1]].class_id == &"mage"
		and run.heroes[run.party[2]].class_id == &"fighter"
		and not run.mage_deck.is_empty(), "missing deck profile starts with version four party and deck")
	if run != null:
		check(HeroHubStore.write_run(path, run).is_empty(), "schema seven profile saves")
		var loaded := HeroHubStore.read_run(path)
		check(loaded.run != null and loaded.run.hero_catalog_version == 4 and loaded.run.to_dict() == run.to_dict(), "schema seven version four store envelope reads back without migration")
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var envelope: Variant = bytes_to_var(file.get_buffer(file.get_length()))
			check(envelope is Dictionary and envelope.get("format") == "hero-hub-v7", "new catalog uses matching profile envelope")
			file.close()
	var old_path := path + "-old"
	var old := HeroHubState.create(7103)
	check(HeroHubStore.write_run(old_path, old).is_empty(), "legacy profile saves")
	var old_roundtrip := HeroHubStore.read_run(old_path)
	check(old_roundtrip.run != null and old_roundtrip.run.to_dict() == old.to_dict(), "catalog one schema seven store roundtrips unchanged")
	var old_loaded := HeroHubStore.read_run(old_path, true)
	check(old_loaded.run != null and old_loaded.run.hero_catalog_version == 1 and old_loaded.run.mage_deck.is_empty() and old_loaded.run.heroes[1].class_id == &"warrior" and old_loaded.run.candidates[0].class_id == &"warrior", "deck mode never auto enables or changes an existing profile")
	for target: String in [path, path + ".bak", path + ".tmp", old_path, old_path + ".bak", old_path + ".tmp"]:
		var absolute := ProjectSettings.globalize_path(target)
		if FileAccess.file_exists(target): DirAccess.remove_absolute(absolute)

func _test_factory_dispatch() -> void:
	var fresh := HeroHubState.create(7201, 2)
	check(fresh.start_battle(), "catalog version two begins battle")
	var bundle := HeroHubBattleFactory.create(fresh)
	check(not bundle.is_empty(), "shieldbearer battle factory succeeds")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var hero_id := 1
	var unit := session.board.get_unit_by_id(bundle.hero_units[hero_id])
	check(unit.combat_perks.definition.passive_opportunist and not unit.combat_perks.definition.tank_reactions and not unit.combat_perks.definition.counterattack and not unit.combat_perks.definition.stunning_strike, "factory gives passive perk without legacy reactions")
	check(RaisedShield.valid(unit.armor.raised_shield) and unit.armor.to_dict().schema_version == 4 and unit.action_resources != null and unit.combat_perks.uses_bonus_actions, "factory attaches raised-shield armor state and modern resources")
	var raise_ability := session.state.abilities.definition(&"unit.raise_shields")
	check(raise_ability != null and raise_ability.cooldown_turns == 1, "factory registers raised shields ability when owned")
	check(session.actor_loadouts[unit.id].class_id == &"shieldbearer" and session.unit_visual_classes[unit.id] == &"shieldbearer", "factory keeps stable melee loadout and selected shieldbearer visual")
	session.close()
	var legacy := HeroHubState.create(7202)
	legacy.start_battle()
	var legacy_bundle := HeroHubBattleFactory.create(legacy)
	check(not legacy_bundle.is_empty(), "legacy warrior factory still succeeds")
	if not legacy_bundle.is_empty():
		var legacy_session: BattleCoreReactionsSession = legacy_bundle.session
		var legacy_unit := legacy_session.board.get_unit_by_id(legacy_bundle.hero_units[1])
		check(legacy_unit.combat_perks.definition.tank_reactions and legacy_unit.combat_perks.definition.counterattack and legacy_unit.combat_perks.definition.stunning_strike and not legacy_unit.combat_perks.definition.passive_opportunist, "legacy warrior keeps old reactions")
		check(legacy_unit.armor.raised_shield.is_empty() and legacy_session.state.abilities.definition(&"unit.raise_shields") == null, "legacy warrior factory does not receive new shield command")
		legacy_session.close()
