extends Command
class_name ControlExpireCommand

var _unit: UnitState
var _control: ControlState
var _before: Dictionary

func _init(unit: UnitState = null) -> void:
	_unit = unit
	_control = unit.control if unit != null else null
	_before = _control.to_dict() if _control != null else {}

func get_kind() -> StringName: return &"control_expire"
func copy_for_queue() -> Command:
	var result := ControlExpireCommand.new(_unit)
	result._control = _control
	result._before = _before.duplicate(true)
	return result

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or _unit == null or _unit.control != _control or _control == null or _control.get_script() != ControlState or _control.to_dict() != _before or not ControlState.valid(_before): return &"control/invalid_binding"
	if context.get_state().get_board().get_unit_by_id(_unit.id) != _unit: return &"control/invalid_binding"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var after := _before.duplicate(true)
	after["stunned_turns"] = 0
	after["entangled_turns"] = 0
	if after == _before: return CommandStepResult.applied([])
	_control.stunned_turns = 0
	_control.entangled_turns = 0
	return CommandStepResult.applied([{"kind": &"control_changed", "target_unit_id": _unit.id, "before": _before.duplicate(true), "after": after, "reason": &"turn_end"}], [], [], null, true)
