extends ControlApplyCommand
class_name EntangleApplyCommand

func _init(actor: UnitState = null, target: UnitState = null, source: DamageSource = null, hit_id: String = "", definition_id: StringName = &"", eligible: bool = false) -> void:
	super(actor, target, source, hit_id, definition_id, eligible, &"entangle")

func copy_for_queue() -> Command:
	return _copy_state_to(EntangleApplyCommand.new(_actor, _target, _source, _hit_id, _definition_id, _eligible))
