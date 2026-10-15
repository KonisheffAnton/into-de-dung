extends RefCounted
class_name CombatAmount

## Целые legacy-значения сохраняют свой тип; V1 хранит дробные запасы в float64.
## Округление разрешено только при показе, не при переносе между DTO и runtime.
static func valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= ArmorRuntime.MAX_EXACT_HP

static func shape(value: Variant, fields: Dictionary, amounts: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var expected := fields.duplicate()
	for field: String in amounts:
		if not value.has(field) or not valid(value[field]): return false
		expected[field] = typeof(value[field])
	return ItemSimulationSnapshot._shape(value, expected)
