extends RefCounted
class_name BoardSnapshotValidator

## Свежая проверка допуска, а не снимок или разрешение для последующего вызова.
## Preflight задаёт приоритет ошибок; runtime-правила принадлежат самим producer.
static func audit(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult:
	var result := preflight(board, unsupported_runtime_ids)
	if result.code != BoardSnapshotResult.Code.OK: return result
	if not board.snapshot_runtime_valid(): return _invalid("board")
	var ids: Dictionary = {}
	var ordered_ids: Array[int] = []
	for id: int in board._units:
		ids[id] = true
		ordered_ids.append(id)
	ordered_ids.sort()
	for id: int in ordered_ids:
		var unit := board._units[id] as UnitState
		if unit.elemental == null: continue
		var reason := status_source_reason(id, unit.bleeding.to_dict(), unit.elemental.to_dict(), ids)
		if not reason.is_empty(): return _invalid(reason)
	return BoardSnapshotResult.ok(null)

## Внешний DTO и runtime используют одну проверку ссылок после проверки формы.
static func status_source_reason(id: int, bleeding: Dictionary, elemental: Dictionary, ids: Dictionary) -> String:
	if bleeding["ticks_left"] > 0 and bleeding["source"]["kind"] == &"attack":
		if not ids.has(bleeding["source"]["instigator_unit_id"]) or not ids.has(bleeding["source"]["credit_unit_id"]): return "unit/%d/bleeding/source" % id
	if elemental["burning_stacks"] > 0 and elemental["burning_source"]["kind"] == &"attack":
		if not ids.has(elemental["burning_source"]["instigator_unit_id"]) or not ids.has(elemental["burning_source"]["credit_unit_id"]): return "unit/%d/elemental/burning_source" % id
	return ""

static func preflight(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult:
	var ids := _sorted_ids(unsupported_runtime_ids)
	if not ids.is_empty(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unsupported_runtime_ids", ids)
	if board == null: return _invalid("board")
	if board.get_script() != BattleBoard: return _unsupported("board/subclass")
	if typeof(board._units) != TYPE_DICTIONARY: return _invalid("board/units")
	# Общий preflight сохраняет приоритет subtype и runtime-компонентов.
	for id in board._units.keys():
		if typeof(id) != TYPE_INT or not (board._units[id] is UnitState): return _invalid("board/units")
		var unit := board._units[id] as UnitState
		var path := "unit/%d" % id
		if unit == null: return _invalid(path)
		if unit.get_script() != UnitState: return _unsupported(path + "/subclass")
		if unit.ai_profile != null: return _unsupported(path + "/ai_profile")
		if unit.stats == null or unit.vitals == null: return _invalid(path + "/stats")
		if unit.stats.get_script() != StatsBag: return _unsupported(path + "/stats/subclass")
		if unit.vitals.get_script() != Vitals: return _unsupported(path + "/vitals/subclass")
		if unit.action_resources != null and unit.action_resources.get_script() != ActionResources: return _unsupported(path + "/action_resources/subclass")
		if unit.control != null:
			if unit.control.get_script() != ControlState: return _unsupported(path + "/control/subclass")
			if not ControlState.valid(unit.control.to_dict()): return _invalid(path + "/control")
		if unit.elemental != null:
			if unit.elemental.get_script() != ElementalState: return _unsupported(path + "/elemental/subclass")
			if not ElementalRules.valid_unit(unit): return _invalid(path + "/elemental")
		if unit.combat_perks != null:
			if unit.combat_perks.get_script() != CombatPerksState or (unit.combat_perks.definition != null and unit.combat_perks.definition.get_script() != CombatPerksDefinition): return _unsupported(path + "/combat_perks/subclass")
			if unit.combat_perks.to_dict().is_empty(): return _invalid(path + "/combat_perks")
		if typeof(unit.stats._stats) != TYPE_DICTIONARY: return _invalid(path + "/stats")
		for stat_key in unit.stats._stats.keys():
			if not StatTypes.is_valid_id(stat_key): return _invalid(path + "/stats")
			if not (unit.stats._stats[stat_key] is Stat): return _invalid(path + "/stat")
			var stat := unit.stats._stats[stat_key] as Stat
			if stat.get_script() != Stat: return _unsupported(path + "/stat/subclass")
			if stat._modifiers.size() != stat._modifier_slots.size(): return _invalid(path + "/stat/modifiers")
			for modifier in stat._modifiers:
				if modifier == null: return _invalid(path + "/stat/modifier")
				if modifier.get_script() != StatModifier: return _unsupported(path + "/stat/modifier/subclass")
	# Кэш проверяется после preflight, чтобы unknown subtype всегда победил stale cache.
	for id in board._units.keys():
		var unit := board._units[id] as UnitState
		for stat_key in unit.stats._stats.keys():
			var stat := unit.stats._stats[stat_key] as Stat
			if stat.snapshot_cache_is_stale(): return _invalid("unit/%d/stats/%d/cache" % [id, stat_key])
	return BoardSnapshotResult.ok(null)

static func _sorted_ids(raw: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in raw:
		if not result.has(id): result.append(id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result

static func _invalid(reason: String) -> BoardSnapshotResult:
	return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_INVALID, reason)

static func _unsupported(reason: String) -> BoardSnapshotResult:
	return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, reason, [StringName(reason)])
