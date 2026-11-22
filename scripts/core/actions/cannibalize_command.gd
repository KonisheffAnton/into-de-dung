extends Command
class_name CannibalizeCommand

var _actor_id: int
var _corpse_id: int
var _revision: int

func _init(actor_id: int = 0, corpse_id: int = 0, revision: int = 0) -> void:
	_actor_id = actor_id; _corpse_id = corpse_id; _revision = revision

func get_kind() -> StringName: return &"cannibalize"
func copy_for_queue() -> Command: return CannibalizeCommand.new(_actor_id, _corpse_id, _revision)

func _corpse(state: ItemSimulationState) -> Dictionary:
	if state.environment != null:
		for record: Dictionary in state.environment.corpses:
			if record.id == _corpse_id: return record.duplicate(true)
	return {}

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().environment == null: return &"cannibalize/no_environment"
	if _revision < 0 or _revision > ActionContext.MAX_ID - 2 or _revision != context.get_revision(): return &"cannibalize/stale_revision"
	var state := context.get_state()
	var board := state.get_board()
	if board == null: return &"cannibalize/invalid_state"
	var actor := board.get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"cannibalize/no_actor"
	if not TroglodyteKit.owns(actor): return &"cannibalize/not_owned"
	if actor.armor == null or not actor.armor.fractional: return &"cannibalize/fractional_hp_required"
	var reason := ControlRules.action_reason(actor)
	if reason != &"": return reason
	if ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids()).code != ItemSnapshotResult.Code.OK: return &"cannibalize/invalid_state"
	if board.occupant_at(actor.cell) != actor or actor.action_resources == null: return &"cannibalize/invalid_actor"
	if actor.action_resources.get_main_left() < 1: return &"cannibalize/insufficient_main"
	var rules := context.get_move_rules()
	if rules == null or not rules.allows(actor.id) or state.is_summon_pending(actor.id): return &"cannibalize/not_admitted"
	if state.abilities != null and (state.abilities.stage != "active" or state.abilities.team != actor.faction): return &"cannibalize/wrong_turn"
	var corpse := _corpse(state)
	if corpse.is_empty() or corpse.remains != "fresh": return &"cannibalize/no_fresh_corpse"
	var delta: Vector2i = corpse.cell - actor.cell
	if absi(delta.x) + absi(delta.y) > 1 or not board.is_terrain_walkable(corpse.cell) or absi(board.get_height_steps(corpse.cell) - board.get_height_steps(actor.cell)) > 1: return &"cannibalize/out_of_reach"
	if board.occupant_at(corpse.cell) != null and corpse.cell != actor.cell: return &"cannibalize/occupied"
	if actor.vitals.get_hp() >= ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX): return &"cannibalize/full_hp"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	var corpse := _corpse(state)
	var before := actor.vitals.get_hp()
	var amount := (ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX) - before) * 0.5
	var main_before := actor.action_resources.get_main_left()
	var source := DamageSource.new(&"creature", actor.id, actor.cell, actor.id, actor.id)
	# Плата и тело расходуются в том же шаге, что лечение, до любого сигнала HP.
	if not actor.action_resources.try_spend_main(1): return CommandStepResult.faulted(&"cannibalize/invalid_actor")
	state.environment.consume_corpse(_corpse_id)
	var guard := SpatialRules.capture_guard(context, [actor], [actor.cell], {actor.id: [StatTypes.StatType.HP_MAX]})
	if guard == null:
		var failed := CommandStepResult.faulted(&"cannibalize/invalid_state")
		failed.state_changed = true
		return failed
	var expected_guard := guard.hit_hp_phase(actor.id, before + amount, false)
	var captured := ItemSimulationSnapshot.capture(state, [])
	if captured.code != ItemSnapshotResult.Code.OK:
		var failed := CommandStepResult.faulted(&"cannibalize/invalid_state")
		failed.state_changed = true
		return failed
	var expected := captured.snapshot.to_dict()
	for unit: Dictionary in expected.board_snapshot.board.units:
		if unit.id == actor.id: unit.vitals.hp = before + amount
	var counters := context.simulation_counters()
	var admission := SummonAdmission.values(context)
	var seal := [_actor_id, _corpse_id, _revision]
	var checkpoint := func() -> StringName:
		if [_actor_id, _corpse_id, _revision] != seal or context.get_state() != state or context.simulation_counters() != counters or SummonAdmission.values(context) != admission or not expected_guard.check(context): return &"cannibalize/invalid_mutation"
		var actual := ItemSimulationSnapshot.capture(state, [])
		return &"" if actual.code == ItemSnapshotResult.Code.OK and actual.snapshot.to_dict() == expected else &"cannibalize/invalid_mutation"
	var mutation := actor.vitals.heal_checked(amount, checkpoint)
	var consumed := {"kind": &"corpse_consumed", "actor_unit_id": actor.id, "target_unit_id": actor.id, "corpse_id": _corpse_id, "cell": corpse.cell, "main_before": main_before, "main_after": main_before - 1}
	var healed := ActionHpExecutor._draft(&"healed", actor.id, source, mutation.hp_before, mutation.hp_after, mutation.hp_after - mutation.hp_before, true, true)
	var result := CommandStepResult.applied([consumed, healed], [], [], null, true)
	if mutation.reason != &"": result.status = CommandStepResult.FAULTED; result.reason = mutation.reason
	return result

static func valid_draft(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "corpse_id": TYPE_INT, "cell": TYPE_VECTOR2I, "main_before": TYPE_INT, "main_after": TYPE_INT}): return false
	return event.kind == &"corpse_consumed" and event.actor_unit_id > 0 and event.actor_unit_id < ActionContext.MAX_ID and event.target_unit_id == event.actor_unit_id and event.corpse_id > 0 and event.corpse_id < ActionContext.MAX_ID and event.main_before >= 1 and event.main_before <= 4096 and event.main_after == event.main_before - 1
