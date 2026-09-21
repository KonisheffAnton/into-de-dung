extends Command
class_name BleedingApplyCommand

var _actor: UnitState
var _target: UnitState
var _source: DamageSource
var _hit_id: String
var _definition_id: StringName
var _policy: StringName
var _eligible: bool
var _seal: Dictionary

func _init(actor: UnitState = null, target: UnitState = null, source: DamageSource = null, hit_id: String = "", definition_id: StringName = &"", policy: StringName = &"", eligible: bool = false) -> void:
	_actor = actor; _target = target
	_source = source.copy() if source != null else null
	_hit_id = hit_id; _definition_id = definition_id; _policy = policy; _eligible = eligible
	_seal = _values()

func get_kind() -> StringName: return &"bleeding_apply"

func copy_for_queue() -> Command:
	var copy := BleedingApplyCommand.new(_actor, _target, _source, _hit_id, _definition_id, _policy, _eligible)
	copy._seal = _seal.duplicate(true)
	return copy

func _values() -> Dictionary:
	return {"actor": _actor, "target": _target, "source": _source.to_dict() if _source != null else {}, "hit_id": _hit_id, "definition": _definition_id, "policy": _policy, "eligible": _eligible}

func validate(context: ActionContext) -> StringName:
	if _values() != _seal or context == null or _actor == null or _target == null or _source == null: return &"bleeding/invalid_source"
	var board := context.get_state().get_board()
	if board.get_unit_by_id(_actor.id) != _actor or board.get_unit_by_id(_target.id) != _target or _source.validate(context) != &"": return &"bleeding/invalid_source"
	if _source.kind != &"attack" or _source.instigator_unit_id != _actor.id or _source.credit_unit_id != _actor.id or _source.source_instance_id != 0 or _hit_id.is_empty(): return &"bleeding/invalid_source"
	var definition := context.get_attack_rules().get_definition(_definition_id)
	if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or definition.bleeding_policy != _policy or _policy not in [&"physical_hp", &"bypass_hp_gate"]: return &"bleeding/invalid_source"
	if _target.bleeding == null or _target.bleeding.get_script() != BleedingState or not BleedingState.valid(_target.bleeding.to_dict()): return &"bleeding/invalid_state"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if not _target.is_alive(): return CommandStepResult.skipped(&"bleeding/dead_target")
	if _target.bleeding.immune: return CommandStepResult.skipped(&"bleeding/immune")
	if not _eligible: return CommandStepResult.skipped(&"bleeding/hp_gate")
	var guard := SpatialRules.capture_guard(context, [_target], [_target.cell], {})
	if guard == null: return CommandStepResult.faulted(&"bleeding/invalid_state")
	var state := _target.bleeding
	var before := state.to_dict()
	var after := before.duplicate(true)
	after["ticks_left"] = BleedingState.DURATION
	after["source"] = _source.to_dict()
	after["hit_id"] = _hit_id
	if not BleedingState.valid(after): return CommandStepResult.faulted(&"bleeding/invalid_source")
	guard = guard.bleeding_phase(_target.id, after)
	state.ticks_left = BleedingState.DURATION
	state.source = _source.to_dict()
	state.hit_id = _hit_id
	var event := {"kind": &"bleeding_changed", "actor_unit_id": _actor.id, "target_unit_id": _target.id, "reason": &"applied" if before["ticks_left"] == 0 else &"refreshed", "before": before, "after": after}
	var result := CommandStepResult.applied([event], [], [], null, true)
	if not guard.check(context) or validate(context) != &"":
		result.status = &"FAULTED"; result.reason = &"bleeding/checkpoint"
		return result
	state.changed.emit()
	if not guard.check(context) or validate(context) != &"":
		result.status = &"FAULTED"; result.reason = &"bleeding/checkpoint"
	return result
