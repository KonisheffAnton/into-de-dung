extends Command
class_name HazardTurnCommand

var _team: int
var _team_seal: int
func _init(team: int = Faction.Type.PLAYER) -> void:
	_team = team; _team_seal = team
func get_kind() -> StringName: return &"hazard_turn"
func copy_for_queue() -> Command:
	var result := HazardTurnCommand.new(_team)
	result._team_seal = _team_seal
	return result
func validate(context: ActionContext) -> StringName:
	if context == null or _team != _team_seal or _team not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return &"hazard/invalid_team"
	return &""
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var environment := context.get_state().environment
	if environment == null or environment.hazards.is_empty(): return CommandStepResult.skipped(&"hazard/disabled")
	if not BattleHazards.valid(environment.hazards): return CommandStepResult.faulted(&"hazard/invalid_state")
	var children: Array[Command] = []
	for trap: Dictionary in BattleHazards.canonical(environment.hazards).traps:
		if trap.armed_team == _team: children.append(HazardCommand.new(environment, null, trap.cell, false, false, Vector2i.ZERO, trap.id, _team))
	return CommandStepResult.applied([], children)
