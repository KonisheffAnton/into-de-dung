extends Command
class_name BleedingMovementCommand

var _unit: UnitState

func _init(unit: UnitState = null) -> void: _unit = unit
func get_kind() -> StringName: return &"bleeding_movement"
func copy_for_queue() -> Command: return BleedingMovementCommand.new(_unit)

func validate(context: ActionContext) -> StringName:
	if context == null or _unit == null or context.get_state().get_board().get_unit_by_id(_unit.id) != _unit or not ElementalRules.valid_unit(_unit): return &"bleeding/invalid_movement"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if not _unit.is_alive() or _unit.bleeding.stacks == 0: return CommandStepResult.skipped(&"bleeding/inactive")
	var amount := ArmorFraction.make(_unit.bleeding.stacks).multiply(ArmorFraction.make(BleedingState.MOVE_DAMAGE))
	if not amount.valid: return CommandStepResult.faulted(&"bleeding/damage_exhausted")
	var guard := SpatialRules.capture_guard(context, [_unit], [_unit.cell], {_unit.id: [StatTypes.StatType.HP_MAX]})
	if guard == null: return CommandStepResult.faulted(&"bleeding/invalid_movement")
	var previous := _unit.bleeding.source
	var source := DamageSource.new(&"status", 0, _unit.cell, previous["instigator_unit_id"], previous["credit_unit_id"])
	var raw: Array[Dictionary] = [{"type": "physical", "policy": "hp_only_natural", "source": "bleeding_move", "numerator": amount.numerator, "denominator": amount.denominator}]
	return ArmorHitExecutor.execute(ArmorAttack.request(_unit.id, raw, source), guard, context)["result"]
