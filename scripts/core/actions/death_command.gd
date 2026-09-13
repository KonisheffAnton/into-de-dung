extends Command
class_name DeathCommand

var target_unit_id: int
var source: DamageSource
func _init(p_target_unit_id: int = 0, p_source: DamageSource = null) -> void:
	target_unit_id = p_target_unit_id; source = p_source.copy() if p_source != null else null
func get_kind() -> StringName: return &"death"
func copy_for_queue() -> Command: return DeathCommand.new(target_unit_id, source)
func validate(context: ActionContext) -> StringName:
	if source == null: return &"invalid_payload"
	return ActionHpExecutor.validate_death(target_unit_id, source, context)
func execute(context: ActionContext) -> CommandStepResult:
	if source == null: return CommandStepResult.faulted(&"invalid_payload")
	return ActionHpExecutor.death(target_unit_id, source, context)
