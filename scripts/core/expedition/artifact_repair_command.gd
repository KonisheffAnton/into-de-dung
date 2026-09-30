extends Command
class_name ArtifactRepairCommand

var _owner: int
var _serial: int
func _init(owner: int = 0, serial: int = 0) -> void: _owner = owner; _serial = serial
func get_kind() -> StringName: return &"artifact_repair"
func copy_for_queue() -> Command: return ArtifactRepairCommand.new(_owner, _serial)
func validate(context: ActionContext) -> StringName:
	if not BattleArtifactRules.references_valid(context) or context.get_state().artifacts.stacks(_owner,"formation") != 1: return &"artifact/invalid_source"
	var owner := context.get_state().get_board().get_unit_by_id(_owner)
	if owner == null or _serial != context.get_state().artifacts.formation_serials[owner.faction]: return &"artifact/invalid_turn"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var unit := state.get_board().get_unit_by_id(_owner)
	if not unit.is_alive() or not BattleArtifactRules.has_neighbour(state,unit): return CommandStepResult.skipped(&"artifact/no_formation")
	var guard := SpatialRules.capture_guard(context, [unit], [unit.cell], {})
	if guard == null: return CommandStepResult.faulted(&"artifact/invalid_state")
	var view: Dictionary = guard.values.participants[unit.id].armor.duplicate(true)
	# Печать ремонтирует только постоянный доспех: излишек не создаёт временную броню.
	view.state.in_battle = false
	var plan := ArmorRecovery.restore(view, ExpeditionCatalog.FORMATION_REPAIR, "artifact")
	if plan.get("reason") == &"armor/full": return CommandStepResult.skipped(&"artifact/full_armor")
	if plan.get("reason", &"") != &"": return CommandStepResult.faulted(plan.reason)
	var changes: Array[Dictionary] = []
	var source := DamageSource.new(&"item",0,unit.cell,unit.id,unit.id)
	var event := {"kind":&"armor_changed","actor_unit_id":unit.id,"target_unit_id":unit.id,"source":source.to_dict(),"items":changes,"grants":[]}
	var result := CommandStepResult.applied([])
	for delta: Dictionary in plan.items:
		var expected: Dictionary = guard.values.participants[unit.id].armor.duplicate(true)
		for item: Dictionary in expected.items:
			if item.item_id == delta.id: item.remaining = delta.after
		guard = guard.armor_phase(unit.id,expected)
		(state.get_owner(unit.id)._items[delta.id] as ItemInstance).armor_remaining = delta.after
		changes.append(delta.duplicate(true)); result.state_changed = true
		if result.events.is_empty(): result.events.append(event)
		if guard.check(context): unit.armor.changed.emit(&"item",delta.id,delta.before,delta.after)
		if not guard.check(context): result.status = &"FAULTED"; result.reason = &"artifact/checkpoint"; return result
	return result
