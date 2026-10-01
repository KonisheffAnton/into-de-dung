extends RefCounted
class_name MageStatusEffect

## Тестовые заклинания проходят обычную оплату мага и проверяемые границы записи.
static func prepare(target: UnitState, effect: StringName, source: DamageSource, hit_id: String, armor: Dictionary) -> Dictionary:
	if not ElementalRules.valid_unit(target) or target.control == null or not ControlState.valid(target.control.to_dict()): return {"reason": &"status/invalid_state"}
	if effect in [&"burning", &"wet", &"freeze"]:
		return ElementalRules.transition(target.elemental.to_dict(), effect, 2 if effect == &"freeze" else 3, source.to_dict(), ElementalRules.freeze_gate(armor))
	if effect in [&"stun", &"entangle"]:
		if ControlRules.immune_to(target, effect): return {"reason": &"control/stun_immune" if effect == &"stun" else &"control/entangle_immune"}
		var after := target.control.to_dict()
		after["stunned_turns" if effect == &"stun" else "entangled_turns"] = 1
		return {"reason": &"", "after": after}
	if effect != &"bleeding": return {"reason": &"mage/unknown_spell"}
	if target.bleeding.immune: return {"reason": &"bleeding/immune"}
	if ElementalRules.burning(target): return {"reason": &"bleeding/burning"}
	if target.bleeding.stacks == BleedingState.MAX_STACKS: return {"reason": &"bleeding/duration_exhausted"}
	var after := target.bleeding.to_dict()
	after.stacks += 1; after.ticks_left = BleedingState.STACK_DURATION
	after.source = source.to_dict(); after.hit_id = hit_id
	return {"reason": &"", "after": after} if BleedingState.valid(after) else {"reason": &"bleeding/invalid_state"}

static func apply(target: UnitState, effect: StringName, after: Dictionary, guard: SpatialRules.Guard, context: ActionContext, seal_check: Callable) -> CommandStepResult:
	if effect in [&"burning", &"wet", &"freeze"]:
		var written := ElementalRules.write(target, after, guard, context, effect, 0, seal_check)
		var result: CommandStepResult = written.result
		if not seal_check.call(): result.status = &"FAULTED"; result.reason = &"mage/checkpoint"
		return result
	var result := CommandStepResult.applied([], [], [], null, true)
	if effect in [&"stun", &"entangle"]:
		var before := target.control.to_dict()
		guard = guard.control_phase(target.id, after)
		target.control.stunned_turns = after.stunned_turns
		target.control.entangled_turns = after.entangled_turns
		var field := "stunned_turns" if effect == &"stun" else "entangled_turns"
		var reason: StringName = (&"stunned" if before[field] == 0 else &"stun_refreshed") if effect == &"stun" else (&"entangled" if before[field] == 0 else &"refreshed")
		result.events.append({"kind": &"control_changed", "target_unit_id": target.id, "before": before, "after": after, "reason": reason})
	else:
		var before := target.bleeding.to_dict()
		guard = guard.bleeding_phase(target.id, after)
		target.bleeding.stacks = after.stacks; target.bleeding.ticks_left = after.ticks_left
		target.bleeding.source = after.source.duplicate(true); target.bleeding.hit_id = after.hit_id
		result.events.append({"kind": &"bleeding_changed", "actor_unit_id": 0, "target_unit_id": target.id, "before": before, "after": after, "reason": &"applied" if before.ticks_left == 0 else &"refreshed"})
		if guard.check(context) and seal_check.call(): target.bleeding.changed.emit()
	if not guard.check(context) or not seal_check.call(): result.status = &"FAULTED"; result.reason = &"mage/checkpoint"
	return result
