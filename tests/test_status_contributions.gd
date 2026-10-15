extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL STATUS CONTRIBUTIONS: " + label)

func _attack_source(credit_id: int, cell: Vector2i) -> Dictionary:
	return DamageSource.new(&"attack", 0, cell, credit_id, credit_id).to_dict()

func _mage_source(source_id: int) -> Dictionary:
	return DamageSource.new(&"mage", source_id, Vector2i(-1, -1), 0, 0).to_dict()

func _run() -> void:
	_test_make_and_total()
	_test_credit()
	_test_validation()
	_test_state_codecs()
	print("STATUS CONTRIBUTIONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_make_and_total() -> void:
	var first_source := _attack_source(11, Vector2i(1, 2))
	var second_source := _attack_source(12, Vector2i(3, 4))
	var first := StatusContributions.make(first_source, 10.0)
	var second := StatusContributions.make(second_source, 20.0)
	_check(first == {"source": first_source, "numerator": 1, "denominator": 1}, "neutral intelligence produces exact unit coefficient")
	var records: Array[Dictionary] = [first, second]
	var total := StatusContributions.total(records)
	_check(total.valid and total.numerator == 23 and total.denominator == 10, "I10 and I20 sum exactly to 2.3")
	var clamped := StatusContributions.make(first_source, -5.0)
	_check(clamped.numerator == 7 and clamped.denominator == 10 and StatusContributions.make(first_source, 0.0) == clamped, "negative and zero intelligence clamp to zero")
	var fractional := StatusContributions.make(first_source, 10.5)
	_check(fractional.numerator == 203 and fractional.denominator == 200, "fractional intelligence remains rational")

func _test_credit() -> void:
	var source_a := _attack_source(11, Vector2i(1, 1))
	var source_a_later := _attack_source(11, Vector2i(8, 8))
	var source_b := _attack_source(12, Vector2i(2, 2))
	var same_author: Array[Dictionary] = [StatusContributions.make(source_a, 10.0), StatusContributions.make(source_a_later, 20.0)]
	var selected := StatusContributions.credited_source(same_author)
	_check(selected == source_a, "credit groups attack stacks by credit unit and returns earliest source")
	selected["origin_cell"] = Vector2i(9, 9)
	_check(same_author[0]["source"]["origin_cell"] == Vector2i(1, 1), "credited source is a detached copy")
	var accumulated: Array[Dictionary] = [StatusContributions.make(source_a, 10.0), StatusContributions.make(source_a_later, 10.0), StatusContributions.make(source_b, 20.0)]
	_check(StatusContributions.credited_source(accumulated) == source_a, "same-author contributions accumulate before credit selection")
	var tied: Array[Dictionary] = [StatusContributions.make(source_a, 10.0), StatusContributions.make(source_b, 10.0)]
	_check(StatusContributions.credited_source(tied) == source_a, "credit ties choose earliest active record")
	var mage_records: Array[Dictionary] = [StatusContributions.make(_mage_source(3), 10.0), StatusContributions.make(_mage_source(18), 10.0)]
	_check(StatusContributions.credited_source(mage_records) == _mage_source(3), "all external mage sources share one author")
	var cell_a := {"kind": &"cell", "source_instance_id": 4, "origin_cell": Vector2i(1, 1), "instigator_unit_id": 0, "credit_unit_id": 0}
	var cell_b := {"kind": &"cell", "source_instance_id": 5, "origin_cell": Vector2i(1, 1), "instigator_unit_id": 0, "credit_unit_id": 0}
	var cell_records: Array[Dictionary] = [StatusContributions.make(cell_a), StatusContributions.make(cell_b)]
	_check(StatusContributions.credited_source(cell_records) == cell_a, "different cell source ids remain separate authors and tie by order")

func _test_validation() -> void:
	var source := _attack_source(11, Vector2i.ZERO)
	var record := StatusContributions.make(source)
	_check(StatusContributions.valid([record], 1), "single exact contribution validates")
	_check(not StatusContributions.valid([record], 0) and StatusContributions.valid([], 0), "record count matches active stacks")
	var nonreduced := record.duplicate(true)
	nonreduced["numerator"] = 2
	nonreduced["denominator"] = 2
	_check(not StatusContributions.valid([nonreduced], 1), "non-reduced contribution rejects")
	var negative := record.duplicate(true)
	negative["numerator"] = -1
	_check(not StatusContributions.valid([negative], 1), "non-positive contribution rejects")
	var bad_source := record.duplicate(true)
	bad_source["source"]["credit_unit_id"] = 0
	_check(not StatusContributions.valid([bad_source], 1), "invalid effect source rejects")
	var extra_key := record.duplicate(true)
	extra_key["live_unit"] = UnitState.new()
	_check(not StatusContributions.valid([extra_key], 1), "extra live object reference rejects")
	_check(StatusContributions.make(source, NAN).is_empty() and StatusContributions.make(source, INF).is_empty(), "non-finite intelligence rejects")
	var overflow := ArmorFraction.make(9223372036854775807).add(ArmorFraction.make(1))
	_check(not overflow.valid, "ArmorFraction overflow is reported")
	var many: Array[Dictionary] = []
	for index: int in StatusContributions.MAX_RECORDS:
		many.append(record)
	_check(StatusContributions.valid(many, StatusContributions.MAX_RECORDS), "maximum contribution count validates")
	many.append(record)
	_check(not StatusContributions.valid(many, many.size()) and not StatusContributions.total(many).valid, "more than 4096 records refuses")
	var invalid_total := StatusContributions.total([negative])
	_check(not invalid_total.valid, "total rejects invalid input")

func _test_state_codecs() -> void:
	var legacy_bleeding := BleedingState.new()
	var legacy_bleeding_data := legacy_bleeding.to_dict()
	_check(not legacy_bleeding_data.has("contributions") and BleedingState.valid(legacy_bleeding_data), "legacy bleeding DTO remains unchanged")
	var legacy_elemental := ElementalState.new()
	var legacy_elemental_data := legacy_elemental.to_dict()
	_check(not legacy_elemental_data.has("burning_contributions") and ElementalState.valid(legacy_elemental_data), "legacy elemental DTO remains unchanged")
	var first_source := _attack_source(11, Vector2i(1, 1))
	var second_source := _attack_source(12, Vector2i(2, 2))
	var records: Array[Dictionary] = [StatusContributions.make(first_source, 10.0), StatusContributions.make(second_source, 20.0)]
	var bleeding := BleedingState.new()
	bleeding.stacked = true
	bleeding.stacks = 2
	bleeding.ticks_left = BleedingState.STACK_DURATION
	bleeding.source = first_source.duplicate(true)
	bleeding.hit_id = "authored-hit"
	bleeding.authored = true
	bleeding.contributions.assign(records.duplicate(true))
	var bleeding_data := bleeding.to_dict()
	_check(BleedingState.valid(bleeding_data) and BleedingState.from_dict(bleeding_data).to_dict() == bleeding_data, "authored bleeding contributions roundtrip")
	var bleeding_copy := BleedingState.from_dict(bleeding_data)
	bleeding_copy.contributions[0]["source"]["origin_cell"] = Vector2i(9, 9)
	_check(bleeding_data["contributions"][0]["source"]["origin_cell"] == Vector2i(1, 1), "bleeding contribution restore is detached")
	var mismatch := bleeding_data.duplicate(true)
	mismatch["stacks"] = 1
	_check(not BleedingState.valid(mismatch), "bleeding authored count must match stacks")
	var elemental := ElementalState.new()
	elemental.burning_stacks = 2
	elemental.burning_ticks = 2
	elemental.burning_source = first_source.duplicate(true)
	elemental.authored = true
	elemental.burning_contributions.assign(records.duplicate(true))
	var elemental_data := elemental.to_dict()
	_check(ElementalState.valid(elemental_data) and ElementalState.from_dict(elemental_data).to_dict() == elemental_data, "authored burning contributions roundtrip")
	var elemental_copy := ElementalState.from_dict(elemental_data)
	elemental_copy.burning_contributions[0]["source"]["origin_cell"] = Vector2i(9, 9)
	_check(elemental_data["burning_contributions"][0]["source"]["origin_cell"] == Vector2i(1, 1), "burning contribution restore is detached")
	elemental_data["burning_contributions"].pop_back()
	_check(not ElementalState.valid(elemental_data), "burning contribution count must match stacks")
	var cleared := ElementalState.new()
	cleared.authored = true
	cleared.burning_contributions.clear()
	_check(ElementalState.valid(cleared.to_dict()), "authored cleared burning state serializes an empty record list")
