extends RefCounted
class_name ElementalRules

static func is_frozen(unit: UnitState) -> bool:
	return unit != null and unit.elemental != null and unit.elemental.frozen_turns > 0

static func burning(unit: UnitState) -> bool:
	return unit != null and unit.elemental != null and unit.elemental.burning_stacks > 0

static func valid_unit(unit: UnitState) -> bool:
	return unit != null and unit.elemental != null and unit.elemental.get_script() == ElementalState and unit.elemental.acid_ticks >= 0 and ElementalState.valid(unit.elemental.to_dict()) and unit.bleeding != null and unit.bleeding.stacked and BleedingState.valid(unit.bleeding.to_dict()) and not (unit.elemental.burning_stacks > 0 and unit.bleeding.stacks > 0)

static func freeze_gate(view: Dictionary) -> bool:
	var totals := ArmorRuntime.totals(view)
	if totals.is_empty(): return false
	# Сравнение без float и удвоения исключает потерю точности/переполнение.
	return (totals["maximum"] == 0 and totals["current"] == 0) or totals["current"] < totals["maximum"] - totals["current"]

## Добивание использует повреждающую часть, ещё не уменьшенную лечением hit.
static func shatter(plan: Dictionary, frozen: bool) -> Dictionary:
	if frozen and plan.get("reason", &"") == &"" and plan.has("total_damage") and float(plan["total_damage"]) > float(plan["hp_before"]) * 0.5:
		plan["hp_without_shatter"] = plan["hp_after"]
		plan["shattered"] = true
		plan["hp_after"] = 0
		plan["hp_loss"] = plan["hp_before"]
		plan["hp_gain"] = 0
	return plan

static func transition(before: Dictionary, effect: StringName, ticks: int, source: Dictionary, freeze_allowed: bool = false) -> Dictionary:
	if not ElementalState.valid(before) or ticks < 1: return {"reason": &"status/invalid_state"}
	var after := before.duplicate(true)
	match effect:
		&"burning":
			if not ElementalState.valid_effect_source(source): return {"reason": &"status/invalid_source"}
			if before["frozen_turns"] > 0:
				after["frozen_turns"] = 0
				after["wet_turns"] = 3
			elif before["wet_turns"] > 0:
				after["wet_turns"] = 0
			else:
				if before["burning_stacks"] == ElementalState.MAX_VALUE or before["burning_ticks"] > ElementalState.MAX_VALUE - ticks: return {"reason": &"status/duration_exhausted"}
				after["burning_stacks"] += 1
				after["burning_ticks"] += ticks
				after["burning_source"] = source.duplicate(true)
		&"wet":
			_clear_burning(after)
			after["wet_turns"] = 3
		&"freeze":
			if before["frozen_turns"] == 0 and before["wet_turns"] == 0:
				_clear_burning(after)
				after["wet_turns"] = 3
			elif freeze_allowed and not before["freeze_immune"]:
				if before["frozen_turns"] > ElementalState.MAX_VALUE - ticks: return {"reason": &"status/duration_exhausted"}
				after["wet_turns"] = 0
				after["frozen_turns"] += ticks
		&"burn_tick":
			if before["burning_ticks"] > 0:
				after["burning_ticks"] -= 1
				if after["burning_ticks"] == 0: _clear_burning(after)
		&"acid_apply":
			var acid_before_apply: int = int(before.get("acid_ticks", 0))
			if acid_before_apply == ElementalState.MAX_VALUE: return {"reason": &"status/duration_exhausted"}
			after["acid_ticks"] = acid_before_apply + 1
		&"acid_tick":
			var acid_before_tick: int = int(before.get("acid_ticks", 0))
			if acid_before_tick > 0:
				after["acid_ticks"] = acid_before_tick - 1
		&"turn_end":
			after["wet_turns"] = maxi(0, after["wet_turns"] - 1)
			after["frozen_turns"] = maxi(0, after["frozen_turns"] - 1)
		_: return {"reason": &"status/invalid_effect"}
	return {"reason": &"", "after": after}

static func _clear_burning(value: Dictionary) -> void:
	value["burning_stacks"] = 0
	value["burning_ticks"] = 0
	value["burning_source"] = {}

## Обе записи защищены тем же guard; сигнал не может подменить второй статус.
static func write(unit: UnitState, after: Dictionary, guard: SpatialRules.Guard, context: ActionContext, effect: StringName, actor: int = 0, command_check: Callable = Callable()) -> Dictionary:
	var result := CommandStepResult.applied([])
	var out := {"result": result, "guard": guard}
	if not valid_unit(unit) or not ElementalState.valid(after) or guard == null or not guard.check(context) or (command_check.is_valid() and not command_check.call()):
		result.status = &"FAULTED"; result.reason = &"status/checkpoint"
		return out
	var before := unit.elemental.to_dict()
	if before != after:
		guard = guard.elemental_phase(unit.id, after)
		var state := unit.elemental
		state.burning_stacks = after["burning_stacks"]
		state.burning_ticks = after["burning_ticks"]
		state.burning_source = after["burning_source"].duplicate(true)
		state.wet_turns = after["wet_turns"]
		state.frozen_turns = after["frozen_turns"]
		state.acid_ticks = int(after.get("acid_ticks", 0))
		result.state_changed = true
		result.events.append({"kind": &"elemental_changed", "actor_unit_id": actor, "target_unit_id": unit.id, "reason": effect, "before": before, "after": after.duplicate(true)})
		if guard.check(context): state.changed.emit()
		if not guard.check(context) or (command_check.is_valid() and not command_check.call()):
			result.status = &"FAULTED"; result.reason = &"status/checkpoint"
			return out
	if effect == &"burning" and after["burning_stacks"] > 0 and unit.bleeding.ticks_left > 0:
		var bleed_before := unit.bleeding.to_dict()
		var bleed_after := bleed_before.duplicate(true)
		bleed_after.merge({"ticks_left": 0, "stacks": 0, "source": {}, "hit_id": ""}, true)
		guard = guard.bleeding_phase(unit.id, bleed_after)
		unit.bleeding.ticks_left = 0
		unit.bleeding.stacks = 0
		unit.bleeding.source = {}
		unit.bleeding.hit_id = ""
		result.state_changed = true
		result.events.append({"kind": &"bleeding_changed", "actor_unit_id": actor, "target_unit_id": unit.id, "reason": &"burned", "before": bleed_before, "after": bleed_after})
		if guard.check(context): unit.bleeding.changed.emit()
		if not guard.check(context) or (command_check.is_valid() and not command_check.call()):
			result.status = &"FAULTED"; result.reason = &"status/checkpoint"
	out["guard"] = guard
	return out
