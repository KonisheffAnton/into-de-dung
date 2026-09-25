extends Command
class_name GuardCommand

## Самостоятельная оплачиваемая команда; выбор и preview не могут включить стойку.
var _actor_id: int
var _revision: int
var _mode: int
var _cover_id: int

func _init(actor_id: int = 0, expected_revision: int = 0, mode: int = -1, cover_target_id: int = 0) -> void:
	_actor_id = actor_id
	_revision = expected_revision
	_mode = mode
	_cover_id = cover_target_id

func get_kind() -> StringName: return &"guard"

func copy_for_queue() -> Command:
	return GuardCommand.new(_actor_id, _revision, _mode, _cover_id)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"guard/invalid_runtime"
	if _revision < 0 or _revision > ActionQueue.MAX_ID - 2 or _revision != context.get_revision(): return &"guard/stale_revision"
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"guard/no_selected_unit"
	var control_reason := ControlRules.action_reason(actor)
	if control_reason != &"": return control_reason
	if actor.get_script() != UnitState or actor.to_snapshot_dict().is_empty() or board.occupant_at(actor.cell) != actor: return &"guard/invalid_runtime"
	var owner := context.get_state().get_owner(_actor_id)
	if owner == null or owner.is_closed() or owner.get_owner() != actor: return &"guard/invalid_runtime"
	var rules := context.get_move_rules()
	if rules == null or rules.validate() != &"" or not rules.allows(_actor_id): return &"guard/not_admitted"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"": return &"guard/invalid_runtime"
	if _mode not in [-1, CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER]: return &"perks/invalid_mode"
	if _mode == CombatPerksState.Mode.COVER:
		if not MeleeThreat.has_tank(actor): return &"perks/not_owned"
		if not MeleeThreat.cover_eligible(context, actor, board.get_unit_by_id(_cover_id)): return &"perks/invalid_cover_target"
	elif _cover_id != 0: return &"perks/invalid_cover_target"
	if _mode >= 0 and not MeleeThreat.has_tank(actor): return &"perks/not_owned"
	var requested_mode := CombatPerksState.Mode.NONE if _mode < 0 else _mode
	if actor.guard_stance and (not MeleeThreat.has_tank(actor) or (actor.combat_perks.mode == requested_mode and actor.combat_perks.cover_target_id == _cover_id)): return &"guard/already_active"
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
	var result := CommandStepResult.applied([event], [], [], null, true)
	if MeleeThreat.has_tank(actor):
		actor.combat_perks.mode = CombatPerksState.Mode.NONE if _mode < 0 else _mode
		actor.combat_perks.cover_target_id = _cover_id
		# Переключение оплачивается действием, но никогда не возвращает заряд реакции.
		result.combat_perk_changes[actor.id] = CombatPerkGuard.record(actor, actor.combat_perks)
		result.events[0]["reaction_mode"] = actor.combat_perks.mode
		result.events[0]["cover_target_id"] = _cover_id
	return result
