extends Command
class_name GuardCommand

## Самостоятельная оплачиваемая команда; выбор и preview не могут включить стойку.
var _actor_id: int
var _revision: int

func _init(actor_id: int = 0, expected_revision: int = 0) -> void:
	_actor_id = actor_id
	_revision = expected_revision

func get_kind() -> StringName: return &"guard"

func copy_for_queue() -> Command:
	return GuardCommand.new(_actor_id, _revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"guard/invalid_runtime"
	if _revision < 0 or _revision > ActionQueue.MAX_ID - 2 or _revision != context.get_revision(): return &"guard/stale_revision"
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"guard/no_selected_unit"
	if actor.get_script() != UnitState or actor.to_snapshot_dict().is_empty() or board.occupant_at(actor.cell) != actor: return &"guard/invalid_runtime"
	var owner := context.get_state().get_owner(_actor_id)
	if owner == null or owner.is_closed() or owner.get_owner() != actor: return &"guard/invalid_runtime"
	var rules := context.get_move_rules()
	if rules == null or rules.validate() != &"" or not rules.allows(_actor_id): return &"guard/not_admitted"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"": return &"guard/invalid_runtime"
	if actor.guard_stance: return &"guard/already_active"
	if actor.action_resources.get_main_left() < 1: return &"guard/insufficient_main"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var actor := context.get_state().get_board().get_unit_by_id(_actor_id)
	var before := actor.action_resources.get_main_left()
	if not actor.action_resources.try_spend_main(1): return CommandStepResult.faulted(&"guard/invalid_runtime")
	actor.guard_stance = true
	var event := {"kind": &"guarded", "actor_unit_id": actor.id, "target_unit_id": actor.id, "main_cost": 1, "main_before": before, "main_after": before - 1}
	return CommandStepResult.applied([event], [], [], null, true)
