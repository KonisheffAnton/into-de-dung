extends Command
class_name RaiseCorpseCommand

var _actor_id: int
var _corpse_id: int
var _revision: int

func _init(actor_id: int = 0, corpse_id: int = 0, revision: int = 0) -> void:
	_actor_id = actor_id; _corpse_id = corpse_id; _revision = revision

func get_kind() -> StringName: return &"raise_corpse"
func copy_for_queue() -> Command: return RaiseCorpseCommand.new(_actor_id, _corpse_id, _revision)

func _corpse(state: ItemSimulationState) -> Dictionary:
	if state.environment != null:
		for record: Dictionary in state.environment.corpses:
			if record["id"] == _corpse_id: return record.duplicate(true)
	return {}

func _host_body(state: ItemSimulationState) -> bool:
	var body := _corpse(state)
	return state.card_effects != null and not body.is_empty() and body.source_unit_id == state.card_effects.host_unit_id

func _admission(context: ActionContext, id: int) -> Dictionary:
	return SummonAdmission.extend_team(context.get_move_rules(),context.get_attack_rules(),id,context.get_state().get_board(),false) if _host_body(context.get_state()) else SummonAdmission.extend(context.get_move_rules(),context.get_attack_rules(),id,_actor_id,false)

func projected_effects(context: ActionContext) -> Dictionary:
	var state := context.get_state()
	if state.card_effects == null: return {}
	var body := _corpse(state)
	var id := UseSummoningItemCommand.next_id(state.get_board())
	if body.is_empty() or id == 0: return {}
	var after := HostBinding.after_raise(state.card_effects.to_dict(),body,id,state.get_board().get_height_steps(body.cell))
	after.ordinary_attacks.append({"unit_id":id,"attack_id":String(MageDeckRules.RAISED_ATTACK)})
	after.ordinary_attacks.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.unit_id < b.unit_id)
	return after

func validate(context: ActionContext) -> StringName:
	return _availability(context, true)

func hint_reason(context: ActionContext) -> StringName:
	return _availability(context, false)

func _availability(context: ActionContext, full_snapshot: bool) -> StringName:
	if context == null or context.get_state() == null or context.get_state().environment == null: return &"environment/not_enabled"
	if _revision < 0 or _revision > ActionContext.MAX_ID - 2 or _revision != context.get_revision(): return &"environment/stale_revision"
	var state := context.get_state()
	var board := state.get_board()
	if not full_snapshot and board == null: return &"environment/invalid_state"
	if state.deck != null and context.get_attack_rules().get_definition(MageDeckRules.RAISED_ATTACK) == null: return &"summon/invalid_admission"
	var actor := board.get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"environment/no_actor"
	var control_reason := ControlRules.action_reason(actor)
	if control_reason != &"": return control_reason
	if not SummonDefinition.new().name_valid(actor.debug_name): return &"environment/invalid_helper_name"
	if full_snapshot and ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids()).code != ItemSnapshotResult.Code.OK: return &"environment/invalid_state"
	if state.is_summon(actor.id): return &"summon/helper_cannot_summon"
	if not _host_body(state) and state.active_summon(actor.id) != null: return &"summon/active_helper"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"" or board.occupant_at(actor.cell) != actor: return &"environment/invalid_actor"
	if actor.action_resources.get_main_left() < 1: return &"item/insufficient_main"
	var move := context.get_move_rules()
	if move == null or not move.allows(actor.id): return &"item/not_admitted"
	var corpse := _corpse(state)
	if corpse.is_empty() or corpse["creature_kind"] != "humanoid": return &"environment/no_corpse"
	if not UseSummoningItemCommand.valid_cell(board, actor.cell, corpse["cell"]) or not state.environment.fire_at(corpse["cell"]).is_empty(): return &"environment/invalid_raise_cell"
	var id := UseSummoningItemCommand.next_id(board)
	if id == 0 or board.board_version >= ActionContext.MAX_ID - 1 or board.get_all_units().size() >= ItemSimulationSnapshot.MAX_OWNERS: return &"summon/id_exhausted"
	if _admission(context,id).is_empty(): return &"summon/invalid_admission"
	return &""

func _new_helper(context: ActionContext, id: int, corpse: Dictionary) -> UnitState:
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	var unit := UseSummoningItemCommand.make_helper(id, Faction.Type.PLAYER if _host_body(state) else actor.faction, corpse["cell"], actor.debug_name)
	unit.creature_kind = &"undead"
	unit.armor = ArmorState.new()
	unit.armor.in_battle = true
	unit.armor.fractional = actor.armor != null and actor.armor.fractional
	unit.bleeding = BleedingState.new()
	unit.bleeding.authored = actor.bleeding != null and actor.bleeding.authored
	unit.bleeding.stacked = actor.bleeding != null and actor.bleeding.stacked
	if actor.elemental != null:
		unit.elemental = ElementalState.new()
		unit.elemental.authored = actor.elemental.authored
		unit.bleeding.stacked = true
	return unit

func _apply(context: ActionContext, unit: UnitState, admission: Dictionary) -> void:
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	var host_body := _host_body(state)
	var effects := projected_effects(context)
	var body := _corpse(state)
	actor.action_resources.try_spend_main(1)
	if state.card_effects != null: ReturnEffects.apply(state.get_board().get_unit_by_id(body.source_unit_id))
	state.environment.consume_corpse(_corpse_id)
	if host_body: state.register_mage_summon(unit)
	else: state.register_summon_owner(unit, actor.id)
	if state.card_effects != null: state.card_effects.apply_values(effects)
	context._move_rules = admission["move"]
	context._attack_rules = admission["attack"]
	state.get_board().add_unit(unit)

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var board := state.get_board()
	var environment := state.environment
	var originals := board.get_all_units()
	var owners := state.get_owners()
	var inventories := state.get_inventories()
	var equipment := state.get_equipment_facades()
	var corpse := _corpse(state)
	var id := UseSummoningItemCommand.next_id(board)
	var admission := _admission(context,id)
	var unit := _new_helper(context, id, corpse)
	var before := ItemSimulationSnapshot.capture(state, [])
	if before.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"environment/invalid_state")
	var expected := SummonMutationProjection.expected(before.snapshot, unit, _actor_id, board.get_height(corpse["cell"]), 1, 0, 0, _corpse_id, {}, _host_body(state))
	if expected.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"environment/invalid_state")
	var expected_context := ActionContext.new(null, null, null, [], admission["move"], admission["attack"])
	var expected_admission := SummonAdmission.values(expected_context)
	var main_before := board.get_unit_by_id(_actor_id).action_resources.get_main_left()
	var counters := context.simulation_counters()
	var rng := context.get_rng()
	var rng_before := rng.to_dict().duplicate(true)
	_apply(context, unit, admission)
	var actual := ItemSimulationSnapshot.capture(state, [])
	var valid := context.get_state() == state and state.get_board() == board and state.environment == environment and context.get_rng() == rng and context.simulation_counters() == counters and rng.to_dict() == rng_before and SummonAdmission.values(context) == expected_admission and actual.code == ItemSnapshotResult.Code.OK
	if valid: valid = actual.snapshot._data == expected.snapshot._data
	for original in originals: valid = valid and board.get_unit_by_id(original.id) == original
	valid = valid and board.get_unit_by_id(id) == unit and state.get_owner(id).get_owner() == unit
	valid = valid and state.get_owners().slice(0, owners.size()) == owners and state.get_inventories().slice(0, inventories.size()) == inventories and state.get_equipment_facades().slice(0, equipment.size()) == equipment
	var event := {"kind": &"corpse_raised", "actor_unit_id": _actor_id, "target_unit_id": id, "corpse_id": _corpse_id, "cell": corpse["cell"], "main_cost": 1, "main_before": main_before, "main_after": main_before - 1}
	var result := CommandStepResult.applied([event], [], [], null, true)
	if state.card_effects != null and board.get_all_units().any(func(other: UnitState) -> bool: return other.combat_perks != null):
		var original := board.get_unit_by_id(corpse.source_unit_id)
		result.combat_perk_changes[original.id] = CombatPerkGuard.record(original,original.combat_perks)
	if not valid:
		result.status = &"FAULTED"; result.reason = &"environment/invalid_mutation"
	return result

static func valid_draft(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "corpse_id": TYPE_INT, "cell": TYPE_VECTOR2I, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}): return false
	for field: String in ["actor_unit_id", "target_unit_id", "corpse_id"]:
		if event[field] < 1 or event[field] >= ActionContext.MAX_ID: return false
	return event["kind"] == &"corpse_raised" and event["actor_unit_id"] != event["target_unit_id"] and event["main_cost"] == 1 and event["main_before"] >= 1 and event["main_before"] <= 4096 and event["main_after"] == event["main_before"] - 1
