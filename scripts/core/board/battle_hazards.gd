extends RefCounted
class_name BattleHazards

## Авторские ловушки: runtime хранит только значения и не использует RNG.
const SPIKE_DAMAGE: int = 1000000
const MAX_RECORDS: int = 1024

static func empty() -> Dictionary:
	return {"schema_version": 1, "next_id": 1, "traps": [], "acid": []}

static func valid(value: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(value, {"schema_version": TYPE_INT, "next_id": TYPE_INT, "traps": TYPE_ARRAY, "acid": TYPE_ARRAY}): return false
	if value.schema_version != 1 or value.next_id < 1 or value.next_id >= ActionContext.MAX_ID or value.traps.size() > MAX_RECORDS or value.acid.size() > MAX_RECORDS: return false
	var ids: Dictionary = {}
	var locations: Dictionary = {}
	for raw: Variant in value.traps:
		if not ItemSimulationSnapshot._shape(raw, {"id": TYPE_INT, "cell": TYPE_VECTOR2I, "kind": TYPE_STRING, "direction": TYPE_VECTOR2I, "occupant_id": TYPE_INT, "armed_team": TYPE_INT}): return false
		if raw.id < 1 or raw.id >= value.next_id or ids.has(raw.id) or raw.kind not in ["floor", "wall"]: return false
		if raw.occupant_id < 0 or raw.occupant_id >= ActionContext.MAX_ID or raw.armed_team not in [-1, Faction.Type.PLAYER, Faction.Type.ENEMY]: return false
		if raw.kind == "floor" and raw.direction != Vector2i.ZERO: return false
		if raw.kind == "wall" and (absi(raw.direction.x) + absi(raw.direction.y) != 1 or raw.armed_team != -1): return false
		var location: Array = [raw.cell, raw.kind, raw.direction]
		if locations.has(location): return false
		locations[location] = true
		ids[raw.id] = true
	var cells: Dictionary = {}
	for cell: Variant in value.acid:
		if typeof(cell) != TYPE_VECTOR2I or cells.has(cell): return false
		cells[cell] = true
	return true

static func canonical(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	if not valid(result): return result
	result.traps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	result.acid.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func add_trap(value: Dictionary, cell: Vector2i, kind: String = "floor", direction: Vector2i = Vector2i.ZERO) -> bool:
	if not valid(value) or value.traps.size() >= MAX_RECORDS or value.next_id >= ActionContext.MAX_ID - 1: return false
	var next := value.duplicate(true)
	next.traps.append({"id": next.next_id, "cell": cell, "kind": kind, "direction": direction, "occupant_id": 0, "armed_team": -1})
	next.next_id += 1
	if not valid(next): return false
	value.merge(next, true)
	return true

static func at(value: Dictionary, cell: Vector2i, kind: String = "floor", direction: Vector2i = Vector2i.ZERO) -> Dictionary:
	for trap: Dictionary in value.get("traps", []):
		if trap.cell == cell and trap.kind == kind and trap.direction == direction: return trap.duplicate(true)
	return {}

static func snapshot_reason(value: Dictionary, board: Dictionary) -> String:
	var units: Dictionary = {}
	for unit: Dictionary in board.units: units[unit.id] = unit
	for cell: Vector2i in value.acid:
		if not EnvironmentRules._safe_cell(cell, board): return "environment/acid_cell"
	for trap: Dictionary in value.traps:
		if not EnvironmentRules._safe_cell(trap.cell, board): return "environment/trap_cell"
		if trap.occupant_id != 0 and not units.has(trap.occupant_id): return "environment/trap_occupant"
		if trap.kind == "wall":
			var wall: Vector2i = trap.cell + trap.direction
			if wall.x < 0 or wall.y < 0 or wall.x >= board.width or wall.y >= board.height or board.terrain[wall.y * board.width + wall.x] != TerrainType.Type.WALL: return "environment/trap_wall"
	return ""

static func remove_support(value: Dictionary, cell: Vector2i) -> Dictionary:
	var result := value.duplicate(true)
	result.acid.erase(cell)
	result.traps = result.traps.filter(func(t: Dictionary) -> bool: return t.cell != cell)
	return result

static func valid_event(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "trap_id": TYPE_INT, "cell": TYPE_VECTOR2I, "trap_kind": TYPE_STRING, "direction": TYPE_VECTOR2I}): return false
	return event.kind in [&"trap_armed", &"trap_fired"] and event.actor_unit_id == 0 and event.target_unit_id >= 0 and event.target_unit_id < ActionContext.MAX_ID and event.trap_id > 0 and event.trap_id < ActionContext.MAX_ID and event.trap_kind in ["floor", "wall"] and ((event.trap_kind == "floor" and event.direction == Vector2i.ZERO) or (event.trap_kind == "wall" and absi(event.direction.x) + absi(event.direction.y) == 1))
