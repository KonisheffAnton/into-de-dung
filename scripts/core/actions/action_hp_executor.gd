extends RefCounted
class_name ActionHpExecutor

# Validate читает отдельный stat: отказ не должен прогревать живой cache.
static func _stat_value(unit: UnitState, type: StatTypes.StatType) -> float:
	var copy := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict())
	return NAN if copy == null else copy.get_value(type)

static func _payload(target_id: int, source: DamageSource, context: ActionContext) -> StringName:
	if target_id <= 0 or target_id >= ItemSimulationSnapshot.MAX_ID: return &"invalid_target_id"
	if source == null: return &"invalid_source"
	return source.validate(context)

static func _target(target_id: int, context: ActionContext) -> StringName:
	var unit := context.get_state().get_board().get_unit_by_id(target_id)
	if unit == null: return &"missing_target"
	if unit.stats == null or unit.vitals == null: return &"invalid_target"
	if not unit.is_alive(): return &"dead_target"
	return &""

static func _damage_payload(request: DamageRequest, context: ActionContext) -> StringName:
	if request == null: return &"invalid_request"
	var reason := _payload(request.target_unit_id, request.source, context)
	if reason != &"": return reason
	if not is_finite(request.amount) or request.amount < 0.0: return &"invalid_amount"
	if request.damage_type != &"physical": return &"invalid_damage_type"
	if request.armor_mode != &"flat" and request.armor_mode != &"bypass": return &"invalid_armor_mode"
	return &""

static func validate_damage(request: DamageRequest, context: ActionContext) -> StringName:
	var reason := _damage_payload(request, context)
	if reason != &"": return reason
	reason = _target(request.target_unit_id, context)
	if reason != &"": return reason
	var amount := _damage_amount(request, context)
	return &"invalid_armor" if not is_finite(amount) else &""

static func _damage_amount(request: DamageRequest, context: ActionContext) -> float:
	if request.armor_mode == &"bypass": return request.amount
	var armor := _stat_value(context.get_state().get_board().get_unit_by_id(request.target_unit_id), StatTypes.StatType.ARMOR)
	if not is_finite(armor): return NAN
	var amount := request.amount - armor
	return maxf(0.0, amount) if is_finite(amount) else NAN

static func validate_heal(target_id: int, amount: float, source: DamageSource, context: ActionContext) -> StringName:
	var reason := _payload(target_id, source, context)
	if reason != &"": return reason
	if not is_finite(amount) or amount < 0.0: return &"invalid_amount"
	reason = _target(target_id, context)
	if reason != &"": return reason
	var maximum := _stat_value(context.get_state().get_board().get_unit_by_id(target_id), StatTypes.StatType.HP_MAX)
	return &"invalid_hp_max" if not is_finite(maximum) else &""

static func validate_death(target_id: int, source: DamageSource, context: ActionContext) -> StringName:
	var reason := _payload(target_id, source, context)
	return reason if reason != &"" else _target(target_id, context)

static func _failed(reason: StringName) -> CommandStepResult:
	var step := CommandStepResult.new()
	step.status = &"SKIPPED" if reason == &"missing_target" or reason == &"dead_target" else &"FAULTED"
	step.reason = reason
	return step

static func damage(request: DamageRequest, context: ActionContext) -> CommandStepResult:
	var reason := validate_damage(request, context)
	if reason != &"": return _failed(reason)
	var unit := context.get_state().get_board().get_unit_by_id(request.target_unit_id)
	var before := unit.vitals.get_hp()
	var alive := unit.is_alive()
	unit.vitals.apply_damage(_damage_amount(request, context))
	return _finalize(unit, before, alive, request.source, context, &"damaged")

static func heal(target_id: int, amount: float, source: DamageSource, context: ActionContext) -> CommandStepResult:
	var reason := validate_heal(target_id, amount, source, context)
	if reason != &"": return _failed(reason)
	var unit := context.get_state().get_board().get_unit_by_id(target_id)
	var before := unit.vitals.get_hp()
	# P02 допускает over-max HP: вызов Vitals.heal в этом случае уменьшил бы HP.
	if amount > 0.0 and before < _stat_value(unit, StatTypes.StatType.HP_MAX):
		unit.vitals.heal(amount)
	return _finalize(unit, before, true, source, context, &"healed")

static func death(target_id: int, source: DamageSource, context: ActionContext) -> CommandStepResult:
	var reason := validate_death(target_id, source, context)
	if reason != &"": return _failed(reason)
	var unit := context.get_state().get_board().get_unit_by_id(target_id)
	var before := unit.vitals.get_hp()
	unit.vitals.apply_damage(maxf(before, 1.0))
	return _finalize(unit, before, true, source, context, &"died")

static func _finalize(unit: UnitState, before: float, alive_before: bool, source: DamageSource, context: ActionContext, kind: StringName) -> CommandStepResult:
	var after := unit.vitals.get_hp()
	var alive_after := unit.is_alive()
	var died := alive_before and not alive_after
	if died: context.get_state().get_board().clear_occupancy(unit)
	var step := CommandStepResult.new()
	step.status = &"APPLIED"
	step.state_changed = before != after or alive_before != alive_after
	var amount := after - before if kind == &"healed" else before - after
	if kind != &"died" and amount > 0.0:
		step.events.append(_draft(kind, unit.id, source, before, after, amount, alive_before, alive_after))
	if died: step.events.append(_draft(&"died", unit.id, source, before, after, 0.0, alive_before, alive_after))
	return step

static func _draft(kind: StringName, target_id: int, source: DamageSource, before: float, after: float, amount: float, alive_before: bool, alive_after: bool) -> Dictionary:
	return {"kind": kind, "actor_unit_id": source.instigator_unit_id, "target_unit_id": target_id, "source": source.to_dict(), "hp_before": before, "hp_after": after, "amount": amount, "alive_before": alive_before, "alive_after": alive_after}


## Caller проверил sealed binding; после первого сигнала live lookup больше недопустим.
static func damage_spatial(request: DamageRequest, context: ActionContext, checkpoint: Callable) -> CommandStepResult:
	if context == null or context.get_state() == null or context.get_state().get_board() == null or not checkpoint.is_valid():
		return CommandStepResult.faulted(&"spatial/invalid_mutation")
	if request == null or request.armor_mode != &"bypass":
		return CommandStepResult.faulted(&"spatial/invalid_mutation")
	var reason := validate_damage(request, context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var board := context.get_state().get_board()
	var unit := board.get_unit_by_id(request.target_unit_id)
	var vitals := unit.vitals
	var target_id := request.target_unit_id
	var source := request.source.copy()
	var amount := request.amount
	var receipt := vitals.apply_spatial_damage(amount, checkpoint)
	return _spatial_result(receipt, target_id, source, false)


static func death_spatial(target_id: int, source: DamageSource, context: ActionContext, checkpoint: Callable) -> CommandStepResult:
	if context == null or context.get_state() == null or context.get_state().get_board() == null or not checkpoint.is_valid():
		return CommandStepResult.faulted(&"spatial/invalid_mutation")
	var reason := validate_death(target_id, source, context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var board := context.get_state().get_board()
	var unit := board.get_unit_by_id(target_id)
	var vitals := unit.vitals
	var pinned_id := target_id
	var pinned_source := source.copy()
	var amount := maxf(vitals.get_hp(), 1.0)
	var receipt := vitals.apply_spatial_damage(amount, checkpoint)
	return _spatial_result(receipt, pinned_id, pinned_source, true)


static func _spatial_result(receipt: Vitals.SpatialMutation, target_id: int, source: DamageSource, explicit_death: bool) -> CommandStepResult:
	var step := CommandStepResult.new()
	step.status = &"APPLIED" if receipt.reason == &"" else &"FAULTED"
	step.reason = receipt.reason
	step.state_changed = (receipt.hp_written and receipt.hp_before != receipt.hp_after) or receipt.death_written
	var amount := receipt.hp_before - receipt.hp_after
	# При fault до death_written lethal оставляет damaged(HP0, alive=true).
	if receipt.hp_written and amount > 0.0 and (not explicit_death or not receipt.death_written):
		step.events.append(_draft(&"damaged", target_id, source, receipt.hp_before, receipt.hp_after, amount, receipt.alive_before, receipt.alive_after))
	if receipt.death_written:
		step.events.append(_draft(&"died", target_id, source, receipt.hp_before, receipt.hp_after, 0.0, receipt.alive_before, receipt.alive_after))
	return step
