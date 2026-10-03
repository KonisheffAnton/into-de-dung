extends RefCounted
class_name MageSummonEffect

## Тестовые заклинания используют прежний runtime помощника; выбранный союзник
## задаёт только связь/лимит и соседство, но не платит действия или предметы.
static func prepare(context: ActionContext, owner_id: int, cell: Vector2i, spell: StringName, paid: Dictionary) -> Dictionary:
	var state := context.get_state()
	var board := state.get_board()
	var owner := board.get_unit_by_id(owner_id)
	if owner == null or not owner.is_alive() or owner.faction != Faction.Type.PLAYER or board.occupant_at(owner.cell) != owner:
		return {"reason": &"mage/invalid_summon_owner"}
	if state.summon_owner_id(owner_id) != 0: return {"reason": &"summon/helper_cannot_summon"}
	if state.active_summon(owner_id) != null: return {"reason": &"summon/active_helper"}
	var facade := state.get_owner(owner_id)
	if facade == null or facade.is_closed() or facade.get_owner() != owner or owner.action_resources == null:
		return {"reason": &"mage/invalid_runtime"}
	if not UseSummoningItemCommand.valid_cell(board, owner.cell, cell) or (state.environment != null and not state.environment.fire_at(cell).is_empty()):
		return {"reason": &"summon/invalid_cell"}
	var corpse_id := 0
	if spell == &"mage.test_raise":
		if state.environment == null: return {"reason": &"environment/not_enabled"}
		for corpse: Dictionary in state.environment.corpses:
			if corpse.cell == cell and corpse.creature_kind == "humanoid" and (corpse_id == 0 or int(corpse.id) < corpse_id): corpse_id = int(corpse.id)
		if corpse_id == 0: return {"reason": &"environment/no_corpse"}
	var id := UseSummoningItemCommand.next_id(board)
	if id == 0 or board.board_version >= ActionContext.MAX_ID - 1 or board.get_all_units().size() >= ItemSimulationSnapshot.MAX_OWNERS:
		return {"reason": &"summon/id_exhausted"}
	var admission := SummonAdmission.extend(context.get_move_rules(), context.get_attack_rules(), id, owner_id, false)
	if admission.is_empty(): return {"reason": &"summon/invalid_admission"}
	var helper := UseSummoningItemCommand.make_helper(id, owner.faction, cell, owner.debug_name)
	if helper == null: return {"reason": &"environment/invalid_helper_name"}
	helper.armor = ArmorState.new(); helper.armor.in_battle = true
	helper.bleeding = BleedingState.new()
	if owner.elemental != null:
		helper.elemental = ElementalState.new(); helper.bleeding.stacked = true
	var before := ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids())
	if before.code != ItemSnapshotResult.Code.OK: return {"reason": &"mage/invalid_runtime"}
	var expected := SummonMutationProjection.expected(before.snapshot, helper, owner_id, board.get_height(cell), 0, 0, 0, corpse_id, paid)
	if expected.code != ItemSnapshotResult.Code.OK: return {"reason": &"mage/invalid_runtime"}
	var guard := SpatialRules.capture_guard(context, [owner], [owner.cell, cell], {})
	if guard == null: return {"reason": &"mage/invalid_runtime"}
	return {"reason": &"", "target": owner, "guard": guard, "helper": helper, "owner_id": owner_id, "corpse_id": corpse_id,
		"admission": admission, "expected": expected.snapshot.to_dict(), "state": state, "board": board,
		"environment": state.environment, "originals": board.get_all_units(), "owners": state.get_owners(),
		"inventories": state.get_inventories(), "equipment": state.get_equipment_facades(),
		"rng": context.get_rng(), "rng_before": context.get_rng().to_dict().duplicate(true), "counters": context.simulation_counters()}

static func apply(context: ActionContext, plan: Dictionary, spell: StringName, source: DamageSource, sealed: Callable) -> CommandStepResult:
	var state: ItemSimulationState = plan.state
	var board: BattleBoard = plan.board
	var helper: UnitState = plan.helper
	var helper_id := helper.id
	var cell := helper.cell
	if int(plan.corpse_id) != 0: state.environment.consume_corpse(int(plan.corpse_id))
	state.register_summon_owner(helper, int(plan.owner_id))
	context._move_rules = plan.admission.move
	context._attack_rules = plan.admission.attack
	board.add_unit(helper)
	var event := {"kind": &"mage_summoned", "spell_id": String(spell), "actor_unit_id": 0, "owner_unit_id": int(plan.owner_id),
		"target_unit_id": helper_id, "corpse_id": int(plan.corpse_id), "cell": cell, "source": source.to_dict()}
	var result := CommandStepResult.applied([event], [], [], null, true)
	var actual := ItemSimulationSnapshot.capture(state, [])
	var expected_context := ActionContext.new(null, null, null, [], plan.admission.move, plan.admission.attack)
	var valid: bool = bool(sealed.call()) and context.get_state() == state and state.get_board() == board and state.environment == plan.environment and context.get_rng() == plan.rng
	valid = valid and context.get_rng().to_dict() == plan.rng_before and context.simulation_counters() == plan.counters and SummonAdmission.values(context) == SummonAdmission.values(expected_context)
	valid = valid and actual.code == ItemSnapshotResult.Code.OK
	if valid: valid = actual.snapshot.to_dict() == plan.expected
	for original: UnitState in plan.originals: valid = valid and board.get_unit_by_id(original.id) == original
	valid = valid and board.get_unit_by_id(helper.id) == helper and state.get_owner(helper.id) != null and state.get_owner(helper.id).get_owner() == helper
	valid = valid and state.get_owners().slice(0, plan.owners.size()) == plan.owners and state.get_inventories().slice(0, plan.inventories.size()) == plan.inventories and state.get_equipment_facades().slice(0, plan.equipment.size()) == plan.equipment
	if not valid:
		result.status = &"FAULTED"; result.reason = &"mage/summon_checkpoint"
	return result

static func valid_draft(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "spell_id": TYPE_STRING, "actor_unit_id": TYPE_INT, "owner_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "corpse_id": TYPE_INT, "cell": TYPE_VECTOR2I, "source": TYPE_DICTIONARY}): return false
	if event.kind != &"mage_summoned" or event.actor_unit_id != 0 or not AbilityDefinition.is_cell_spell(StringName(event.spell_id)): return false
	for key: String in ["owner_unit_id", "target_unit_id"]:
		if event[key] <= 0 or event[key] >= ActionContext.MAX_ID: return false
	if event.owner_unit_id == event.target_unit_id: return false
	if event.spell_id == "mage.test_raise":
		if event.corpse_id <= 0 or event.corpse_id >= ActionContext.MAX_ID: return false
	elif event.corpse_id != 0: return false
	return event.source == DamageSource.new(&"mage", AbilityDefinition.mage_source_id(StringName(event.spell_id)), Vector2i(-1, -1), 0, 0).to_dict()
