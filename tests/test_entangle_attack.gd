extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ENTANGLE ATTACK: " + label)

func _run() -> void:
	_test_definition_contract()
	_test_attack_refresh_and_preview()
	_test_hp_gate_and_death()
	_test_net_healing_gate()
	_test_rejection_and_internal_command()
	_test_fault_prefix_and_limits()
	_test_expiry_and_push()
	_test_spatial_death_and_disabled()
	print("ENTANGLE ATTACK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func fixture(enabled: bool = true) -> BattleCoreCombinationSession:
	var session := BattleCoreCombinationSession.new()
	var rules := session.context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for id: StringName in [&"demo_strike", &"blood_rune"]:
		var definition := rules.get_definition(id)
		definition.entangle_on_physical_hp = enabled and id == &"demo_strike"
		definitions.append(definition)
	session.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	var actor := session.units[2]
	var target := session.units[3]
	target.control.entangled_turns = 0
	session.select_unit(actor.id)
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 20.0)
	actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 4.0)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
	target.vitals.set_hp(256.0)
	target.armor.natural["physical"] = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	return session

func _test_definition_contract() -> void:
	var definition := AttackDefinition.new()
	check(not definition.entangle_on_physical_hp, "definition defaults disabled")
	var session := fixture()
	check(session.context.get_attack_rules().validate() == &"" and session.context.get_attack_rules().get_definition(&"demo_strike").entangle_on_physical_hp, "armor profile admits copied enabled definition")
	var rules := session.context.get_attack_rules()
	var invalid_definition := AttackDefinition.new()
	invalid_definition.id = &"invalid_entangle_profile"
	invalid_definition.profile = AttackRules.PROFILE
	invalid_definition.entangle_on_physical_hp = true
	check(AttackRules.new(rules._actors, rules._pairs, [invalid_definition]).validate() == &"attack/invalid_rules", "enabled definition rejected outside armor profile")
	session.close()

func _test_attack_refresh_and_preview() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	var before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng := session.context.get_rng().to_dict()
	var counters := session.context.simulation_counters()
	var revision := session.context.get_revision()
	var next_root := session.context._next_root_id
	var next_event := session.context._next_event_seq
	var main_before := actor.action_resources.get_main_left()
	var unit_id_counter := UnitId.get_counter()
	var preview := session.preview_attack(target.id)
	check(preview.status == ActionReceipt.APPLIED and preview.units[target.id]["after"]["control"]["entangled_turns"] == 1 and target.control.entangled_turns == 0, "preview executes application on isolated copy")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == before and session.context.get_rng().to_dict() == rng and session.context.simulation_counters() == counters and session.context.get_revision() == revision and session.context._next_root_id == next_root and session.context._next_event_seq == next_event and actor.action_resources.get_main_left() == main_before and UnitId.get_counter() == unit_id_counter, "preview leaves live state resources RNG ids and counters unchanged")
	var second_preview := session.preview_attack(target.id)
	check(second_preview.events == preview.events and second_preview.steps == preview.steps and second_preview.snapshot_after == preview.snapshot_after, "repeated preview deterministic")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var decoded := ItemSimulationSnapshot.from_dict(preview.snapshot_after)
	var restored := decoded.snapshot.instantiate(definitions) if decoded.code == ItemSnapshotResult.Code.OK else ItemSnapshotResult.new()
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == preview.snapshot_after, "application snapshot restores exact status and item state")
	if restored.state != null: AttackForecast._close(restored.state)
	var receipt := session.attack_unit(target.id)
	var control_events: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "live matches preview events and steps")
	check(control_events.size() == 1 and control_events[0]["reason"] == &"entangled" and control_events[0]["after"]["entangled_turns"] == 1, "first accepted application event")
	check(actor.action_resources.get_main_left() == main_before - 1, "attack consumes one main action")
	check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == preview.snapshot_after and session.context.get_rng().to_dict() == preview.rng_after and session.context.simulation_counters() == preview.counters_after, "live snapshot RNG and counters match forecast")
	target.control.stunned_turns = 1
	actor.try_refill_turn_resources()
	receipt = session.attack_unit(target.id)
	control_events = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(control_events.size() == 1 and control_events[0]["reason"] == &"refreshed" and control_events[0]["before"]["stunned_turns"] == 1 and control_events[0]["after"]["stunned_turns"] == 1, "repeat refresh preserves stun and does not stack")
	check(target.control.entangled_turns == 1, "repeated applications retain one turn")
	session.close()

func _test_net_healing_gate() -> void:
	var session := fixture()
	var target := session.units[3]
	target.vitals.set_hp(100.0)
	target.armor.natural["fire"] = 11000
	target.armor.perks = [{"id": "limit", "type": "fire", "branch": "both", "bonus": 3500}]
	var rules := session.context.get_attack_rules()
	var strike := rules.get_definition(&"demo_strike")
	strike.damage_components[0]["numerator"] = 1000
	session.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, [strike, rules.get_definition(&"blood_rune")])
	var preview := session.preview_attack(target.id)
	var receipt := session.attack_unit(target.id)
	var hit_events: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"hit_resolved")
	var physical_hp: int = 0
	if hit_events.size() == 1:
		for row: Dictionary in hit_events[0]["hit"]["rows"]:
			if row["type"] == &"physical": physical_hp += int(row["hp_damage"])
	check(receipt.status == ActionReceipt.APPLIED and physical_hp > 0 and target.vitals.get_hp() > 100.0 and target.control.entangled_turns == 1, "physical damage before same-hit net healing opens gate")
	check(receipt.get_events() == preview.events and receipt.get_steps() == preview.steps and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == preview.snapshot_after, "net healing hit preview matches live")
	check(receipt.get_events().all(func(event: Dictionary) -> bool: return event.get("kind") != &"damaged"), "net-healing hit has no damaged event")
	session.close()
	# Предметная реакция проверяется отдельно от лечения внутри прямого попадания.
	session = fixture()
	target = session.units[3]
	target.vitals.set_hp(100.0)
	var definition := ItemDef.new()
	definition.id = &"entangle_test_heal"
	var healing := HealOnDamageEffect.new()
	healing.heal_amount = 80.0
	definition.effects.append(healing)
	var healing_item := session.state.get_owner(target.id).create_item(definition)
	check(healing_item != null and session.state.get_inventory(target.id).add_item(healing_item), "healing reaction fixture installed")
	receipt = session.attack_unit(target.id)
	var kinds: Array = receipt.get_events().map(func(event: Dictionary) -> StringName: return event["kind"])
	check(receipt.status == ActionReceipt.APPLIED and target.vitals.get_hp() > 100.0 and target.control.entangled_turns == 1, "healing item preserves already applied root")
	check(kinds.find(&"healed") > kinds.find(&"control_changed") and kinds.find(&"control_changed") >= 0, "optional healing reaction occurs after application")
	session.close()

func _test_hp_gate_and_death() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	actor.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, -50.0)
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = item.get_definition().armor_max
	var receipt := session.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and target.control.entangled_turns == 0, "zero physical HP damage does not apply")
	check(receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed").is_empty(), "failed HP gate emits no state event")
	actor.try_refill_turn_resources()
	target.armor.natural["physical"] = 0
	target.vitals.set_hp(1.0)
	receipt = session.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and not target.is_alive() and target.control.entangled_turns == 0, "direct lethal hit skips application")
	check(receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed").is_empty(), "dead target has no entangle event")
	session.close()

func _test_rejection_and_internal_command() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	var main := actor.action_resources.get_main_left()
	var rng := session.context.get_rng().to_dict()
	target.control = null
	var attack := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	check(attack.validate(session.context) == &"control/capability_required", "missing capability rejected before payment")
	var rejected := session._queue.submit(attack, session.context)
	check(rejected.status == ActionReceipt.REJECTED and actor.action_resources.get_main_left() == main and session.context.get_rng().to_dict() == rng, "capability rejection spends no main or RNG")
	target.control = ControlState.new()
	var source := DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	var direct := EntangleApplyCommand.new(actor, target, source, "direct", &"demo_strike", true)
	check(direct.get_kind() == &"entangle_apply" and direct.validate(session.context) == &"", "internal command validates exact capability")
	var internal := session._queue.submit(direct, session.context)
	check(internal.status == ActionReceipt.REJECTED and internal.reason == &"control/internal_command", "public queue rejects internal application command")
	session.close()

func _test_fault_prefix_and_limits() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	var main_before := actor.action_resources.get_main_left()
	var mutate_control := func(_before: float, _after: float) -> void: target.control.stunned_turns = 1
	target.vitals.hp_changed.connect(mutate_control)
	var receipt := session.attack_unit(target.id)
	target.vitals.hp_changed.disconnect(mutate_control)
	check(receipt.status == ActionReceipt.FAULTED and target.vitals.get_hp() < 256.0 and actor.action_resources.get_main_left() == main_before - 1, "HP callback fault preserves paid hit prefix")
	check(target.control.entangled_turns == 0 and receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed").is_empty(), "callback fault prevents application sibling")
	session.close()
	session = fixture()
	session._queue = ActionQueue.new(2)
	receipt = session.attack_unit(session.units[3].id)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"command_limit" and session.units[3].control.entangled_turns == 0, "command limit faults before application")
	session.close()
	session = fixture()
	session._queue = ActionQueue.new(256, 3)
	receipt = session.attack_unit(session.units[3].id)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"event_limit" and session.units[3].control.entangled_turns == 1, "event limit retains applied status prefix")
	check(receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed").size() == 1, "event limit retains application event")
	session.close()

func _test_expiry_and_push() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	var receipt := session.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and target.control.entangled_turns == 1, "attack establishes root before boundary")
	var other_faction: Faction.Type = Faction.Type.ENEMY if target.faction == Faction.Type.PLAYER else Faction.Type.PLAYER
	var other_end := session._queue.submit(ControlTurnEndCommand.new(other_faction, session.context.get_revision()), session.context)
	check(other_end.status == ActionReceipt.APPLIED and target.control.entangled_turns == 1, "other team boundary preserves root")
	var own_end := session._queue.submit(ControlTurnEndCommand.new(target.faction, session.context.get_revision()), session.context)
	check(own_end.status == ActionReceipt.APPLIED and target.control.entangled_turns == 0, "own team boundary expires root")
	target.control.entangled_turns = 1
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	actor.try_refill_turn_resources()
	receipt = session.attack_unit(target.id)
	var control_events: Array = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(receipt.status == ActionReceipt.APPLIED and target.cell != Vector2i(3, 3) and target.control.entangled_turns == 1, "push clears existing root before successful reapplication")
	check(control_events.size() >= 2 and control_events[0]["reason"] == &"push" and control_events[-1]["reason"] == &"entangled", "push event precedes new application")
	# Вторая атака исполняет обычный push без нового допуска; уже наложенные путы снимаются.
	target.vitals.set_hp(256.0)
	actor.try_refill_turn_resources()
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	var rules := session.context.get_attack_rules()
	var ordinary := rules.get_definition(&"demo_strike")
	ordinary.entangle_on_physical_hp = false
	var all_definitions: Array[AttackDefinition] = [ordinary, rules.get_definition(&"blood_rune")]
	session.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, all_definitions)
	check(session.board.move_unit(actor, Vector2i(3, 3)), "close distance for next push")
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	receipt = session._queue.submit(command, session.context)
	control_events = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"control_changed")
	check(receipt.status == ActionReceipt.APPLIED and target.cell != Vector2i(2, 3) and target.control.entangled_turns == 0 and control_events.size() == 1 and control_events[0]["reason"] == &"push", "later ordinary push clears applied root")
	session.close()

func _test_spatial_death_and_disabled() -> void:
	var session := fixture()
	var actor := session.units[2]
	var target := session.units[3]
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 100.0)
	target.vitals.set_hp(58.0)
	var receipt := session.attack_unit(target.id)
	check(receipt.status == ActionReceipt.APPLIED and not target.is_alive() and target.cell == Vector2i(2, 3) and target.control.entangled_turns == 0, "spike death after direct hit skips root")
	check(receipt.get_steps().any(func(step: Dictionary) -> bool: return step["kind"] == &"entangle_apply" and step["reason"] == &"control/dead_target"), "spatial death yields explicit skipped application")
	session.close()
	session = fixture(false)
	receipt = session.attack_unit(session.units[3].id)
	check(receipt.status == ActionReceipt.APPLIED and session.units[3].control.entangled_turns == 0 and receipt.get_steps().all(func(step: Dictionary) -> bool: return step["kind"] != &"entangle_apply"), "disabled flag preserves ordinary attack pipeline")
	session.close()
