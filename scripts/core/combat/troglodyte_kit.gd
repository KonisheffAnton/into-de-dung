extends RefCounted
class_name TroglodyteKit

const ID: StringName = &"tamed_troglodyte"
const REDUCTION: int = 2

static func owns(unit: UnitState) -> bool:
	return unit != null and unit.archetype_id == ID

## Один запас на всё прямое попадание; компоненты и их порядок не размножают защиту.
static func mitigate(raw: Array[Dictionary]) -> Dictionary:
	var remaining := ArmorFraction.make(REDUCTION)
	var result: Array[Dictionary] = []
	for component: Dictionary in raw:
		var amount := ArmorFraction.make(component.numerator, component.denominator)
		if not amount.valid or amount.numerator < 0: return {"reason": &"troglodyte/invalid_damage"}
		var difference := amount.add(ArmorFraction.make(-remaining.numerator, remaining.denominator))
		if not difference.valid: return {"reason": &"troglodyte/overflow"}
		if difference.numerator < 0:
			remaining = ArmorFraction.make(-difference.numerator, difference.denominator)
			amount = ArmorFraction.make(0)
		else:
			amount = difference
			remaining = ArmorFraction.make(0)
		var row := component.duplicate(true)
		row.numerator = amount.numerator; row.denominator = amount.denominator
		result.append(row)
	return {"reason": &"", "raw": result}
