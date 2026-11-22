extends SceneTree

var passed: int = 0
var failed: int = 0

class InternalStep extends Command:
	var child: Command
	func _init(command: Command) -> void: child = command
	func get_kind() -> StringName: return &"hazard_test_parent"
	func copy_for_queue() -> Command: return InternalStep.new(child.copy_for_queue())
	func validate(context: ActionContext) -> StringName: return child.validate(context)
	func execute(_context: ActionContext) -> CommandStepResult: return CommandStepResult.applied([], [child])

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HAZARDS: " + label)

func _run() -> void:
	_codec()
	_deep_acid_codec()
	_deep_acid_ai()
	_delayed()
	_leave_reenter()
	_falls()
	_push_and_wall()
	_ledge_traps_and_obstacle()
	_acid_turns()
	_collapse_and_fault()
	_prior_death_and_admission()
	await _parity_workers()
	_opening()
	print("HAZARDS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func fixture() -> BattleCoreReactionsSession:
	var s := BattleCoreReactionsSession.new()
	s.state.abilities = null
	s.phase = BattleTacticalSession.Phase.PLAYER_TURN
	s.state.environment.fires.clear()
	s.state.environment.hazards = BattleHazards.empty()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for u: UnitState in s.units: s.board.clear_occupancy(u)
	for i: int in s.units.size():
		var u := s.units[i]
		if not u.is_alive(): continue
		s.board.move_unit(u, Vector2i(i, 0))
		u.stats.set_base_value(StatTypes.StatType.HP_MAX, 1000.0)
		u.vitals._hp = 1000.0
		u.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1.0)
		u.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 16.0 if i == 0 else 0.0)
		u.stats.set_base_value(StatTypes.StatType.STRENGTH, 1.0 if i == 0 else 0.0)
		u.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		u.control.stunned_turns = 0; u.control.entangled_turns = 0
		if u.combat_perks != null: u.combat_perks.mode = CombatPerksState.Mode.NONE
		u.move_points_left = 100.0
		u.action_resources._main_left = 10
	s.board.move_unit(s.units[0], Vector2i(2, 3))
	s.board.move_unit(s.units[1], Vector2i(3, 3))
	s.selected_id = s.units[0].id
	return s

func snap(s: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "snapshot captures: " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func move(s: BattleCoreReactionsSession, unit: UnitState, to: Vector2i) -> ActionReceipt:
	var path: Array[Vector2i] = [unit.cell, to]
	return s._queue.submit(MoveCommand.new(unit.id, path, s.context.get_revision()), s.context)

func turn(s: BattleCoreReactionsSession, team: int) -> ActionReceipt:
	return s._queue.submit(BleedingTurnCommand.new(team as Faction.Type, s.context.get_revision()), s.context)

func count(receipt: ActionReceipt, kind: StringName) -> int:
	var found := 0
	for event: Dictionary in receipt.get_events():
		if event.kind == kind: found += 1
	return found

func plate(s: BattleCoreReactionsSession, cell: Vector2i) -> void:
	check(BattleHazards.add_trap(s.state.environment.hazards, cell), "floor plate added")

func _codec() -> void:
	var old := BattleEnvironmentSession.new()
	var before := old.state.environment.to_dict()
	check(before.schema_version == 6 and before.status_effects == false and CombatEnvironmentState.from_dict(before).to_dict() == before, "empty environment roundtrips with explicit disabled capability")
	var old_shape := before.duplicate(true); old_shape.schema_version = 4; old_shape.erase("status_effects")
	check(not CombatEnvironmentState.valid(old_shape), "old environment reader format is refused")
	old.close()
	var s := fixture()
	plate(s, Vector2i(2, 4))
	s.state.environment.hazards.acid.append(Vector2i(4, 4))
	var raw := snap(s)
	check(raw.environment.schema_version == 6 and raw.environment.status_effects and CombatEnvironmentState.from_dict(raw.environment).to_dict() == raw.environment, "current environment schema roundtrip")
	var detached := CombatEnvironmentState.from_dict(raw.environment)
	detached.hazards.traps[0].armed_team = Faction.Type.ENEMY
	check(s.state.environment.hazards.traps[0].armed_team == -1, "detached timers do not alias live")
	for key: String in ["schema_version", "next_id"]:
		var broken: Dictionary = raw.environment.duplicate(true)
		broken.hazards[key] = true
		check(not CombatEnvironmentState.valid(broken), "reject typed hazard field " + key)
	var broken: Dictionary = raw.environment.duplicate(true)
	broken.schema_version = 4.0
	check(not CombatEnvironmentState.valid(broken), "reject float environment schema")
	broken = raw.environment.duplicate(true); broken.hazards.traps[0].extra = 0
	check(not CombatEnvironmentState.valid(broken), "reject extra trap field")
	broken = raw.duplicate(true); broken.environment.hazards.traps[0].cell = Vector2i(-1, 2)
	check(ItemSimulationSnapshot.from_dict(broken).code != ItemSnapshotResult.Code.OK, "reject off-board trap")
	broken = raw.duplicate(true); broken.environment.hazards.traps[0].occupant_id = 99999
	check(ItemSimulationSnapshot.from_dict(broken).code != ItemSnapshotResult.Code.OK, "reject unknown latch occupant")
	broken = raw.duplicate(true); broken.environment.hazards.acid = [Vector2i(4, 4), Vector2i(4, 4)]
	check(ItemSimulationSnapshot.from_dict(broken).code != ItemSnapshotResult.Code.OK, "reject duplicate acid")
	s.close()

func _deep_acid_codec() -> void:
	check(TerrainType.Type.DEEP_ACID == 4 and TerrainType.Type.VOID == 3, "terrain IDs append without renumbering")
	var board := BattleBoard.new(6, 1)
	for kind: int in 5: board.set_terrain(Vector2i(kind, 0), kind as TerrainType.Type)
	var raw := board.to_snapshot_dict()
	check(BattleBoard.validate_snapshot_dict(raw), "board2 accepts all five terrain IDs")
	var restored := BattleBoard.from_snapshot_dict(raw)
	check(restored != null and restored.to_snapshot_dict() == raw, "board2 deep acid roundtrip")
	var captured := SimulationSnapshot.capture_board(board, [])
	check(captured.code == BoardSnapshotResult.Code.OK and captured.snapshot.instantiate_board().to_snapshot_dict() == raw, "board-only snapshot roundtrips deep acid")
	var broken := raw.duplicate(true)
	broken.terrain[0] = 5
	check(not BattleBoard.validate_snapshot_dict(broken) and BattleBoard.from_snapshot_dict(broken) == null, "unknown future terrain ID rejected by board")
	check(SimulationSnapshot.from_dict({"schema_version": 1, "scope": SimulationSnapshot.SCOPE, "board": broken}).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "unknown terrain rejected by board-only snapshot")
	var s := fixture()
	s.board.set_terrain(Vector2i(4, 4), TerrainType.Type.DEEP_ACID)
	var item_raw := snap(s)
	check(ItemSimulationSnapshot.from_dict(item_raw).code == ItemSnapshotResult.Code.OK, "item snapshot accepts deep acid")
	check(s.state.environment.hazards.acid.is_empty(), "deep liquid is independent from shallow corrosion cells")
	s.close()

func _deep_acid_ai() -> void:
	var s := fixture()
	var actor := s.units[0]
	s.board.move_unit(s.units[1], Vector2i(4, 3))
	for cell: Vector2i in [Vector2i(1, 3), Vector2i(2, 2), Vector2i(2, 4)]:
		s.board.set_terrain(cell, TerrainType.Type.WALL)
	var bt := BattleDemoBT.new()
	bt._session = s
	bt._actor = actor
	check(bt._advance() != null, "AI can advance through ordinary corridor")
	s.board.set_terrain(Vector2i(3, 3), TerrainType.Type.DEEP_ACID)
	var before := snap(s)
	var rng := s.context.get_rng().to_dict()
	check(bt._advance() == null, "AI refuses only available route into deep acid")
	check(snap(s) == before and s.context.get_rng().to_dict() == rng, "AI refusal leaves snapshot and RNG unchanged")
	s.state.environment.collapse = {"turn": 1, "marked": [actor.cell]}
	before = snap(s)
	check(bt._escape_collapse() == null, "AI cannot escape collapse into deep acid")
	check(snap(s) == before and s.context.get_rng().to_dict() == rng, "collapse escape refusal preserves state")
	s.board.set_terrain(Vector2i(2, 2), TerrainType.Type.FLOOR)
	var advance := bt._advance()
	var escape := bt._escape_collapse()
	check(advance != null and not advance.path.has(Vector2i(3, 3)), "AI finds alternate path around deep acid")
	check(escape != null and not escape.path.has(Vector2i(3, 3)), "collapse escape uses alternate safe route")
	s.close()

func _delayed() -> void:
	for team: int in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
		var s := fixture()
		var u := s.units[0] if team == Faction.Type.PLAYER else s.units[1]
		var dest := u.cell + Vector2i.DOWN
		plate(s, dest)
		u.armor.natural = {"physical": 10000, "fire": 10000}
		var hp := u.vitals.get_hp()
		var rng := s.context.get_rng().to_dict()
		var entry := move(s, u, dest)
		check(entry.status == ActionReceipt.APPLIED and count(entry, &"trap_armed") == 1 and u.vitals.get_hp() == hp, "voluntary step arms without damage")
		var opposite := Faction.Type.ENEMY if team == Faction.Type.PLAYER else Faction.Type.PLAYER
		var other := turn(s, opposite)
		check(count(other, &"trap_fired") == 0 and u.is_alive(), "opposing turn does not fire")
		var fired := turn(s, team)
		check(fired.status == ActionReceipt.APPLIED and count(fired, &"trap_fired") == 1 and count(fired, &"died") == 1 and not u.is_alive(), "own next turn kills through resistance and armor")
		check(s.state.environment.corpses_at(dest).size() == 1 and s.board.occupant_at(dest) == null, "ordinary trap death creates one corpse and frees tile")
		check(count(turn(s, team), &"trap_fired") == 0, "remaining corpse does not re-trigger")
		check(s.context.get_rng().to_dict() == rng, "trap and waiting turns use no random draws")
		s.close()

func _leave_reenter() -> void:
	var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
	plate(s, dest)
	move(s, u, dest)
	move(s, u, Vector2i(2, 5))
	check(s.state.environment.hazards.traps[0].occupant_id == 0 and s.state.environment.hazards.traps[0].armed_team == u.faction, "leaving clears latch but retains timer")
	check(count(turn(s, u.faction), &"trap_fired") == 1 and u.is_alive(), "empty armed plate fires harmlessly")
	check(count(turn(s, u.faction), &"trap_fired") == 0, "empty plate remains retracted")
	check(count(move(s, u, dest), &"trap_armed") == 1, "same character can rearm after leave and return")
	# Завершённое срабатывание с живым occupant моделирует будущую нелетальную настройку.
	s.state.environment.hazards.traps[0].armed_team = -1
	var repeated := s._queue.submit(InternalStep.new(HazardCommand.new(s.state.environment, u, dest, true)), s.context)
	check(count(repeated, &"trap_fired") == 0 and u.is_alive(), "contact on same occupant does not fire again")
	s.close()

func _falls() -> void:
	for steps: int in [0, 1, 2, 4]:
		var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
		s.board.set_height_steps(u.cell, steps)
		u.height = s.board.get_height(u.cell)
		plate(s, dest)
		var receipt := move(s, u, dest)
		check(receipt.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], "fall movement completes its allowed prefix")
		check(count(receipt, &"trap_fired") == (1 if steps >= 2 else 0) and u.is_alive() == (steps < 2), "drop threshold is one full tile (2 halfsteps): %d" % steps)
		s.close()

func _push_and_wall() -> void:
	for wall: bool in [false, true]:
		var s := fixture(); var victim := s.units[1]
		var target := victim.cell + Vector2i.RIGHT
		if wall:
			s.board.set_terrain(target, TerrainType.Type.WALL)
			var legacy_hazards := BattleHazards.empty()
			legacy_hazards.erase("wall_mount")
			s.state.environment.hazards = legacy_hazards
			check(BattleHazards.add_trap(s.state.environment.hazards, victim.cell, "wall", Vector2i.RIGHT), "wall face authored")
		else: plate(s, target)
		var forecast := s.preview_attack(victim.id)
		var receipt := s.attack_unit(victim.id)
		check(receipt.status == ActionReceipt.APPLIED and not victim.is_alive() and count(receipt, &"trap_fired") == 1, "real attack/push triggers " + ("wall" if wall else "floor"))
		check(victim.cell == (Vector2i(3, 3) if wall else target), "wall collision does not move through wall")
		check(forecast.status == receipt.status and forecast.events == receipt.get_events() and forecast.steps == receipt.get_steps() and forecast.snapshot_after == snap(s) and forecast.rng_after == s.context.get_rng().to_dict() and forecast.counters_after == s.context.simulation_counters(), "attack preview/live complete parity")
		s.close()
	var s := fixture(); var u := s.units[0]
	s.board.set_terrain(Vector2i(3, 4), TerrainType.Type.WALL)
	var legacy_hazards := BattleHazards.empty()
	legacy_hazards.erase("wall_mount")
	s.state.environment.hazards = legacy_hazards
	BattleHazards.add_trap(s.state.environment.hazards, Vector2i(2, 4), "wall", Vector2i.RIGHT)
	var entry := move(s, u, Vector2i(2, 4))
	check(u.is_alive() and count(entry, &"trap_fired") == 0 and count(turn(s, u.faction), &"trap_fired") == 0, "walking beside wall and standing do not activate wall spikes")
	s.close()

func _acid_turns() -> void:
	var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
	s.state.environment.hazards.acid.append(dest)
	var hp := u.vitals.get_hp()
	u.armor.grants = [{"grant_id": 1, "source": "fixture", "remaining": 100, "expires": "battle", "battle_id": 1}]
	u.armor.next_grant_id = 2
	var entry := move(s, u, dest)
	check(entry.status == ActionReceipt.APPLIED and u.elemental.acid_ticks == 1 and u.armor.grants[0].remaining == 100, "puddle entry adds duration without immediate armor damage")
	turn(s, Faction.Type.ENEMY)
	check(u.elemental.acid_ticks == 1 and u.armor.grants[0].remaining == 100, "opponent turn does not tick acid")
	turn(s, u.faction); turn(s, u.faction)
	check(u.elemental.acid_ticks == 3 and u.armor.grants[0].remaining == 80 and u.vitals.get_hp() == hp, "standing adds duration and fixed armor10 per own turn")
	move(s, u, Vector2i(2, 5))
	for i: int in 3: turn(s, u.faction)
	check(u.elemental.acid_ticks == 0 and u.armor.grants[0].remaining == 50 and u.vitals.get_hp() == hp, "leaving consumes accumulated duration without HP loss")
	turn(s, u.faction)
	check(u.armor.grants[0].remaining == 50, "expired acid no longer damages armor")
	s.close()

func _collapse_and_fault() -> void:
	var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
	plate(s, dest); s.state.environment.hazards.acid.append(dest)
	move(s, u, dest); move(s, u, Vector2i(2, 5))
	s.state.environment.collapse = {"turn": 1, "marked": [dest]}
	var receipt := s._queue.submit(CollapsePhaseCommand.new(s.context.get_revision()), s.context)
	check(receipt.status == ActionReceipt.APPLIED and s.state.environment.hazards.traps.is_empty() and s.state.environment.hazards.acid.is_empty(), "collapse removes plate timer and puddle")
	check(u.elemental.acid_ticks == 1 and count(turn(s, u.faction), &"trap_fired") == 0, "status survives lost source; removed trap does not fire")
	snap(s); s.close()
	s = fixture(); u = s.units[0]; plate(s, dest); move(s, u, dest)
	var mutate := func(_before: float, _after: float) -> void: u.elemental.acid_ticks = 1
	u.vitals.hp_changed.connect(mutate)
	receipt = turn(s, u.faction)
	check(receipt.status == ActionReceipt.FAULTED and u.vitals.get_hp() == 0.0 and u.vitals.is_alive() and count(receipt, &"died") == 0, "HP callback mutation faults before death and preserves written prefix")
	u.vitals.hp_changed.disconnect(mutate)
	s.close()

func _prior_death_and_admission() -> void:
	for falling: bool in [false, true]:
		var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
		plate(s, dest)
		u.vitals._hp = 1.0
		for item: ItemInstance in s.state.get_owner(u.id)._items.values(): item.armor_remaining = 0
		if falling:
			s.board.set_height_steps(u.cell, 4); u.height = 2
		else:
			u.bleeding.stacks = 1; u.bleeding.ticks_left = 3
			u.bleeding.source = DamageSource.new(&"attack", 0, s.units[1].cell, s.units[1].id, s.units[1].id).to_dict()
			u.bleeding.hit_id = "prior-death"
		var receipt := move(s, u, dest)
		check(receipt.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED] and not s.context.is_faulted() and not u.is_alive(), "prior lethal fall/bleeding ends normally before trap: " + str(falling))
		check(count(receipt, &"died") == 1 and count(receipt, &"trap_fired") == 0 and s.state.environment.corpses_at(dest).size() == 1, "prior death has one corpse and no second trap hit")
		s.close()
	var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
	plate(s, dest); move(s, u, dest)
	var before := snap(s); var counters := s.context.simulation_counters(); var rng := s.context.get_rng().to_dict()
	for command: Command in [HazardTurnCommand.new(u.faction), HazardCommand.new(s.state.environment, u, dest, true), AcidCommand.new(u, true, true)]:
		var receipt := s._queue.submit(command, s.context)
		check(receipt.status == ActionReceipt.REJECTED and receipt.reason == &"hazard/internal_command" and snap(s) == before and s.context.simulation_counters() == counters and s.context.get_rng().to_dict() == rng, "internal hazard/acid root rejected without side effects")
	s.context._next_event_seq = ActionContext.MAX_ID - 2
	var limited := s._queue.submit(InternalStep.new(HazardCommand.new(s.state.environment, null, dest, false, false, Vector2i.ZERO, 1, u.faction)), s.context)
	check(limited.status == ActionReceipt.FAULTED and limited.reason == &"sequence_exhausted" and u.is_alive() and u.vitals.get_hp() == 1000.0 and s.state.environment.hazards.traps[0].armed_team == u.faction, "three lethal events are reserved before trap mutation")
	s.close()

func _parity_workers() -> void:
	var s := fixture(); var u := s.units[0]; var dest := Vector2i(2, 4)
	plate(s, dest)
	var before := snap(s)
	var preview := ForecastSimulation.run_prepared(s.prepare_move_forecast(dest))
	var worker := MoveForecastWorker.new()
	worker.start(s.prepare_move_forecast(dest))
	var result: MoveForecast
	var deadline := Time.get_ticks_msec() + 10000
	while result == null and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
		result = worker.take_finished()
	worker.close()
	check(result != null and result.events == preview.events and result.steps == preview.steps and result.snapshot_after == preview.snapshot_after and result.rng_after == preview.rng_after and result.counters_after == preview.counters_after, "forecast worker matches full delayed trap result")
	check(snap(s) == before, "preview and worker leave live unchanged")
	var live := BattleExecutionWorker.new()
	check(live.start(s, &"move_to", [dest], true, true), "ownership audit accepts new hazards")
	var completed: Dictionary = {}
	deadline = Time.get_ticks_msec() + 10000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
		completed = live.take_finished()
	if completed.is_empty(): completed = live.take_finished(true)
	check(not completed.is_empty() and snap(s) == preview.snapshot_after and s.context.get_rng().to_dict() == preview.rng_after and s.context.simulation_counters() == preview.counters_after, "live worker matches isolated movement")
	var capture := ItemSimulationSnapshot.capture(s.state, [])
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners(): definitions.merge(owner._definitions)
	var restored := capture.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state.environment.to_dict() == s.state.environment.to_dict(), "armed runtime snapshot restores exactly")
	if restored.state != null:
		restored.state.environment.hazards.traps[0].armed_team = -1
		check(s.state.environment.hazards.traps[0].armed_team == u.faction, "restored armed timer owns its data")
		ForecastSimulation.close(restored.state)
	s.close()

func _opening() -> void:
	var hub := HeroHubState.create(443)
	hub.enable_mage_deck()
	var started := ExpeditionTransitions.apply(hub, "start")
	check(started.is_ok(), "production opening transition accepted")
	if not started.is_ok(): return
	var profile_before := started.profile.to_dict()
	var bundle := HeroHubBattleFactory.create(started.profile)
	check(not bundle.is_empty(), "factory builds real opening with new hazards")
	if bundle.is_empty(): return
	var s: BattleCoreReactionsSession = bundle.session
	check(s.state.environment.hazards.traps.size() == 3 and s.state.environment.hazards.acid == [Vector2i(2, 6)], "first room contains two floor plates, wall spikes and acid")
	check(s.board.get_terrain(Vector2i(3, 6)) == TerrainType.Type.DEEP_ACID and s.board.occupant_at(Vector2i(3, 6)) == null, "opening deep acid occupies a free D7 without changing shallow acid")
	var ledge_face_count: int = 0
	for trap: Dictionary in s.state.environment.hazards.traps:
		if trap.kind == "wall" and trap.cell == Vector2i(5, 3) and trap.direction == Vector2i.LEFT: ledge_face_count += 1
	var column_face_traps: int = 0
	for trap: Dictionary in s.state.environment.hazards.traps:
		if trap.kind == "wall" and trap.cell + trap.direction == Vector2i(3, 0): column_face_traps += 1
	check(ledge_face_count == 1 and column_face_traps == 0
		and s.board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.WALL,
		"production opening places the trap only on the (5,3) left ledge face, not column (3,0)")
	check(s.board.get_height_steps(Vector2i(4, 3)) - s.board.get_height_steps(Vector2i(5, 3)) == 2, "opening ledge has a two-half-step support-to-contact height difference")
	check(started.profile.to_dict() == profile_before, "battle authoring preserves profile manifest and persisted plan")
	snap(s); s.close()
func _ledge_fixture() -> BattleCoreReactionsSession:
	var s := fixture()
	var actor := s.units[0]
	var victim := s.units[1]
	s.board.set_height_steps(Vector2i(4, 3), 2)
	s.board.move_unit(actor, Vector2i(6, 3))
	s.board.move_unit(victim, Vector2i(5, 3))
	actor.height = s.board.get_height(actor.cell)
	victim.height = s.board.get_height(victim.cell)
	s.selected_id = actor.id
	check(BattleHazards.add_trap(s.state.environment.hazards, Vector2i(5, 3), "wall", Vector2i.LEFT),
		"schema1 ledge-mode trap added on contact floor")
	return s

func _snapshot_accepts(state: BattleCoreReactionsSession) -> bool:
	return ItemSimulationSnapshot.capture(state.state, []).code == ItemSnapshotResult.Code.OK

func _ledge_traps_and_obstacle() -> void:
	var empty_hazards := BattleHazards.empty()
	check(empty_hazards.schema_version == 1 and empty_hazards.get("wall_mount") == "ledge"
		and BattleHazards.valid(empty_hazards), "new empty hazard records explicitly select ledge mounts")
	var unknown_mount := empty_hazards.duplicate(true)
	unknown_mount.wall_mount = "unknown"
	check(not BattleHazards.valid(unknown_mount), "unknown wall mount mode is rejected")
	var wrong_mount_type := empty_hazards.duplicate(true)
	wrong_mount_type.wall_mount = 1
	check(not BattleHazards.valid(wrong_mount_type), "non-string wall mount mode is rejected")
	var extra_mount_field := empty_hazards.duplicate(true)
	extra_mount_field.extra = true
	check(not BattleHazards.valid(extra_mount_field), "unrecognized hazard fields are rejected")
	var legacy_empty := empty_hazards.duplicate(true)
	legacy_empty.erase("wall_mount")
	check(BattleHazards.valid(legacy_empty), "schema1 without wall_mount retains strict legacy wall semantics")
	var valid_ledge := _ledge_fixture()
	check(_snapshot_accepts(valid_ledge), "ledge wall trap accepts a raised floor support two half-steps above contact")
	valid_ledge.close()
	var legacy := fixture()
	legacy.board.set_terrain(Vector2i(6, 3), TerrainType.Type.WALL)
	var legacy_hazards := BattleHazards.empty()
	legacy_hazards.erase("wall_mount")
	legacy.state.environment.hazards = legacy_hazards
	check(BattleHazards.add_trap(legacy.state.environment.hazards, Vector2i(5, 3), "wall", Vector2i.RIGHT),
		"legacy schema1 wall-anchor fixture remains writable")
	var legacy_raw := snap(legacy)
	var wrong_legacy := legacy_raw.duplicate(true)
	wrong_legacy.environment.hazards.traps[0].cell = Vector2i(6, 3)
	wrong_legacy.environment.hazards.traps[0].direction = Vector2i.LEFT
	check(ItemSimulationSnapshot.from_dict(wrong_legacy).code != ItemSnapshotResult.Code.OK,
		"schema1 still requires a floor contact anchor adjacent to its WALL")
	var restored_legacy := ItemSimulationSnapshot.from_dict(legacy_raw)
	var legacy_roundtrip: Dictionary = restored_legacy.snapshot.to_dict() if restored_legacy.snapshot != null else {}
	var legacy_environment: Dictionary = legacy_roundtrip.get("environment", {})
	var legacy_roundtrip_hazards: Dictionary = legacy_environment.get("hazards", {})
	check(restored_legacy.code == ItemSnapshotResult.Code.OK
		and legacy_roundtrip_hazards.get("schema_version", 0) == 1
		and not legacy_roundtrip_hazards.has("wall_mount"),
		"schema1 wall-anchor snapshot roundtrips without implicit mount migration")
	legacy.close()
	var invalid_cases: Array[Dictionary] = [
		{"name": "WALL cannot be a ledge contact", "contact_wall": true},
		{"name": "WALL cannot support a ledge trap", "support_wall": true},
		{"name": "flat contact is not a ledge", "height": 0},
		{"name": "one half-step is below threshold", "height": 1},
		{"name": "downward support is invalid", "direction": Vector2i.DOWN},
		{"name": "VOID cannot support a wall trap", "support_void": true},
	]
	for test_case: Dictionary in invalid_cases:
		var invalid := _ledge_fixture()
		var row: Dictionary = invalid.state.environment.hazards.traps[0]
		if test_case.get("contact_wall", false): invalid.board.set_terrain(row.cell, TerrainType.Type.WALL)
		if test_case.get("support_wall", false):
			row.cell = Vector2i(3, 1)
			row.direction = Vector2i.UP
			invalid.board.set_terrain(Vector2i(3, 0), TerrainType.Type.WALL)
		if test_case.has("height"): invalid.board.set_height_steps(row.cell + row.direction, int(test_case.height))
		if test_case.get("direction", Vector2i.LEFT) == Vector2i.DOWN:
			row.direction = Vector2i.DOWN
			invalid.board.set_height_steps(row.cell, 2)
			invalid.board.set_height_steps(row.cell + row.direction, 0)
		if test_case.get("support_void", false): invalid.board.set_terrain(row.cell + row.direction, TerrainType.Type.VOID)
		check(not _snapshot_accepts(invalid), "snapshot rejects invalid ledge face: " + String(test_case.name))
		invalid.close()
	var column := _ledge_fixture()
	var column_trap: Dictionary = column.state.environment.hazards.traps[0]
	column_trap.cell = Vector2i(3, 0)
	column_trap.direction = Vector2i.DOWN
	column.board.set_terrain(column_trap.cell, TerrainType.Type.WALL)
	check(not _snapshot_accepts(column), "ledge trap cannot attach to the authored WALL column")
	column.close()
	var collapse := _ledge_fixture()
	var collapsing_cells: Array[Vector2i] = [Vector2i(4, 3)]
	collapse.state.environment.collapse = {"turn": 1, "marked": collapsing_cells}
	var collapse_command := CollapsePhaseCommand.new(collapse.context.get_revision())
	var collapse_receipt := collapse._queue.submit(collapse_command, collapse.context)
	var collapse_valid := _snapshot_accepts(collapse)
	check(collapse_receipt.status == ActionReceipt.APPLIED and collapse.state.environment.hazards.traps.is_empty()
		and collapse_valid, "collapsing a wall-face support removes its adjacent trap and restores a valid snapshot")
	collapse.close()
	var no_contact := _ledge_fixture()
	var mover := no_contact.units[1]
	var contact_hp := mover.vitals.get_hp()
	var pass_through := move(no_contact, no_contact.units[1], Vector2i(5, 4))
	check(pass_through.status == ActionReceipt.APPLIED and count(pass_through, &"trap_fired") == 0
		and mover.vitals.get_hp() == contact_hp,
		"wall-face trap does not fire during movement without a blocked collision")
	no_contact.close()
	var wrong_face := fixture()
	var wrong_actor := wrong_face.units[0]
	var wrong_victim := wrong_face.units[1]
	wrong_face.board.set_height_steps(Vector2i(5, 2), 2)
	wrong_face.board.set_height_steps(Vector2i(6, 3), 2)
	check(wrong_face.board.move_unit(wrong_actor, Vector2i(4, 3))
		and wrong_face.board.move_unit(wrong_victim, Vector2i(5, 3)), "wrong-face fixture places adjacent units")
	wrong_face.selected_id = wrong_actor.id
	check(BattleHazards.add_trap(wrong_face.state.environment.hazards, Vector2i(5, 3), "wall", Vector2i.UP),
		"mismatched face fixture remains a valid ledge trap")
	var wrong_direction := wrong_face.attack_unit(wrong_victim.id)
	var wrong_height_blocked := false
	for event: Dictionary in wrong_direction.get_events():
		wrong_height_blocked = wrong_height_blocked or (event.kind == &"push_blocked" and event.reason == &"height")
	check(wrong_height_blocked and count(wrong_direction, &"trap_fired") == 0
		and wrong_victim.cell == Vector2i(5, 3),
		"a real height collision on the opposite face does not activate a directionally mismatched trap")
	wrong_face.close()
	var live := _ledge_fixture()
	var live_victim := live.units[1]
	var baseline_rng := live.context.get_rng().to_dict()
	var baseline_counters := live.context.simulation_counters()
	var live_before := snap(live)
	var forecast := live.preview_attack(live_victim.id)
	check(snap(live) == live_before and live.context.get_rng().to_dict() == baseline_rng
		and live.context.simulation_counters() == baseline_counters, "ledge preview leaves live state untouched")
	var receipt := live.attack_unit(live_victim.id)
	var height_blocked := false
	var blocked_index: int = -1
	var fired_index: int = -1
	var events := receipt.get_events()
	for index: int in range(events.size()):
		var event: Dictionary = events[index]
		if event.kind == &"push_blocked" and event.reason == &"height":
			height_blocked = true
			blocked_index = index
		if event.kind == &"trap_fired": fired_index = index
	check(receipt.status == ActionReceipt.APPLIED and height_blocked and fired_index > blocked_index
		and count(receipt, &"trap_fired") == 1,
		"real attack triggers the matching high-ledge trap after the height-blocked push")
	var final_snapshot := snap(live)
	var live_rng := live.context.get_rng().to_dict()
	var live_counters := live.context.simulation_counters()
	check(forecast.status == receipt.status and forecast.events == events and forecast.steps == receipt.get_steps()
		and forecast.snapshot_after == final_snapshot and forecast.rng_after == live_rng
		and forecast.counters_after == live_counters,
		"ledge preview/live match events, steps, snapshot and RNG")
	check(live.context.simulation_counters() == forecast.counters_after,
		"live ledge attack records only its ordinary command counters")
	live.close()
	var obstacle := fixture()
	var walker := obstacle.units[0]
	var other := obstacle.units[1]
	check(obstacle.board.move_unit(other, Vector2i(4, 4)), "move the second fixture unit clear of the column test")
	var cell_blocker := obstacle.board.occupant_at(Vector2i(2, 0))
	check(cell_blocker != null and obstacle.board.move_unit(cell_blocker, Vector2i(4, 5)),
		"move the original unit at (2,0) clear of the relocation route")
	obstacle.board.set_terrain(Vector2i(3, 0), TerrainType.Type.WALL)
	var wall_hp := walker.vitals.get_hp()
	var relocation_path: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]
	var relocation := obstacle._queue.submit(MoveCommand.new(walker.id, relocation_path, obstacle.context.get_revision()), obstacle.context)
	check(relocation.status == ActionReceipt.APPLIED and walker.cell == Vector2i(2, 0),
		"voluntary-movement fixture relocates the walker through the command boundary")
	var blocked_move := move(obstacle, walker, Vector2i(3, 0))
	check(blocked_move.status != ActionReceipt.APPLIED and walker.cell == Vector2i(2, 0)
		and obstacle.board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.WALL
		and walker.vitals.get_hp() == wall_hp,
		"column WALL blocks voluntary movement and has no destructible HP state")
	var pusher := fixture()
	var attacker := pusher.units[0]
	var target := pusher.units[1]
	for unit: UnitState in pusher.units: pusher.board.clear_occupancy(unit)
	pusher.board.move_unit(attacker, Vector2i(1, 0))
	pusher.board.move_unit(target, Vector2i(2, 0))
	pusher.selected_id = attacker.id
	pusher.board.set_terrain(Vector2i(3, 0), TerrainType.Type.WALL)
	var column_push := pusher.attack_unit(target.id)
	var wall_blocked := false
	for event: Dictionary in column_push.get_events():
		wall_blocked = wall_blocked or (event.kind == &"push_blocked" and event.reason == &"wall")
	check(wall_blocked and target.cell == Vector2i(2, 0) and pusher.board.get_terrain(Vector2i(3, 0)) == TerrainType.Type.WALL
		and pusher.board.occupant_at(Vector2i(3, 0)) == null and count(column_push, &"trap_fired") == 0,
		"column WALL blocks push without a health-bearing target or wall trap")
	pusher.close()
	obstacle.close()
