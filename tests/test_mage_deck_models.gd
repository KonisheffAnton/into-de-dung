extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL MAGE DECK MODELS: " + label)

func _run() -> void:
	_test_catalog()
	_test_deck()
	_test_effect_state()
	print("MAGE DECK MODEL RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_catalog() -> void:
	check(MageCardCatalog.all().size() == 12 and MageCardCatalog.default_base_types().size() == 10, "catalog and default counts")
	check(MageCardCatalog.valid_base(MageCardCatalog.default_base_types()), "default base validates")
	check(not MageCardCatalog.valid_base(["card.fire"]), "base rejects wrong count")
	check(not MageCardCatalog.valid_base(["card.fire","card.fire","card.fire","card.heal","card.heal","card.shield","card.shield","card.summon","card.summon","card.wet"]), "base rejects more than two copies")
	var fire := MageCardCatalog.get_card("card.fire")
	check(fire != null and fire.source_id() == 13 and MageCardDefinition.from_dict(fire.to_dict()) != null, "card definition roundtrip and source id")
	var bad := fire.to_dict(); bad["mana_cost"] = 1
	check(MageCardDefinition.from_dict(bad) == null, "card codec rejects changed price")

func _cards() -> Array:
	var result: Array = []
	var types: Array[String] = MageCardCatalog.default_base_types()
	for i: int in range(types.size()): result.append({"id":i + 1,"type_id":types[i],"origin":"base"})
	return result

func _test_deck() -> void:
	var deck := BattleDeckState.create(_cards(), 771)
	var same := BattleDeckState.create(_cards(), 771)
	check(deck != null and same != null and deck.hand_ids.size() == 5 and deck.to_dict() == same.to_dict(), "seeded initial shuffle and hand are deterministic")
	var restored := BattleDeckState.from_dict(deck.to_dict())
	check(restored != null and restored.to_dict() == deck.to_dict(), "battle deck codec roundtrip")
	var original := deck.to_dict()
	var chosen: Array[int] = [deck.hand_ids[0], deck.hand_ids[1]]
	var plan := deck.mulligan(chosen)
	check(not plan.is_empty() and deck.to_dict() == original, "mulligan plans without mutating live state")
	var changed := BattleDeckState.from_dict(plan.after)
	check(changed != null and changed.mulligan_done and changed.hand_ids.size() == 5, "mulligan changes exactly two slots")
	check(deck.mulligan(chosen).after == plan.after, "mulligan preserves copies and deterministic fallback")
	check(changed.replace(changed.hand_ids[0], 0).is_empty(), "replace rejects invalid serial")
	var replace_plan := changed.replace(changed.hand_ids[0], 1)
	var replaced := BattleDeckState.from_dict(replace_plan.after)
	check(replaced != null and replaced.replaced_serial == 1 and replaced.hand_ids.size() == 5, "replace consumes one hand copy and records serial")
	check(replaced.replace(replaced.hand_ids[0], 1).is_empty(), "replace cannot repeat in same serial")
	var play_plan := replaced.play(replaced.hand_ids[0])
	check(not play_plan.is_empty() and replaced.hand_ids.size() == 5, "play plans without live mutation")
	var played := BattleDeckState.from_dict(play_plan.after)
	check(played != null and played.hand_ids.size() == 4 and played.spent_ids.size() == 1, "play transfers hand copy to spent")
	var exhausted := BattleDeckState.create(_cards(), 9)
	exhausted.apply_values(exhausted.mulligan([]).after)
	for _i: int in range(5):
		exhausted.apply_values(exhausted.play(exhausted.hand_ids[0]).after)
		exhausted.apply_values(exhausted.draw().after)
	exhausted.apply_values(exhausted.play(exhausted.hand_ids[0]).after)
	var empty_draw := exhausted.draw()
	check(BattleDeckState.from_dict(empty_draw.after).draw_ids.is_empty() and BattleDeckState.from_dict(empty_draw.after).hand_ids.size() == 4, "draw exhaustion does not recycle spent")
	var invalid := deck.to_dict(); invalid["spent_ids"] = [deck.hand_ids[0]]
	check(BattleDeckState.from_dict(invalid) == null, "deck rejects overlapping zones")
	var detached := deck.duplicate(); detached.draw_rng.next_int(&"combat",5)
	check(detached.to_dict() != deck.to_dict(), "clone RNG is independent")
	var rng_reference := deck.draw_rng
	check(deck.apply_values(deck.mulligan([]).after),"confirm before end-turn draw")
	var apply_values := deck.draw(); check(deck.apply_values(apply_values.after), "deck apply values accepts validated candidate")
	check(deck.draw_rng == rng_reference, "deck apply values preserves RNG identity")
	var full_hand := deck.to_dict()
	check(deck.hand_ids.size() == 6 and deck.draw().after == full_hand,"full hand discards no draw and uses no RNG")
	var uniform: Array = []
	for id: int in range(1,11): uniform.append({"id":id,"type_id":"card.fire","origin":"found"})
	var fallback := BattleDeckState.create(uniform,37)
	var returned: Array[int] = [fallback.hand_ids[0],fallback.hand_ids[1]]
	var substitute := BattleDeckState.from_dict(fallback.mulligan(returned).after)
	check(substitute != null and not substitute.hand_ids.has(returned[0]) and not substitute.hand_ids.has(returned[1]),"same type fallback never redraws either returned copy")
	var one := BattleDeckState.create(_cards(),52)
	var old_id: int = one.hand_ids[0]; var old_type: String = one.card(old_id).type_id
	var single := BattleDeckState.from_dict(one.mulligan([old_id]).after)
	check(single != null and single.card(single.hand_ids[0]).type_id != old_type,"one-card mulligan prefers another type")
	var bad_rng := one.to_dict(); bad_rng.draw_rng["unexpected"] = 1
	check(BattleDeckState.from_dict(bad_rng) == null,"draw RNG shape strict")

func _test_effect_state() -> void:
	var state := BattleCardEffectState.new()
	state.ordinary_attacks = [{"unit_id":4,"attack_id":"attack.default.4"}]
	check(BattleCardEffectState.from_dict(state.to_dict()) != null, "ordinary attack registry roundtrip")
	var plan := state.imbue(4, 7, 3)
	check(not plan.is_empty() and state.fire_imbues.is_empty(), "imbue returns after without live mutation")
	var imbued := BattleCardEffectState.from_dict(plan.after)
	check(imbued != null and imbued.fire_imbues[0].expires_after_serial == 5, "imbue has exact two-serial duration")
	var refreshed := BattleCardEffectState.from_dict(imbued.imbue(4,8,4).after)
	check(refreshed.fire_imbues[0].source_card_id == 8 and refreshed.fire_imbues[0].expires_after_serial == 6, "re-imbue replaces source and expiry")
	var expiry_plan := refreshed.expire(6,[4])
	check(BattleCardEffectState.from_dict(expiry_plan.after).fire_imbues.is_empty(), "expiry removes after target team's serial")
	var other_team_plan := imbued.expire(5,[9])
	check(BattleCardEffectState.from_dict(other_team_plan.after).fire_imbues.size() == 1, "expiry leaves unrelated team unit effect")
	var bad := imbued.to_dict(); bad.fire_imbues[0].expires_after_serial = 6
	check(BattleCardEffectState.from_dict(bad) == null, "effect codec rejects inconsistent duration")
	var effect_reference := state.fire_imbues
	check(state.apply_values(plan.after) and state.fire_imbues.size() == 1 and effect_reference == state.fire_imbues, "effect apply values preserves runtime array identity")
