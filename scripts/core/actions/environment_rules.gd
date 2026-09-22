extends RefCounted
class_name EnvironmentRules

## Слой среды не меняет старый codec геометрии доски.
static func snapshot_reason(data: Dictionary, board: Dictionary, summons: Array) -> String:
	if not CombatEnvironmentState.valid(data): return "environment/schema"
	var units: Dictionary = {}
	for unit: Dictionary in board["units"]:
		units[unit["id"]] = unit
		if not unit.has("armor"): return "environment/armor_required"
	var summoned: Dictionary = {}
	for record: Dictionary in summons: summoned[record["unit_id"]] = true
	for record: Dictionary in data["fires"]:
		if not _safe_cell(record["cell"], board): return "environment/fire_cell"
	for id: int in data["processed_deaths"]:
		if not units.has(id) or units[id]["vitals"]["is_alive"]: return "environment/death_reference"
	for record: Dictionary in data["corpses"]:
		var id: int = record["source_unit_id"]
		if not units.has(id) or summoned.has(id) or not _safe_cell(record["cell"], board): return "environment/corpse_reference"
		var unit: Dictionary = units[id]
		if unit["vitals"]["is_alive"] or record["cell"] != Vector2i(unit["cell_x"], unit["cell_y"]) or record["faction"] != unit["faction"]: return "environment/corpse_reference"
	return ""

static func _safe_cell(cell: Vector2i, board: Dictionary) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= board["width"] or cell.y >= board["height"]: return false
	return board["terrain"][cell.y * board["width"] + cell.x] == TerrainType.Type.FLOOR

static func consequences(event: Dictionary, context: ActionContext) -> Array[Command]:
	var result: Array[Command] = []
	var state := context.get_state()
	if state.environment == null: return result
	if event["kind"] == &"died":
		result.append(EnvironmentCommand.for_death(event, context))
	elif event["kind"] == &"moved":
		var cells: Array[Vector2i] = []
		if event.has("transit_path"):
			cells.assign(event["transit_path"].slice(1))
		else: cells.append(event["to_cell"])
		for cell: Vector2i in cells:
			if not state.environment.fire_at(cell).is_empty(): result.append(EnvironmentCommand.for_entry(event["target_unit_id"], cell, context))
	return result

static func valid_draft(event: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "corpse": TYPE_DICTIONARY}): return false
	var corpse: Dictionary = event["corpse"]
	if not ItemSimulationSnapshot._shape(corpse, {"id": TYPE_INT, "cell": TYPE_VECTOR2I, "source_unit_id": TYPE_INT, "faction": TYPE_INT, "creature_kind": TYPE_STRING}): return false
	return event["kind"] == &"corpse_created" and event["actor_unit_id"] == 0 and event["target_unit_id"] == corpse["source_unit_id"] and corpse["id"] > 0 and corpse["id"] < ActionContext.MAX_ID and corpse["source_unit_id"] > 0 and corpse["source_unit_id"] < ActionContext.MAX_ID and corpse["faction"] in Faction.Type.values() and corpse["creature_kind"] == "humanoid"
