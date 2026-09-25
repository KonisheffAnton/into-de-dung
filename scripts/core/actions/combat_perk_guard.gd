extends RefCounted
class_name CombatPerkGuard

## Малый checkpoint перков на весь каскад, без повторного снимка вещей/характеристик.
var _units: Dictionary = {}

static func capture(board: BattleBoard) -> CombatPerkGuard:
	var result := CombatPerkGuard.new()
	var enabled := false
	for unit: UnitState in board.get_all_units():
		result._units[unit.id] = record(unit, unit.combat_perks)
		enabled = enabled or unit.combat_perks != null
	return result if enabled else null

static func record(unit: UnitState, state: CombatPerksState) -> Dictionary:
	return {"unit": unit, "state": state, "definition": state.definition if state != null else null, "value": state.to_dict() if state != null else {}}

func accept(changes: Dictionary) -> void:
	for id: int in changes:
		_units[id] = changes[id].duplicate(true)

func check(board: BattleBoard) -> bool:
	for id: int in _units:
		if board.get_unit_by_id(id) != _units[id]["unit"]: return false
	for unit: UnitState in board.get_all_units():
		if not _units.has(unit.id):
			# Нынешние шаблоны призыва не выдают классовые перки новому помощнику.
			if unit.combat_perks != null: return false
			_units[unit.id] = record(unit, null)
			continue
		var expected: Dictionary = _units[unit.id]
		if unit != expected["unit"] or unit.combat_perks != expected["state"]: return false
		if unit.combat_perks != null:
			if unit.combat_perks.definition != expected["definition"] or unit.combat_perks.to_dict() != expected["value"]: return false
	return true
