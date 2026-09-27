extends RefCounted
class_name ArmorHitExecutor

static func prepare(request: DamageRequest, view: Dictionary, hp: float, maximum: float, rng: ActionRngPort, frozen: bool = false) -> Dictionary:
	if request == null or request.armor_mode != &"armor" or request.source == null: return {"reason": &"armor/invalid_hit"}
	return ElementalRules.shatter(ArmorRuntime.plan(view, request.armor_components, hp, maximum, rng), frozen)

static func execute(request: DamageRequest, guard: SpatialRules.Guard, context: ActionContext, outer_check: Callable = Callable()) -> Dictionary:
	var step := CommandStepResult.faulted(&"armor/invalid_hit")
	var out := {"result": step, "guard": guard}
	if guard == null or not guard.check(context) or request == null or not guard.values["participants"].has(request.target_unit_id): return out
	var id := request.target_unit_id
	var values: Dictionary = guard.values["participants"][id]
	var refs: Dictionary = guard.refs["participants"][id]
	if not values.has("armor") or not values["alive"] or request.source.validate(context) != &"": return out
	var unit: UnitState = refs["unit"]
	var maximum := ActionHpExecutor._stat_value(unit, StatTypes.StatType.HP_MAX)
	var plan := prepare(request, values["armor"], values["hp"], maximum, context.get_rng(), ElementalRules.is_frozen(unit))
	if plan.get("reason", &"") != &"":
		step.reason = plan["reason"]
		return out
	var seal := request.copy()
	var pinned_source := request.source.copy()
	var state: ArmorState = unit.armor
	var owner: ItemOwnerState = refs["owner"]
	var rng := context.get_rng()
	var current: Array[SpatialRules.Guard] = [guard.copy()]
	var check := func() -> bool:
		return BalancePushRules._same_request(request, seal) and current[0].check(context) and (not outer_check.is_valid() or bool(outer_check.call()))
	if not check.call(): return out
	if plan["hp_after"] == 0 and context.get_state().get_board().board_version >= ActionContext.MAX_ID:
		step.reason = &"push/board_version_exhausted"
		return out
	var changed_grants: Array[Dictionary] = []
	var changed_items: Array[Dictionary] = []
	var armor_event := {"kind": &"armor_changed", "actor_unit_id": pinned_source.instigator_unit_id, "target_unit_id": id, "source": pinned_source.to_dict(), "grants": changed_grants, "items": changed_items}
	for delta: Dictionary in plan["grant_changes"]:
		var next_view: Dictionary = current[0].values["participants"][id]["armor"].duplicate(true)
		for grant: Dictionary in next_view["state"]["grants"]:
			if grant["grant_id"] == delta["id"]: grant["remaining"] = delta["after"]
		current[0] = current[0].armor_phase(id, next_view)
		for grant: Dictionary in state.grants:
			if grant["grant_id"] == delta["id"]: grant["remaining"] = delta["after"]
		changed_grants.append(delta.duplicate(true))
		step.state_changed = true
		if step.events.is_empty(): step.events.append(armor_event)
		if not check.call(): return out
		state.changed.emit(&"extra", delta["id"], delta["before"], delta["after"])
		if not check.call(): return out
	if plan["draws"] > 0:
		current[0] = current[0].rng_phase(plan["rng_after"])
		var committed := rng.from_dict(plan["rng_after"].duplicate(true))
		step.state_changed = step.state_changed or rng.to_dict() != plan["rng_before"]
		if not committed or not check.call(): return out
	for delta: Dictionary in plan["item_changes"]:
		var next_view: Dictionary = current[0].values["participants"][id]["armor"].duplicate(true)
		for item: Dictionary in next_view["items"]:
			if item["item_id"] == delta["id"]: item["remaining"] = delta["after"]
		current[0] = current[0].armor_phase(id, next_view)
		(owner._items[delta["id"]] as ItemInstance).armor_remaining = delta["after"]
		changed_items.append(delta.duplicate(true))
		step.state_changed = true
		if step.events.is_empty(): step.events.append(armor_event)
		if not check.call(): return out
		state.changed.emit(&"item", delta["id"], delta["before"], delta["after"])
		if not check.call(): return out
	var written := current[0].hit_hp_phase(id, float(plan["hp_after"]), false)
	var done := current[0].hit_hp_phase(id, float(plan["hp_after"]), plan["hp_after"] == 0)
	var checkpoint := func(stage: StringName) -> StringName:
		current[0] = written if stage == &"hp_written" else done
		return &"" if check.call() else &"armor/invalid_hit"
	var receipt := (refs["vitals"] as Vitals).apply_hit_hp(float(plan["hp_after"]), checkpoint)
	step.state_changed = step.state_changed or receipt.hp_written or receipt.death_written
	if receipt.hp_written and receipt.hp_before != receipt.hp_after:
		var kind: StringName = &"damaged" if receipt.hp_before > receipt.hp_after else &"healed"
		step.events.append(ActionHpExecutor._draft(kind, id, pinned_source, receipt.hp_before, receipt.hp_after, absf(receipt.hp_after - receipt.hp_before), receipt.alive_before, receipt.alive_after))
	if receipt.death_written: step.events.append(ActionHpExecutor._draft(&"died", id, pinned_source, receipt.hp_before, receipt.hp_after, 0.0, receipt.alive_before, receipt.alive_after))
	if receipt.reason != &"" or not check.call(): return out
	var explanation := plan.duplicate(true)
	explanation.erase("reason")
	# Sequence + target различает обе жертвы collision внутри одного шага.
	step.events.append({"kind": &"hit_resolved", "actor_unit_id": pinned_source.instigator_unit_id, "target_unit_id": id, "source": pinned_source.to_dict(), "hit_id": "%d:%d" % [context._next_command_seq - 1, id], "hit": explanation})
	step.status = &"APPLIED"; step.reason = &""
	out["guard"] = done
	return out
