extends SceneTree

var passed: int = 0
var failed: int = 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE DAMAGE FEEDBACK: " + label)

func event(kind: StringName, actor: int, target: int, source: Dictionary, extra: Dictionary = {}, command_seq: int = 1) -> Dictionary:
	var result := {"kind": kind, "actor_unit_id": actor, "target_unit_id": target,
		"source": source.duplicate(true), "command_seq": command_seq}
	result.merge(extra, true)
	return result

func assert_entry(entries: Array[Dictionary], index: int, kind: StringName, actor: int, target: int, amount: float, label: String) -> void:
	check(index < entries.size(), label + " exists")
	if index >= entries.size(): return
	var value: Dictionary = entries[index]
	check(value.keys().size() == 5 and value.get("kind") == kind and int(value.get("actor", -1)) == actor
		and int(value.get("target", -1)) == target and is_equal_approx(float(value.get("amount", -1.0)), amount), label + " shape and value")

func _initialize() -> void:
	var source := {"kind": &"attack", "id": 71, "nested": {"token": 9}}
	var source_b := {"kind": &"environment", "id": 72}
	var combined: Array = [
		event(&"damaged", 1, 10, source, {"amount": 3.0}),
		event(&"armor_changed", 1, 10, source, {"grants": [{"before": 5.0, "after": 2.0}], "items": [{"before": 3.0, "after": 2.0}]}),
		event(&"shield_changed", 1, 10, source, {"absorbed": 2.0, "after": {"hp": 1.0}}),
		event(&"hit_resolved", 1, 10, source, {"hit_id": "h1", "hit": {"total_damage": 999.0}}),
		event(&"hit_resolved", 1, 10, source, {"hit_id": "h1", "hit": {"total_damage": 999.0}}),
	]
	var untouched := combined.duplicate(true)
	var entries := BattleDamageFeedback.entries(combined)
	check(entries.size() == 1, "HP, armor and shield aggregate into one damage entry; hit marker does not add damage")
	assert_entry(entries, 0, &"damage", 1, 10, 9.0, "combined actual loss")
	check(combined == untouched, "input events remain deeply equal")
	if not entries.is_empty():
		var copied_source: Dictionary = entries[0].source
		var copied_nested: Dictionary = copied_source.nested
		copied_nested.token = 55
		check(combined == untouched, "entry source is isolated from input")

	entries = BattleDamageFeedback.entries([
		event(&"armor_changed", 2, 20, source, {"grants": [{"before": 5.0, "after": 1.0}], "items": []}),
		event(&"hit_resolved", 2, 20, source, {"hit_id": "armor-only"})
	])
	check(entries.size() == 1, "armor-only hit has one number")
	assert_entry(entries, 0, &"damage", 2, 20, 4.0, "armor-only total")

	entries = BattleDamageFeedback.entries([
		event(&"shield_changed", 3, 30, source, {"absorbed": 5.5, "after": {"hp": 0.0}}),
		event(&"hit_resolved", 3, 30, source, {"hit_id": "shield-only"})
	])
	check(entries.size() == 1, "shield-only hit has one number")
	assert_entry(entries, 0, &"damage", 3, 30, 5.5, "shield-only total")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 4, 40, source, {"amount": 1.0, "hp_before": 8.0, "hp_after": 0.0}),
		event(&"hit_resolved", 4, 40, source, {"hit_id": "lethal", "hit": {"total_damage": 500.0, "hp_after": 0.0}})
	])
	assert_entry(entries, 0, &"damage", 4, 40, 1.0, "lethal uses actual capped damage")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 5, 50, source, {"amount": 3.0}),
		event(&"healed", 5, 50, source, {"amount": 2.0}),
		event(&"hit_resolved", 5, 50, source, {"hit_id": "mixed"})
	])
	check(entries.size() == 2, "mixed hit keeps one damage and one healing entry")
	assert_entry(entries, 0, &"damage", 5, 50, 3.0, "mixed damage")
	assert_entry(entries, 1, &"healed", 5, 50, 2.0, "mixed healing")

	entries = BattleDamageFeedback.entries([
		event(&"healed", 6, 60, source, {"amount": 2.5}),
		event(&"armor_changed", 6, 60, source, {"grants": [{"before": 1.0, "after": 3.0}], "items": [{"before": 0.0, "after": 1.0}]}),
		event(&"shield_changed", 6, 60, source, {"absorbed": 0.0, "after": {"hp": 4.0}}),
		event(&"hit_resolved", 6, 60, source, {"hit_id": "recovery-only"})
	])
	check(entries.size() == 3, "recovery-only hit does not create a zero damage entry")
	assert_entry(entries, 0, &"healed", 6, 60, 2.5, "healing actual amount")
	assert_entry(entries, 1, &"armor_gain", 6, 60, 3.0, "armor gain aggregate")
	assert_entry(entries, 2, &"shield_gain", 6, 60, 4.0, "shield applied amount")

	entries = BattleDamageFeedback.entries([event(&"hit_resolved", 7, 70, source, {"hit_id": "zero"}),
		event(&"hit_resolved", 7, 70, source, {"hit_id": "zero"})])
	check(entries.size() == 1, "zero hit marker emits once despite duplicate hit id")
	assert_entry(entries, 0, &"damage", 7, 70, 0.0, "zero hit")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 8, 80, source, {"amount": 1.0}), event(&"hit_resolved", 8, 80, source, {"hit_id": "multi:a"}),
		event(&"damaged", 8, 81, source, {"amount": 2.0}), event(&"hit_resolved", 8, 81, source, {"hit_id": "multi:b"})
	])
	check(entries.size() == 2, "one actor attacking multiple targets makes separate entries")
	assert_entry(entries, 0, &"damage", 8, 80, 1.0, "first target")
	assert_entry(entries, 1, &"damage", 8, 81, 2.0, "second target")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 9, 90, source, {"amount": 2.0}), event(&"hit_resolved", 9, 90, source, {"hit_id": "source-a"}),
		event(&"damaged", 11, 90, source_b, {"amount": 3.0}), event(&"hit_resolved", 11, 90, source_b, {"hit_id": "source-b"})
	])
	check(entries.size() == 2, "different actors and sources against one target remain separate")
	assert_entry(entries, 0, &"damage", 9, 90, 2.0, "first source")
	assert_entry(entries, 1, &"damage", 11, 90, 3.0, "second source")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 12, 120, source, {"amount": 1.0}, 1), event(&"hit_resolved", 12, 120, source, {"hit_id": "cmd-1"}, 1),
		event(&"damaged", 12, 120, source, {"amount": 2.0}, 2), event(&"hit_resolved", 12, 120, source, {"hit_id": "cmd-2"}, 2)
	])
	check(entries.size() == 2, "distinct command sequences do not merge")
	assert_entry(entries, 0, &"damage", 12, 120, 1.0, "first command")
	assert_entry(entries, 1, &"damage", 12, 120, 2.0, "second command")

	entries = BattleDamageFeedback.entries([
		event(&"damaged", 13, 130, source, {"amount": 1.0}), event(&"hit_resolved", 13, 130, source, {"hit_id": "first"}),
		event(&"damaged", 13, 130, source, {"amount": 4.0}), event(&"hit_resolved", 13, 130, source, {"hit_id": "second"}),
		event(&"hit_resolved", 13, 130, source, {"hit_id": "second"})
	])
	check(entries.size() == 2, "consecutive hits with distinct hit ids stay separate and duplicate marker adds nothing")
	assert_entry(entries, 0, &"damage", 13, 130, 1.0, "first hit id")
	assert_entry(entries, 1, &"damage", 13, 130, 4.0, "second hit id")

	var obstacle_packet: Array[Dictionary] = [
		{"step": {"kind": &"push", "status": &"APPLIED", "command_seq": 20}, "events": [
			{"kind": &"push_blocked", "actor_unit_id": 1, "target_unit_id": 2, "root_id": 8,
				"command_seq": 20, "attempted_cell": Vector2i(3, 4)}]},
		{"step": {"kind": &"push_damage", "status": &"APPLIED", "command_seq": 21}, "events": [
			{"kind": &"damaged", "actor_unit_id": 1, "target_unit_id": 2, "root_id": 8, "command_seq": 21,
				"source": {"kind": &"collision", "origin_cell": Vector2i(3, 4)}, "amount": 7.0}]}]
	var original_packet := obstacle_packet.duplicate(true)
	var borrowed := BattleDamageFeedback.obstacle_results(obstacle_packet, 0)
	check(borrowed.size() == 1 and borrowed[0].amount == 7.0, "obstacle binds only confirmed next mandatory result")
	if not borrowed.is_empty(): borrowed[0].amount = 99.0
	check(obstacle_packet == original_packet, "borrowed contact values cannot mutate receipt")
	for field: String in ["root_id", "command_seq", "actor_unit_id", "target_unit_id"]:
		var other := original_packet.duplicate(true)
		other[1].events[0][field] = 999
		check(BattleDamageFeedback.obstacle_results(other, 0).is_empty(), "reject mismatched obstacle result " + field)
	for mismatch: String in ["kind", "origin_cell"]:
		var other := original_packet.duplicate(true)
		other[1].events[0].source[mismatch] = &"attack" if mismatch == "kind" else Vector2i(0, 0)
		check(BattleDamageFeedback.obstacle_results(other, 0).is_empty(), "reject mismatched obstacle source " + mismatch)
	var faulted := original_packet.duplicate(true)
	faulted[1].step.status = &"FAULTED"
	check(BattleDamageFeedback.obstacle_results(faulted, 0).size() == 1, "actual fault prefix damage can be shown on contact")
	faulted[1].events.clear()
	check(BattleDamageFeedback.obstacle_results(faulted, 0).is_empty(), "fault without actual result never invents damage")
	check(BattleDamageFeedback.obstacle_results(original_packet, 1).is_empty(), "no following frame has no invented result")

	for mismatch: String in ["kind", "command_seq", "status"]:
		var other := original_packet.duplicate(true)
		other[1].step[mismatch] = 99 if mismatch == "command_seq" else &"unrelated"
		check(BattleDamageFeedback.obstacle_results(other, 0).is_empty(), "reject mismatched next step " + mismatch)
	var collision_packet := original_packet.duplicate(true)
	collision_packet[0].events[0].kind = &"collision"
	collision_packet[0].events[0]["blocker_unit_id"] = 3
	collision_packet[1].step.kind = &"collision_damage"
	var second_victim: Dictionary = collision_packet[1].events[0].duplicate(true)
	second_victim.target_unit_id = 3
	second_victim.amount = 5.0
	collision_packet[1].events.append(second_victim)
	check(BattleDamageFeedback.obstacle_results(collision_packet, 0).size() == 2, "collision lookahead includes both targets before marking the frame shown")

	print("BATTLE DAMAGE FEEDBACK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
