extends Command
class_name HazardCommand

## Внутренняя команда контакта/таймера; вызывается после обязательного падения.
var _environment: CombatEnvironmentState
var _unit: UnitState
var _cell: Vector2i
var _direction: Vector2i
var _immediate: bool
var _wall: bool
var _trap_id: int
var _team: int
var _seal: Array

func _init(environment: CombatEnvironmentState = null, unit: UnitState = null, cell: Vector2i = Vector2i.ZERO, immediate: bool = false, wall: bool = false, direction: Vector2i = Vector2i.ZERO, trap_id: int = 0, team: int = -1) -> void:
	_environment = environment; _unit = unit; _cell = cell; _immediate = immediate
	_wall = wall; _direction = direction; _trap_id = trap_id; _team = team
	_seal = _values()

func _values() -> Array:
	return [_environment, _unit, _cell, _immediate, _wall, _direction, _trap_id, _team]

func get_kind() -> StringName: return &"hazard_trigger" if _trap_id > 0 else &"hazard_contact"
func copy_for_queue() -> Command:
	var result := HazardCommand.new(_environment, _unit, _cell, _immediate, _wall, _direction, _trap_id, _team)
	result._seal = _seal.duplicate()
	return result

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or _values() != _seal or _environment == null or context.get_state().environment != _environment or not BattleHazards.valid(_environment.hazards): return &"hazard/invalid_binding"
	if _trap_id > 0:
		if _team not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return &"hazard/invalid_team"
	elif _unit == null or context.get_state().get_board().get_unit_by_id(_unit.id) != _unit:
		return &"hazard/invalid_unit"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var board := context.get_state().get_board()
	var next := _environment.hazards.duplicate(true)
	var trap: Dictionary = {}
	var target: UnitState = _unit
	var fire := false
	var armed := false
	if _trap_id > 0:
		for row: Dictionary in next.traps:
			if row.id == _trap_id: trap = row
		if trap.is_empty() or trap.armed_team != _team: return CommandStepResult.skipped(&"hazard/not_armed")
		target = board.occupant_at(trap.cell)
		trap.armed_team = -1
		fire = true
	else:
		# Выход снимает защёлку присутствия, но уже взведённый таймер не отменяет.
		for row: Dictionary in next.traps:
			if row.occupant_id == target.id and row.cell != target.cell: row.occupant_id = 0
		if target.is_alive():
			for row: Dictionary in next.traps:
				if row.cell == _cell and row.kind == ("wall" if _wall else "floor") and row.direction == _direction: trap = row
			if not trap.is_empty() and trap.occupant_id != target.id:
				trap.occupant_id = target.id if target.cell == _cell else 0
				if _immediate or _wall:
					trap.armed_team = -1
					fire = true
				elif trap.armed_team == -1 and target.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
					trap.armed_team = int(target.faction)
					armed = true
	var participants: Array[UnitState] = []
	var cells: Array[Vector2i] = [_cell]
	if target != null:
		if target.is_alive(): participants.append(target)
		cells.append(target.cell)
	if fire and target != null and target.is_alive() and board.board_version >= ActionContext.MAX_ID: return CommandStepResult.faulted(&"push/board_version_exhausted")
	var guard := SpatialRules.capture_guard(context, participants, cells, {})
	if guard == null or not CombatEnvironmentState.valid(_environment.to_dict()) or not BattleHazards.valid(next): return CommandStepResult.faulted(&"hazard/invalid_state")
	var result := CommandStepResult.applied()
	if next != _environment.hazards:
		guard = guard.copy()
		guard.values.environment["hazards"] = BattleHazards.canonical(next)
		guard.seal()
		_environment.hazards = next
		result.state_changed = true
		if not guard.check(context): return CommandStepResult._make(CommandStepResult.FAULTED, &"hazard/checkpoint", [], [], [], null, true)
	if fire or armed:
		result.events.append({"kind": &"trap_fired" if fire else &"trap_armed", "actor_unit_id": 0, "target_unit_id": target.id if target != null else 0, "trap_id": trap.id, "cell": trap.cell, "trap_kind": trap.kind, "direction": trap.direction})
	if fire and target != null and target.is_alive():
		# Временная летальная настройка явно обходит броню/щиты; RNG не расходуется.
		var damage := maxf(float(BattleHazards.SPIKE_DAMAGE), target.vitals.get_hp())
		var written := guard.hp_phase(target.id, damage, false)
		var done := guard.hp_phase(target.id, damage, true)
		var checkpoint := func(stage: StringName) -> StringName:
			return &"" if _values() == _seal and (written if stage == &"hp_written" else done).check(context) else &"hazard/checkpoint"
		var source := DamageSource.new(&"cell", trap.id, trap.cell)
		var receipt := target.vitals.apply_spatial_damage(damage, checkpoint)
		var hit := ActionHpExecutor._spatial_result(receipt, target.id, source, false)
		result.events.append_array(hit.events)
		result.state_changed = result.state_changed or hit.state_changed
		result.status = hit.status; result.reason = hit.reason
	if result.status == CommandStepResult.APPLIED and _trap_id == 0 and not _wall and target.is_alive() and _cell in next.acid:
		result.mandatory.append(AcidCommand.new(target))
	return result
