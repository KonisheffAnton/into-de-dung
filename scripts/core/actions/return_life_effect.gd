extends RefCounted
class_name ReturnLifeEffect

## Воскрешение сохраняет исходный UnitState и его вещи. Полный ожидаемый after
## строится до оплаты/сигнала, поэтому callback не может подменить baseline.
static func prepare(context: ActionContext, cell: Vector2i, source: DamageSource, paid: Dictionary, deck_after: Dictionary, effects_after: Dictionary) -> Dictionary:
	var state := context.get_state()
	var board := state.get_board()
	if not HostBinding.return_cell_valid(state, cell): return {"reason":&"return/invalid_cell"}
	var body: Dictionary = {}
	var target: UnitState = null
	for candidate: Dictionary in state.environment.corpses_at(cell):
		var unit := board.get_unit_by_id(candidate.source_unit_id)
		if candidate.remains != "fresh" or candidate.creature_kind != "humanoid" or unit == null: continue
		if unit.is_alive() or unit.faction != Faction.Type.PLAYER or unit.creature_kind != &"living" or state.is_summon(unit.id): continue
		body = candidate; target = unit; break
	if target == null: return {"reason":&"return/no_fresh_ally"}
	if board.board_version >= ActionContext.MAX_ID - 1: return {"reason":&"summon/id_exhausted"}
	var hp := minf(12.0, ActionHpExecutor._stat_value(target, StatTypes.StatType.HP_MAX))
	if not is_finite(hp) or hp <= 0.0: return {"reason":&"return/invalid_hp"}
	var admission := SummonAdmission.wait_for_return(context.get_move_rules(),context.get_attack_rules(),target.id)
	if admission.is_empty(): return {"reason":&"summon/invalid_admission"}
	var before := ItemSimulationSnapshot.capture(state, [])
	if before.code != ItemSnapshotResult.Code.OK: return {"reason":&"return/invalid_runtime"}
	var data := before.snapshot.to_dict()
	var after_effects := effects_after.duplicate(true)
	after_effects.fire_imbues = after_effects.fire_imbues.filter(func(entry: Dictionary) -> bool: return entry.unit_id != target.id)
	after_effects.pending_revivals.append(target.id); after_effects.pending_revivals.sort()
	data.card_effects = after_effects; data.deck = deck_after.duplicate(true); data.abilities = paid.duplicate(true)
	var environment := CombatEnvironmentState.from_dict(data.environment)
	environment.consume_corpse(body.id); environment.processed_deaths.erase(target.id)
	data.environment = environment.to_dict()
	var board_data: Dictionary = data.board_snapshot.board
	for index: int in board_data.units.size():
		if board_data.units[index].id != target.id: continue
		var unit_data := ReturnEffects.cleared(board_data.units[index])
		unit_data.vitals.hp = hp; unit_data.vitals.is_alive = true; unit_data.vitals.balance = 0.0
		unit_data.move_points_left = 0.0; unit_data.has_attacked = true
		unit_data.action_resources.main_left = 0; unit_data.action_resources.bonus_left = 0
		unit_data.height = board.get_height(cell)
		board_data.units[index] = unit_data
	board_data.occupancy.append({"x":cell.x,"y":cell.y,"unit_id":target.id})
	board_data.board_version += 1
	var expected := ItemSimulationSnapshot.from_dict(data)
	if expected.code != ItemSnapshotResult.Code.OK: return {"reason":&"return/invalid_projection"}
	var guard := SpatialRules.capture_guard(context,[target],[cell],{target.id:[StatTypes.StatType.HP_MAX]},true)
	if guard == null: return {"reason":&"return/invalid_runtime"}
	return {"reason":&"","target":target,"guard":guard,"source":source,"paid":paid,"effect":&"return_to_life",
		"effects_after":after_effects,"return_plan":{"body":body,"target":target,"hp":hp,"expected":expected.snapshot.to_dict(),
		"state":state,"board":board,"environment":state.environment,"effects_after":after_effects,
		"admission":admission,"originals":board.get_all_units(),"owners":state.get_owners(),"inventories":state.get_inventories(),
		"equipment":state.get_equipment_facades(),"references":_references(state),"rng":context.get_rng(),"rng_before":context.get_rng().to_dict(),"counters":context.simulation_counters()}}

static func apply(context: ActionContext, plan: Dictionary, source: DamageSource, sealed: Callable) -> CommandStepResult:
	var state: ItemSimulationState = plan.state
	var target: UnitState = plan.target
	var old_hp := target.vitals.get_hp()
	ReturnEffects.apply(target)
	state.environment.consume_corpse(plan.body.id)
	state.environment.processed_deaths.erase(target.id)
	state.card_effects.apply_values(plan.effects_after)
	target.vitals._hp = plan.hp; target.vitals._is_alive = true; target.vitals._balance = 0.0
	target.move_points_left = 0.0; target.has_attacked = true
	target.action_resources._main_left = 0; target.action_resources._bonus_left = 0
	context._move_rules = plan.admission.move; context._attack_rules = plan.admission.attack
	var placed: bool = state.get_board().restore_living_occupancy(target)
	var result := CommandStepResult.applied([{"kind":&"unit_revived","actor_unit_id":0,"target_unit_id":target.id,
		"corpse_id":int(plan.body.id),"cell":target.cell,"hp":float(plan.hp),"source":source.to_dict()}],[],[],null,true)
	if state.get_board().get_all_units().any(func(unit: UnitState) -> bool: return unit.combat_perks != null):
		result.combat_perk_changes[target.id] = CombatPerkGuard.record(target,target.combat_perks)
	if placed: target.vitals.hp_changed.emit(old_hp,float(plan.hp))
	var actual := ItemSimulationSnapshot.capture(state, [])
	var expected_context := ActionContext.new(null,null,null,[],plan.admission.move,plan.admission.attack)
	var valid: bool = placed and bool(sealed.call()) and context.get_state() == state and state.get_board() == plan.board and state.environment == plan.environment
	valid = valid and context.get_rng() == plan.rng and context.get_rng().to_dict() == plan.rng_before and context.simulation_counters() == plan.counters
	valid = valid and SummonAdmission.values(context) == SummonAdmission.values(expected_context) and actual.code == ItemSnapshotResult.Code.OK
	if valid: valid = actual.snapshot.to_dict() == plan.expected
	for unit: UnitState in plan.originals: valid = valid and state.get_board().get_unit_by_id(unit.id) == unit
	valid = valid and _references(state) == plan.references
	valid = valid and state.get_owners() == plan.owners and state.get_inventories() == plan.inventories and state.get_equipment_facades() == plan.equipment
	if not valid: result.status = &"FAULTED"; result.reason = &"return/checkpoint"
	return result

static func valid_draft(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event,{"kind":TYPE_STRING_NAME,"actor_unit_id":TYPE_INT,"target_unit_id":TYPE_INT,"corpse_id":TYPE_INT,"cell":TYPE_VECTOR2I,"hp":TYPE_FLOAT,"source":TYPE_DICTIONARY}): return false
	return event.kind == &"unit_revived" and event.actor_unit_id == 0 and event.target_unit_id > 0 and event.target_unit_id < ActionContext.MAX_ID and event.corpse_id > 0 and event.corpse_id < ActionContext.MAX_ID and event.cell.x >= 0 and event.cell.y >= 0 and is_finite(event.hp) and event.hp > 0.0 and event.hp <= 12.0 and event.source == DamageSource.new(&"mage",29,Vector2i(-1,-1),0,0).to_dict()

## Полный after защищает значения; этот свидетель дополнительно удерживает личности
## компонентов и вещей при синхронном сигнале HP.
static func _references(state: ItemSimulationState) -> Array:
	var result: Array = [state.abilities,state.deck,state.deck.draw_rng,state.card_effects]
	for unit: UnitState in state.get_board().get_all_units():
		result.append([unit,unit.stats,unit.vitals,unit.action_resources,unit.armor,unit.bleeding,unit.elemental,unit.control,unit.combat_perks,unit.combat_perks.definition if unit.combat_perks != null else null])
	for owner: ItemOwnerState in state.get_owners():
		result.append([owner,owner._items.duplicate(),owner._definitions.duplicate()])
		for item: ItemInstance in owner._items.values(): result.append([item,item._definition,item._effects.duplicate()])
	return result
