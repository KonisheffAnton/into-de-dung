extends Command
class_name ElementalTickCommand

var _unit: UnitState
var _expire: bool

func _init(unit: UnitState = null, expire: bool = false) -> void:
	_unit = unit; _expire = expire
func get_kind() -> StringName: return &"elemental_expire" if _expire else &"burning_tick"
func copy_for_queue() -> Command: return ElementalTickCommand.new(_unit, _expire)

func validate(context: ActionContext) -> StringName:
	if context == null or _unit == null or context.get_state().get_board().get_unit_by_id(_unit.id) != _unit or not ElementalRules.valid_unit(_unit): return &"status/invalid_tick"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if not _unit.is_alive(): return CommandStepResult.skipped(&"status/dead_target")
	var before := _unit.elemental.to_dict()
	if not _expire and before["burning_stacks"] == 0: return CommandStepResult.skipped(&"status/inactive")
	var guard := SpatialRules.capture_guard(context, [_unit], [_unit.cell], {_unit.id: [StatTypes.StatType.HP_MAX]})
	if guard == null: return CommandStepResult.faulted(&"status/invalid_tick")
	var effect: StringName = &"turn_end" if _expire else &"burn_tick"
	var planned := ElementalRules.transition(before, effect, 1, {})
	var request: DamageRequest
	var actor := 0
	if not _expire:
		var source := DamageSource.new(&"status", 0, _unit.cell, before["burning_source"]["instigator_unit_id"], before["burning_source"]["credit_unit_id"])
		actor = source.instigator_unit_id
		var raw: Array[Dictionary] = [{"type": "fire", "policy": "standard", "source": "burning", "numerator": before["burning_stacks"], "denominator": 1}]
		request = ArmorAttack.request(_unit.id, raw, source)
		var plan := ArmorHitExecutor.prepare(request, guard.values["participants"][_unit.id]["armor"], _unit.vitals.get_hp(), ActionHpExecutor._stat_value(_unit, StatTypes.StatType.HP_MAX), context.get_rng())
		if source.validate(context) != &"" or plan.get("reason", &"") != &"": return CommandStepResult.faulted(&"status/invalid_tick")
		if plan["hp_after"] == 0 and context.get_state().get_board().board_version >= ActionContext.MAX_ID: return CommandStepResult.faulted(&"push/board_version_exhausted")
	var written := ElementalRules.write(_unit, planned["after"], guard, context, effect, actor)
	var result: CommandStepResult = written["result"]
	if _expire or result.status != &"APPLIED": return result
	var hit: CommandStepResult = ArmorHitExecutor.execute(request, written["guard"], context)["result"]
	result.events.append_array(hit.events)
	result.state_changed = result.state_changed or hit.state_changed
	result.status = hit.status; result.reason = hit.reason
	return result
