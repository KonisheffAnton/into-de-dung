extends Command
class_name BleedingTurnCommand

var _faction: Faction.Type
var _revision: int

func _init(faction: Faction.Type = Faction.Type.PLAYER, revision: int = 0) -> void:
	_faction = faction; _revision = revision

func get_kind() -> StringName: return &"bleeding_turn"
func copy_for_queue() -> Command: return BleedingTurnCommand.new(_faction, _revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_revision() != _revision: return &"bleeding/stale_turn"
	if _faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return &"bleeding/invalid_team"
	for unit: UnitState in context.get_state().get_board().get_all_units():
		if unit.bleeding != null and (unit.armor == null or not BleedingState.valid(unit.bleeding.to_dict())): return &"bleeding/invalid_state"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var units := context.get_state().get_board().get_all_units()
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	var children: Array[Command] = []
	for unit: UnitState in units:
		if unit.faction == _faction and unit.is_alive() and unit.bleeding != null and unit.bleeding.ticks_left > 0:
			children.append(BleedingTickCommand.new(unit))
	return CommandStepResult.applied([], children)
