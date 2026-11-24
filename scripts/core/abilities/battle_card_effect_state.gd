extends RefCounted
class_name BattleCardEffectState

const MAX_ID: int = ActionContext.MAX_ID
var ordinary_attacks: Array[Dictionary] = []
var fire_imbues: Array[Dictionary] = []
var host_unit_id: int = 0
var light_step_serial: int = 0
var host_has_died: bool = false
var host_death_cell: Vector2i = Vector2i(-1, -1)
var host_death_height: int = 0
var pending_revivals: Array[int] = []

func to_dict() -> Dictionary:
	return {"schema":3,"ordinary_attacks":ordinary_attacks.duplicate(true),"fire_imbues":fire_imbues.duplicate(true),"host_unit_id":host_unit_id,"light_step_serial":light_step_serial,"host_has_died":host_has_died,"host_death_cell":host_death_cell,"host_death_height":host_death_height,"pending_revivals":pending_revivals.duplicate()}

func duplicate() -> BattleCardEffectState:
	return from_dict(to_dict())

func apply_values(value: Dictionary) -> bool:
	var checked := BattleCardEffectState.from_dict(value)
	if checked == null: return false
	ordinary_attacks.assign(checked.ordinary_attacks); fire_imbues.assign(checked.fire_imbues)
	host_unit_id = checked.host_unit_id; light_step_serial = checked.light_step_serial
	host_has_died = checked.host_has_died; host_death_cell = checked.host_death_cell
	host_death_height = checked.host_death_height; pending_revivals.assign(checked.pending_revivals)
	return true

func valid() -> bool:
	if host_unit_id < 0 or host_unit_id >= MAX_ID or light_step_serial < 0 or light_step_serial >= MAX_ID: return false
	if host_unit_id == 0 and (light_step_serial != 0 or host_has_died): return false
	if not host_has_died and (host_death_cell != Vector2i(-1, -1) or host_death_height != 0): return false
	if host_has_died and (host_death_cell.x < 0 or host_death_cell.y < 0): return false
	if host_death_height < SpatialRules.MIN_STEPS or host_death_height > SpatialRules.MAX_STEPS: return false
	var prior: int = 0
	for id: int in pending_revivals:
		if id <= prior or id >= MAX_ID: return false
		prior = id
	var seen: Dictionary = {}; var last_id: int = 0
	for entry: Dictionary in ordinary_attacks:
		if not ItemSimulationSnapshot._shape(entry,{"unit_id":TYPE_INT,"attack_id":TYPE_STRING}): return false
		if entry.unit_id <= last_id or entry.unit_id >= MAX_ID or entry.attack_id.is_empty(): return false
		last_id=entry.unit_id
	last_id=0
	for entry: Dictionary in fire_imbues:
		if not ItemSimulationSnapshot._shape(entry,{"unit_id":TYPE_INT,"source_card_id":TYPE_INT,"applied_team_serial":TYPE_INT,"expires_after_serial":TYPE_INT}): return false
		if entry.unit_id <= last_id or entry.unit_id >= MAX_ID or seen.has(entry.unit_id): return false
		if entry.source_card_id <= 0 or entry.source_card_id >= MAX_ID: return false
		if entry.applied_team_serial <= 0 or entry.applied_team_serial > MAX_ID - 2 or entry.expires_after_serial != entry.applied_team_serial + 2: return false
		seen[entry.unit_id]=true; last_id=entry.unit_id
	return true

static func from_dict(value: Variant) -> BattleCardEffectState:
	if typeof(value) != TYPE_DICTIONARY: return null
	if not ItemSimulationSnapshot._shape(value,{"schema":TYPE_INT,"ordinary_attacks":TYPE_ARRAY,"fire_imbues":TYPE_ARRAY,"host_unit_id":TYPE_INT,"light_step_serial":TYPE_INT,"host_has_died":TYPE_BOOL,"host_death_cell":TYPE_VECTOR2I,"host_death_height":TYPE_INT,"pending_revivals":TYPE_ARRAY}) or value.schema != 3: return null
	var result := BattleCardEffectState.new()
	result.host_unit_id = value.host_unit_id; result.light_step_serial = value.light_step_serial
	result.host_has_died = value.host_has_died; result.host_death_cell = value.host_death_cell
	result.host_death_height = value.host_death_height
	for id: Variant in value.pending_revivals:
		if typeof(id) != TYPE_INT: return null
		result.pending_revivals.append(id)
	for entry: Variant in value.ordinary_attacks:
		if typeof(entry) != TYPE_DICTIONARY: return null
		result.ordinary_attacks.append(entry.duplicate(true))
	for entry: Variant in value.fire_imbues:
		if typeof(entry) != TYPE_DICTIONARY: return null
		result.fire_imbues.append(entry.duplicate(true))
	return result if result.valid() else null

## План обновления срока эффекта; исполнителю остаётся применить готовое значение.
func imbue(unit_id: int, source_card_id: int, team_serial: int) -> Dictionary:
	if not valid() or unit_id <= 0 or unit_id >= MAX_ID or source_card_id <= 0 or source_card_id >= MAX_ID or team_serial <= 0 or team_serial > MAX_ID - 2: return {}
	var after := duplicate()
	var replacement: Dictionary = {"unit_id":unit_id,"source_card_id":source_card_id,
		"applied_team_serial":team_serial,"expires_after_serial":team_serial + 2}
	var found: bool = false
	for index: int in range(after.fire_imbues.size()):
		if after.fire_imbues[index].unit_id == unit_id: after.fire_imbues[index]=replacement; found=true; break
	if not found: after.fire_imbues.append(replacement)
	after.fire_imbues.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.unit_id < b.unit_id)
	return {"after":after.to_dict()}

## К границе хода передаются бойцы уходящей команды, поскольку serial у команд независимы.
func expire(team_serial: int, ending_unit_ids: Array[int]) -> Dictionary:
	if not valid() or team_serial <= 0 or team_serial >= MAX_ID: return {}
	var owners: Dictionary = {}
	for id: int in ending_unit_ids:
		if id <= 0 or id >= MAX_ID or owners.has(id): return {}
		owners[id]=true
	var after := duplicate()
	var kept: Array[Dictionary] = []
	for entry: Dictionary in after.fire_imbues:
		if owners.has(entry.unit_id) and entry.expires_after_serial <= team_serial: continue
		kept.append(entry)
	after.fire_imbues=kept
	return {"after":after.to_dict()}
