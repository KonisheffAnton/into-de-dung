extends RefCounted
class_name MeleeThreat

static func has_sneak(unit: UnitState) -> bool:
	return unit != null and unit.combat_perks != null and unit.combat_perks.definition.sneak_attack

static func has_tank(unit: UnitState) -> bool:
	return unit != null and unit.combat_perks != null and unit.combat_perks.definition.tank_reactions

static func has_counterattack(unit: UnitState) -> bool:
	return unit != null and unit.combat_perks != null and unit.combat_perks.definition.counterattack

static func has_reactions(unit: UnitState) -> bool:
	return has_tank(unit) or has_counterattack(unit)

static func reaches(board: BattleBoard, unit: UnitState, cell: Vector2i) -> bool:
	var reach := ActionHpExecutor._stat_value(unit, StatTypes.StatType.ATTACK_RANGE)
	return AttackReachCheck.inspect_spatial_cells(board, unit.cell, unit.faction, cell, reach) == &""

static func threatens(context: ActionContext, unit: UnitState, target: UnitState) -> bool:
	if unit == null or target == null or not unit.is_alive() or not target.is_alive() or not unit.is_hostile_to(target): return false
	if ControlRules.action_reason(unit) != &"" or context.get_state().is_summon_pending(unit.id): return false
	var rules := context.get_attack_rules()
	if rules == null or not rules.allows(unit.id, target.id): return false
	var board := context.get_state().get_board()
	return board.occupant_at(unit.cell) == unit and board.occupant_at(target.cell) == target and reaches(board, unit, target.cell)

static func participants(context: ActionContext, target: UnitState) -> Array[int]:
	var result: Array[int] = []
	var board := context.get_state().get_board()
	for unit: UnitState in board.get_all_units():
		if not threatens(context, unit, target): continue
		# Скрытая атака требует соседства по стороне, даже если оружие угрозы дальнобойное.
		if AttackReachCheck.inspect_spatial_cells(board, unit.cell, unit.faction, target.cell, 1.0) == &"":
			result.append(unit.id)
	result.sort()
	return result

static func reaction_ready(context: ActionContext, unit: UnitState, mode: int) -> bool:
	var owned: bool = has_counterattack(unit) if mode == CombatPerksState.Mode.COUNTERATTACK else has_tank(unit)
	return owned and unit.is_alive() and unit.guard_stance and unit.combat_perks.mode == mode and unit.combat_perks.reaction_left == 1 and ControlRules.action_reason(unit) == &"" and not context.get_state().is_summon_pending(unit.id)

static func cover_eligible(context: ActionContext, tank: UnitState, ally: UnitState) -> bool:
	if tank == null or ally == null or tank == ally or not tank.is_alive() or not ally.is_alive() or not tank.is_friendly_to(ally): return false
	var board := context.get_state().get_board()
	return board.occupant_at(tank.cell) == tank and board.occupant_at(ally.cell) == ally and absi(tank.cell.x - ally.cell.x) + absi(tank.cell.y - ally.cell.y) == 1 and reaches(board, tank, ally.cell)

static func cover_for(context: ActionContext, target: UnitState) -> UnitState:
	var result: UnitState = null
	for unit: UnitState in context.get_state().get_board().get_all_units():
		if reaction_ready(context, unit, CombatPerksState.Mode.COVER) and unit.combat_perks.cover_target_id == target.id and cover_eligible(context, unit, target):
			if result == null or unit.id < result.id: result = unit
	return result

static func departure(context: ActionContext, mover: UnitState, endpoint: Vector2i) -> UnitState:
	var result: UnitState = null
	for unit: UnitState in context.get_state().get_board().get_all_units():
		if reaction_ready(context, unit, CombatPerksState.Mode.OPPORTUNIST) and threatens(context, unit, mover) and not reaches(context.get_state().get_board(), unit, endpoint):
			if result == null or unit.id < result.id: result = unit
	return result
