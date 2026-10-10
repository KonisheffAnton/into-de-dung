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
	_delayed()
	_leave_reenter()
	_falls()
	_push_and_wall()
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
	check(before.schema_version == 5 and before.status_effects == false and CombatEnvironmentState.from_dict(before).to_dict() == before, "empty environment roundtrips with explicit disabled capability")
	var old_shape := before.duplicate(true); old_shape.schema_version = 4; old_shape.erase("status_effects")
	check(not CombatEnvironmentState.valid(old_shape), "old environment reader format is refused")
	old.close()
	var s := fixture()
	plate(s, Vector2i(2, 4))
	s.state.environment.hazards.acid.append(Vector2i(4, 4))
	var raw := snap(s)
	check(raw.environment.schema_version == 5 and raw.environment.status_effects and CombatEnvironmentState.from_dict(raw.environment).to_dict() == raw.environment, "current environment schema roundtrip")
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
	check(s.board.get_height_steps(Vector2i(4, 3)) - s.board.get_height_steps(Vector2i(4, 2)) == 2, "opening ledge provides one-tile fall onto floor plate")
	check(started.profile.to_dict() == profile_before, "battle authoring preserves profile4 and persisted plan")
	snap(s); s.close()
