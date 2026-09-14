extends Command
class_name BalanceCommand

var _binding: BalancePushRules.Binding
func _init(binding: BalancePushRules.Binding = null) -> void: _binding = binding.copy() if binding != null else null
func get_kind() -> StringName: return &"balance"
func copy_for_queue() -> Command: return BalanceCommand.new(_binding)
func validate(context: ActionContext) -> StringName:
	var reason := BalancePushRules.binding_reason(_binding, context, &"balance")
	if reason != &"": return &"balance/invalid_binding"
	if _binding.target.vitals.get_balance() != float(_binding.values.get("balance_before", NAN)) or _binding.target.vitals.get_balance_max() != float(_binding.values.get("balance_max", NAN)):
		return &"balance/invalid_binding"
	return &""
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
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
