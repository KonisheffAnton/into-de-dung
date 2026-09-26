extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SAFE RETREAT INTEGRATION: " + label)

func fixture() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s.state.environment.fires.clear()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in 6:
		check(s.board.move_unit(s.units[index], Vector2i(index, 0)), "park fixture")
		s.units[index].control.stunned_turns = 0
		s.units[index].control.entangled_turns = 0
	s.board.move_unit(s.units[0], Vector2i(0, 2))
	s.select_unit(s.units[0].id)
	return s

func command(s: BattleCoreReactionsSession) -> MoveCommand:
	return MoveCommand.new(s.selected_id, [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)], s.context.get_revision(), &"safe_retreat")

func snapshot(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "capture " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func parity(s: BattleCoreReactionsSession, cmd: MoveCommand, status: StringName) -> MoveForecast:
	var before := snapshot(s)
	var counters := s.context.simulation_counters()
	var rng := s.context.get_rng().to_dict()
	var allocator := UnitId.get_counter()
	var sync := MoveForecast.build(s.context, s._queue, cmd)
	var prepared := ForecastSimulation.prepare(s.context, s._queue, cmd)
	var worker := MoveForecastWorker.new()
	worker.start(prepared)
	var deadline := Time.get_ticks_msec() + 5000
	var result: MoveForecast
	while result == null and Time.get_ticks_msec() < deadline:
		result = worker.take_finished()
		if result == null: await create_timer(0.001).timeout
	worker.close()
	check(result != null and result.status == sync.status and result.reason == sync.reason and result.events == sync.events and result.steps == sync.steps and result.snapshot_after == sync.snapshot_after and result.rng_after == sync.rng_after and result.counters_after == sync.counters_after and result.admission_after == sync.admission_after, "prepared worker equals synchronous preview")
	check(snapshot(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng and UnitId.get_counter() == allocator, "previews preserve live state counters RNG and IDs")
	var receipt := s._queue.submit(cmd, s.context)
	check(receipt.status == status and sync.status == status, "expected result %s: %s/%s" % [status, receipt.status, receipt.reason])
	check(receipt.get_events() == sync.events and receipt.get_steps() == sync.steps and snapshot(s) == sync.snapshot_after and s.context.get_rng().to_dict() == sync.rng_after and s.context.simulation_counters() == sync.counters_after and SummonAdmission.values(s.context) == sync.admission_after, "complete live parity")
	if status == ActionReceipt.FAULTED: check(sync.units.is_empty() and sync.traversed_path.is_empty(), "fault does not expose ready preview")
	return sync

func run() -> void:
	for kind: int in 5:
		var s := fixture()
		var actor := s.selected_unit()
		for item: ItemInstance in s.state.get_owner(actor.id)._items.values(): item.armor_remaining = 0
		if kind in [0, 1]: s.state.environment.ignite(Vector2i(1, 2))
		if kind == 1: actor.vitals.set_hp(1)
		if kind == 2: s.board.set_terrain(Vector2i(1, 2), TerrainType.Type.HAZARD)
		if kind == 3:
			s.board.set_height_steps(actor.cell, 6)
			actor.height = 3
			actor.vitals.set_hp(1)
		if kind == 4: s._queue = ActionQueue.new(1)
		var status := ActionReceipt.APPLIED if kind == 0 else (ActionReceipt.FAULTED if kind == 4 else ActionReceipt.INTERRUPTED)
		var result := await parity(s, command(s), status)
		check(actor.action_resources.get_main_left() == 0, "hazard or fault retains single main payment")
		if kind in [1, 2, 3]: check(not actor.is_alive() and actor.cell == Vector2i(1, 2) and result.traversed_path.size() == 2, "lethal hazard retains only executed prefix")
		if kind == 0: check(actor.vitals.get_hp() < 32 and actor.cell == Vector2i(3, 2), "nonlethal spikes remain active")
		if kind == 4: check(actor.cell == Vector2i(1, 2) and actor.move_points_left == 4.0, "queue limit retains first paid segment")
		s.close()
	await transit_and_reactions()
	await helpers()
	callbacks()
	print("SAFE RETREAT INTEGRATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func transit_and_reactions() -> void:
	var s := fixture()
	s.board.move_unit(s.units[2], Vector2i(1, 2))
	var result := await parity(s, command(s), ActionReceipt.APPLIED)
	var moves: Array[Dictionary] = result.events.filter(func(e: Dictionary) -> bool: return e.get("kind") == &"moved")
	check(moves.size() == 2 and moves[0].transit_path.size() == 3 and moves[0].main_cost == 1 and moves[1].main_cost == 0 and s.units[0].move_points_left == 2.0, "transit pays main once and every edge")
	var malformed := moves[0].duplicate(true)
	malformed.erase("event_seq"); malformed.erase("root_id"); malformed.erase("command_seq"); malformed.erase("parent_event_seq")
	check(ActionQueue._valid_draft(malformed, s.context), "transit accepts exact recorded payment")
	malformed["main_after"] = 12
	check(not ActionQueue._valid_draft(malformed, s.context), "transit event rejects incorrect payment")
	s.close()
	s = fixture()
	for index: int in [1, 3]:
		var tank := s.units[index]
		s.board.move_unit(tank, Vector2i(0 if index == 1 else 1, 1))
		tank.combat_perks.definition.tank_reactions = true
		tank.combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
		tank.combat_perks.reaction_left = 1
		tank.guard_stance = true
	await parity(s, command(s), ActionReceipt.APPLIED)
	check(s.units[1].combat_perks.reaction_left == 1 and s.units[3].combat_perks.reaction_left == 1, "all opportunists remain unused across route")
	s.board.move_unit(s.units[1], Vector2i(3, 3))
	var receipt := s._queue.submit(MoveCommand.new(s.selected_id, [Vector2i(3, 2), Vector2i(4, 2)], s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.INTERRUPTED and receipt.reason == &"perks/opportunist_stopped" and s.units[1].combat_perks.reaction_left == 0, "following ordinary movement is no longer protected")
	s.close()

func helpers() -> void:
	var s := fixture()
	var owner := s.selected_unit()
	var receipt := s.use_summoning_item(Vector2i(1, 2))
	var helper := s.state.active_summon(owner.id)
	check(receipt.status == ActionReceipt.APPLIED and helper != null, "summon helper")
	if helper == null:
		s.close()
		return
	var cmd := MoveCommand.new(helper.id, [helper.cell, Vector2i(2, 2)], s.context.get_revision(), &"safe_retreat")
	check(cmd.validate(s.context) == &"move/not_admitted", "pending helper denied")
	receipt = s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
	check(receipt.status == ActionReceipt.APPLIED and not s.state.is_summon_pending(helper.id), "real refill admits helper")
	s.select_unit(helper.id)
	cmd = MoveCommand.new(helper.id, [helper.cell, Vector2i(2, 2)], s.context.get_revision(), &"safe_retreat")
	await parity(s, cmd, ActionReceipt.APPLIED)
	check(s.state.active_summon(owner.id) == helper and helper.action_resources.get_main_left() == 0, "helper identity and paid resource survive")
	s.close()

func callbacks() -> void:
	var s := fixture()
	var actor := s.selected_unit()
	var observed: Array[int] = []
	var callback := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		observed.append(unit.action_resources.get_main_left())
		unit.action_resources._set_for_refill(1, unit.action_resources.get_bonus_left())
	s.board.unit_position_changed.connect(callback)
	check(not BattleExecutionWorker.can_transfer(s), "external callback prevents live worker transfer")
	var receipt := s._queue.submit(command(s), s.context)
	s.board.unit_position_changed.disconnect(callback)
	check(observed == [0] and receipt.status == ActionReceipt.FAULTED and actor.cell == Vector2i(1, 2) and actor.move_points_left == 4.0, "callback sees paid main; guard detects corruption after real prefix")
	check(receipt.get_events().size() == 1 and receipt.get_events()[0].main_cost == 1 and receipt.get_events()[0].main_after == 0, "fault event preserves commanded payment")
	s.close()
