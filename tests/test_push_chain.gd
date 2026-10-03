extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL PUSH CHAIN: " + label)

func fixture(impact: float = 16.0) -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	for i: int in 6:
		var unit: UnitState = s.units[i]
		check(s.board.move_unit(unit, Vector2i(i, 0)), "fixture parks unit " + str(i))
		unit.guard_stance = false
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.bleeding.ticks_left = 0
		unit.bleeding.source.clear()
		unit.bleeding.hit_id = ""
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, impact if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ARMOR, 0.0)
		unit.armor.natural["physical"] = 0
		for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	check(s.board.move_unit(s.units[0], Vector2i(1, 3)), "fixture actor")
	check(s.board.move_unit(s.units[1], Vector2i(2, 3)), "fixture direct target")
	check(s.board.move_unit(s.units[2], Vector2i(3, 3)), "fixture allied middle")
	check(s.board.move_unit(s.units[5], Vector2i(4, 3)), "fixture enemy end")
	check(s.select_unit(s.units[0].id), "fixture player selection")
	var rules := s.context.get_attack_rules()
	var definitions: Array[AttackDefinition] = []
	for source: AttackDefinition in rules._definitions:
		var definition := AttackRules._copy_definition(source)
		definition.chain_push = definition.profile == AttackRules.ARMOR_PROFILE and not definition.reaction_strike
		definitions.append(definition)
	s.context._attack_rules = AttackRules.new(rules._actors, rules._pairs, definitions)
	check(s.context.get_attack_rules().validate() == &"", "chain definition configuration")
	return s

func command(s: BattleCoreReactionsSession) -> AttackCommand:
	var a: UnitState = s.units[0]
	var b: UnitState = s.units[1]
	return AttackCommand.new(a.id, b.id, a.cell, b.cell, &"demo_strike", s.context.get_revision())

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "snapshot capture " + String(captured.reason))
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func events(receipt: ActionReceipt, kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in receipt.get_events():
		if event["kind"] == kind: result.append(event)
	return result

func parity(s: BattleCoreReactionsSession, label: String) -> ActionReceipt:
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var ids := UnitId.get_counter()
	var admission := SummonAdmission.values(s.context)
	var forecast := s.preview_attack(s.units[1].id)
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and UnitId.get_counter() == ids and SummonAdmission.values(s.context) == admission, label + " preview isolation")
	var receipt := s.attack_unit(s.units[1].id)
	check(receipt.status == forecast.status and receipt.reason == forecast.reason and receipt.get_events() == forecast.events and receipt.get_steps() == forecast.steps, label + " complete receipt parity: " + String(receipt.reason))
	check(snapshot(s) == forecast.snapshot_after and s.context.get_rng().to_dict() == forecast.rng_after and s.context.simulation_counters() == forecast.counters_after, label + " complete state parity")
	return receipt

func run() -> void:
	_normal_and_fraction()
	_stops_and_stance()
	_deaths()
	_shielded_collision_capacity()
	_geometry()
	_admission_and_faults()
	await _workers_and_restore()
	print("PUSH CHAIN RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _normal_and_fraction() -> void:
	var s := fixture()
	var a: UnitState = s.units[0]
	var direct: UnitState = s.units[1]
	var middle: UnitState = s.units[2]
	var last: UnitState = s.units[5]
	var receipt := parity(s, "three bodies, mixed factions")
	var links := events(receipt, &"chain_link")
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 2, "two links execute")
	if links.size() == 2:
		check(links[0]["actor_unit_id"] == a.id and links[0]["from_unit_id"] == direct.id and links[0]["target_unit_id"] == middle.id and links[0]["impulse"] == 12.0 and links[0]["broke"], "first link is allied Bor at 75 percent")
		check(links[1]["actor_unit_id"] == a.id and links[1]["from_unit_id"] == middle.id and links[1]["target_unit_id"] == last.id and links[1]["impulse"] == 9.0 and links[1]["broke"], "second link is enemy Dozorny at 75 percent")
	check(direct.cell == Vector2i(2, 3) and middle.cell == Vector2i(3, 3) and last.cell == Vector2i(5, 3), "only terminal body moves")
	check(events(receipt, &"collision").size() == 2 and events(receipt, &"moved").size() == 1, "two collisions and one move")
	s.close()
	s = fixture(10.0)
	receipt = parity(s, "fractional decay")
	links = events(receipt, &"chain_link")
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 2, "fractional chain executes")
	if links.size() == 2:
		check(links[0]["impulse"] == 7.5 and links[1]["impulse"] == 5.625, "75 percent remains exact across links")
	check(s.units[2].vitals.get_hp() == 244.0 and s.units[5].vitals.get_hp() == 251.0, "D0 floors 7.5 to 7 and 5.625 to 5 on each collision")
	check(s.units[5].cell == Vector2i(5, 3), "fractional force still pushes terminal")
	s.close()

func _stops_and_stance() -> void:
	var s := fixture()
	s.units[2].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 20.0)
	var receipt := parity(s, "middle holds")
	var links := events(receipt, &"chain_link")
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 1 and s.units[2].vitals.get_balance() == 12.0 and s.units[5].vitals.get_balance() == 0.0, "middle accumulates and stops before last")
	check(s.units[1].cell == Vector2i(2, 3) and s.units[2].cell == Vector2i(3, 3) and s.units[5].cell == Vector2i(4, 3), "held chain does not move")
	s.close()
	s = fixture()
	s.units[2].guard_stance = true
	receipt = parity(s, "middle guard halves onward impulse")
	links = events(receipt, &"chain_link")
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 2, "guarded middle still breaks")
	if links.size() == 2: check(links[0]["impulse"] == 6.0 and links[1]["impulse"] == 4.5, "guard attenuation is inherited by next transfer")
	s.close()
	s = fixture()
	s.units[2].control.entangled_turns = 1
	s.units[2].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 8.0)
	receipt = parity(s, "entangled middle holds doubled threshold")
	check(receipt.status == ActionReceipt.APPLIED and events(receipt, &"chain_link").size() == 1 and s.units[2].vitals.get_balance() == 12.0 and s.units[2].control.entangled_turns == 1 and s.units[5].cell == Vector2i(4, 3), "held entangle persists")
	s.close()
	s = fixture()
	s.units[5].control.entangled_turns = 1
	receipt = parity(s, "terminal entangle clears on move")
	check(receipt.status == ActionReceipt.APPLIED and s.units[5].cell == Vector2i(5, 3) and s.units[5].control.entangled_turns == 0, "only actual move clears terminal entangle")
	s.close()
	s = fixture()
	s.units[2].stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
	receipt = parity(s, "immune middle")
	links = events(receipt, &"chain_link")
	check(receipt.status == ActionReceipt.APPLIED and links.size() == 1 and not links[0]["broke"] and s.units[2].vitals.get_balance() == 0.0 and s.units[5].cell == Vector2i(4, 3), "zero maximum neither accumulates nor transmits")
	s.close()

func _deaths() -> void:
	var s := fixture()
	s.units[1].vitals.set_hp(1.0)
	var receipt := parity(s, "direct lethal")
	check(receipt.status == ActionReceipt.APPLIED and not s.units[1].is_alive() and events(receipt, &"chain_link").is_empty() and s.units[2].vitals.get_hp() == 256.0, "lethal direct hit never starts chain")
	s.close()
	for victim: int in [1, 2, 5]:
		s = fixture()
		s.units[victim].vitals.set_hp(12.0 if victim == 1 else 1.0)
		receipt = parity(s, "collision death " + str(victim))
		check(receipt.status == ActionReceipt.APPLIED and not s.units[victim].is_alive(), "collision kills selected body " + str(victim))
		check(events(receipt, &"chain_link").size() == 2 and s.units[1].cell == Vector2i(2, 3) and s.units[2].cell == Vector2i(3, 3) and s.units[5].cell == (Vector2i(4, 3) if victim == 5 else Vector2i(5, 3)), "death does not fill intermediate vacancy " + str(victim))
		var dead_cell: Vector2i = s.units[victim].cell
		check(s.board.occupant_at(dead_cell) == null, "dead occupancy cleared " + str(victim))
		s.close()

func _armor_item_with_capacity(s: BattleCoreReactionsSession, unit: UnitState) -> ItemInstance:
	for item: ItemInstance in s.state.get_owner(unit.id)._items.values():
		if item.get_definition().armor_max >= 3 and item._placement >= ItemOwnerState.EQUIPMENT_BASE:
			return item
	return null

func _shielded_collision_capacity() -> void:
	var s := fixture(100.0)
	var middle: UnitState = s.units[2]
	var terminal: UnitState = s.units[5]
	var middle_armor := _armor_item_with_capacity(s, middle)
	var terminal_armor := _armor_item_with_capacity(s, terminal)
	check(middle_armor != null and terminal_armor != null, "shielded chain collision fixture has equipped armor for both participants")
	if middle_armor == null or terminal_armor == null:
		s.close()
		return
	middle.vitals.set_hp(1.0)
	terminal.vitals.set_hp(1.0)
	middle_armor.armor_remaining = 1
	terminal_armor.armor_remaining = 1
	# Middle принимает оба collision packet: щит гасит первый и оставляет 1 HP
	# щита для смертельного overflow во второй паре.
	middle.armor.shield = SpellShield.make(&"mage.shield", 76, 2)
	terminal.armor.shield = SpellShield.make(&"mage.shield", 1, 1)
	var receipt := parity(s, "shielded lethal chain collisions")
	var collisions := events(receipt, &"collision")
	var shields := events(receipt, &"shield_changed")
	var armor_changes := events(receipt, &"armor_changed")
	var damaged := events(receipt, &"damaged")
	var died := events(receipt, &"died")
	var hits := events(receipt, &"hit_resolved")
	var expected_targets: Array[int] = [middle.id, middle.id, terminal.id]
	var shield_targets: Array[int] = []
	for event: Dictionary in shields: shield_targets.append(event.target_unit_id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.reason == &"", "shielded chain completes without capacity fault: %s" % String(receipt.reason))
	check(collisions.size() == 2 and shields.size() == 3 and shield_targets == expected_targets, "both collisions retain middle's two shield hits and terminal shield hit")
	check(armor_changes.size() >= 2 and damaged.size() >= 2 and died.size() == 2 and hits.size() >= 2, "both lethal overflow packets retain armor, damage, death and hit events (%d,%d,%d,%d)" % [armor_changes.size(), damaged.size(), died.size(), hits.size()])
	check(middle_armor.armor_remaining == 0 and terminal_armor.armor_remaining == 0 and middle.armor.shield.is_empty() and terminal.armor.shield.is_empty(), "both collision participants spend one armor and their shields")
	check(not middle.is_alive() and not terminal.is_alive(), "middle survives first shielded hit then both participants die from chain collision overflow")
	var pair_kinds: Array[StringName] = []
	if not collisions.is_empty():
		for event: Dictionary in receipt.get_events():
			if event.command_seq == collisions[-1].command_seq: pair_kinds.append(event.kind)
	check(pair_kinds == [&"collision", &"shield_changed", &"armor_changed", &"damaged", &"died", &"hit_resolved", &"shield_changed", &"armor_changed", &"damaged", &"died", &"hit_resolved"], "one pair step retains all eleven ordered events: " + str(pair_kinds))
	s.close()

func _geometry() -> void:
	for shape: String in ["wall", "ledge", "void", "hazard", "fall", "fire"]:
		var s := fixture()
		var destination := Vector2i(5, 3)
		match shape:
			"wall": s.board.set_terrain(destination, TerrainType.Type.WALL)
			"ledge": s.board.set_height_steps(destination, 2)
			"void": s.board.set_terrain(destination, TerrainType.Type.VOID)
			"hazard": s.board.set_terrain(destination, TerrainType.Type.HAZARD)
			"fall": s.board.set_height_steps(destination, -2)
			"fire": s.state.environment.ignite(destination)
		var receipt := parity(s, "terminal " + shape)
		check(receipt.status == ActionReceipt.APPLIED and events(receipt, &"chain_link").size() == 2, "terminal geometry keeps chain " + shape)
		if shape in ["wall", "ledge"]:
			check(s.units[5].cell == Vector2i(4, 3) and events(receipt, &"push_blocked").size() == 1, "wall or ledge blocks terminal " + shape)
		elif shape in ["void", "hazard"]:
			check(not s.units[5].is_alive() and s.units[1].cell == Vector2i(2, 3) and s.units[2].cell == Vector2i(3, 3), "lethal terrain kills only terminal movement " + shape)
		else:
			check(s.units[5].cell == destination and events(receipt, &"moved").size() == 1, "fall or fire moves only terminal " + shape)
		s.close()

func _admission_and_faults() -> void:
	var s := fixture()
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	s.units[2].stats._stats.erase(StatTypes.StatType.BALANCE_MAX)
	var invalid := s.units[2].stats.to_snapshot_dict()
	var receipt := s._queue.submit(command(s), s.context)
	check(receipt.status == ActionReceipt.REJECTED and String(receipt.reason).begins_with("chain/") and s.units[0].action_resources.get_main_left() == 1 and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters and s.units[2].stats.to_snapshot_dict() == invalid and s.units[1].vitals.get_hp() == 256.0, "reached invalid stat refuses before debit or RNG")
	s.close()
	s = fixture()
	var before := snapshot(s)
	receipt = s._queue.submit(PushChainCommand.new(), s.context)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"chain/internal_command" and snapshot(s) == before, "internal chain command cannot be root")
	s.close()
	for bound: String in ["commands", "events", "depth"]:
		s = fixture()
		match bound:
			"commands": s._queue._max_commands = 3
			"events": s._queue._max_events = 5
			"depth": s._queue._max_depth = 2
		receipt = parity(s, "queue " + bound)
		check(receipt.status == ActionReceipt.FAULTED and s.units[0].action_resources.get_main_left() == 0, "queue limit retains paid prefix " + bound)
		s.close()
	s = fixture()
	var middle: UnitState = s.units[2]
	var last: UnitState = s.units[5]
	var mutate := func(_old: float, _new: float) -> void: last.guard_stance = true
	middle.vitals.add_impact(0.5)
	middle.vitals.balance_changed.connect(mutate)
	receipt = s.attack_unit(s.units[1].id)
	middle.vitals.balance_changed.disconnect(mutate)
	check(receipt.status == ActionReceipt.FAULTED and s.units[0].action_resources.get_main_left() == 0 and s.units[1].vitals.get_hp() < 256.0 and last.cell == Vector2i(4, 3), "balance callback mutation faults after truthful paid prefix")
	s.close()
	s = fixture()
	middle = s.units[2]
	last = s.units[5]
	mutate = func(_old: float, _new: float) -> void: middle.guard_stance = true
	s.units[1].vitals.hp_changed.connect(mutate)
	receipt = s.attack_unit(s.units[1].id)
	s.units[1].vitals.hp_changed.disconnect(mutate)
	check(receipt.status == ActionReceipt.FAULTED and s.units[1].vitals.get_hp() < 256.0 and last.cell == Vector2i(4, 3), "direct HP callback faults without erasing applied hit")
	s.close()
	s = fixture()
	middle = s.units[2]
	last = s.units[5]
	var corrupt_move := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == last: middle.guard_stance = true
	s.board.unit_position_changed.connect(corrupt_move)
	receipt = s.attack_unit(s.units[1].id)
	s.board.unit_position_changed.disconnect(corrupt_move)
	check(receipt.status == ActionReceipt.FAULTED and last.cell == Vector2i(5, 3) and events(receipt, &"moved").size() == 1, "board move callback faults after truthful moved prefix")
	s.close()

func _workers_and_restore() -> void:
	var s := fixture()
	var before := snapshot(s)
	var expected := s.preview_attack(s.units[1].id)
	var worker := AttackForecastWorker.new()
	worker.start(s.prepare_attack_forecast(s.units[1].id))
	var detached: AttackForecast
	var deadline := Time.get_ticks_msec() + 5000
	while detached == null and Time.get_ticks_msec() < deadline:
		detached = worker.take_finished()
		if detached == null: await create_timer(0.002).timeout
	worker.close()
	check(detached != null, "forecast worker completes")
	if detached != null:
		check(detached.status == expected.status and detached.reason == expected.reason and detached.events == expected.events and detached.steps == expected.steps and detached.snapshot_after == expected.snapshot_after and detached.rng_after == expected.rng_after and detached.counters_after == expected.counters_after, "forecast worker exact chain parity")
	check(snapshot(s) == before, "worker leaves live snapshot isolated")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var decoded := ItemSimulationSnapshot.from_dict(before)
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == before, "chain fixture restores without runtime sharing")
	if restored.state != null: ForecastSimulation.close(restored.state)
	var live := BattleExecutionWorker.new()
	check(BattleExecutionWorker.can_transfer(s) and live.start(s, &"attack_unit", [s.units[1].id], true), "live worker accepts chain graph")
	var completed := live.take_finished(true)
	var receipt := completed.get("result") as ActionReceipt
	check(receipt != null, "live worker returns receipt")
	if receipt != null:
		check(receipt.status == expected.status and receipt.reason == expected.reason and receipt.get_events() == expected.events and receipt.get_steps() == expected.steps and snapshot(s) == expected.snapshot_after and s.context.get_rng().to_dict() == expected.rng_after and s.context.simulation_counters() == expected.counters_after, "live worker exact chain parity")
	s.close()
