extends RefCounted
class_name CheckedBoardClone

## Синхронный builder для вызывающего, который только что завершил полный capture на owned live-графе.
static func copy_board_unchecked(source: BattleBoard) -> BattleBoard:
	# Копия строится только после полного capture на принадлежащем вызывающему live-графе.
	assert(source != null)
	var board := BattleBoard.new(source.width, source.height)
	board._heights = source._heights.duplicate()
	board._height_half_steps = source._height_half_steps.duplicate()
	board._terrain = source._terrain.duplicate()
	var units := source.get_all_units()
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	for source_unit: UnitState in units:
		var unit := copy_unit_unchecked(source_unit)
		board._units[unit.id] = unit
		board._register_death_callback(unit)
	board._occupancy = source._occupancy.duplicate()
	board.board_version = source.board_version
	return board

static func copy_unit_unchecked(source: UnitState) -> UnitState:
	# Прямое копирование сохраняет семантику benchmark без промежуточного DTO юнита.
	var unit := UnitState.new()
	unit.id = source.id
	unit.faction = source.faction
	unit.cell = source.cell
	unit.height = source.height
	unit.debug_name = source.debug_name
	unit.move_points_left = source.move_points_left
	unit.has_attacked = source.has_attacked
	unit.guard_stance = source.guard_stance
	unit.stats = StatsBag.new()
	for key: int in source.stats._stats:
		var original: Stat = source.stats._stats[key]
		var stat := Stat.new(original.base_value)
		stat._next_modifier_slot = original._next_modifier_slot
		stat._modifier_slots.assign(original._modifier_slots)
		for modifier: StatModifier in original._modifiers:
			stat._modifiers.append(StatModifier.new(modifier.source_id, modifier.operation, modifier.value))
		unit.stats._stats[key] = stat
	unit.vitals = Vitals.from_dict(source.vitals.to_dict(), unit.stats)
	if source.action_resources != null: unit.action_resources = ActionResources.from_snapshot_dict(source.action_resources.to_snapshot_dict(), unit.id)
	if source.armor != null: unit.armor = ArmorState.from_dict(source.armor.to_dict())
	if source.bleeding != null: unit.bleeding = BleedingState.from_dict(source.bleeding.to_dict())
	if source.control != null: unit.control = ControlState.from_dict(source.control.to_dict())
	if source.combat_perks != null: unit.combat_perks = CombatPerksState.from_dict(source.combat_perks.to_dict())
	if source.elemental != null: unit.elemental = ElementalState.from_dict(source.elemental.to_dict())
	return unit
