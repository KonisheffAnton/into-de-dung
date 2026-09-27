extends Command
class_name AbilityBoundaryCommand

var operation: StringName
var team: int
var serial: int
var revision: int
func _init(op: StringName = &"", side: int = 0, turn: int = 0, rev: int = 0) -> void:
	operation = op; team = side; serial = turn; revision = rev
func get_kind() -> StringName: return &"ability_boundary"
func copy_for_queue() -> Command: return AbilityBoundaryCommand.new(operation, team, serial, revision)
func projected_after(context: ActionContext) -> Dictionary:
	if context == null or context.get_state() == null or context.get_state().abilities == null or context.get_revision() != revision: return {}
	return context.get_state().abilities.boundary(operation, team, serial)
func validate(context: ActionContext) -> StringName:
	return &"ability/invalid_boundary" if projected_after(context).is_empty() else &""
func execute(context: ActionContext) -> CommandStepResult:
	var after := projected_after(context)
	if after.is_empty(): return CommandStepResult.faulted(&"ability/invalid_boundary")
	var guard := SpatialRules.capture_guard(context, [], [], {})
	if guard == null: return CommandStepResult.faulted(&"ability/invalid_runtime")
	guard = guard.ability_phase(after)
	context.get_state().abilities.apply_values(after)
	if not guard.check(context): return CommandStepResult.faulted(&"ability/checkpoint")
	return CommandStepResult.applied([], [], [], null, true)
