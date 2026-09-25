extends Command
class_name EntangleApplyCommand

var _actor: UnitState
var _target: UnitState
var _source: DamageSource
var _hit_id: String
var _definition_id: StringName
var _eligible: bool
var _control: ControlState
var _seal: Dictionary

func _init(actor: UnitState = null, target: UnitState = null, source: DamageSource = null, hit_id: String = "", definition_id: StringName = &"", eligible: bool = false) -> void:
	_actor = actor; _target = target
	_source = source.copy() if source != null else null
	_hit_id = hit_id; _definition_id = definition_id; _eligible = eligible
	# Push меняет значения контроля до этого sibling, но ссылка capability должна остаться исходной.
	_control = target.control if target != null else null
	_seal = _values()

func get_kind() -> StringName: return &"entangle_apply"

func copy_for_queue() -> Command:
	var copy := EntangleApplyCommand.new(_actor, _target, _source, _hit_id, _definition_id, _eligible)
	copy._control = _control
	copy._seal = _seal.duplicate(true)
	return copy

func _values() -> Dictionary:
	return {"actor": _actor, "target": _target, "control": _control, "source": _source.to_dict() if _source != null else {}, "hit_id": _hit_id, "definition": _definition_id, "eligible": _eligible}

func validate(context: ActionContext) -> StringName:
	if _values() != _seal or context == null or _actor == null or _target == null or _source == null:
		return &"control/invalid_source"
	var state := context.get_state()
	if state == null or state.get_board() == null:
		return &"control/invalid_source"
	var board := state.get_board()
	if board.get_unit_by_id(_actor.id) != _actor or board.get_unit_by_id(_target.id) != _target or _source.validate(context) != &"":
		return &"control/invalid_source"
	if _source.kind != &"attack" or _source.instigator_unit_id != _actor.id or _source.credit_unit_id != _actor.id or _source.source_instance_id != 0 or _hit_id.is_empty():
		return &"control/invalid_source"
	var definition := context.get_attack_rules().get_definition(_definition_id)
	if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or not definition.entangle_on_physical_hp:
		return &"control/invalid_source"
	if _control == null or _target.control != _control or _control.get_script() != ControlState or not ControlState.valid(_control.to_dict()):
		return &"control/invalid_state"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if not _target.is_alive(): return CommandStepResult.skipped(&"control/dead_target")
	if not _eligible: return CommandStepResult.skipped(&"control/hp_gate")
	var guard := SpatialRules.capture_guard(context, [_target], [_target.cell], {})
	if guard == null: return CommandStepResult.faulted(&"control/invalid_state")
	var before := _control.to_dict()
	var after := before.duplicate(true)
	after["entangled_turns"] = 1
	if not ControlState.valid(after): return CommandStepResult.faulted(&"control/invalid_state")
	guard = guard.control_phase(_target.id, after)
	_control.entangled_turns = 1
	var event := {"kind": &"control_changed", "target_unit_id": _target.id, "before": before, "after": after, "reason": &"entangled" if before["entangled_turns"] == 0 else &"refreshed"}
	var result := CommandStepResult.applied([event], [], [], null, true)
	# Callback/event fault сохраняет уже применённую мутацию как завершённый prefix.
	if not guard.check(context) or validate(context) != &"":
		result.status = &"FAULTED"; result.reason = &"control/checkpoint"
	return result
