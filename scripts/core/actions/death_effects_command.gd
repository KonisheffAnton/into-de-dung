extends Command
class_name DeathEffectsCommand

var _unit_id: int
func _init(id: int = 0) -> void: _unit_id = id
func get_kind() -> StringName: return &"death_effects_clear"
func copy_for_queue() -> Command: return DeathEffectsCommand.new(_unit_id)
func validate(context: ActionContext) -> StringName:
	var unit := context.get_state().get_board().get_unit_by_id(_unit_id)
	return &"" if unit != null and not unit.is_alive() else &"return/death_target"
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var unit := state.get_board().get_unit_by_id(_unit_id)
	var before := ItemSimulationSnapshot.capture(state, [])
	if before.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"return/death_state")
	var expected := before.snapshot.to_dict()
	for index: int in expected.board_snapshot.board.units.size():
		if expected.board_snapshot.board.units[index].id == _unit_id:
			expected.board_snapshot.board.units[index] = ReturnEffects.cleared(expected.board_snapshot.board.units[index])
	var checked := ItemSimulationSnapshot.from_dict(expected)
	if checked.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"return/death_projection")
	ReturnEffects.apply(unit)
	var result := CommandStepResult.applied([],[],[],null,true)
	if state.get_board().get_all_units().any(func(other: UnitState) -> bool: return other.combat_perks != null):
		result.combat_perk_changes[_unit_id] = CombatPerkGuard.record(unit,unit.combat_perks)
	var after := ItemSimulationSnapshot.capture(state, [])
	if after.code != ItemSnapshotResult.Code.OK or after.snapshot.to_dict() != checked.snapshot.to_dict():
		result.status = &"FAULTED"; result.reason = &"return/death_checkpoint"
	return result
