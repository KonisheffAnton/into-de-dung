extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST SELECTION: " + label)

func _run() -> void:
	var empty := HeroHubState.create(7154, 4)
	empty.enable_mage_deck()
	var before_empty := empty.to_dict()
	var missing_start := ExpeditionTransitions.apply(empty, "start")
	_check(not missing_start.is_ok() and empty.to_dict() == before_empty, "fresh unselected host blocks start without mutation")
	var initial_glow: Dictionary = empty.mage_deck.host_glow.duplicate(true)
	var party_id: int = empty.party[0]
	var party_hero: HeroProgression = empty.heroes[party_id]
	var hero_before: Dictionary = party_hero.to_dict()
	var normal_rng: int = empty.rng_state
	var expedition_rng: int = empty.expedition_rng_state
	_check(empty.select_mage_host(party_id), "living party hero can be selected")
	_check(party_hero.to_dict() == hero_before and empty.rng_state == normal_rng and empty.expedition_rng_state == expedition_rng, "selection changes only cosmetic profile field")
	var reserve_id: int = 0
	for id: Variant in empty.heroes:
		if not empty.party.has(int(id)):
			reserve_id = int(id); break
	_check(reserve_id > 0 and not empty.select_mage_host(reserve_id), "reserve cannot be selected as host")
	var second_id: int = int(empty.party[1])
	var dead_hero: HeroProgression = empty.heroes[second_id]
	dead_hero.hp_current = 0.0
	_check(not empty.select_mage_host(second_id), "dead party hero cannot be selected")
	dead_hero.hp_current = dead_hero.max_hp()
	_check(empty.set_host_glow("violet", "flame", "still"), "valid glow settings save without requiring another carrier")
	var persisted_glow: Dictionary = empty.mage_deck.host_glow.duplicate(true)
	var expected_party: Array[int] = empty.party.duplicate()
	_check(empty.move_party_member(party_id, 1, expected_party) and empty.mage_deck.host_hero_id == party_id, "party reorder preserves selected host identity")
	var expected_after_move: Array[int] = empty.party.duplicate()
	_check(empty.select_party_member(0, party_id, expected_after_move) and empty.mage_deck.host_hero_id == party_id, "party swap preserves selected host identity")
	_check(empty.toggle_party(party_id) and empty.mage_deck.host_hero_id == 0 and empty.mage_deck.host_glow == persisted_glow, "removal clears host but preserves glow")
	_check(empty.set_host_glow("white", "glow", "soft"), "glow can be set without a selected carrier")
	persisted_glow = empty.mage_deck.host_glow.duplicate(true)
	var glow_before_invalid := persisted_glow.duplicate(true)
	_check(not empty.set_host_glow("green", "flame", "still") and empty.mage_deck.host_glow == glow_before_invalid, "invalid glow choice leaves appearance unchanged")
	var replacement_host_id: int = int(empty.party[0])
	_check(empty.select_mage_host(replacement_host_id), "another living party host can be selected")
	var expected_replace: Array[int] = empty.party.duplicate()
	_check(reserve_id > 0 and empty.select_party_member(0, reserve_id, expected_replace), "reserve can replace a selected party slot")
	_check(empty.mage_deck.host_hero_id == 0 and empty.mage_deck.host_glow == persisted_glow, "replacement clears missing host without automatic reselection")
	_check(empty.select_mage_host(reserve_id), "replacement party member can be selected as host")
	var doomed: HeroProgression = empty.heroes[reserve_id]
	doomed.hp_current = 0.0
	empty.clear_missing_mage_host()
	_check(empty.mage_deck.host_hero_id == 0 and empty.mage_deck.host_glow == persisted_glow, "carrier death clears id and preserves chosen glow")
	doomed.hp_current = doomed.max_hp()
	_check(empty.select_mage_host(reserve_id), "live carrier can be reselected")
	var profile := empty.to_dict()
	_check(HeroHubState.from_dict(profile) != null, "selected host and glow roundtrip through profile")
	var invalid := profile.duplicate(true); invalid.mage_deck.schema = 1
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects old schema")
	invalid = profile.duplicate(true); invalid.mage_deck.erase("host_hero_id")
	_check(HeroHubState.from_dict(invalid) == null, "deck profile requires host id")
	invalid = profile.duplicate(true); invalid.mage_deck.host_hero_id = "bad"
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects mistyped host id")
	invalid = profile.duplicate(true); invalid.mage_deck.host_hero_id = -1
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects out-of-range host id")
	invalid = profile.duplicate(true); invalid.mage_deck.host_glow.extra = "unknown"
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects unknown glow key")
	invalid = profile.duplicate(true); invalid.mage_deck.host_glow.color = "green"
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects unknown glow color")
	invalid = profile.duplicate(true); invalid.mage_deck.host_glow.form = 7
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects mistyped nested glow values")
	invalid = profile.duplicate(true); invalid.mage_deck.host_hero_id = 999999
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects saved nonparty host")
	invalid = profile.duplicate(true)
	for row: Dictionary in invalid.heroes:
		if row.id == reserve_id: row.hp_current = 0.0
	_check(HeroHubState.from_dict(invalid) == null, "deck profile rejects saved dead host")
	var selected_start := ExpeditionTransitions.apply(empty, "start")
	_check(selected_start.is_ok() and selected_start.profile.expedition.host_hero_id == reserve_id, "empty start args use saved host")
	if selected_start.is_ok():
		_check(HeroHubState.from_dict(selected_start.profile.to_dict()) != null, "expedition profile keeps matching saved host")
	var explicit_match := ExpeditionTransitions.apply(empty, "start", {"host_hero_id":reserve_id})
	_check(explicit_match.is_ok() and explicit_match.profile.expedition.host_hero_id == reserve_id, "explicit start host must match saved selection")
	var untouched := empty.to_dict()
	var explicit_mismatch := ExpeditionTransitions.apply(empty, "start", {"host_hero_id":second_id})
	_check(not explicit_mismatch.is_ok() and empty.to_dict() == untouched, "start rejects host differing from saved choice without mutation")
	_check(initial_glow == {"color":"amber","form":"flame","flicker":"soft"}, "default glow is animated upward flame")
	_test_legacy_battle_death(persisted_glow)
	print("HOST SELECTION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_legacy_battle_death(expected_glow: Dictionary) -> void:
	var hub := HeroHubState.create(8811, 4)
	hub.enable_mage_deck()
	var host_id: int = int(hub.party[0])
	_check(hub.select_mage_host(host_id) and hub.set_host_glow(String(expected_glow.color),String(expected_glow.form),String(expected_glow.flicker)), "legacy battle fixture has selected carrier and glow")
	var gear: Dictionary = {}
	for id: int in hub.battle_items(): gear[id] = hub.items[id].remaining
	_check(hub.start_battle(), "legacy battle starts with selected carrier")
	var hp: Dictionary = {}
	for id: int in hub.party:
		hp[id] = 0.0 if id == host_id else float((hub.heroes[id] as HeroProgression).max_hp())
	_check(hub.finish_battle(hub.run_serial,true,hp,gear), "legacy victory resolves carrier death")
	_check(hub.mage_deck.host_hero_id == 0 and hub.mage_deck.host_glow == expected_glow, "legacy battle death clears selection and preserves glow")
