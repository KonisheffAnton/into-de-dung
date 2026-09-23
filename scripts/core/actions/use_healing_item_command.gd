extends Command
class_name UseHealingItemCommand

## Заряд и main оплачиваются в том же шаге, что HP: у лечения нет обрываемого хвоста.
var _actor_id: int
var _item_id: int
var _revision: int

func _init(actor_id: int = 0, item_id: int = 0, expected_revision: int = 0) -> void:
	_actor_id = actor_id
	_item_id = item_id
	_revision = expected_revision

func get_kind() -> StringName: return &"use_healing_item"

func copy_for_queue() -> Command:
	return UseHealingItemCommand.new(_actor_id, _item_id, _revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"item/invalid_runtime"
	if _revision < 0 or _revision > ActionQueue.MAX_ID - 2 or _revision != context.get_revision(): return &"item/stale_revision"
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"item/no_selected_unit"
	var control_reason := ControlRules.action_reason(actor)
	if control_reason != &"": return control_reason
	var capture := ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids())
	if capture.code != ItemSnapshotResult.Code.OK: return &"item/invalid_runtime"
	var owner := state.get_owner(_actor_id)
	if owner == null or owner.is_closed() or owner.get_owner() != actor or state.get_board().occupant_at(actor.cell) != actor: return &"item/invalid_runtime"
	var rules := context.get_move_rules()
	if rules == null or rules.validate() != &"" or not rules.allows(actor.id): return &"item/not_admitted"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"": return &"item/invalid_runtime"
	var item: ItemInstance = owner._items.get(_item_id)
	if item == null or item.get_owner_unit_id() != actor.id: return &"item/not_owned"
	if not item.is_active() or item._get_placement() == 0: return &"item/inactive"
	if item.get_definition().use_summon or item.get_definition().use_heal_amount <= 0.0: return &"item/not_usable"
	if item.get_charges_left() == 0: return &"item/no_charges"
	if actor.action_resources.get_main_left() < 1: return &"item/insufficient_main"
	var maximum := ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX)
	if not is_finite(maximum) or maximum <= 0.0: return &"item/invalid_runtime"
	if actor.vitals.get_hp() >= maximum: return &"item/full_hp"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	var item: ItemInstance = state.get_owner(_actor_id)._items[_item_id]
	var maximum := ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX)
	var amount := minf(item.get_definition().use_heal_amount, maximum - actor.vitals.get_hp())
	var main_before := actor.action_resources.get_main_left()
	var charges_before := item.get_charges_left()
	var source := DamageSource.new(&"item", _item_id, actor.cell, actor.id, actor.id)
	if not actor.action_resources.try_spend_main(1): return CommandStepResult.faulted(&"item/invalid_runtime")
	item._charges_left -= 1
	# Ожидаемые bytes строятся до сигнала; callback не может стать новым baseline.
	var expected := ItemSimulationSnapshot.capture(state, []).snapshot.to_dict()
	for unit: Dictionary in expected["board_snapshot"]["board"]["units"]:
		if unit["id"] == actor.id: unit["vitals"]["hp"] = actor.vitals.get_hp() + amount
	var counters := context.simulation_counters()
	var rng := context.get_rng()
	var rng_before := rng.to_dict().duplicate(true)
	var checkpoint := func() -> StringName:
		if context.get_state() != state or context.get_rng() != rng or context.get_revision() != _revision or context.simulation_counters() != counters or rng.to_dict() != rng_before:
			return &"item/invalid_mutation"
		var actual := ItemSimulationSnapshot.capture(state, [])
		return &"" if actual.code == ItemSnapshotResult.Code.OK and actual.snapshot.to_dict() == expected else &"item/invalid_mutation"
	var mutation := actor.vitals.heal_checked(amount, checkpoint)
	var used := {"kind": &"item_used", "actor_unit_id": _actor_id, "target_unit_id": _actor_id, "item_instance_id": _item_id, "main_cost": 1, "main_before": main_before, "main_after": main_before - 1, "charges_before": charges_before, "charges_after": charges_before - 1}
	var healed := ActionHpExecutor._draft(&"healed", _actor_id, source, mutation.hp_before, mutation.hp_after, mutation.hp_after - mutation.hp_before, true, true)
	var result := CommandStepResult.applied([used, healed], [], [], null, true)
	if mutation.reason != &"":
		result.status = &"FAULTED"
		result.reason = mutation.reason
	return result
