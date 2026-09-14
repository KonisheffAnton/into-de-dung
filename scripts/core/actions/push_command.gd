extends Command
class_name PushCommand

var _binding: BalancePushRules.Binding
var _after_collision: bool = false
func _init(binding: BalancePushRules.Binding = null, after_collision: bool = false) -> void: _binding = binding.copy() if binding != null else null; _after_collision = after_collision
static func after_collision(binding: BalancePushRules.Binding) -> PushCommand: return PushCommand.new(binding, true)
func get_kind() -> StringName: return &"push"
func copy_for_queue() -> Command:
	var c := PushCommand.new(_binding, _after_collision); return c
func validate(context: ActionContext) -> StringName:
	var phase: StringName = &"after_collision" if _after_collision else &"push"
	var reason := BalancePushRules.binding_reason(_binding, context, phase)
	if reason != &"": return reason
	if _after_collision:
		var blocker := _binding.blocker
		if blocker == null or _binding.board.get_unit_by_id(blocker.id) != blocker or blocker.is_alive() or blocker.cell != _binding.values.get("blocker_cell", Vector2i.ZERO) or _binding.board.occupant_at(_binding.values.get("attempted_cell", Vector2i.ZERO)) != null:
			return &"push/entry_obstructed"
	return &""
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if _binding.values.get("spatial", false): return _execute_spatial(context)
	var prep := BalancePushRules.prepare_push(_binding, context, false)
	if prep.get("reason", &"") != &"": return CommandStepResult.faulted(prep["reason"])
	var required_touches: int = int(prep.get("board_touches", 0))
	if _binding.board.board_version < 0 or (required_touches > 0 and _binding.board.board_version > ActionContext.MAX_ID - required_touches):
		return CommandStepResult.faulted(&"push/board_version_exhausted")
	var out: int = prep["outcome"]
	if _after_collision and out != PushResult.Outcome.MOVED and out != PushResult.Outcome.FELL:
		return CommandStepResult.faulted(&"push/entry_obstructed")
	var actor := _binding.actor; var target := _binding.target
	var events: Array[Dictionary] = []
	if out == PushResult.Outcome.BLOCKED:
		events.append({"kind": &"push_blocked", "actor_unit_id": actor.id, "target_unit_id": target.id, "from_cell": prep["from_cell"], "attempted_cell": prep["attempted_cell"], "reason": prep["blocked_reason"]})
		return CommandStepResult.applied(events, [PushDamageCommand.new(prep["first"], prep["binding"] as BalancePushRules.Binding)], [], null, false)
	if out == PushResult.Outcome.COLLISION:
		var collision_binding := prep["binding"] as BalancePushRules.Binding
		if collision_binding == null or collision_binding.blocker == null: return CommandStepResult.faulted(&"push/invalid_binding")
		events.append({"kind": &"collision", "actor_unit_id": actor.id, "target_unit_id": target.id, "from_cell": prep["from_cell"], "attempted_cell": prep["attempted_cell"], "blocker_unit_id": collision_binding.blocker.id})
		return CommandStepResult.applied(events, [CollisionDamageCommand.new(prep["first"], prep["second"], collision_binding)], [], null, false)
	if out == PushResult.Outcome.FELL and not _binding.board.is_in_bounds(prep["attempted_cell"]):
		events.append({"kind": &"fell", "actor_unit_id": actor.id, "target_unit_id": target.id, "from_cell": prep["from_cell"], "attempted_cell": prep["attempted_cell"], "reason": &"bounds"})
		var source := DamageSource.new(&"fall", 0, prep["attempted_cell"], actor.id, actor.id)
		var death_result := ActionHpExecutor.death(target.id, source, context)
		events.append_array(death_result.events)
		return CommandStepResult.applied(events, [], [], null, true)
	var destination: Vector2i = prep["attempted_cell"]
	if not _binding.board.move_unit(target, destination): return CommandStepResult.faulted(&"push/board_move_failed")
	var move_event := {"kind": &"moved", "actor_unit_id": actor.id, "target_unit_id": target.id, "from_cell": prep["from_cell"], "to_cell": destination, "movement_kind": &"push", "move_cost": 0.0, "move_before": target.move_points_left, "move_after": target.move_points_left}
	events.append(move_event)
	# Callback от авторитетного move может отклонить остаток, но не стирает
	# уже завершённый movement prefix.
	if target.vitals != _binding.target_vitals or _binding.board.get_unit_by_id(target.id) != target or not target.is_alive():
		var stale := CommandStepResult.faulted(&"push/invalid_binding")
		stale.events = events
		stale.state_changed = true
		return stale
	if out == PushResult.Outcome.FELL:
		var source2 := DamageSource.new(&"fall", 0, destination, actor.id, actor.id)
		var death_result2 := ActionHpExecutor.death(target.id, source2, context)
		events.append_array(death_result2.events)
		return CommandStepResult.applied(events, [], [], null, true)
	var mandatory: Array[Command] = []
	if prep["first"] != null:
		var damage_binding := (prep["binding"] as BalancePushRules.Binding).copy()
		damage_binding.values["phase"] = &"push_damage"
		damage_binding.values["target_cell"] = destination
		damage_binding.values["expected_hp"] = target.vitals.get_hp()
		damage_binding.values["expected_alive"] = target.is_alive()
		damage_binding.values["expected_target_hp"] = target.vitals.get_hp()
		damage_binding.values["expected_target_alive"] = target.is_alive()
		damage_binding.seal()
		mandatory.append(PushDamageCommand.new(prep["first"], damage_binding))
	return CommandStepResult.applied(events, mandatory, [], null, true)

func _execute_spatial(context: ActionContext) -> CommandStepResult:
	var prep := BalancePushRules.prepare_push(_binding, context)
	if prep["reason"] != &"": return CommandStepResult.faulted(prep["reason"])
	var required: int = prep["board_touches"]
	if int(_binding.spatial_guard.values["expected_board_version"]) > ActionContext.MAX_ID - required:
		return CommandStepResult.faulted(&"push/board_version_exhausted")
	var binding: BalancePushRules.Binding = prep["binding"]
	var outcome: int = prep["outcome"]
	var actor_id: int = binding.values["actor_id"]
	var target_id: int = binding.values["target_id"]
	var from: Vector2i = prep["from_cell"]
	var to: Vector2i = prep["attempted_cell"]
	if _after_collision and outcome not in [PushResult.Outcome.MOVED, PushResult.Outcome.FELL]: return CommandStepResult.faulted(&"push/entry_obstructed")
	if outcome == PushResult.Outcome.BLOCKED:
		var event := {"kind": &"push_blocked", "actor_unit_id": actor_id, "target_unit_id": target_id, "from_cell": from, "attempted_cell": to, "reason": prep["blocked_reason"]}
		return CommandStepResult.applied([event], [PushDamageCommand.new(prep["first"], binding)], [], null, false)
	if outcome == PushResult.Outcome.COLLISION:
		var event := {"kind": &"collision", "actor_unit_id": actor_id, "target_unit_id": target_id, "from_cell": from, "attempted_cell": to, "blocker_unit_id": binding.values["blocker_id"]}
		return CommandStepResult.applied([event], [CollisionDamageCommand.new(prep["first"], prep["second"], binding)], [], null, false)
	var events: Array[Dictionary] = []
	var changed := false
	if outcome == PushResult.Outcome.FELL and not binding.board.is_in_bounds(to):
		events.append({"kind": &"fell", "actor_unit_id": actor_id, "target_unit_id": target_id, "from_cell": from, "attempted_cell": to, "reason": &"bounds"})
	else:
		var before: float = binding.spatial_guard.values["participants"][target_id]["move"]
		var moved := binding.spatial_guard.moved(target_id, to)
		if not binding.board.move_unit(binding.target, to): return CommandStepResult.faulted(&"push/board_move_failed")
		events.append({"kind": &"moved", "actor_unit_id": actor_id, "target_unit_id": target_id, "from_cell": from, "to_cell": to, "movement_kind": &"push", "move_cost": 0.0, "move_before": before, "move_after": before})
		if not binding.sealed() or not moved.check(context):
			var fault := CommandStepResult.faulted(&"push/invalid_binding")
			fault.events = events; fault.state_changed = true
			return fault
		changed = true
		binding = BalancePushRules.spatial_phase(binding, moved, &"push_damage")
	if outcome == PushResult.Outcome.FELL:
		var source := DamageSource.new(&"fall", 0, to, actor_id, actor_id)
		var request := DamageRequest.new(target_id, 1.0, &"physical", &"bypass", source)
		var death := BalancePushRules.spatial_hp(binding, request, context, &"push/invalid_binding", true)
		var result: CommandStepResult = death["result"]
		events.append_array(result.events)
		result.events = events; result.state_changed = changed or result.state_changed
		return result
	var children: Array[Command] = []
	if prep["first"] != null: children.append(PushDamageCommand.new(prep["first"], binding))
	return CommandStepResult.applied(events, children, [], null, changed)
