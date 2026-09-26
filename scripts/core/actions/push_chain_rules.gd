extends RefCounted
class_name PushChainRules

static func _failure(reason: StringName) -> Dictionary:
	var units: Array[UnitState] = []
	var cells: Array[Vector2i] = []
	return {"reason": reason, "plan": {}, "units": units, "cells": cells}

static func _fraction(data: Dictionary) -> ArmorFraction:
	if not data.has("numerator") or not data.has("denominator") or typeof(data["numerator"]) != TYPE_INT or typeof(data["denominator"]) != TYPE_INT:
		return ArmorFraction.make(1, 0)
	return ArmorFraction.make(data["numerator"], data["denominator"])

static func _value(amount: ArmorFraction) -> float:
	return float(amount.numerator) / float(amount.denominator)

static func gather(board: BattleBoard, actor: UnitState, target: UnitState, impact: float) -> Dictionary:
	if board == null or actor == null or target == null or actor.get_script() != UnitState or target.get_script() != UnitState or actor == target or not is_finite(impact) or impact < 0.0:
		return _failure(&"chain/invalid_binding")
	if not board.is_in_bounds(actor.cell) or not board.is_in_bounds(target.cell) or (actor.cell.x != target.cell.x and actor.cell.y != target.cell.y):
		return _failure(&"chain/invalid_direction")
	if board.get_unit_by_id(actor.id) != actor or board.get_unit_by_id(target.id) != target or board.occupant_at(actor.cell) != actor or board.occupant_at(target.cell) != target:
		return _failure(&"chain/invalid_binding")
	var direction := PushResolver.compute_push_direction(actor.cell, target.cell)
	if direction == Vector2i.ZERO: return _failure(&"chain/invalid_direction")
	var effective := ArmorFraction.from_decimal(impact)
	if not effective.valid: return _failure(&"chain/invalid_fraction")
	var units: Array[UnitState] = [actor, target]
	var cells: Array[Vector2i] = []
	var path_cell := actor.cell
	while path_cell != target.cell:
		cells.append(path_cell)
		path_cell += direction
	cells.append(target.cell)
	var links: Array[Dictionary] = []
	var visited: Dictionary = {target.id: true}
	var current := target
	var may_push := false
	while true:
		var attempted: Vector2i = current.cell + direction
		if board.is_in_bounds(attempted) and not cells.has(attempted): cells.append(attempted)
		var resolved := PushResolver.resolve_push_steps(board, current, current.cell, direction, 1)
		if resolved.outcome != PushResult.Outcome.COLLISION:
			may_push = true
			break
		var receiver: UnitState = resolved.blocker
		if receiver == null or visited.has(receiver.id) or receiver.stats == null or receiver.vitals == null or receiver.armor == null or receiver.vitals._stats != receiver.stats:
			return _failure(&"chain/invalid_participant")
		if receiver.stats.get_script() != StatsBag or receiver.vitals.get_script() != Vitals or not receiver.is_alive():
			return _failure(&"chain/invalid_participant")
		var snapshot := StatsBag.from_snapshot_dict(receiver.stats.to_snapshot_dict())
		if snapshot == null or not snapshot.has_stat(StatTypes.StatType.BALANCE_MAX) or not snapshot.has_stat(StatTypes.StatType.HP_MAX) or not snapshot.has_stat(StatTypes.StatType.ARMOR):
			return _failure(&"chain/missing_stat")
		var maximum := ControlRules.balance_maximum(receiver, snapshot.get_value(StatTypes.StatType.BALANCE_MAX))
		var before := receiver.vitals.get_balance()
		var hp := receiver.vitals.get_hp()
		if not is_finite(maximum) or not is_finite(before) or before < 0.0 or not is_finite(hp) or hp <= 0.0 or not is_finite(snapshot.get_value(StatTypes.StatType.HP_MAX)) or not is_finite(snapshot.get_value(StatTypes.StatType.ARMOR)):
			return _failure(&"chain/invalid_stat")
		var force := effective.multiply(ArmorFraction.make(3, 4))
		if not force.valid: return _failure(&"chain/fraction_overflow")
		var next_effective := force.multiply(ArmorFraction.make(1, 2)) if receiver.guard_stance else force
		if not next_effective.valid: return _failure(&"chain/fraction_overflow")
		var impulse := _value(next_effective)
		if not is_finite(impulse): return _failure(&"chain/nonfinite_impact")
		var total := before
		if impulse > 0.0 and maximum > 0.0:
			total += impulse
			if not is_finite(total): return _failure(&"chain/nonfinite_sum")
		var broke := impulse > 0.0 and maximum > 0.0 and total >= maximum
		var after := 0.0 if broke else total
		links.append({"from_id": current.id, "to_id": receiver.id, "from_cell": current.cell, "to_cell": receiver.cell, "force": {"numerator": force.numerator, "denominator": force.denominator}, "impact": impulse, "balance_before": before, "balance_after": after, "balance_max": maximum, "broke": broke})
		units.append(receiver)
		visited[receiver.id] = true
		current = receiver
		effective = next_effective
		if not broke: break
	var plan := {"links": links, "end_id": current.id, "end_force": {"numerator": effective.numerator, "denominator": effective.denominator}, "may_push": may_push}
	return {"reason": &"", "plan": plan, "units": units, "cells": cells}

static func retarget(binding: BalancePushRules.Binding, id: int, force: Dictionary) -> BalancePushRules.Binding:
	if binding == null or binding.spatial_guard == null or not binding.spatial_guard.refs["participants"].has(id): return null
	var amount := _fraction(force)
	if not amount.valid or amount.numerator < 0: return null
	var next := binding.copy()
	var refs: Dictionary = next.spatial_guard.refs["participants"][id]
	next.target = refs["unit"]
	next.target_stats = refs["stats"]
	next.target_vitals = refs["vitals"]
	next.target_owner = refs["owner"]
	next.blocker = null
	next.blocker_stats = null
	next.blocker_vitals = null
	next.blocker_owner = null
	next.first = null
	next.second = null
	next.first_seal = null
	next.second_seal = null
	next.values.erase("chain")
	next.values["target_id"] = id
	next.values["blocker_id"] = 0
	next.values.erase("blocker_cell")
	next.values.erase("blocker_height_steps")
	next.values["armor_raw"] = force.duplicate(true)
	var raw := _value(amount)
	next.values["raw_attack"] = raw
	next.values["impact"] = raw
	return BalancePushRules.spatial_phase(next, next.spatial_guard, &"push")

static func prepare_damage(binding: BalancePushRules.Binding, id: int, force: Dictionary, cell: Vector2i, context: ActionContext) -> Dictionary:
	var failed := {"reason": &"chain/invalid_binding", "request": null}
	if binding == null or binding.spatial_guard == null or context == null or not binding.spatial_guard.values["participants"].has(id): return failed
	var amount := _fraction(force)
	if not amount.valid or amount.numerator < 0: return {"reason": &"chain/invalid_fraction", "request": null}
	var participant: Dictionary = binding.spatial_guard.values["participants"][id]
	if not participant.has("armor") or not participant.has("hp"): return {"reason": &"chain/armor_required", "request": null}
	var simulation: Dictionary = {"views": {}, "hp": {}, "rng": context.get_rng()}
	simulation["views"][id] = participant["armor"].duplicate(true)
	simulation["hp"][id] = participant["hp"]
	var source := DamageSource.new(&"collision", 0, cell, binding.actor.id, binding.actor.id)
	var hit := ArmorSpatial._hit(binding, simulation, id, amount, source)
	if hit.get("reason", &"") != &"": return {"reason": hit["reason"], "request": null}
	return {"reason": &"", "request": hit["request"]}

static func admission_touches(binding: BalancePushRules.Binding, context: ActionContext) -> Dictionary:
	var failed := {"reason": &"chain/invalid_binding", "board_touches": 0}
	if binding == null or context == null or binding.spatial_guard == null or not BalancePushRules.spatial_valid(binding, context, &"balance", true): return failed
	var plan: Dictionary = binding.values.get("chain", {})
	var links: Array = plan.get("links", [])
	if links.is_empty(): return failed
	var guard := binding.spatial_guard
	var simulation: Dictionary = {"views": {}, "hp": {}, "rng": context.get_rng()}
	for id: int in guard.values["participants"]:
		var participant: Dictionary = guard.values["participants"][id]
		if not participant.has("armor") or not participant.has("hp"): return {"reason": &"chain/armor_required", "board_touches": 0}
		simulation["views"][id] = participant["armor"].duplicate(true)
		simulation["hp"][id] = participant["hp"]
	var direct: Dictionary = binding.values.get("armor_plan", {})
	var target_id: int = binding.values["target_id"]
	if not direct.has("after") or not direct.has("hp_after") or not simulation["hp"].has(target_id): return failed
	simulation["views"][target_id] = direct["after"].duplicate(true)
	simulation["hp"][target_id] = float(direct["hp_after"])
	if not ArmorSpatial._advance_rng(simulation, direct): return {"reason": &"chain/rng_not_cloneable", "board_touches": 0}
	var touches := 0
	for row: Variant in links:
		if typeof(row) != TYPE_DICTIONARY: return failed
		var link: Dictionary = row
		var force := _fraction(link.get("force", {}))
		if not force.valid or force.numerator < 0: return {"reason": &"chain/invalid_fraction", "board_touches": 0}
		var cell: Vector2i = link["to_cell"]
		for id: int in [int(link["from_id"]), int(link["to_id"])]:
			if not simulation["hp"].has(id): return failed
			if float(simulation["hp"][id]) <= 0.0: continue
			var source := DamageSource.new(&"collision", 0, cell, binding.actor.id, binding.actor.id)
			var hit := ArmorSpatial._hit(binding, simulation, id, force, source)
			if hit.get("reason", &"") != &"": return {"reason": hit["reason"], "board_touches": 0}
			if float(simulation["hp"][id]) <= 0.0: touches += 1
	if bool(plan.get("may_push", false)):
		var end_id: int = plan["end_id"]
		if not simulation["hp"].has(end_id): return failed
		if float(simulation["hp"][end_id]) > 0.0:
			var final_binding := retarget(binding, end_id, plan["end_force"])
			if final_binding == null: return failed
			var end: Dictionary = guard.values["participants"][end_id]
			var from: Vector2i = end["cell"]
			var to: Vector2i = from + Vector2i(binding.values["direction"])
			var resolved := PushResolver.resolve_push_steps(binding.board, final_binding.target, from, binding.values["direction"], 1)
			if resolved.outcome == PushResult.Outcome.COLLISION: return failed
			if resolved.outcome == PushResult.Outcome.BLOCKED:
				var blocked_force := _fraction(plan["end_force"])
				if not blocked_force.valid: return {"reason": &"chain/invalid_fraction", "board_touches": 0}
				var blocked := ArmorSpatial._hit(final_binding, simulation, end_id, blocked_force, DamageSource.new(&"collision", 0, to, binding.actor.id, binding.actor.id))
				if blocked.get("reason", &"") != &"": return {"reason": blocked["reason"], "board_touches": 0}
				if float(simulation["hp"][end_id]) <= 0.0: touches += 1
			elif resolved.outcome == PushResult.Outcome.MOVED:
				touches += 1
				if resolved.fall_steps >= 2:
					var fall := ArmorSpatial._fall(final_binding, simulation, end_id, resolved.fall_steps, to)
					if fall.get("reason", &"") != &"": return {"reason": fall["reason"], "board_touches": 0}
					if float(simulation["hp"][end_id]) <= 0.0: touches += 1
			elif resolved.outcome == PushResult.Outcome.FELL:
				touches += 1
				if binding.board.is_in_bounds(to): touches += 1
	return {"reason": &"", "board_touches": touches}
