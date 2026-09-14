extends Command
class_name DeathCommand

var target_unit_id: int
var source: DamageSource
var _spatial_binding: MoveFallCommand.Binding
var _has_spatial_binding: bool = false
func _init(p_target_unit_id: int = 0, p_source: DamageSource = null, spatial_binding: MoveFallCommand.Binding = null) -> void:
	target_unit_id = p_target_unit_id; source = p_source.copy() if p_source != null else null
	_spatial_binding = spatial_binding.copy() if spatial_binding != null else null
	_has_spatial_binding = spatial_binding != null
func get_kind() -> StringName: return &"death"
func copy_for_queue() -> Command:
	var result := DeathCommand.new(target_unit_id, source, _spatial_binding)
	result._has_spatial_binding = _has_spatial_binding
	return result
func validate(context: ActionContext) -> StringName:
	if _has_spatial_binding or _spatial_binding != null:
		return &"" if _has_spatial_binding and _spatial_binding != null and _spatial_binding.check(context, &"cell_death") and target_unit_id == _spatial_binding.values["target_id"] and source != null and source.to_dict() == _spatial_binding.source_seal.to_dict() else &"move/fall_binding"
	if source == null: return &"invalid_payload"
	return ActionHpExecutor.validate_death(target_unit_id, source, context)
func execute(context: ActionContext) -> CommandStepResult:
	if _has_spatial_binding or _spatial_binding != null:
		return MoveFallCommand.execute_binding(_spatial_binding, context, &"cell_death") if validate(context) == &"" else CommandStepResult.faulted(&"move/fall_binding")
	if source == null: return CommandStepResult.faulted(&"invalid_payload")
	return ActionHpExecutor.death(target_unit_id, source, context)
