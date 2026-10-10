extends SceneTree

var passed: int = 0
var failed: int = 0
var changed_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_bleeding_codecs()
	_test_elemental_codec()
	print("STATUS STATE MODEL RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_bleeding_codecs() -> void:
	var unstacked := BleedingState.new()
	unstacked.ticks_left = BleedingState.MAX_TICKS
	unstacked.hit_id = "active-unstacked"
	unstacked.source = _source(&"attack")
	var unstacked_dto: Dictionary = unstacked.to_dict()
	_check(unstacked_dto["schema_version"] == 4 and unstacked_dto["stacked"] == false and unstacked_dto["stacks"] == 0, "unstacked duration uses current schema with explicit stack state")
	_check(BleedingState.valid(unstacked_dto) and BleedingState.from_dict(unstacked_dto).to_dict() == unstacked_dto, "unstacked current state roundtrip")
	_check(BleedingState.from_dict(unstacked_dto).ticks_left == BleedingState.MAX_TICKS, "unstacked int64 duration boundary")
	var old_unstacked := unstacked_dto.duplicate(true); old_unstacked.schema_version = 2
	old_unstacked.erase("stacked"); old_unstacked.erase("stacks")
	_check(not BleedingState.valid(old_unstacked), "old unstacked schema is refused")
	unstacked.stacks = 1
	_check(not BleedingState.valid(unstacked.to_dict()), "unstacked state cannot hide a nonzero stack")

	var stacked := BleedingState.new()
	stacked.stacked = true
	stacked.stacks = BleedingState.MAX_STACKS
	stacked.ticks_left = BleedingState.STACK_DURATION
	stacked.hit_id = "hit/new"
	stacked.source = _source(&"cell")
	var dto: Dictionary = stacked.to_dict()
	_check(dto["schema_version"] == 4 and BleedingState.valid(dto), "stacked cell source and max stacks accepted")
	var decoded := BleedingState.from_dict(dto)
	_check(decoded != null and decoded.stacked and decoded.stacks == BleedingState.MAX_STACKS and decoded.to_dict() == dto, "new bleeding roundtrip")
	decoded.source["origin_cell"] = Vector2i(90, 90)
	_check(stacked.source["origin_cell"] == Vector2i(4, 5) and dto["source"]["origin_cell"] == Vector2i(4, 5), "bleeding source copies are detached")
	var empty := BleedingState.new()
	empty.stacked = true
	var empty_dto: Dictionary = empty.to_dict()
	_check(empty_dto["schema_version"] == 4 and empty_dto["stacked"] and empty_dto["stacks"] == 0 and BleedingState.valid(empty_dto), "empty stacked state uses current schema")
	var bad: Dictionary = dto.duplicate(true)
	bad["ticks_left"] = BleedingState.STACK_DURATION + 1
	_check(not BleedingState.valid(bad), "stacked duration has fixed upper boundary")
	bad = dto.duplicate(true)
	bad["stacks"] = 0
	_check(not BleedingState.valid(bad), "active stack needs a positive count")
	bad = dto.duplicate(true)
	bad["source"]["extra"] = true
	_check(not BleedingState.valid(bad), "stacked source rejects uncontracted fields")
	bad = dto.duplicate(true)
	bad["stacks"] = 1.0
	_check(not BleedingState.valid(bad), "stack count rejects float")
	bad = dto.duplicate(true)
	bad["hit_id"] = ""
	_check(not BleedingState.valid(bad), "active status needs hit id")
	bad = empty_dto.duplicate(true)
	bad["ticks_left"] = 1
	_check(not BleedingState.valid(bad), "empty source cannot describe active stack")
	bad = empty_dto.duplicate(true)
	bad["schema_version"] = 5
	_check(not BleedingState.valid(bad), "unknown bleeding schema rejected")
	var attack_state := stacked.to_dict()
	attack_state["source"] = _source(&"attack")
	_check(BleedingState.valid(attack_state), "stacked attack source accepted")
	attack_state["source"]["credit_unit_id"] = ElementalState.MAX_ID
	_check(not BleedingState.valid(attack_state), "unit id int64 maximum is excluded")

func _test_elemental_codec() -> void:
	var state := ElementalState.new()
	state.burning_stacks = ElementalState.MAX_VALUE
	state.burning_ticks = ElementalState.MAX_VALUE
	state.burning_source = _source(&"attack")
	state.freeze_immune = true
	var dto: Dictionary = state.to_dict()
	_check(ElementalState.valid(dto), "elemental int64 maxima and attack source accepted")
	state.changed.connect(_on_changed)
	var restored := ElementalState.from_dict(dto)
	_check(restored != null and restored.to_dict() == dto and changed_count == 0, "elemental roundtrip without runtime signal")
	restored.burning_source["origin_cell"] = Vector2i(-1, -1)
	_check(state.burning_source["origin_cell"] == Vector2i(4, 5) and dto["burning_source"]["origin_cell"] == Vector2i(4, 5), "elemental source copies are detached")
	var cell_dto: Dictionary = state.to_dict()
	cell_dto["burning_source"] = _source(&"cell")
	_check(ElementalState.valid(cell_dto), "cell source accepted")
	var clear := ElementalState.new().to_dict()
	_check(ElementalState.valid(clear), "empty statuses roundtrip shape")
	var bad: Dictionary = dto.duplicate(true)
	bad["wet_turns"] = 1
	_check(not ElementalState.valid(bad), "burning conflicts with wet state")
	bad = dto.duplicate(true)
	bad["frozen_turns"] = 1
	_check(not ElementalState.valid(bad), "burning conflicts with frozen state")
	bad = clear.duplicate(true)
	bad["wet_turns"] = 4
	_check(not ElementalState.valid(bad), "wet duration upper bound")
	bad = clear.duplicate(true)
	bad["burning_stacks"] = 1
	_check(not ElementalState.valid(bad), "burning counters must become active together")
	bad = dto.duplicate(true)
	bad["burning_source"]["kind"] = "attack"
	_check(not ElementalState.valid(bad), "source kind must be StringName")
	bad = dto.duplicate(true)
	bad["burning_source"]["source_instance_id"] = 0.0
	_check(not ElementalState.valid(bad), "source id must be integer")
	bad = clear.duplicate(true)
	bad.erase("freeze_immune")
	_check(not ElementalState.valid(bad), "required elemental property cannot be omitted")
	bad = clear.duplicate(true)
	bad["extra"] = 1
	_check(not ElementalState.valid(bad), "elemental codec rejects extra keys")
	bad = clear.duplicate(true)
	bad["schema_version"] = 2
	bad["acid_ticks"] = 1
	_check(not ElementalState.valid(bad), "old elemental schema is refused")
	bad = clear.duplicate(true)
	bad["wet_turns"] = true
	_check(not ElementalState.valid(bad), "bool is not an integer counter")
	var no_source: Dictionary = clear.duplicate(true)
	no_source["burning_stacks"] = 1
	no_source["burning_ticks"] = 1
	_check(not ElementalState.valid(no_source), "active burning requires a source")
	var cell: Dictionary = clear.duplicate(true)
	cell["burning_stacks"] = 1
	cell["burning_ticks"] = ElementalState.MAX_VALUE
	cell["burning_source"] = _source(&"cell")
	_check(ElementalState.valid(cell), "burn duration accepts int64 maximum")

func _source(kind: StringName) -> Dictionary:
	if kind == &"attack":
		return {"kind": &"attack", "source_instance_id": 0, "origin_cell": Vector2i(4, 5), "instigator_unit_id": 7, "credit_unit_id": 7}
	return {"kind": &"cell", "source_instance_id": ElementalState.MAX_ID - 1, "origin_cell": Vector2i(4, 5), "instigator_unit_id": 0, "credit_unit_id": 0}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _on_changed() -> void:
	changed_count += 1
