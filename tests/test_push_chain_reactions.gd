extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PUSH CHAIN REACTIONS: " + label)

func fixture() -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for i: int in 6:
		var unit: UnitState = s.units[i]
		check(s.board.move_unit(unit, Vector2i(i, 0)), "park " + str(i))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.bleeding.ticks_left = 0
		unit.bleeding.source.clear()
		unit.bleeding.hit_id = ""
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ARMOR, 0.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	check(s.board.move_unit(s.units[0], Vector2i(1, 3)), "actor placement")
	check(s.board.move_unit(s.units[1], Vector2i(2, 3)), "target placement")
	check(s.board.move_unit(s.units[2], Vector2i(3, 3)), "middle placement")
	check(s.board.move_unit(s.units[5], Vector2i(4, 3)), "last placement")
	check(s.select_unit(s.units[0].id), "select actor")
	var rules := s.context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for source: AttackDefinition in rules._definitions:
		var definition := AttackRules._copy_definition(source)
		definition.chain_push = definition.profile == AttackRules.ARMOR_PROFILE and not definition.reaction_strike
		definitions.append(definition)
	s.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	check(s.context.get_attack_rules().validate() == &"", "chain definitions valid")
	return s

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(s.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "snapshot " + String(result.reason))
	return result.snapshot.to_dict() if result.snapshot != null else {}

func events(receipt: ActionReceipt, kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == kind: out.append(event)
	return out

func parity(s: BattleCoreReactionsSession, label: String) -> ActionReceipt:
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var admission := SummonAdmission.values(s.context)
	var forecast := s.preview_attack(s.units[1].id)
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and SummonAdmission.values(s.context) == admission, label + " isolated preview")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, label + " events and steps parity " + String(receipt.reason))
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, label + " state RNG counters parity")
	return receipt

func summon(s: BattleCoreReactionsSession, owner: UnitState, cell: Vector2i) -> UnitState:
	var item := s.summoning_item(owner.id)
	check(item != null, "summon item owned")
	if item == null: return null
	var command := UseSummoningItemCommand.new(owner.id, item.get_item_instance_id(), cell, s.context.get_revision())
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == ActionReceipt.APPLIED, "real summon " + String(receipt.reason))
	return s.state.active_summon(owner.id)

func run() -> void:
	_helpers()
	_reactions_and_armor()
	_death_spikes_and_collapse()
	print("PUSH CHAIN REACTIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _helpers() -> void:
	var s := fixture()
	var owner: UnitState = s.units[2]
	check(s.board.move_unit(s.units[5], Vector2i(5, 0)), "clear terminal for helper")
	var helper := summon(s, owner, Vector2i(4, 3))
	check(helper != null and helper.faction == owner.faction and s.state.summon_owner_id(helper.id) == owner.id, "real allied terminal helper tracked")
	if helper != null:
		helper.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		helper.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		helper.vitals.set_hp(256.0)
		var receipt := parity(s, "allied helper terminal")
		var links := events(receipt, &"chain_link")
		check(receipt.status == ActionReceipt.APPLIED and links.size() == 2 and links[1]["target_unit_id"] == helper.id and helper.cell == Vector2i(5, 3), "helper receives second impulse and final move")
		check(s.units[1].cell == Vector2i(2, 3) and owner.cell == Vector2i(3, 3), "earlier bodies remain in place")
	s.close()

	s = fixture()
	owner = s.units[4]
	check(s.board.move_unit(s.units[2], Vector2i(2, 0)), "clear middle for helper")
	check(s.board.move_unit(owner, Vector2i(3, 2)), "helper owner adjacent to middle")
	helper = summon(s, owner, Vector2i(3, 3))
	check(helper != null and s.state.summon_owner_id(helper.id) == owner.id, "real middle helper tracked")
	if helper != null:
		helper.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		helper.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		helper.vitals.set_hp(256.0)
		var receipt := parity(s, "allied helper middle")
		var links := events(receipt, &"chain_link")
		check(receipt.status == ActionReceipt.APPLIED and links.size() == 2 and links[0]["target_unit_id"] == helper.id and links[1]["from_unit_id"] == helper.id, "helper transmits impulse")
		check(helper.cell == Vector2i(3, 3) and s.units[5].cell == Vector2i(5, 3), "middle helper remains while last moves")
	s.close()

func _reactions_and_armor() -> void:
	var s := fixture()
	var attacker: UnitState = s.units[0]
	var target: UnitState = s.units[1]
	var middle: UnitState = s.units[2]
	# Предметный ответ на два столкновения ждёт завершения пространственного хвоста.
	var definition := ItemDef.new()
	definition.id = &"chain_reaction_heal"
	var effect := HealOnDamageEffect.new()
	effect.heal_amount = 2.0
	definition.effects.append(effect)
	var item := s.state.get_owner(middle.id).create_item(definition)
	check(item != null and s.state.get_inventory(middle.id).add_item(item), "equip heal reaction in inventory")
	middle.vitals.set_hp(200.0)
	var coat := s.state.get_equipment(middle.id).get_equipped(EquipmentState.EquipSlot.ARMOR)
	check(coat != null, "fixture owns real equipped armor")
	if coat != null: coat.armor_remaining = 4
	var armor_before := coat.armor_remaining if coat != null else -1
	target.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	target.action_resources._set_for_refill(target.action_resources.get_main_left(), 1)
	target.guard_stance = true
	var receipt := parity(s, "item armor heal and one counter")
	var links := events(receipt, &"chain_link")
	var healed := events(receipt, &"healed")
	var counters := events(receipt, &"counterattacked")
	var middle_heals := 0
	for event: Dictionary in healed:
		if event.get("target_unit_id") == middle.id: middle_heals += 1
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 2 and counters.size() == 1 and target.action_resources.get_bonus_left() == 0, "counter executes once after full chain")
	check(coat != null and coat.armor_remaining < armor_before and events(receipt, &"armor_changed").size() > 0, "collision consumes equipped armor")
	check(middle_heals == 2, "two collision hits schedule two middle-item heals")
	var collision_hits := 0
	var last_spatial_seq := 0
	for event: Dictionary in receipt.get_events():
		if event.get("kind") in [&"chain_link", &"collision", &"moved"]: last_spatial_seq = maxi(last_spatial_seq, int(event.get("event_seq", 0)))
		if event.get("kind") == &"hit_resolved" and event.get("source", {}).get("kind", &"") == &"collision": collision_hits += 1
	check(collision_hits == 4, "both collision pairs resolve each participant once")
	if not healed.is_empty(): check(int(healed[0]["event_seq"]) > last_spatial_seq, "item heal is deferred after spatial tail")
	if not counters.is_empty() and not healed.is_empty(): check(int(counters[0]["event_seq"]) > int(healed[-1]["event_seq"]), "counter follows item heal")
	for event: Dictionary in receipt.get_events():
		if event.get("kind") != &"hit_resolved": continue
		var source: Dictionary = event.get("source", {})
		if source.get("kind") != &"collision": continue
		check(source.get("instigator_unit_id") == attacker.id and source.get("credit_unit_id") == attacker.id, "collision source credits original attacker")
	s.close()

## Один каскад связывает смерть помощника, реальные шипы K17 и следующий обвал.
func _death_spikes_and_collapse() -> void:
	var s := fixture()
	var owner: UnitState = s.units[4]
	check(s.board.move_unit(s.units[2], Vector2i(2, 0)), "audit clears middle")
	check(s.board.move_unit(owner, Vector2i(3, 2)), "audit helper owner")
	var helper := summon(s, owner, Vector2i(3, 3))
	if helper == null:
		s.close()
		return
	helper.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
	helper.vitals.set_hp(1.0)
	var heal_definition := ItemDef.new()
	heal_definition.id = &"audit_dead_helper_heal"
	var heal := HealOnDamageEffect.new()
	heal.heal_amount = 2.0
	heal_definition.effects.append(heal)
	var item := s.state.get_owner(helper.id).create_item(heal_definition)
	check(item != null and s.state.get_inventory(helper.id).add_item(item), "helper owns damage reaction")
	var last: UnitState = s.units[5]
	last.control.entangled_turns = 1
	last.bleeding.stacks = 1
	last.bleeding.ticks_left = 3
	last.bleeding.hit_id = "audit"
	last.bleeding.source = DamageSource.new(&"attack", 0, owner.cell, owner.id, owner.id).to_dict()
	var target: UnitState = s.units[1]
	target.guard_stance = true
	target.combat_perks.mode = CombatPerksState.Mode.COUNTERATTACK
	target.action_resources._set_for_refill(target.action_resources.get_main_left(), 1)
	var destination := Vector2i(5, 3)
	s.state.environment.ignite(destination, "bleeding")
	s.state.environment.collapse = {"turn": 1, "marked": [destination]}
	var receipt := parity(s, "dead helper to spikes before collapse")
	check(receipt.status == ActionReceipt.APPLIED and not helper.is_alive() and s.board.occupant_at(helper.cell) == null, "middle helper dies and releases occupancy")
	check(s.state.environment.processed_deaths.count(helper.id) == 1 and s.state.environment.corpses_at(helper.cell).is_empty(), "disappearing helper records one death without a corpse")
	check(last.cell == destination and last.control.entangled_turns == 0 and last.bleeding.stacks == 2 and last.bleeding.ticks_left == 3, "last moves, loses roots and gains spike stack")
	check(s.units[1].cell == Vector2i(2, 3) and helper.cell == Vector2i(3, 3), "dead middle never pulls earlier bodies into vacancy")
	var move_damage_seq := 0
	var spike_damage_seq := 0
	var spike_status_seq := 0
	for event: Dictionary in receipt.get_events():
		if event.get("target_unit_id") == helper.id:
			check(event["kind"] != &"healed", "dead helper cannot receive an item heal")
		if event.get("target_unit_id") != last.id: continue
		if event["kind"] == &"hit_resolved":
			for row: Dictionary in event["hit"]["raw"]:
				if row["source"] == "bleeding_move": move_damage_seq = event["event_seq"]
			if event["source"]["kind"] == &"cell": spike_damage_seq = event["event_seq"]
		if event["kind"] == &"bleeding_changed": spike_status_seq = event["event_seq"]
	check(move_damage_seq > 0 and spike_damage_seq > move_damage_seq and spike_status_seq > spike_damage_seq, "old bleed damage precedes spike hit and new stack")
	var counter := events(receipt, &"counterattacked")
	check(counter.size() == 1 and counter[0]["event_seq"] > spike_status_seq and target.action_resources.get_bonus_left() == 0, "one counter follows full spatial and status tail")
	check(s.board.get_terrain(destination) == TerrainType.Type.FLOOR, "marked destination survives until environment phase")
	var before := snapshot(s)
	var forecast := TurnForecast.build(s)
	check(forecast.status == ActionReceipt.APPLIED and snapshot(s) == before, "combined boundary forecast is isolated")
	check(s.end_player_turn(), "combined boundary executes")
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after and s.turn_events == forecast.events, "combined boundary matches snapshot events RNG counters")
	check(not last.is_alive() and s.board.occupant_at(destination) == null and s.board.get_terrain(destination) == TerrainType.Type.VOID, "environment kills pushed terminal at marked destination")
	check(s.state.environment.fire_at(destination).is_empty() and s.state.environment.corpses_at(destination).is_empty() and s.state.environment.processed_deaths.count(last.id) == 1, "collapse removes spikes and records one death without corpse")
	check(s.state.environment.corpses_at(helper.cell).is_empty() and s.state.environment.processed_deaths.count(helper.id) == 1, "later phase never recreates disappearing helper corpse")
	s.close()
