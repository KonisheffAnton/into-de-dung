extends Command
class_name CollisionDamageCommand

var _first: DamageRequest
var _second: DamageRequest
var _binding: BalancePushRules.Binding
var _first_seal: DamageRequest
var _second_seal: DamageRequest
func _init(first: DamageRequest = null, second: DamageRequest = null, binding: BalancePushRules.Binding = null) -> void:
	_first = first.copy() if first != null else null; _second = second.copy() if second != null else null; _binding = binding.copy() if binding != null else null; _first_seal = _first.copy() if _first != null else null; _second_seal = _second.copy() if _second != null else null
func get_kind() -> StringName: return &"collision_damage"
func copy_for_queue() -> Command:
	var result := CollisionDamageCommand.new(_first, _second, _binding); result._first_seal = _first_seal.copy() if _first_seal != null else null; result._second_seal = _second_seal.copy() if _second_seal != null else null; return result
func validate(context: ActionContext) -> StringName:
	if _binding == null or _binding.context != context or _first == null or _second == null or _first_seal == null or _second_seal == null or not PushDamageCommand._same_request(_first, _first_seal) or not PushDamageCommand._same_request(_second, _second_seal): return &"push/invalid_binding"
	if not BalancePushRules.requests_sealed(_binding) or not BalancePushRules._same_request(_first, _binding.first) or not BalancePushRules._same_request(_second, _binding.second): return &"push/invalid_binding"
	if BalancePushRules.binding_reason(_binding, context, &"push") != &"": return &"push/invalid_binding"
	if not _valid_blocker(context, true): return &"push/invalid_binding"
	var required_touches := 0
	if _first.amount >= _binding.target.vitals.get_hp(): required_touches += 1
	if _second.amount >= _binding.blocker.vitals.get_hp(): required_touches += 1
	if _binding.board.board_version < 0 or (required_touches > 0 and _binding.board.board_version > ActionContext.MAX_ID - required_touches): return &"push/board_version_exhausted"
	var reason := ActionHpExecutor.validate_damage(_first, context)
	if reason != &"": return reason
	return ActionHpExecutor.validate_damage(_second, context)
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var first_result := ActionHpExecutor.damage(_first, context)
	if first_result.status != &"APPLIED": return first_result
	if not _valid_blocker(context, true):
		var first_fault := CommandStepResult.faulted(&"push/invalid_binding")
		first_fault.events = first_result.events
		first_fault.state_changed = first_result.state_changed
		return first_fault
	var second_result := ActionHpExecutor.damage(_second, context)
	var result := CommandStepResult.new()
	result.status = second_result.status; result.reason = second_result.reason; result.state_changed = first_result.state_changed or second_result.state_changed
	result.events.append_array(first_result.events); result.events.append_array(second_result.events)
	if second_result.status == &"APPLIED" and _binding.blocker != null and not _binding.blocker.is_alive() and _binding.target.is_alive():
		var entry := _binding.copy()
		entry.values["phase"] = &"after_collision"
		entry.values["expected_hp"] = _binding.target.vitals.get_hp()
		entry.values["expected_alive"] = _binding.target.is_alive()
		entry.values["expected_target_hp"] = _binding.target.vitals.get_hp()
		entry.values["expected_target_alive"] = _binding.target.is_alive()
		entry.values["blocker_after_hp"] = _binding.blocker.vitals.get_hp()
		entry.seal()
		result.mandatory.append(PushCommand.after_collision(entry))
	return result

func _valid_blocker(context: ActionContext, require_alive: bool) -> bool:
	var blocker := _binding.blocker
	if blocker == null or blocker.get_script() != UnitState or context == null or context.get_state() == null or context.get_state().get_board() != _binding.board or _binding.board.get_unit_by_id(blocker.id) != blocker or blocker.id != int(_binding.values.get("blocker_id", 0)) or blocker.cell != _binding.values.get("blocker_cell", Vector2i.ZERO): return false
	if require_alive and not blocker.is_alive(): return false
	if blocker.stats != _binding.blocker_stats or blocker.vitals != _binding.blocker_vitals or blocker.stats == null or blocker.vitals == null or blocker.vitals._stats != blocker.stats or blocker.vitals.get_hp() != float(_binding.values.get("blocker_hp", NAN)) or context.get_state().get_owner(blocker.id) != _binding.blocker_owner or _binding.blocker_owner == null or _binding.blocker_owner.get_owner() != blocker: return false
	return true
