extends RefCounted
class_name MageSummonEffect

## Прежний вариант с владельцем сохранён для будущего персонажа-мага.
## Верховный маг выбирает лишь опорного союзника для проверки зоны, не владельца.
static func prepare_owned(context: ActionContext, owner_id: int, cell: Vector2i, spell: StringName, paid: Dictionary) -> Dictionary:
	return _prepare(context, owner_id, cell, spell, paid, true)

static func zone_anchor(state: ItemSimulationState, cell: Vector2i) -> UnitState:
	var found: UnitState = null
	for ally: UnitState in state.get_board().get_all_units():
		if not ally.is_alive() or ally.faction != Faction.Type.PLAYER: continue
		if not UseSummoningItemCommand.valid_cell(state.get_board(), ally.cell, cell): continue
		if found == null or ally.id < found.id: found = ally
	return found

static func prepare(context: ActionContext, _selected_id: int, cell: Vector2i, spell: StringName, paid: Dictionary, deck_after: Dictionary = {}, effects_after: Dictionary = {}) -> Dictionary:
	var anchor := zone_anchor(context.get_state(), cell)
	if anchor == null: return {"reason": &"summon/invalid_cell"}
	return _prepare(context, anchor.id, cell, spell, paid, false, deck_after, effects_after)

static func _prepare(context: ActionContext, owner_id: int, cell: Vector2i, spell: StringName, paid: Dictionary, owned: bool, deck_after: Dictionary = {}, effects_after: Dictionary = {}) -> Dictionary:
	var state := context.get_state()
	var board := state.get_board()
	var owner := board.get_unit_by_id(owner_id)
	if owner == null or not owner.is_alive() or owner.faction != Faction.Type.PLAYER or board.occupant_at(owner.cell) != owner:
		return {"reason": &"mage/invalid_summon_owner"}
	if owned and state.is_summon(owner_id): return {"reason": &"summon/helper_cannot_summon"}
	if owned and state.active_summon(owner_id) != null: return {"reason": &"summon/active_helper"}
	var facade := state.get_owner(owner_id)
	if facade == null or facade.is_closed() or facade.get_owner() != owner or owner.action_resources == null:
		return {"reason": &"mage/invalid_runtime"}
	if not UseSummoningItemCommand.valid_cell(board, owner.cell, cell) or (state.environment != null and not state.environment.fire_at(cell).is_empty()):
		return {"reason": &"summon/invalid_cell"}
	var corpse_id := 0
	if spell in [&"mage.test_raise", &"card.raise"]:
		if state.environment == null: return {"reason": &"environment/not_enabled"}
		for corpse: Dictionary in state.environment.corpses:
			if corpse.cell == cell and corpse.creature_kind == "humanoid" and (corpse_id == 0 or int(corpse.id) < corpse_id): corpse_id = int(corpse.id)
		if corpse_id == 0: return {"reason": &"environment/no_corpse"}
	var id := UseSummoningItemCommand.next_id(board)
	if id == 0 or board.board_version >= ActionContext.MAX_ID - 1 or board.get_all_units().size() >= ItemSimulationSnapshot.MAX_OWNERS:
		return {"reason": &"summon/id_exhausted"}
	var admission := SummonAdmission.extend(context.get_move_rules(), context.get_attack_rules(), id, owner_id, false) if owned else SummonAdmission.extend_team(context.get_move_rules(), context.get_attack_rules(), id, board, false)
	if admission.is_empty(): return {"reason": &"summon/invalid_admission"}
	var helper := UseSummoningItemCommand.make_helper(id, owner.faction, cell, owner.debug_name if owned else "Верховный маг")
	if helper == null: return {"reason": &"environment/invalid_helper_name"}
	helper.armor = ArmorState.new(); helper.armor.in_battle = true
	helper.bleeding = BleedingState.new()
	if not owned or owner.elemental != null:
		helper.elemental = ElementalState.new(); helper.bleeding.stacked = true
	if state.deck != null:
		if effects_after.is_empty() or context.get_attack_rules().get_definition(&"demo_strike") == null: return {"reason": &"summon/invalid_admission"}
		if BattleCardEffectState.from_dict(effects_after) == null: return {"reason": &"summon/invalid_admission"}
	var before := ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids())
	if before.code != ItemSnapshotResult.Code.OK: return {"reason": &"mage/invalid_runtime"}
	var expected := SummonMutationProjection.expected(before.snapshot, helper, owner_id, board.get_height(cell), 0, 0, 0, corpse_id, paid, not owned, deck_after, effects_after)
	if expected.code != ItemSnapshotResult.Code.OK: return {"reason": &"mage/invalid_runtime"}
	var final_effects: Dictionary = effects_after.duplicate(true)
	if state.deck != null:
		final_effects["ordinary_attacks"].append({"unit_id":id,"attack_id":"demo_strike"})
		final_effects["ordinary_attacks"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.unit_id < b.unit_id)
	var guard := SpatialRules.capture_guard(context, [owner], [owner.cell, cell], {})
	if guard == null: return {"reason": &"mage/invalid_runtime"}
	return {"reason": &"", "target": owner, "guard": guard, "helper": helper, "owner_id": owner_id if owned else 0, "anchor_id": owner_id, "corpse_id": corpse_id,
		"admission": admission, "expected": expected.snapshot.to_dict(), "effects_after": final_effects, "state": state, "board": board,
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
	if int(plan.owner_id) == 0: state.register_mage_summon(helper)
	else: state.register_summon_owner(helper, int(plan.owner_id))
	context._move_rules = plan.admission.move
	context._attack_rules = plan.admission.attack
	board.add_unit(helper)
	var event := {"kind": &"mage_summoned", "actor_unit_id": 0, "owner_unit_id": int(plan.owner_id),
		"target_unit_id": helper_id, "corpse_id": int(plan.corpse_id), "cell": cell, "source": source.to_dict()}
	if String(spell).begins_with("card."): event["card_type_id"] = String(spell)
	else: event["spell_id"] = String(spell)
	if int(plan.owner_id) == 0: event["anchor_unit_id"] = int(plan.anchor_id)
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
	var fields := {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "owner_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "corpse_id": TYPE_INT, "cell": TYPE_VECTOR2I, "source": TYPE_DICTIONARY}
	if event.has("card_type_id") == event.has("spell_id"): return false
	if event.has("card_type_id"): fields["card_type_id"] = TYPE_STRING
	else: fields["spell_id"] = TYPE_STRING
	if event.has("anchor_unit_id"): fields["anchor_unit_id"] = TYPE_INT
	if not ItemSimulationSnapshot._shape(event, fields): return false
	if event.kind != &"mage_summoned" or event.actor_unit_id != 0: return false
	var effect_id: StringName = StringName(event.card_type_id) if event.has("card_type_id") else StringName(event.spell_id)
	if event.has("card_type_id"):
		if effect_id not in [&"card.summon", &"card.raise"]: return false
	elif not AbilityDefinition.is_cell_spell(effect_id): return false
	if event.has("anchor_unit_id") and (event.owner_unit_id != 0 or event.anchor_unit_id <= 0 or event.anchor_unit_id >= ActionContext.MAX_ID or event.anchor_unit_id == event.target_unit_id): return false
	for key: String in (["anchor_unit_id", "target_unit_id"] if event.has("anchor_unit_id") else ["owner_unit_id", "target_unit_id"]):
		if event[key] <= 0 or event[key] >= ActionContext.MAX_ID: return false
	if event.owner_unit_id == event.target_unit_id: return false
	if effect_id in [&"mage.test_raise", &"card.raise"]:
		if event.corpse_id <= 0 or event.corpse_id >= ActionContext.MAX_ID: return false
	elif event.corpse_id != 0: return false
	var source_id: int = int(MageCardDefinition.SOURCE_IDS.get(String(effect_id), 0)) if event.has("card_type_id") else AbilityDefinition.mage_source_id(effect_id)
	return event.source == DamageSource.new(&"mage", source_id, Vector2i(-1, -1), 0, 0).to_dict()
