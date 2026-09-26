extends RefCounted
class_name BattleUnitView

var id: int = UnitId.NONE
var faction: Faction.Type = Faction.Type.NEUTRAL
var debug_name: String = ""
var alive: bool = false
var hp: float = 0.0
var hp_max: float = 0.0
var balance: float = 0.0
var balance_max: float = 0.0

static func capture(unit: UnitState) -> BattleUnitView:
	if unit == null: return null
	var result := BattleUnitView.new()
	result.id = unit.id
	result.faction = unit.faction
	result.debug_name = unit.debug_name
	result.alive = unit.is_alive()
	result.hp = unit.vitals.get_hp() if unit.vitals != null else 0.0
	result.hp_max = unit.get_stat(StatTypes.StatType.HP_MAX)
	result.balance = unit.vitals.get_balance() if unit.vitals != null else 0.0
	result.balance_max = ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX))
	return result
