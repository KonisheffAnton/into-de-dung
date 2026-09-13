extends RefCounted
class_name Command

func get_kind() -> StringName:
	return &"unknown"
func copy_for_queue() -> Command:
	return null
func validate(_context: ActionContext) -> StringName:
	return &"unknown_command"
func execute(_context: ActionContext) -> CommandStepResult:
	return CommandStepResult.faulted(&"unknown_command")
