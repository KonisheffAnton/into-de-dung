extends Command
class_name ArtifactFormationCommand

var _team: int
func _init(team: int = 0) -> void: _team = team
func get_kind() -> StringName: return &"artifact_formation"
func copy_for_queue() -> Command: return ArtifactFormationCommand.new(_team)
func projected_after(context: ActionContext) -> Dictionary:
	if validate(context) != &"": return {}
	var after := context.get_state().artifacts.to_dict()
	after.formation_serials[_team] = maxi(after.formation_serials[_team],context.get_state().abilities.serials[_team] + 1)
	return after
func validate(context: ActionContext) -> StringName:
	if _team not in [0,1] or not BattleArtifactRules.references_valid(context): return &"artifact/invalid_turn"
	var abilities := context.get_state().abilities
	if abilities == null or abilities.stage != "ended" or abilities.team == _team or abilities.serials[_team] >= ActionContext.MAX_ID: return &"artifact/invalid_turn"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var serial: int = state.abilities.serials[_team] + 1
	if state.artifacts.formation_serials[_team] >= serial: return CommandStepResult.skipped(&"artifact/already_processed")
	var guard := SpatialRules.capture_guard(context, [], [], {})
	if guard == null: return CommandStepResult.faulted(&"artifact/invalid_state")
	var after := state.artifacts.to_dict()
	after.formation_serials[_team] = serial
	guard = guard.artifacts_phase(after)
	state.artifacts.formation_serials[_team] = serial
	if not guard.check(context): return CommandStepResult.faulted(&"artifact/checkpoint")
	var children: Array[Command] = []
	for id: int in state.artifacts.heroes:
		var owner := state.get_board().get_unit_by_id(id)
		if owner.is_alive() and owner.faction == _team and state.artifacts.stacks(id,"formation") == 1 and BattleArtifactRules.has_neighbour(state,owner):
			children.append(ArtifactRepairCommand.new(id, serial))
	return CommandStepResult.applied([], children, [], null, true)
