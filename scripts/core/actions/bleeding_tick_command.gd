extends Command
class_name BleedingTickCommand

var _target: UnitState
var _expected: Dictionary

func _init(target: UnitState = null) -> void:
	_target = target
	_expected = target.bleeding.to_dict() if target != null and target.bleeding != null else {}

func get_kind() -> StringName: return &"bleeding_tick"

func copy_for_queue() -> Command:
	var copy := BleedingTickCommand.new(_target)
	copy._expected = _expected.duplicate(true)
	return copy

func validate(context: ActionContext) -> StringName:
	if context == null or _target == null or context.get_state().get_board().get_unit_by_id(_target.id) != _target: return &"bleeding/invalid_tick"
	if _target.bleeding == null or _target.armor == null or not BleedingState.valid(_expected) or _expected["ticks_left"] < 1 or _target.bleeding.to_dict() != _expected: return &"bleeding/invalid_tick"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	if validate(context) != &"": return CommandStepResult.faulted(&"bleeding/invalid_tick")
	if not _target.is_alive(): return CommandStepResult.skipped(&"bleeding/dead_target")
	var guard := SpatialRules.capture_guard(context, [_target], [_target.cell], {_target.id: [StatTypes.StatType.HP_MAX]})
	if guard == null: return CommandStepResult.faulted(&"bleeding/invalid_tick")
	var source := DamageSource.new(&"status", 0, _target.cell, _expected["source"]["instigator_unit_id"], _expected["source"]["credit_unit_id"])
	var raw: Array[Dictionary] = [{"type": "physical", "policy": "hp_only_natural", "source": "bleeding", "numerator": _target.bleeding.stacks if _target.bleeding.stacked else BleedingState.DAMAGE, "denominator": 1}]
	var request := ArmorAttack.request(_target.id, raw, source)
	var plan := ArmorHitExecutor.prepare(request, guard.values["participants"][_target.id]["armor"], _target.vitals.get_hp(), ActionHpExecutor._stat_value(_target, StatTypes.StatType.HP_MAX), context.get_rng(), ElementalRules.is_frozen(_target))
	if source.validate(context) != &"" or plan.get("reason", &"") != &"": return CommandStepResult.faulted(&"bleeding/invalid_tick")
	if plan["hp_after"] == 0 and context.get_state().get_board().board_version >= ActionContext.MAX_ID: return CommandStepResult.faulted(&"push/board_version_exhausted")
	request.amount = float(plan["hp_before"] - plan["hp_after"])
	var state := _target.bleeding
	var after := _expected.duplicate(true)
	after["ticks_left"] -= 1
	if after["ticks_left"] == 0:
		if state.stacked: after["stacks"] = 0
		after["source"] = {}
		after["hit_id"] = ""
	guard = guard.bleeding_phase(_target.id, after)
	state.ticks_left = after["ticks_left"]
	state.source = after["source"].duplicate(true)
	state.hit_id = after["hit_id"]
	if state.stacked: state.stacks = after["stacks"]
	var event := {"kind": &"bleeding_changed", "actor_unit_id": source.instigator_unit_id, "target_unit_id": _target.id, "reason": &"tick", "before": _expected.duplicate(true), "after": after}
	var result := CommandStepResult.applied([event], [], [], null, true)
	if not guard.check(context):
		result.status = &"FAULTED"; result.reason = &"bleeding/checkpoint"
		return result
	state.changed.emit()
	if not guard.check(context):
		result.status = &"FAULTED"; result.reason = &"bleeding/checkpoint"
		return result
	# Срок уже записан; ошибка HP сохраняет этот prefix, как любая guarded команда.
	var hit: Dictionary = ArmorHitExecutor.execute(request, guard, context)
	var hp_result: CommandStepResult = hit["result"]
	result.events.append_array(hp_result.events)
	result.status = hp_result.status; result.reason = hp_result.reason
	return result
