extends Command
class_name DamageCommand

var request: DamageRequest
func _init(p_request: DamageRequest = null) -> void: request = p_request.copy() if p_request != null else null
func get_kind() -> StringName: return &"damage"
func copy_for_queue() -> Command:
	return DamageCommand.new(request)
func validate(context: ActionContext) -> StringName:
	if request == null: return &"invalid_payload"
	return ActionHpExecutor.validate_damage(request, context)
func execute(context: ActionContext) -> CommandStepResult:
	if request == null: return CommandStepResult.faulted(&"invalid_payload")
	return ActionHpExecutor.damage(request, context)
