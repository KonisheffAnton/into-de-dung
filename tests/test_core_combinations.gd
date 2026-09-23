extends SceneTree

const FIXTURE = preload("res://tests/fixtures/core_combination_session.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL CORE COMBINATIONS: " + label)

func _run() -> void:
	_test_snapshot_restore_isolation()
	_test_rear_attack_pushes_rooted_target_to_spikes()
	_test_blocked_destination()
	_test_spike_death()
	_test_stunned_actor_rejected()
	_test_hostile_position_callback()
	print("CORE COMBINATIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_snapshot_restore_isolation() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "D4 fixture and attack definition validate")
	if not session.context.get_attack_rules().validate().is_empty():
		session.close()
		return
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	check(capture.code == ItemSnapshotResult.Code.OK and capture.snapshot != null, "full item snapshot captures combat composition")
	if capture.snapshot != null:
		var original := capture.snapshot.to_dict()
		var decoded := ItemSimulationSnapshot.from_dict(original)
		check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_bytes() == capture.snapshot.canonical_bytes(), "canonical decode preserves combined capabilities")
		check(_command(session).validate(session.context) == &"", "actual production attack command validates")
		var definitions: Dictionary = _copy_definitions(session)
		var restored := capture.snapshot.instantiate(definitions)
		check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null, "snapshot restores with copied catalogue")
		if restored.state != null:
			var recaptured := ItemSimulationSnapshot.capture(restored.state, [])
			check(recaptured.code == ItemSnapshotResult.Code.OK and recaptured.snapshot.to_dict() == original, "restored combat snapshot round-trips exactly")
			var restored_target := restored.state.get_board().get_unit_by_id(session.units[3].id)
			restored_target.control.entangled_turns = 0
			restored_target.bleeding.immune = true
			restored.state.environment.ignite(Vector2i(0, 0))
			var restored_owner := restored.state.get_owner(session.units[0].id)
			var mutated_items: int = 0
			for restored_item: ItemInstance in restored_owner._items.values():
				if restored_item.armor_remaining > 0:
					restored_item.armor_remaining -= 1
					mutated_items += 1
			check(mutated_items > 0 and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() != original, "restore mutations change valid independent runtime")
			check(_snapshot(session) == original and capture.snapshot.to_dict() == original, "restored control, bleeding, environment and item mutations leave live state and source snapshot intact")
			var sword_copy: ItemDef = definitions[&"d4_piercing_sword"]
			var original_sword: ItemDef = session.state.get_owner(session.units[0].id)._definitions[&"d4_piercing_sword"]
			(sword_copy.effects[0] as StatModifierEffect).value = 17.0
			check((original_sword.effects[0] as StatModifierEffect).value == 50.0, "restored catalogue definition is independent")
			AttackForecast._close(restored.state)
		var attack_copy := session.context.get_attack_rules().get_definition(&"demo_strike")
		attack_copy.backstab_bonus_percent = 0
		attack_copy.damage_components[0]["numerator"] = 999
		var rules_copy := session.context.get_attack_rules().copy()
		rules_copy._definitions[0].critical_on_control = false
		var live_definition := session.context.get_attack_rules().get_definition(&"demo_strike")
		check(live_definition.backstab_bonus_percent == 50 and live_definition.damage_components[0]["numerator"] == 10 and live_definition.critical_on_control, "attack definition and rules deep copies are isolated")
	session.close()

func _test_rear_attack_pushes_rooted_target_to_spikes() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "rear/spike fixture builds")
	_add_heal_reaction(session, session.units[3])
	var forecast := _check_preview_live_parity(session, "rear rooted spike attack")
	if forecast != null:
		var target := session.units[3]
		check(target.cell == Vector2i(2, 3) and target.control.entangled_turns == 0, "successful push enters spike cell and clears root")
		check(target.vitals.get_hp() < 32.0 and target.bleeding.ticks_left > 0, "piercing physical HP damage enables bleeding before environment damage")
		var events := forecast.events
		var moved_index := _event_index(events, &"moved")
		var root_index := _event_index(events, &"control_changed")
		var spike_index := _environment_hit_index(events)
		var bleed_index := _bleed_index(events, &"applied")
		var reaction_index := _event_index(events, &"healed")
		check(moved_index >= 0 and root_index > moved_index and spike_index > root_index, "movement, root clear, then spike events are ordered")
		check(bleed_index > spike_index and reaction_index > bleed_index, "spike consequences, bleeding apply, then item reaction are ordered")
		check(_attack_hit_sources(events).size() >= 2, "attack and entry spike publish distinct hit sources")
		var attacked_index := _event_index(events, &"attacked")
		check(attacked_index >= 0 and events[attacked_index].get("modifiers") == {"backstab_percent": 50, "critical": true}, "joint hit really uses rear bonus and control critical")
		var hit_index := _event_index(events, &"hit_resolved")
		if hit_index >= 0:
			var rows: Array = events[hit_index]["hit"]["rows"]
			check(rows.size() == 3 and rows[0]["D"] == 15 and rows[1]["D"] == 15 and rows[1]["policy"] == &"hp_only_natural" and rows[1]["hp_damage"] == 15 and rows[2]["D"] == 20, "critical rear base splits through production piercing; fire remains separate")
		check(session.units[0].action_resources.get_main_left() == 0, "joint attack pays exactly one main")
	session.close()

func _test_blocked_destination() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "blocked fixture builds")
	check(session.board.move_unit(session.units[4], Vector2i(2, 3)), "alive blocker occupies spike destination")
	var forecast := _check_preview_live_parity(session, "blocked rooted spike attack")
	if forecast != null:
		var target := session.units[3]
		check(target.cell == Vector2i(3, 3) and target.control.entangled_turns == 1, "blocked push leaves target and root in place")
		check(session.state.environment.corpses_at(Vector2i(3, 3)).is_empty(), "blocked push creates no environment death record")
		check(_environment_hit_index(forecast.events) < 0, "blocked destination causes no entry damage")
	session.close()

func _test_spike_death() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "lethal fixture builds")
	var target := session.units[3]
	# Без остатка брони прямой крит наносит 50: четыре оставшихся HP снимают шипы.
	var target_owner := session.state.get_owner(target.id)
	for item: ItemInstance in target_owner._items.values():
		item.armor_remaining = 0
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 64)
	target.vitals.set_hp(54.0)
	# Лечение привязано к самой цели: реакция обязана увидеть уже завершённую смерть и не оживлять её.
	_add_heal_reaction(session, target)
	var forecast := _check_preview_live_parity(session, "rear attack with lethal mandatory spike")
	if forecast != null:
		var death_index := _event_index(forecast.events, &"died")
		var spike_index := _environment_hit_index(forecast.events)
		var bleeding_apply := _bleed_index(forecast.events, &"applied")
		var direct_damage := _damage_event(forecast.events, &"attack")
		var spike_damage := _damage_event(forecast.events, &"cell")
		var deaths := 0
		for event: Dictionary in forecast.events:
			if event.get("kind") == &"died" and event.get("target_unit_id") == target.id: deaths += 1
		# ArmorHitExecutor публикует HP/death-дельты перед итоговым hit_resolved.
		check(not target.is_alive() and deaths == 1 and death_index > _event_index(forecast.events, &"moved") and spike_index > death_index and forecast.events[death_index]["source"]["kind"] == &"cell", "spike kills target exactly once after movement and before hit summary")
		check(not direct_damage.is_empty() and direct_damage["alive_after"] and direct_damage["hp_after"] == 4 and not spike_damage.is_empty() and not spike_damage["alive_after"] and spike_damage["hp_before"] == 4, "direct hit leaves target alive and spike damage causes death")
		check(not session.board.is_occupied(target.cell) and session.state.environment.corpses_at(target.cell).size() == 1, "spike death frees occupancy and records one corpse")
		check(bleeding_apply < 0 and target.bleeding.ticks_left == 0, "mandatory death prevents bleeding from being applied to dead target")
		check(_event_index(forecast.events, &"healed") < 0 and not target.is_alive(), "queued healing reaction cannot revive a dead target")
	session.close()

func _test_stunned_actor_rejected() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "stun fixture builds")
	var actor := session.units[0]
	var target := session.units[3]
	actor.control.stunned_turns = 1
	var before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var revision_before := session.context.get_revision()
	var main_before := actor.action_resources.get_main_left()
	var command := _command(session)
	check(command.validate(session.context) == &"control/stunned", "attack rules reject stunned actor")
	var receipt: ActionReceipt = session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"control/stunned", "stunned attack returns exact rejection")
	check(_snapshot(session) == before and actor.action_resources.get_main_left() == main_before, "stunned rejection spends no action or mutates state")
	check(session.context.get_rng().to_dict() == rng_before and session.context.get_revision() == revision_before and target.is_alive(), "stunned rejection preserves RNG, revision and target")
	session.close()

func _test_hostile_position_callback() -> void:
	var session: D4BattleSession = FIXTURE.new()
	check(session.build(), "callback fixture builds")
	var target := session.units[3]
	_add_heal_reaction(session, target)
	var mutate := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == target: target.control.stunned_turns = 1
	session.board.unit_position_changed.connect(mutate)
	var receipt: ActionReceipt = session._queue.submit(_command(session), session.context)
	session.board.unit_position_changed.disconnect(mutate)
	check(receipt.status == ActionReceipt.FAULTED and session.context.is_faulted(), "hostile position callback faults the attack and context")
	check(session.units[0].action_resources.get_main_left() == 0 and target.cell == Vector2i(2, 3), "fault retains paid and moved prefix")
	check(target.vitals.get_hp() == 17 and _event_index(receipt.get_events(), &"hit_resolved") >= 0 and _event_index(receipt.get_events(), &"moved") >= 0, "fault preserves completed direct hit HP and movement events")
	check(target.control.entangled_turns == 1 and not session.state.environment.fire_at(Vector2i(2, 3)).is_empty(), "fault stops before root clear and spike entry processing")
	check(_environment_hit_index(receipt.get_events()) < 0 and _bleed_index(receipt.get_events(), &"applied") < 0 and _event_index(receipt.get_events(), &"healed") < 0 and _event_index(receipt.get_events(), &"control_changed") < 0, "fault has no later environment, bleeding or item reaction events")
	session.close()

func _check_preview_live_parity(session: D4BattleSession, label: String) -> AttackForecast:
	var before := _snapshot(session)
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var revision_before := session.context.get_revision()
	var id_before := UnitId.get_counter()
	var definition_before := _attack_definition_value(session)
	check(_command(session).validate(session.context) == &"", label + " real command admission")
	var preview_one: AttackForecast = session.preview_attack(session.units[3].id)
	var preview_two: AttackForecast = session.preview_attack(session.units[3].id)
	check(preview_one.status == ActionReceipt.APPLIED and preview_two.status == ActionReceipt.APPLIED, label + " forecasts apply")
	check(preview_one.events == preview_two.events and preview_one.steps == preview_two.steps and preview_one.snapshot_after == preview_two.snapshot_after and preview_one.rng_after == preview_two.rng_after and preview_one.counters_after == preview_two.counters_after, label + " repeated forecast deterministic")
	check(_snapshot(session) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before and session.context.get_revision() == revision_before and UnitId.get_counter() == id_before, label + " forecasts preserve state RNG counters revision and IDs")
	check(_attack_definition_value(session) == definition_before, label + " forecasts preserve attack definitions")
	if preview_one.status != ActionReceipt.APPLIED:
		return null
	var receipt: ActionReceipt = session.attack_unit(session.units[3].id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview_one.events and receipt.get_steps() == preview_one.steps, label + " live events and steps match forecast")
	check(_snapshot(session) == preview_one.snapshot_after and session.context.get_rng().to_dict() == preview_one.rng_after and session.context.simulation_counters() == preview_one.counters_after, label + " live snapshot RNG and counters match forecast")
	return preview_one

func _snapshot(session: D4BattleSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, "capture succeeds: " + captured.reason)
	return captured.snapshot.to_dict() if captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null else {}

func _attack_definition_value(session: D4BattleSession) -> Dictionary:
	var definition := session.context.get_attack_rules().get_definition(&"demo_strike")
	return {"id": definition.id, "profile": definition.profile, "components": definition.damage_components.duplicate(true), "bleeding": definition.bleeding_policy, "backstab": definition.backstab_bonus_percent, "critical": definition.critical_on_control}

func _copy_definitions(session: D4BattleSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _add_heal_reaction(session: D4BattleSession, target: UnitState) -> void:
	var definition := ItemDef.new()
	definition.id = &"k1_test_heal"
	definition.display_name = "K1 тестовый амулет"
	var effect := HealOnDamageEffect.new()
	effect.heal_amount = 2.0
	definition.effects.append(effect)
	var owner := session.state.get_owner(target.id)
	var item := owner.create_item(definition)
	check(item != null and session.state.get_inventory(target.id).add_item(item), "validated heal reaction item registers through owner and inventory")

func _command(session: D4BattleSession) -> AttackCommand:
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[3]
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())

func _event_index(events: Array[Dictionary], kind: StringName) -> int:
	for index: int in events.size():
		if events[index].get("kind") == kind: return index
	return -1

func _bleed_index(events: Array[Dictionary], reason: StringName) -> int:
	for index: int in events.size():
		if events[index].get("kind") == &"bleeding_changed" and events[index].get("reason") == reason: return index
	return -1

func _attack_hit_sources(events: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.get("kind") == &"hit_resolved": result.append(event.get("source", {}).duplicate(true))
	return result

func _environment_hit_index(events: Array[Dictionary]) -> int:
	for index: int in events.size():
		var event: Dictionary = events[index]
		if event.get("kind") == &"hit_resolved" and event.get("source", {}).get("kind") == &"cell": return index
	return -1

func _damage_event(events: Array[Dictionary], source_kind: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == &"damaged" and event.get("source", {}).get("kind") == source_kind: return event
	return {}
