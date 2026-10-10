extends RefCounted

# Это экспериментальный допуск для harness: он не создаёт board/unit/stats/modifier DTO.
# Малые DTO компонентов остаются намеренным ограничением; OK с null snapshot означает только допуск.
const MAX_BOARD_SIDE: int = 1024
const MAX_CELLS: int = 65536

static func audit(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult:
	var ids := _sorted_ids(unsupported_runtime_ids)
	if not ids.is_empty(): return BoardSnapshotResult.failure(BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "unsupported_runtime_ids", ids)
	if board == null: return _invalid("board")
	if board.get_script() != BattleBoard: return _unsupported("board/subclass")
	if typeof(board._units) != TYPE_DICTIONARY: return _invalid("board/units")
	# Повторённый preflight сохраняет приоритет subtype и runtime-компонентов.
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
	var validation_reason := _validate_board(board)
	if not validation_reason.is_empty(): return _invalid(validation_reason)
	return BoardSnapshotResult.ok(null)

static func _validate_board(board: BattleBoard) -> String:
	var w := board.width
	var h := board.height
	var cells := w * h
	if w < 0 or h < 0 or board.board_version < 0 or w > MAX_BOARD_SIDE or h > MAX_BOARD_SIDE or cells > MAX_CELLS: return "board"
	if board._heights.size() != cells or board._terrain.size() != cells or board._height_half_steps.size() != cells: return "board"
	for i in cells:
		if board._heights[i] < -2147483648 or board._heights[i] > 2147483647 or board._terrain[i] < 0 or board._terrain[i] > 3: return "board"
		if board._height_half_steps[i] < 0 or board._height_half_steps[i] > 1: return "board"
	var units_by_id: Dictionary = {}
	var occupied_ids: Dictionary = {}
	for key in board._units.keys():
		if typeof(key) != TYPE_INT or not (board._units[key] is UnitState): return "board"
		var unit := board._units[key] as UnitState
		if unit == null or unit.id != key or not board.is_in_bounds(unit.cell) or units_by_id.has(unit.id): return "board"
		if not _validate_unit(unit): return "board"
		units_by_id[unit.id] = unit
	for cell_variant in board._occupancy.keys():
		if typeof(cell_variant) != TYPE_VECTOR2I or typeof(board._occupancy[cell_variant]) != TYPE_INT: return "board"
		var cell: Vector2i = cell_variant
		var owner_id: int = board._occupancy[cell]
		if not board.is_in_bounds(cell) or not units_by_id.has(owner_id) or occupied_ids.has(owner_id): return "board"
		var owner := units_by_id[owner_id] as UnitState
		if not owner.vitals.is_alive() or owner.cell != cell: return "board"
		occupied_ids[owner_id] = true
	return _validate_status_sources(board)

static func _validate_unit(unit: UnitState) -> bool:
	if unit.id < UnitId.FIRST or int(unit.faction) < 0 or int(unit.faction) > 2 or not is_finite(unit.move_points_left) or unit.move_points_left < 0.0: return false
	if unit.vitals._stats != unit.stats: return false
	if not _validate_stats(unit.stats): return false
	var hp := unit.vitals._hp
	var balance := unit.vitals._balance
	if not is_finite(hp) or not is_finite(balance) or hp < 0.0 or balance < 0.0: return false
	if unit.action_resources != null and unit.action_resources.validate(unit.id) != &"": return false
	if unit.guard_stance and unit.action_resources == null: return false
	if unit.armor != null:
		if unit.armor.get_script() != ArmorState or unit.action_resources == null or not ArmorState.valid(unit.armor.to_dict()): return false
		if not _armor_hp_valid(hp, unit.stats): return false
	if unit.bleeding != null:
		if unit.bleeding.get_script() != BleedingState or unit.action_resources == null or unit.armor == null or not BleedingState.valid(unit.bleeding.to_dict()): return false
	if unit.control != null and unit.action_resources == null: return false
	if unit.combat_perks != null:
		if unit.action_resources == null or (unit.combat_perks.mode == CombatPerksState.Mode.COVER and unit.combat_perks.cover_target_id == unit.id): return false
	if unit.elemental != null:
		if unit.action_resources == null or unit.armor == null or unit.bleeding == null or not unit.bleeding.stacked: return false
		if unit.elemental.burning_stacks > 0 and unit.bleeding.stacks > 0: return false
	elif unit.bleeding != null and unit.bleeding.stacked: return false
	return true

static func _validate_stats(bag: StatsBag) -> bool:
	if typeof(bag._stats) != TYPE_DICTIONARY: return false
	for key in bag._stats.keys():
		if not StatTypes.is_valid_id(key) or not (bag._stats[key] is Stat): return false
		var stat := bag._stats[key] as Stat
		if stat == null or stat.get_script() != Stat or stat._modifiers.size() != stat._modifier_slots.size() or stat._next_modifier_slot < 0 or not is_finite(stat.base_value): return false
		var slots: Dictionary = {}
		var flat := 0.0
		var percent := 0.0
		var multiplier := 1.0
		for i in stat._modifiers.size():
			var modifier := stat._modifiers[i]
			var slot := stat._modifier_slots[i]
			if modifier == null or modifier.get_script() != StatModifier or not is_finite(modifier.value) or int(modifier.operation) < 0 or int(modifier.operation) > 2 or slot < 0 or slot >= stat._next_modifier_slot or slots.has(slot): return false
			slots[slot] = true
			match modifier.operation:
				StatModifier.Operation.ADD_FLAT: flat += modifier.value
				StatModifier.Operation.ADD_PERCENT: percent += modifier.value
				StatModifier.Operation.MULTIPLY: multiplier *= modifier.value
		if not is_finite((stat.base_value + flat) * (1.0 + percent) * multiplier): return false
	return true

static func _armor_hp_valid(hp: float, stats: StatsBag) -> bool:
	if hp != floorf(hp) or hp > ArmorRuntime.MAX_EXACT_HP: return false
	var maximum := _stat_value(stats, StatTypes.StatType.HP_MAX)
	return is_finite(maximum) and maximum >= 0.0 and maximum <= ArmorRuntime.MAX_EXACT_HP and maximum == floorf(maximum) and hp <= maximum

static func _stat_value(stats: StatsBag, key: StatTypes.StatType) -> float:
	if not stats._stats.has(key): return 0.0
	var stat := stats._stats[key] as Stat
	var flat := 0.0
	var percent := 0.0
	var multiplier := 1.0
	for modifier in stat._modifiers:
		match modifier.operation:
			StatModifier.Operation.ADD_FLAT: flat += modifier.value
			StatModifier.Operation.ADD_PERCENT: percent += modifier.value
			StatModifier.Operation.MULTIPLY: multiplier *= modifier.value
	return (stat.base_value + flat) * (1.0 + percent) * multiplier

static func _validate_status_sources(board: BattleBoard) -> String:
	var ids: Dictionary = {}
	var ordered_ids: Array[int] = []
	for key in board._units.keys(): ordered_ids.append(key)
	ordered_ids.sort()
	for id in ordered_ids:
		var unit := board._units[id] as UnitState
		ids[unit.id] = true
	for id in ordered_ids:
		var unit := board._units[id] as UnitState
		if unit.elemental == null: continue
		if unit.bleeding != null and unit.bleeding.ticks_left > 0 and unit.bleeding.source.get("kind") == &"attack":
			if not ids.has(unit.bleeding.source.get("instigator_unit_id")) or not ids.has(unit.bleeding.source.get("credit_unit_id")): return "unit/%d/bleeding/source" % unit.id
		if unit.elemental != null and unit.elemental.burning_stacks > 0 and unit.elemental.burning_source.get("kind") == &"attack":
			if not ids.has(unit.elemental.burning_source.get("instigator_unit_id")) or not ids.has(unit.elemental.burning_source.get("credit_unit_id")): return "unit/%d/elemental/burning_source" % unit.id
	return ""

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
