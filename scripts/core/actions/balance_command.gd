extends Command
class_name BalanceCommand

var _binding: BalancePushRules.Binding
func _init(binding: BalancePushRules.Binding = null) -> void: _binding = binding.copy() if binding != null else null
func get_kind() -> StringName: return &"balance"
func copy_for_queue() -> Command: return BalanceCommand.new(_binding)
func validate(context: ActionContext) -> StringName:
	var reason := BalancePushRules.binding_reason(_binding, context, &"balance")
	if reason != &"": return &"balance/invalid_binding"
	if _binding.values.get("spatial", false): return &""
	if _binding.target.vitals.get_balance() != float(_binding.values.get("balance_before", NAN)) or _binding.target.vitals.get_balance_max() != float(_binding.values.get("balance_max", NAN)):
		return &"balance/invalid_binding"
	return &""
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if _binding.values.get("spatial", false): return _execute_spatial(context)
	var target := _binding.target
	var before := target.vitals.get_balance()
	var impact := float(_binding.values.get("impact", -1.0))
	var maximum := target.vitals.get_balance_max()
	if not is_finite(impact) or impact < 0.0 or not is_finite(maximum): return CommandStepResult.faulted(&"balance/invalid_stat")
	var broke := target.vitals.add_impact(impact)
	var after := target.vitals.get_balance()
	var events: Array[Dictionary] = []
	if before != after: events.append({"kind": &"balance_changed", "actor_unit_id": _binding.actor.id, "target_unit_id": target.id, "balance_before": before, "balance_after": after, "balance_max": maximum, "impact": impact, "broke": broke})
	if broke: events.append({"kind": &"balance_broken", "actor_unit_id": _binding.actor.id, "target_unit_id": target.id, "balance_before": before, "balance_after": after, "balance_max": maximum, "impact": impact, "broke": true})
	var children: Array[Command] = []
	if broke:
		var push_binding := _binding.copy()
		push_binding.values["phase"] = &"push"
		push_binding.values["balance_after"] = after
		push_binding.values["broke"] = true
		push_binding.values["expected_target_hp"] = target.vitals.get_hp()
		push_binding.values["expected_target_alive"] = target.is_alive()
		push_binding.seal()
		children.append(PushCommand.new(push_binding))
	return CommandStepResult.applied(events, children, [], null, before != after or broke)

func _execute_spatial(context: ActionContext) -> CommandStepResult:
	var target_id: int = _binding.values["target_id"]
	var actor_id: int = _binding.values["actor_id"]
	var done := _binding.spatial_guard.balance_phase(target_id, _binding.values["balance_after"])
	var checkpoint := func(_stage: StringName) -> StringName:
		return &"" if _binding.sealed() and done.check(context) else &"balance/invalid_binding"
	var control: Dictionary = _binding.spatial_guard.values["participants"][target_id]["control"]
	var maximum_multiplier: int = 2 if control.get("entangled_turns", 0) > 0 else 1
	var receipt := _binding.target_vitals.add_spatial_impact(_binding.values["impact"], checkpoint, maximum_multiplier)
	var result := CommandStepResult.new()
	result.status = &"APPLIED" if receipt.reason == &"" and _binding.sealed() and done.check(context) else &"FAULTED"
	result.reason = &"" if result.status == &"APPLIED" else &"balance/invalid_binding"
	result.state_changed = (receipt.balance_written and receipt.balance_before != receipt.balance_after) or receipt.broken_emitted
	var draft := {"kind": &"balance_changed", "actor_unit_id": actor_id, "target_unit_id": target_id, "balance_before": receipt.balance_before, "balance_after": receipt.balance_after, "balance_max": receipt.balance_max, "impact": receipt.impact, "broke": receipt.broke}
	if receipt.balance_written and receipt.balance_before != receipt.balance_after: result.events.append(draft.duplicate(true))
	if receipt.broken_emitted:
		draft["kind"] = &"balance_broken"
		result.events.append(draft.duplicate(true))
	if result.status == &"APPLIED" and receipt.broken_emitted:
		result.mandatory.append(PushCommand.new(BalancePushRules.spatial_phase(_binding, done, &"push")))
	return result
