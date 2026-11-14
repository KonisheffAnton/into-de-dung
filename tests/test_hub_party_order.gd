extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HUB PARTY ORDER: " + label)

func _run() -> void:
	for version: int in [1, 2, 3, 4]:
		var hub := HeroHubState.create(73191, version)
		var before := hub.to_dict()
		var initial: Array[int] = hub.party.duplicate()
		check(hub.move_party_member(initial[0], 2, initial), "move first to last catalogue %d" % version)
		check(hub.party == [initial[1], initial[2], initial[0]], "stable order of other members")
		var unchanged := hub.to_dict()
		unchanged.party = before.party
		check(unchanged == before, "only party changed: no RNG/items/HP/catalogue/save schema changes")
		var loaded := HeroHubState.from_dict(hub.to_dict())
		check(loaded != null and loaded.party == hub.party, "order roundtrips through existing profile codec")
		var changed := hub.to_dict()
		check(not hub.move_party_member(initial[0], 1, initial) and hub.to_dict() == changed, "stale move rejected atomically")
		check(not hub.move_party_member(initial[0], 2, hub.party.duplicate()), "same position is no-op")
		for target: int in [-1, 3]:
			check(not hub.move_party_member(initial[0], target, hub.party.duplicate()) and hub.to_dict() == changed, "invalid move index")
		check(not hub.move_party_member(999999, 0, hub.party.duplicate()) and hub.to_dict() == changed, "foreign move ID")
		var expected: Array[int] = hub.party.duplicate()
		check(hub.select_party_member(0, expected[2], expected), "existing member swaps")
		check(hub.party == [expected[2], expected[1], expected[0]], "swap has no duplicate or lost member")
		var reserve_id := 0
		for id: int in hub.heroes:
			if not hub.party.has(id): reserve_id = id; break
		var displaced: int = hub.party[1]
		expected = hub.party.duplicate()
		check(reserve_id > 0 and hub.select_party_member(1, reserve_id, expected), "reserve replaces selected slot")
		check(not hub.party.has(displaced) and hub.heroes.has(displaced) and hub.party[1] == reserve_id, "displaced hero remains owned reserve")
		changed = hub.to_dict()
		check(not hub.select_party_member(0, displaced, expected) and hub.to_dict() == changed, "stale picker rejected")
		check(not hub.select_party_member(3, displaced, hub.party.duplicate()) and hub.to_dict() == changed, "limit unchanged")
		check(not hub.select_party_member(0, hub.candidates[0].id, hub.party.duplicate()) and hub.to_dict() == changed, "candidate cannot bypass hiring")
		var dead := hub.heroes[displaced] as HeroProgression
		dead.hp_current = 0.0
		changed = hub.to_dict()
		check(not hub.select_party_member(0, displaced, hub.party.duplicate()) and hub.to_dict() == changed, "dead reserve rejected")
		dead.hp_current = dead.max_hp()
		hub.party.clear()
		check(hub.select_party_member(0, displaced, []), "empty party has selectable first slot")
		check(not hub.select_party_member(1, displaced, hub.party.duplicate()), "append does not duplicate hero")
		hub.phase = "battle"
		changed = hub.to_dict()
		check(not hub.select_party_member(0, reserve_id, hub.party.duplicate()) and not hub.move_party_member(displaced, 0, hub.party.duplicate()) and hub.to_dict() == changed, "phase barrier")
	print("HUB PARTY ORDER RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
