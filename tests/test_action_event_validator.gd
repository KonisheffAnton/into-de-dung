extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_simple_events()
	_test_transit_context()
	print("ACTION EVENT VALIDATOR RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_simple_events() -> void:
	var valid_damage := {
		"kind": &"damaged", "actor_unit_id": 1, "target_unit_id": 2,
		"source": {"kind": &"attack", "source_instance_id": 0, "origin_cell": Vector2i.ZERO, "instigator_unit_id": 1, "credit_unit_id": 0},
		"hp_before": 4.0, "hp_after": 3.0, "amount": 1.0, "alive_before": true, "alive_after": true,
	}
	var original: Dictionary = valid_damage.duplicate(true)
	_check(ActionEventValidator.valid_draft(valid_damage), "accepts representative damage event")
	_check(valid_damage == original, "does not mutate event dictionary")
	var invalid_damage: Dictionary = valid_damage.duplicate(true)
	invalid_damage["amount"] = -1.0
	_check(not ActionEventValidator.valid_draft(invalid_damage), "rejects negative damage amount")

func _test_transit_context() -> void:
	var context := ActionContext.new(null, null, null, [], MoveRules.new([1], 1, &"spatial_move_v1"))
	var counters: Dictionary = context.simulation_counters()
	var transit := {
		"kind": &"moved", "actor_unit_id": 1, "target_unit_id": 1,
		"from_cell": Vector2i(0, 0), "to_cell": Vector2i(2, 0),
		"movement_kind": &"voluntary", "move_cost": 2.0, "move_before": 5.0, "move_after": 3.0,
		"transit_path": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	}
	var original: Dictionary = transit.duplicate(true)
	_check(ActionEventValidator.valid_draft(transit, context), "accepts transit with spatial rules")
	_check(transit == original and context.simulation_counters() == counters, "does not mutate event or context")
	_check(not ActionEventValidator.valid_draft(transit), "rejects transit without spatial context")
	var bad_path: Dictionary = transit.duplicate(true)
	bad_path["transit_path"] = [Vector2i(0, 0), Vector2i(2, 0)]
	_check(not ActionEventValidator.valid_draft(bad_path, context), "rejects non-adjacent transit edge")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)
