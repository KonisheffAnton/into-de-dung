extends Command
class_name StatusTurnUnitCommand

var _unit: UnitState
var _stage: int

func _init(unit: UnitState = null, stage: int = 0) -> void:
	_unit = unit; _stage = stage
func get_kind() -> StringName: return &"status_turn_unit"
func copy_for_queue() -> Command: return StatusTurnUnitCommand.new(_unit, _stage)
func validate(context: ActionContext) -> StringName:
	if context == null or _unit == null or context.get_state().get_board().get_unit_by_id(_unit.id) != _unit or not ElementalRules.valid_unit(_unit) or _stage not in [0, 1, 2, 3, 4]: return &"status/invalid_turn"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if not _unit.is_alive(): return CommandStepResult.skipped(&"status/dead_target")
	var children: Array[Command] = []
	if _stage == 0:
		var environment := context.get_state().environment
		if environment != null:
			var cell := environment.fire_at(_unit.cell)
			if cell.get("effect", "") == "burning": children.append(EnvironmentCommand.for_entry(_unit.id, _unit.cell, context))
	elif _stage == 1:
		if _unit.elemental.burning_stacks > 0: children.append(ElementalTickCommand.new(_unit))
	elif _stage == 2 and _unit.bleeding.ticks_left > 0:
		children.append(BleedingTickCommand.new(_unit))
	elif _stage == 3:
		var environment := context.get_state().environment
		var standing: bool = environment != null and _unit.cell in environment.hazards.get("acid", [])
		if standing or _unit.elemental.acid_ticks > 0: children.append(AcidCommand.new(_unit, true, standing))
	elif _stage == 4:
		if _unit.elemental.poison_stacks > 0: children.append(ElementalTickCommand.new(_unit, false, true))
	# Следующий шаг читает уже завершённую клетку/тик, не устаревший снимок статуса.
	var environment := context.get_state().environment
	var acid_active: bool = _unit.elemental.acid_ticks > 0 or (environment != null and _unit.cell in environment.hazards.get("acid", []))
	var next_stage: int = _stage + 1 if _stage < 2 or (_stage == 2 and acid_active) else 4
	var continuation: Command = null
	if _stage < 2 or (_stage == 2 and acid_active) or (_stage < 4 and _unit.elemental.poison_stacks > 0):
		continuation = StatusTurnUnitCommand.new(_unit, next_stage)
	return CommandStepResult.applied([], children, [], continuation)
