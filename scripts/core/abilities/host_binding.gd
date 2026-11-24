extends RefCounted
class_name HostBinding

## Привязка выводится из авторитетных юнита/останков. Дух не создаёт UnitState,
## поэтому не занимает клетку, не принимает урон и не продлевает жизнь отряда.
static func anchor(state: ItemSimulationState) -> Dictionary:
	if state == null or state.card_effects == null or state.card_effects.host_unit_id == 0: return {}
	var host := state.get_board().get_unit_by_id(state.card_effects.host_unit_id)
	if host == null: return {}
	if host.is_alive():
		return {"unit_id":host.id,"cell":host.cell,"height":state.get_board().get_height_steps(host.cell),"kind":"living"}
	var body := corpse(state, host.id)
	if not body.is_empty():
		return {"unit_id":host.id,"cell":body.cell,"height":state.get_board().get_height_steps(body.cell),"kind":String(body.remains)}
	var effects := state.card_effects
	return {"unit_id":host.id,"cell":effects.host_death_cell if effects.host_has_died else host.cell,
		"height":effects.host_death_height if effects.host_has_died else state.get_board().get_height_steps(host.cell),"kind":"spirit"}

static func corpse(state: ItemSimulationState, unit_id: int) -> Dictionary:
	if state == null or state.environment == null: return {}
	for body: Dictionary in state.environment.corpses:
		if body.source_unit_id == unit_id: return body.duplicate(true)
	return {}

static func return_cell_valid(state: ItemSimulationState, cell: Vector2i) -> bool:
	var point := anchor(state)
	if point.is_empty(): return false
	var board := state.get_board()
	var delta: Vector2i = cell - point.cell
	if absi(delta.x) + absi(delta.y) > 1 or not board.is_in_bounds(cell): return false
	if board.get_terrain(cell) != TerrainType.Type.FLOOR or board.is_occupied(cell): return false
	if board.get_height_steps(cell) != int(point.height): return false
	return state.environment != null and state.environment.fire_at(cell).is_empty()

static func party_dead(state: ItemSimulationState) -> bool:
	if state == null or state.card_effects == null or state.card_effects.host_unit_id == 0: return false
	for unit: UnitState in state.get_board().get_all_units():
		if unit.faction == Faction.Type.PLAYER and unit.is_alive() and not state.is_summon(unit.id): return false
	return true

## Вызывается по подтверждённому событию смерти, одинаково для live и preview.
static func after_death(value: Dictionary, event: Dictionary, board: BattleBoard) -> Dictionary:
	var result := value.duplicate(true)
	var id: int = event.target_unit_id
	result.fire_imbues = result.fire_imbues.filter(func(entry: Dictionary) -> bool: return entry.unit_id != id)
	result.pending_revivals.erase(id)
	if id == result.host_unit_id:
		var unit := board.get_unit_by_id(id)
		result.host_has_died = true
		result.host_death_cell = unit.cell
		result.host_death_height = board.get_height_steps(unit.cell)
		var origin: Vector2i = event.source.origin_cell
		if event.source.kind == &"fall" and board.is_in_bounds(origin): result.host_death_cell = origin
	return result

static func after_raise(value: Dictionary, body: Dictionary, raised_id: int, height: int) -> Dictionary:
	var result := value.duplicate(true)
	result.fire_imbues = result.fire_imbues.filter(func(entry: Dictionary) -> bool: return entry.unit_id != body.source_unit_id)
	if result.host_unit_id == int(body.source_unit_id):
		result.host_unit_id = raised_id; result.host_has_died = true
		result.host_death_cell = body.cell; result.host_death_height = height
	return result
