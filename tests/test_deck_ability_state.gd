extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL DECK ABILITY STATE: " + label)

func _run() -> void:
	_test_schema_one_compatibility()
	_test_deck_codec_and_mixed_rejection()
	_test_team_order(0)
	_test_team_order(1)
	print("DECK ABILITY STATE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_schema_one_compatibility() -> void:
	var state := BattleAbilityState.create(AbilityCatalog.defaults())
	check(state != null and state.schema_version == 1, "legacy constructor remains schema one")
	var values := state.to_dict()
	check(values == {"schema_version":1,"catalog":values.catalog,"mana":6,"maximum":6,"ledger":[],"serials":[0,0],"ended":[0,0],"team":1,"stage":"setup","mage_allowed":false}, "legacy bytes retain exact field shape and values")
	check(not values.has("ruleset_id") and not values.has("first_team"), "legacy bytes omit deck fields")
	check(BattleAbilityState.from_dict(values).to_dict() == values, "legacy codec roundtrip unchanged")

func _test_deck_codec_and_mixed_rejection() -> void:
	var deck := BattleAbilityState.create_deck(AbilityCatalog.defaults(), 0)
	check(deck != null and deck.schema_version == 2 and deck.ruleset_id == "u14-deck-v1" and deck.first_team == 0, "deck constructor tags schema and first team")
	check(deck != null and deck.maximum == 2 and deck.mana == 2 and not deck.mage_allowed and deck.ledger.is_empty(), "deck constructor starts at two mana without legacy mage state")
	check(deck != null and deck.definition(&"mage.fire") == null and BattleAbilityState.valid(deck.to_dict()), "deck catalog excludes legacy mage definitions")
	var restored := BattleAbilityState.from_dict(deck.to_dict())
	check(restored != null and restored.to_dict() == deck.to_dict() and restored.schema_version == 2, "deck state codec roundtrip")
	var mixed := deck.to_dict(); mixed["catalog"].append(AbilityCatalog.defaults().back().to_dict())
	check(not BattleAbilityState.valid(mixed), "deck rejects mixed legacy mage catalog")
	mixed = deck.to_dict(); mixed.erase("first_team")
	check(not BattleAbilityState.valid(mixed), "deck rejects missing first team")
	mixed = deck.to_dict(); mixed["unknown"] = true
	check(not BattleAbilityState.valid(mixed), "deck rejects unknown field")
	mixed = deck.to_dict(); mixed["ruleset_id"] = "other"
	check(not BattleAbilityState.valid(mixed), "deck rejects unknown ruleset")
	check(BattleAbilityState.create_deck(AbilityCatalog.defaults(), 2) == null, "deck rejects invalid first team")
	check(deck.paid(&"mage.fire").is_empty(), "legacy paid path rejects deck runtime")
	var before := deck.to_dict()
	check(deck.serials == [0,0] and deck.team == 0 and deck.to_dict() == before, "selection state is independent of clocks and mana")

func _test_team_order(first_team: int) -> void:
	var state := BattleAbilityState.create_deck(AbilityCatalog.defaults(), first_team)
	check(state != null and BattleAbilityState.valid(state.to_dict()), "first team %d setup valid" % first_team)
	var expected_player_max: int = 2
	for turn_index: int in range(12):
		if turn_index == 0:
			var start := state.boundary(&"start", state.team, state.serials[state.team])
			check(not start.is_empty(), "first %d turn %d starts" % [first_team,turn_index])
			state.apply_values(start)
		else:
			check(state.stage == "active", "first %d turn %d opens" % [first_team,turn_index])
		check(state.mage_allowed == (state.team == 0), "first %d turn %d has team-appropriate card window" % [first_team,turn_index])
		if state.team == 0:
			expected_player_max = mini(9, expected_player_max + (1 if state.serials[0] > 1 else 0))
			check(state.maximum == expected_player_max and state.mana == expected_player_max, "first %d player turn %d grows and refills" % [first_team,turn_index])
		else:
			check(state.maximum == expected_player_max, "first %d enemy turn %d preserves mana cap" % [first_team,turn_index])
		var close := state.boundary(&"close", state.team, state.serials[state.team]); state.apply_values(close)
		var end := state.boundary(&"end", state.team, state.serials[state.team]); state.apply_values(end)
		if turn_index < 11:
			var begin := state.boundary(&"begin", state.team, state.serials[state.team]); state.apply_values(begin)
			var open := state.boundary(&"open", state.team, state.serials[state.team]); state.apply_values(open)
		check(BattleAbilityState.valid(state.to_dict()), "first %d clocks valid after turn %d" % [first_team,turn_index])
	check(state.stage == "ended" and state.serials == state.ended, "first %d terminal turn closes both clocks" % first_team)
	var terminal := state.to_dict(); terminal["stage"] = "terminal"
	check(BattleAbilityState.valid(terminal), "first %d terminal stage keeps closed clocks valid" % first_team)
