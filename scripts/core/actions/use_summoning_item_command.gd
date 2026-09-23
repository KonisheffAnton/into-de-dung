extends Command
class_name UseSummoningItemCommand

var _actor_id: int
var _item_id: int
var _cell: Vector2i
var _revision: int

func _init(actor_id: int = 0, item_id: int = 0, cell: Vector2i = Vector2i.ZERO, expected_revision: int = 0) -> void:
	_actor_id = actor_id
	_item_id = item_id
	_cell = cell
	_revision = expected_revision

func get_kind() -> StringName: return &"use_summoning_item"

func copy_for_queue() -> Command:
	return UseSummoningItemCommand.new(_actor_id, _item_id, _cell, _revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"item/invalid_runtime"
	if _revision < 0 or _revision > ActionQueue.MAX_ID - 2 or _revision != context.get_revision(): return &"item/stale_revision"
	var state := context.get_state()
	var board := state.get_board()
	var actor := board.get_unit_by_id(_actor_id)
	if actor == null or not actor.is_alive(): return &"item/no_selected_unit"
	var control_reason := ControlRules.action_reason(actor)
	if control_reason != &"": return control_reason
	if actor.armor != null: return &"armor/summon_unsupported"
	if ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids()).code != ItemSnapshotResult.Code.OK: return &"item/invalid_runtime"
	var owner := state.get_owner(_actor_id)
	if owner == null or owner.is_closed() or owner.get_owner() != actor or board.occupant_at(actor.cell) != actor: return &"item/invalid_runtime"
	var move := context.get_move_rules()
	if move == null or move.validate() != &"" or not move.allows(actor.id): return &"item/not_admitted"
	if state.summon_owner_id(actor.id) != 0: return &"summon/helper_cannot_summon"
	if actor.action_resources == null or actor.action_resources.validate(actor.id) != &"": return &"item/invalid_runtime"
	var item: ItemInstance = owner._items.get(_item_id)
	if item == null or item.get_owner_unit_id() != actor.id: return &"item/not_owned"
	if not item.is_active() or item._get_placement() == 0: return &"item/inactive"
	if not item.get_definition().use_summon: return &"item/not_usable"
	var summon_definition := item._definition.get_summon_definition()
	if not SummonDefinition.valid_definition(summon_definition) or not summon_definition.name_valid(actor.debug_name): return &"item/invalid_definition"
	if item.get_charges_left() == 0: return &"item/no_charges"
	if actor.action_resources.get_main_left() < 1: return &"item/insufficient_main"
	if state.active_summon(actor.id) != null: return &"summon/active_helper"
	if not valid_cell(board, actor.cell, _cell): return &"summon/invalid_cell"
	var id := next_id(board)
	if id == 0 or board.board_version >= ActionQueue.MAX_ID - 1: return &"summon/id_exhausted"
	if SummonAdmission.extend(move, context.get_attack_rules(), id, actor.id, false).is_empty(): return &"summon/invalid_admission"
	return &""

static func valid_cell(board: BattleBoard, origin: Vector2i, cell: Vector2i) -> bool:
	return absi(cell.x - origin.x) + absi(cell.y - origin.y) == 1 and board.is_in_bounds(cell) and board.is_terrain_walkable(cell) and not board.is_lethal(cell) and not board.is_occupied(cell) and board.get_height_steps(cell) == board.get_height_steps(origin)

static func next_id(board: BattleBoard) -> int:
	var highest := 0
	for unit in board.get_all_units(): highest = maxi(highest, unit.id)
	return highest + 1 if highest < ActionQueue.MAX_ID - 2 else 0

static func make_helper(id: int, faction: Faction.Type, cell: Vector2i, owner_name: String, definition: SummonDefinition = null) -> UnitState:
	# Локальный id не трогает глобальный allocator ни в preflight, ни в preview.
	var effective_definition := SummonDefinition.new() if definition == null else definition
	if not SummonDefinition.valid_definition(effective_definition) or not effective_definition.name_valid(owner_name): return null
	var unit := UnitState.new()
	unit.id = id
	unit.faction = faction
	unit.cell = cell
	unit.debug_name = effective_definition.make_name(owner_name)
	unit.stats = StatsBag.from_base_values(effective_definition.base_values())
	unit.vitals = Vitals.new(unit.stats, true)
	unit.enable_action_resources()
	return unit

func _apply(context: ActionContext, id: int, admission: Dictionary) -> UnitState:
	var state := context.get_state()
	var actor := state.get_board().get_unit_by_id(_actor_id)
	var item: ItemInstance = state.get_owner(_actor_id)._items[_item_id]
	var unit := make_helper(id, actor.faction, _cell, actor.debug_name, item._definition.get_summon_definition())
	actor.action_resources.try_spend_main(1)
	item._charges_left -= 1
	state.register_summon_owner(unit, actor.id)
	context._move_rules = admission["move"]
	context._attack_rules = admission["attack"]
	state.get_board().add_unit(unit)
	return unit

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var board := state.get_board()
	var originals := board.get_all_units()
	var owners := state.get_owners()
	var inventories := state.get_inventories()
	var equipment := state.get_equipment_facades()
	var id := next_id(board)
	var admission := SummonAdmission.extend(context.get_move_rules(), context.get_attack_rules(), id, _actor_id, false)
	var definitions: Dictionary = {}
	for owner in owners:
		for key: StringName in owner._definitions: definitions[key] = (owner._definitions[key] as ItemDef).duplicate(true)
	var restored := ItemSimulationSnapshot.capture(state, []).snapshot.instantiate(definitions)
	if restored.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"summon/invalid_runtime")
	var copy_context := ActionContext.new(restored.state, ActionRngPort.new(), ActionEventSink.new(), [], context.get_move_rules(), context.get_attack_rules())
	_apply(copy_context, id, admission)
	var expected := ItemSimulationSnapshot.capture(restored.state, [])
	var expected_admission := SummonAdmission.values(copy_context)
	AttackForecast._close(restored.state)
	if expected.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"summon/invalid_runtime")
	var actor := board.get_unit_by_id(_actor_id)
	var item: ItemInstance = state.get_owner(_actor_id)._items[_item_id]
	var main_before := actor.action_resources.get_main_left()
	var charges_before := item.get_charges_left()
	var counters := context.simulation_counters()
	var rng := context.get_rng()
	var rng_before := rng.to_dict().duplicate(true)
	var unit := _apply(context, id, admission)
	var actual := ItemSimulationSnapshot.capture(state, [])
	var valid := context.get_state() == state and state.get_board() == board and context.get_rng() == rng and context.simulation_counters() == counters and rng.to_dict() == rng_before and SummonAdmission.values(context) == expected_admission and actual.code == ItemSnapshotResult.Code.OK
	if valid: valid = actual.snapshot.to_dict() == expected.snapshot.to_dict()
	for original in originals: valid = valid and board.get_unit_by_id(original.id) == original
	valid = valid and board.get_unit_by_id(id) == unit and state.get_owner(id).get_owner() == unit
	valid = valid and state.get_owners().slice(0, owners.size()) == owners and state.get_inventories().slice(0, inventories.size()) == inventories and state.get_equipment_facades().slice(0, equipment.size()) == equipment
	var used := {"kind": &"item_used", "actor_unit_id": _actor_id, "target_unit_id": _actor_id, "item_instance_id": _item_id, "main_cost": 1, "main_before": main_before, "main_after": main_before - 1, "charges_before": charges_before, "charges_after": charges_before - 1}
	var spawned := {"kind": &"summoned", "actor_unit_id": _actor_id, "target_unit_id": id, "item_instance_id": _item_id, "cell": _cell}
	var result := CommandStepResult.applied([used, spawned], [], [], null, true)
	if not valid:
		result.status = &"FAULTED"
		result.reason = &"summon/invalid_mutation"
	return result
