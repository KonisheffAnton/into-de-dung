extends RefCounted
class_name ArmorSpatial

## Admission переносит будущие A/HP/RNG последовательно, не меняя живой граф.
static func prepare_push(binding: BalancePushRules.Binding, context: ActionContext, admission: bool) -> Dictionary:
	var target_id: int = binding.values["target_id"]
	var target: Dictionary = binding.spatial_guard.values["participants"][target_id]
	var from: Vector2i = target["cell"]
	var to: Vector2i = from + Vector2i(binding.values["direction"])
	var resolved := PushResolver.resolve_push_steps(binding.board, binding.target, from, binding.values["direction"], 1)
	var simulation := {"views": {}, "hp": {}, "rng": context.get_rng()}
	for id: int in binding.spatial_guard.values["participants"]:
		var participant: Dictionary = binding.spatial_guard.values["participants"][id]
		if not participant.has("armor"): return BalancePushRules._push_failure(&"armor/capability_required")
		simulation["views"][id] = participant["armor"].duplicate(true)
		simulation["hp"][id] = participant["hp"]
	if admission:
		var direct: Dictionary = binding.values["armor_plan"]
		simulation["views"][target_id] = direct["after"].duplicate(true)
		simulation["hp"][target_id] = float(direct["hp_after"])
		if not _advance_rng(simulation, direct): return BalancePushRules._push_failure(&"armor/rng_not_cloneable")
	var touches := 0
	var first: DamageRequest = null
	var second: DamageRequest = null
	var source := DamageSource.new(&"collision", 0, to, binding.actor.id, binding.actor.id)
	var raw := ArmorFraction.make(binding.values["armor_raw"]["numerator"], binding.values["armor_raw"]["denominator"])
	if resolved.outcome in [PushResult.Outcome.BLOCKED, PushResult.Outcome.COLLISION]:
		var hit := _hit(binding, simulation, target_id, raw, source)
		if hit["reason"] != &"": return BalancePushRules._push_failure(hit["reason"])
		first = hit["request"]
		if simulation["hp"][target_id] == 0.0: touches += 1
	if resolved.outcome == PushResult.Outcome.COLLISION:
		if binding.blocker == null or resolved.blocker != binding.blocker: return BalancePushRules._push_failure()
		var blocker_id := binding.blocker.id
		var hit := _hit(binding, simulation, blocker_id, raw, source)
		if hit["reason"] != &"": return BalancePushRules._push_failure(hit["reason"])
		second = hit["request"]
		if simulation["hp"][blocker_id] == 0.0:
			touches += 1
			if simulation["hp"][target_id] > 0.0:
				touches += 1
				if binding.board.is_lethal(to): touches += 1
				else:
					var drop := maxi(0, binding.board.get_height_steps(from) - binding.board.get_height_steps(to))
					if drop >= 2:
						var fall := _fall(binding, simulation, target_id, drop, to)
						if fall["reason"] != &"": return BalancePushRules._push_failure(fall["reason"])
						if simulation["hp"][target_id] == 0.0: touches += 1
	elif resolved.outcome == PushResult.Outcome.MOVED:
		touches = 1
		if resolved.fall_steps >= 2:
			var fall := _fall(binding, simulation, target_id, resolved.fall_steps, to)
			if fall["reason"] != &"": return BalancePushRules._push_failure(fall["reason"])
			first = fall["request"]
			if simulation["hp"][target_id] == 0.0: touches += 1
	elif resolved.outcome == PushResult.Outcome.FELL:
		touches = 2 if binding.board.is_in_bounds(to) else 1
	var stage := binding.copy()
	stage.first = first; stage.first_seal = first.copy() if first != null else null
	stage.second = second; stage.second_seal = second.copy() if second != null else null
	stage.values["from_cell"] = from; stage.values["attempted_cell"] = to
	stage.values["outcome"] = resolved.outcome; stage.values["fall_steps"] = resolved.fall_steps; stage.values["fall_height"] = resolved.fall_height
	stage.values["phase"] = &"push"
	stage.seal()
	return {"reason": &"", "outcome": resolved.outcome, "blocked_reason": resolved.blocked_reason, "from_cell": from, "attempted_cell": to, "fall_height": resolved.fall_height, "fall_steps": resolved.fall_steps, "first": first, "second": second, "binding": stage, "board_touches": touches}

static func _advance_rng(simulation: Dictionary, plan: Dictionary) -> bool:
	if plan["draws"] == 0: return true
	var rng: ActionRngPort = simulation["rng"]
	var clone := rng.clone()
	if clone == null or clone == rng or clone.get_script() != rng.get_script(): return false
	if not clone.from_dict(plan["rng_after"].duplicate(true)) or clone.to_dict() != plan["rng_after"]: return false
	simulation["rng"] = clone
	return true

static func _hit(binding: BalancePushRules.Binding, simulation: Dictionary, id: int, amount: ArmorFraction, source: DamageSource) -> Dictionary:
	var request := ArmorAttack.request(id, ArmorRuntime.physical(amount, String(source.kind)), source)
	var plan := ArmorHitExecutor.prepare(request, simulation["views"][id], simulation["hp"][id], BalancePushRules._spatial_stat(binding, id, StatTypes.StatType.HP_MAX), simulation["rng"], ElementalRules.is_frozen(binding.board.get_unit_by_id(id)))
	if plan.get("reason", &"") != &"": return plan
	if not _advance_rng(simulation, plan): return {"reason": &"armor/rng_not_cloneable"}
	request.amount = float(plan["hp_before"] - plan["hp_after"])
	simulation["views"][id] = plan["after"]
	simulation["hp"][id] = float(plan["hp_after"])
	return {"reason": &"", "request": request}

static func _fall(binding: BalancePushRules.Binding, simulation: Dictionary, id: int, steps: int, to: Vector2i) -> Dictionary:
	var amount := ArmorAttack.fall(BalancePushRules._spatial_stat(binding, id, StatTypes.StatType.HP_MAX), steps, false)
	return _hit(binding, simulation, id, amount, DamageSource.new(&"fall", 0, to, binding.actor.id, binding.actor.id))
