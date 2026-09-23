extends Command
class_name ControlTurnEndCommand

var _faction: Faction.Type
var _revision: int

func _init(faction: Faction.Type = Faction.Type.PLAYER, revision: int = 0) -> void:
	_faction = faction
	_revision = revision

func get_kind() -> StringName: return &"control_turn_end"
func copy_for_queue() -> Command: return ControlTurnEndCommand.new(_faction, _revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_revision() != _revision: return &"control/stale_turn"
	if _faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return &"control/invalid_team"
	for unit: UnitState in context.get_state().get_board().get_all_units():
		if unit.control != null and (unit.control.get_script() != ControlState or not ControlState.valid(unit.control.to_dict())): return &"control/invalid_state"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var units := context.get_state().get_board().get_all_units()
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	var children: Array[Command] = []
	for unit: UnitState in units:
		if unit.faction == _faction and unit.is_alive() and unit.control != null and (unit.control.stunned_turns > 0 or unit.control.entangled_turns > 0):
			children.append(ControlExpireCommand.new(unit))
	return CommandStepResult.applied([], children)
