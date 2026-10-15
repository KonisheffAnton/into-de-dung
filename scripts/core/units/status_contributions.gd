extends RefCounted
class_name StatusContributions

const MAX_RECORDS: int = 4096

static func intelligence(unit: UnitState) -> float:
	if unit == null or unit.stats == null or not unit.stats.has_stat(StatTypes.StatType.INTELLECT): return 10.0
	var copied := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict())
	return copied.get_value(StatTypes.StatType.INTELLECT) if copied != null else NAN

static func damage_source(records: Array, cell: Vector2i) -> DamageSource:
	var source := credited_source(records)
	if source.is_empty(): return null
	return DamageSource.new(&"status_snapshot", 0, cell, source.instigator_unit_id, source.credit_unit_id)

static func make(source: Dictionary, intelligence: float = 10.0) -> Dictionary:
	if not _valid_effect_source(source) or not is_finite(intelligence):
		return {}
	var intelligence_fraction := ArmorFraction.from_decimal(maxf(0.0, intelligence))
	if not intelligence_fraction.valid:
		return {}
	var scaled_intelligence := intelligence_fraction.multiply(ArmorFraction.make(3))
	if not scaled_intelligence.valid:
		return {}
	var numerator := ArmorFraction.make(70).add(scaled_intelligence)
	if not numerator.valid:
		return {}
	var contribution := numerator.multiply(ArmorFraction.make(1, 100))
	if not contribution.valid or contribution.numerator <= 0:
		return {}
	return {"source": source.duplicate(true), "numerator": contribution.numerator, "denominator": contribution.denominator}

static func valid(records: Variant, stacks: int) -> bool:
	if typeof(records) != TYPE_ARRAY or stacks < 0:
		return false
	var values: Array = records
	if values.size() > MAX_RECORDS or values.size() != stacks:
		return false
	for record_value: Variant in values:
		if typeof(record_value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_value
		if record.size() != 3 or not record.has("source") or not record.has("numerator") or not record.has("denominator"):
			return false
		if typeof(record["source"]) != TYPE_DICTIONARY or not _valid_effect_source(record["source"]):
			return false
		if typeof(record["numerator"]) != TYPE_INT or typeof(record["denominator"]) != TYPE_INT:
			return false
		var numerator: int = record["numerator"]
		var denominator: int = record["denominator"]
		if numerator <= 0 or denominator <= 0:
			return false
		var reduced := ArmorFraction.make(numerator, denominator)
		if not reduced.valid or reduced.numerator != numerator or reduced.denominator != denominator:
			return false
	return true

static func total(records: Array) -> ArmorFraction:
	if not valid(records, records.size()):
		return ArmorFraction.make(1, 0)
	var result := ArmorFraction.make(0)
	for record: Dictionary in records:
		var contribution := ArmorFraction.make(record["numerator"], record["denominator"])
		result = result.add(contribution)
		if not result.valid:
			return result
	return result

static func credited_source(records: Array) -> Dictionary:
	if not valid(records, records.size()):
		return {}
	var totals: Dictionary = {}
	var representatives: Dictionary = {}
	var author_order: Array[String] = []
	for record: Dictionary in records:
		var source: Dictionary = record["source"]
		var key := _author_key(source)
		var current: ArmorFraction = totals.get(key, ArmorFraction.make(0))
		var contribution := ArmorFraction.make(record["numerator"], record["denominator"])
		var combined := current.add(contribution)
		if not combined.valid:
			return {}
		totals[key] = combined
		if not representatives.has(key):
			representatives[key] = source.duplicate(true)
			author_order.append(key)
	var winner: String = ""
	var winning_total: ArmorFraction = null
	for key: String in author_order:
		var candidate: ArmorFraction = totals[key]
		if winning_total == null or _compare(candidate, winning_total) > 0:
			winner = key
			winning_total = candidate
	return representatives[winner].duplicate(true) if not winner.is_empty() else {}

static func _author_key(source: Dictionary) -> String:
	match source["kind"]:
		&"attack": return "attack:%d" % int(source["credit_unit_id"])
		&"mage": return "mage"
		&"cell": return "cell:%d" % int(source["source_instance_id"])
		_: return ""

static func _valid_effect_source(source: Dictionary) -> bool:
	# Валидация загружается при вызове, чтобы state и contribution-код могли проверять друг друга без циклического импорта.
	var validator_script: Script = load("res://scripts/core/units/elemental_state.gd")
	var validator := Callable(validator_script, "valid_effect_source")
	return validator.is_valid() and bool(validator.call(source))

static func _compare(left: ArmorFraction, right: ArmorFraction) -> int:
	var left_numerator := left.numerator
	var left_denominator := left.denominator
	var right_numerator := right.numerator
	var right_denominator := right.denominator
	var inverted := false
	while true:
		var left_quotient := left_numerator / left_denominator
		var right_quotient := right_numerator / right_denominator
		if left_quotient != right_quotient:
			var comparison := -1 if left_quotient < right_quotient else 1
			return -comparison if inverted else comparison
		var left_remainder := left_numerator % left_denominator
		var right_remainder := right_numerator % right_denominator
		if left_remainder == 0 or right_remainder == 0:
			if left_remainder == 0 and right_remainder == 0:
				return 0
			var comparison := -1 if left_remainder == 0 else 1
			return -comparison if inverted else comparison
		left_numerator = left_denominator
		left_denominator = left_remainder
		right_numerator = right_denominator
		right_denominator = right_remainder
		inverted = not inverted
	return 0
