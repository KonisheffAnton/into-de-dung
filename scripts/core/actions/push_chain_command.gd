extends Command
class_name PushChainCommand

var _binding: BalancePushRules.Binding
var _stage: StringName
var _index: int
var _stage_seal: StringName
var _index_seal: int

func _init(binding: BalancePushRules.Binding = null, stage: StringName = &"balance", index: int = 0) -> void:
	_binding = binding.copy() if binding != null else null
	_stage = stage; _stage_seal = stage
	_index = index; _index_seal = index

func get_kind() -> StringName: return &"push_chain"

func copy_for_queue() -> Command:
	var result := PushChainCommand.new(_binding, _stage, _index)
	result._stage_seal = _stage_seal; result._index_seal = _index_seal
	return result

func validate(context: ActionContext) -> StringName:
	if _stage != _stage_seal or _index != _index_seal or _stage not in [&"balance", &"pair", &"final"]: return &"chain/invalid_binding"
	if _binding == null or not BalancePushRules.spatial_valid(_binding, context, &"chain"): return &"chain/invalid_binding"
	var plan: Dictionary = _binding.values.get("chain", {})
	if plan.is_empty() or plan.get("links", []).is_empty(): return &"chain/invalid_binding"
	if _index < 0 or _index >= plan.links.size(): return &"chain/invalid_binding"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if _stage == &"balance": return _balance(context)
	if _stage == &"pair": return _pair(context)
	var plan: Dictionary = _binding.values.chain
	if not plan.may_push or not _binding.spatial_guard.values.participants[plan.end_id].alive:
		return CommandStepResult.applied()
	var final_binding := PushChainRules.retarget(_binding, plan.end_id, plan.end_force)
	return CommandStepResult.applied([], [PushCommand.new(final_binding)])

func _balance(context: ActionContext) -> CommandStepResult:
	var links: Array = _binding.values.chain.links
	var link: Dictionary = links[_index]
	var id: int = link.to_id
	var guard := _binding.spatial_guard
	var done := guard.balance_phase(id, link.balance_after)
	var checkpoint := func(_phase: StringName) -> StringName:
		return &"" if _binding.sealed() and done.check(context) else &"chain/invalid_binding"
	var target: UnitState = guard.refs.participants[id].unit
	var multiplier: int = 2 if guard.values.participants[id].control.get("entangled_turns", 0) > 0 else 1
	var receipt := target.vitals.add_spatial_impact(link.impact, checkpoint, multiplier)
	var result := CommandStepResult.new()
	result.status = ActionReceipt.APPLIED if receipt.reason == &"" and _binding.sealed() and done.check(context) else ActionReceipt.FAULTED
	result.reason = &"" if result.status == ActionReceipt.APPLIED else &"chain/invalid_binding"
	result.state_changed = (receipt.balance_written and receipt.balance_before != receipt.balance_after) or receipt.broken_emitted
	var event := {"kind": &"balance_changed", "actor_unit_id": _binding.actor.id, "target_unit_id": id, "balance_before": receipt.balance_before, "balance_after": receipt.balance_after, "balance_max": receipt.balance_max, "impact": receipt.impact, "broke": receipt.broke}
	if receipt.balance_written and receipt.balance_before != receipt.balance_after: result.events.append(event.duplicate(true))
	if receipt.broken_emitted:
		event.kind = &"balance_broken"
		result.events.append(event.duplicate(true))
	if result.status == ActionReceipt.APPLIED:
		result.events.append({"kind": &"chain_link", "actor_unit_id": _binding.actor.id, "from_unit_id": link.from_id, "target_unit_id": id, "impulse": link.impact, "broke": link.broke})
		var next := BalancePushRules.spatial_phase(_binding, done, &"chain")
		result.mandatory.append(PushChainCommand.new(next, &"balance", _index + 1) if _index + 1 < links.size() else PushChainCommand.new(next, &"pair", 0))
	return result

func _pair(context: ActionContext) -> CommandStepResult:
	var links: Array = _binding.values.chain.links
	var link: Dictionary = links[_index]
	var next := _binding
	var result := CommandStepResult.applied([{"kind": &"collision", "actor_unit_id": _binding.actor.id, "target_unit_id": link.from_id, "from_cell": link.from_cell, "attempted_cell": link.to_cell, "blocker_unit_id": link.to_id}])
	for id: int in [link.from_id, link.to_id]:
		if not next.spatial_guard.values.participants[id].alive: continue
		var hit := PushChainRules.prepare_damage(next, id, link.force, link.to_cell, context)
		if hit.reason != &"":
			result.status = ActionReceipt.FAULTED; result.reason = hit.reason
			return result
		var hp := BalancePushRules.spatial_hp(next, hit.request, context, &"chain/invalid_binding")
		var applied: CommandStepResult = hp.result
		result.events.append_array(applied.events)
		result.state_changed = result.state_changed or applied.state_changed
		if applied.status != ActionReceipt.APPLIED:
			result.status = applied.status; result.reason = applied.reason
			return result
		next = hp.binding
	# Дочернее поддерево держит следующую пару и финальный сдвиг впереди среды
	# и реакций от смертей этой пары; уже выполненный prefix не откатывается.
	result.mandatory.append(PushChainCommand.new(next, &"pair", _index + 1) if _index + 1 < links.size() else PushChainCommand.new(next, &"final", _index))
	return result

static func valid_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "from_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "impulse": TYPE_FLOAT, "broke": TYPE_BOOL}): return false
	for key: String in ["actor_unit_id", "from_unit_id", "target_unit_id"]:
		if draft[key] <= 0 or draft[key] >= ActionContext.MAX_ID: return false
	return draft.kind == &"chain_link" and draft.actor_unit_id != draft.from_unit_id and draft.actor_unit_id != draft.target_unit_id and draft.from_unit_id != draft.target_unit_id and is_finite(draft.impulse) and draft.impulse >= 0.0
