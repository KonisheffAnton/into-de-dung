extends Command
class_name HealCommand

var target_unit_id: int
var amount: float
var source: DamageSource
var _reaction_binding: RefCounted = null
func _init(p_target_unit_id: int = 0, p_amount: float = 0.0, p_source: DamageSource = null) -> void:
	target_unit_id = p_target_unit_id; amount = p_amount; source = p_source.copy() if p_source != null else null
func get_kind() -> StringName: return &"heal"
func copy_for_queue() -> Command:
	var copy := HealCommand.new(target_unit_id, amount, source)
	copy._reaction_binding = _reaction_binding
	return copy
func validate(context: ActionContext) -> StringName:
	if source == null: return &"invalid_payload"
	return ActionHpExecutor.validate_heal(target_unit_id, amount, source, context)
func execute(context: ActionContext) -> CommandStepResult:
	if _reaction_binding != null:
		var reaction_reason := ItemReactionAdapter.revalidate(_reaction_binding, context)
		if reaction_reason == &"stale_reaction": return CommandStepResult.skipped(reaction_reason)
		if reaction_reason != &"": return CommandStepResult.faulted(reaction_reason)
	if source == null: return CommandStepResult.faulted(&"invalid_payload")
	return ActionHpExecutor.heal(target_unit_id, amount, source, context)
