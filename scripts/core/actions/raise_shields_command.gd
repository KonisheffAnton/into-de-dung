extends Command
class_name RaiseShieldsCommand

var _actor_id: int
var _revision: int

func _init(actor_id: int = 0, revision: int = 0) -> void:
	_actor_id = actor_id
	_revision = revision

func get_kind() -> StringName: return &"raise_shields"
func copy_for_queue() -> Command: return RaiseShieldsCommand.new(_actor_id, _revision)

static func definition() -> AbilityDefinition:
	var value := AbilityDefinition.new()
	value.ability_id = &"unit.raise_shields"
	value.cooldown_turns = 1
	return value

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"raise_shields/invalid_runtime"
	if _revision != context.get_revision() or _revision < 0 or _revision > ActionContext.MAX_ID - 2: return &"raise_shields/stale_revision"
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"raise_shields/no_actor"
	if actor.to_snapshot_dict().is_empty() or state.get_board().occupant_at(actor.cell) != actor: return &"raise_shields/invalid_runtime"
	if actor.armor == null or not RaisedShield.valid(actor.armor.raised_shield): return &"raise_shields/not_owned"
	if not actor.armor.in_battle or state.abilities == null or not BattleAbilityState.valid(state.abilities.to_dict()): return &"raise_shields/invalid_runtime"
	var clock := state.abilities
	if clock.stage != "active" or clock.team != actor.faction or BattleAbilityState.battle_over(state): return &"raise_shields/wrong_turn"
	var registered := clock.definition(&"unit.raise_shields")
	if registered == null or registered.to_dict() != definition().to_dict(): return &"raise_shields/not_registered"
	var owner := state.get_owner(actor.id)
	if owner == null or owner.is_closed() or owner.get_owner() != actor: return &"raise_shields/invalid_runtime"
	var rules := context.get_move_rules()
	if state.is_summon_pending(actor.id) or rules == null or rules.validate() != &"" or not rules.allows(actor.id): return &"raise_shields/not_admitted"
	var reason := ControlRules.action_reason(actor)
	if reason != &"": return reason
	if actor.armor.raised_shield.active: return &"raise_shields/already_active"
	if clock.serials[actor.faction] < int(actor.armor.raised_shield.ready_turn): return &"raise_shields/cooldown"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"": return &"raise_shields/invalid_runtime"
	if actor.action_resources.get_main_left() < 1: return &"raise_shields/insufficient_main"
	if RaisedShield.activated(actor.armor.raised_shield, clock.serials[actor.faction]).is_empty(): return &"raise_shields/clock_exhausted"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var actor := context.get_state().get_board().get_unit_by_id(_actor_id)
	var before := actor.armor.raised_shield.duplicate(true)
	var after := RaisedShield.activated(before, context.get_state().abilities.serials[actor.faction])
	var main_before := actor.action_resources.get_main_left()
	# Оба результата проверены до оплаты; между записями нет игровых callbacks.
	if not actor.action_resources.try_spend_main(1): return CommandStepResult.faulted(&"raise_shields/invalid_runtime")
	actor.armor.raised_shield = after
	return CommandStepResult.applied([{"kind": &"raised_shields", "actor_unit_id": actor.id, "target_unit_id": actor.id, "main_before": main_before, "main_after": main_before - 1, "before": before, "after": after}], [], [], null, true)
