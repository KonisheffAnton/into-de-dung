extends Command
class_name ReactionStopCommand

## Отдельный финальный шаг позволяет очереди сначала завершить удар и предметные реакции.
func get_kind() -> StringName: return &"reaction_stop"
func copy_for_queue() -> Command: return ReactionStopCommand.new()
func validate(_context: ActionContext) -> StringName: return &""
func execute(_context: ActionContext) -> CommandStepResult:
	return CommandStepResult.interrupted(&"perks/opportunist_stopped")
