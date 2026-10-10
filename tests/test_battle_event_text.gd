extends SceneTree

const EXPECTED_PATH := "res://tests/fixtures/battle_event_text_expected.json"
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE EVENT TEXT: " + label)

func _run() -> void:
	var actual: Array[String] = []
	_detached_values()
	for core: bool in [false, true]:
		var demo := BattleDemo.new()
		demo.session = BattleCoreReactionsSession.new() if core else BattleTacticalSession.new()
		var actor := demo.session.units[0]
		var target := demo.session.units[1]
		var before := ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict()
		var rng := demo.session.context.get_rng().to_dict()
		for bleeding: bool in [false, true]:
			demo.bleeding_mode = bleeding
			for event: Dictionary in _events(actor.id, target.id):
				var original := event.duplicate(true)
				actual.append(demo._event_text(event))
				check(event == original, "event remains unchanged")
			# Предмет ищется в текущем владельце, включая отсутствующий ID.
			for owner: ItemOwnerState in demo.session.state.get_owners():
				for item: ItemInstance in owner._items.values():
					if item.get_use_action() == null: continue
					actual.append(demo._event_text({"kind": &"item_used", "actor_unit_id": item.get_owner_unit_id(), "item_instance_id": item.get_item_instance_id(), "main_cost": 1, "charges_after": 2}))
		var named_event := {"kind": &"attacked", "actor_unit_id": actor.id, "target_unit_id": target.id}
		var previous := demo._event_text(named_event)
		var old_name := actor.debug_name
		actor.debug_name = "Новое имя"
		check(demo._event_text(named_event) != previous and demo._event_text(named_event).begins_with("Новое имя"), "fresh name without revision")
		actor.debug_name = old_name
		check(ItemSimulationSnapshot.capture(demo.session.state, []).snapshot.to_dict() == before, "formatting preserves battle snapshot")
		check(demo.session.context.get_rng().to_dict() == rng, "formatting preserves RNG")
		for effect: StringName in [&"mage.test_burning", &"mage.test_wet", &"mage.test_freeze", &"mage.test_stun", &"mage.test_roots", &"mage.test_bleeding", &"mage.test_heal", &"mage.test_summon", &"mage.shield", &"mage.test_raise", &"mage.fire", &"mage.heal", &"burning", &"wet", &"freeze", &"unknown"]:
			actual.append(demo._elemental_effect_label(effect))
		for value: Variant in [null, {}, {"ticks_left": 0}, {"ticks_left": 2}, {"ticks_left": 3, "stacked": true, "stacks": 2}, {"ticks_left": 3, "stacked": true, "stacks": 4611686018427387904}]:
			actual.append(demo._bleeding_summary(value))
		for value: Variant in [null, {}, {"burning_stacks": 2, "burning_ticks": 3, "wet_turns": 1, "frozen_turns": 2, "acid_ticks": 4}]:
			actual.append(demo._elemental_summary(value))
		demo.session.close()
		demo.session = null
		demo.free()
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
	check(expected is Array and expected.size() == actual.size(), "base output count")
	if expected is Array and expected.size() == actual.size():
		for index: int in actual.size():
			check(actual[index] == expected[index], "base text %d" % index)
	print("BATTLE EVENT TEXT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _detached_values() -> void:
	# Сессии и UI здесь нет: подписи должны зависеть только от переданных значений.
	var names: Dictionary[int, String] = {11: "Первый", 12: "Второй"}
	var event := {"kind": &"attacked", "actor_unit_id": 11, "target_unit_id": 12,
		"modifiers": {"sneak_percent": 50, "threat_ids": [12, 11, 12, "skip", -1]}}
	var original := event.duplicate(true)
	var original_names := names.duplicate()
	check(BattleEventText.format_event(event, names, true, false, "флакон") == "Первый атакует Второй. Скрытая атака +50% физической базы (угроза: Второй, Первый, Второй, Окружение).", "detached names retain order, duplicates and unknown fallback")
	check(event == original and names == original_names, "formatter does not mutate nested values or names")
	names[11] = "Третий"
	check(BattleEventText.format_event(event, names, true, false, "флакон").begins_with("Третий"), "formatter retains no names between calls")

func _events(actor: int, target: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for reason: StringName in [&"burned", &"tick", &"applied", &"refreshed"]:
		for stacked: bool in [false, true]:
			for ticks: int in [0, 2]:
				events.append({"kind": &"bleeding_changed", "reason": reason, "after": {"ticks_left": ticks, "stacked": stacked, "stacks": 3}})
	for reason: StringName in [&"burn_tick", &"turn_end", &"wet"]:
		events.append({"kind": &"elemental_changed", "reason": reason, "after": {"wet_turns": 2}})
	events.append({"kind": &"trap_armed", "cell": Vector2i(2, 3)})
	events.append({"kind": &"trap_fired", "cell": Vector2i(2, 3)})
	events.append({"kind": &"trap_fired", "target_unit_id": 0})
	events.append({"kind": &"mage_cast", "spell_id": &"mage.fire", "mana_before": 3, "mana_after": 1, "cooldown_after": 2})
	for card: String in ["card.fire", "card.summon", "card.raise", "missing"]:
		events.append({"kind": &"mage_card_played", "type_id": card, "target_cell": Vector2i(1, 2), "card_instance_id": 9, "mana_before": 3, "mana_after": 1})
	events.append({"kind": &"deck_changed", "reason": &"draw", "after": {"hand_ids": [1, 2], "draw_ids": [3], "spent_ids": []}})
	events.append({"kind": &"elemental_cast", "effect": &"burning", "main_before": 1, "main_after": 0})
	events.append({"kind": &"attacked", "modifiers": {"sneak_percent": 50, "threat_ids": [target, actor, target, "skip", 1.5, -9], "backstab_percent": 50, "critical": true}})
	events.append({"kind": &"attacked"})
	for mode: int in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]:
		events.append({"kind": &"reaction_used", "mode": mode, "bonus_before": 2, "bonus_after": 1})
		events.append({"kind": &"reaction_used", "mode": mode, "charge_before": 1, "charge_after": 0})
		events.append({"kind": &"guarded", "reaction_mode": mode, "cover_target_id": target})
	events.append({"kind": &"guarded"})
	for reason: StringName in [&"entangled", &"refreshed", &"stunned", &"stun_refreshed", &"push", &"expired"]:
		events.append({"kind": &"control_changed", "reason": reason})
	events.append({"kind": &"item_used", "item_instance_id": -1, "main_cost": 1, "charges_after": 0})
	events.append({"kind": &"item_used", "actor_unit_id": -1, "item_instance_id": -1, "main_cost": 1, "charges_after": 0})
	for corpse: int in [0, 5]:
		for owner: int in [0, actor]:
			events.append({"kind": &"mage_summoned", "corpse_id": corpse, "owner_unit_id": owner})
	events.append({"kind": &"corpse_created", "corpse": {"cell": Vector2i(2, 3)}})
	events.append({"kind": &"support_collapsed", "cell": Vector2i(2, 3)})
	for marked: Array in [[], [Vector2i(2, 3)]]:
		events.append({"kind": &"environment_turn", "turn": 3, "marked": marked})
	for kind: StringName in [&"damaged", &"healed"]:
		for source: StringName in [&"fall", &"status", &"cell", &"attack", &"collision", &"mage", &"item", &""]:
			events.append({"kind": kind, "amount": 2.5, "source": {"kind": source}})
	for shattered: bool in [false, true]:
		events.append({"kind": &"hit_resolved", "hit": {"hp_before": 20, "hp_after": 12, "shattered": shattered}})
	for movement: StringName in [&"push", &"safe_retreat", &"walk"]:
		events.append({"kind": &"moved", "movement_kind": movement, "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 2), "main_cost": 1, "move_cost": 1.5})
	for broke: bool in [false, true]:
		events.append({"kind": &"chain_link", "from_unit_id": actor, "impulse": 4.5, "broke": broke})
	events.append({"kind": &"collision", "blocker_unit_id": actor})
	events.append({"kind": &"balance_changed", "balance_after": 4.0, "balance_max": 12.0})
	for kind: StringName in [&"opportunity_attacked", &"counterattacked", &"summoned", &"corpse_raised", &"armor_changed", &"balance_broken", &"push_blocked", &"fell", &"died", &"unknown"]:
		events.append({"kind": kind})
	events.append({})
	for event: Dictionary in events:
		if not event.has("actor_unit_id"): event.actor_unit_id = actor
		if not event.has("target_unit_id"): event.target_unit_id = target
	return events
