extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := CombatEnvironmentState.new()
	var fire := state.ignite(Vector2i(2, 3))
	_check(fire["damage"] == 8 and state.ignite(Vector2i(2, 3)).is_empty(), "fire unique cell")
	var body_a := state.record_death(11, Vector2i(2, 3), Faction.Type.PLAYER, "wolf")
	var body_b := state.record_death(12, Vector2i(2, 3), Faction.Type.ENEMY, "orc")
	_check(body_a["faction"] != body_b["faction"] and state.corpses_at(Vector2i(2, 3)).size() == 2, "multiple corpses")
	var isolated := state.corpses_at(Vector2i(2, 3))
	isolated[0]["creature_kind"] = "changed"
	_check(state.corpses_at(Vector2i(2, 3))[0]["creature_kind"] != "changed", "getter isolation")
	var raw := state.to_dict()
	_check(CombatEnvironmentState.valid(raw), "valid roundtrip")
	var restored := CombatEnvironmentState.from_dict(raw)
	_check(restored != null and restored.to_dict() == raw, "canonical roundtrip")
	var consumed := state.consume_corpse(body_a["id"])
	_check(consumed["source_unit_id"] == 11 and state.processed_deaths.has(11), "consume keeps processed death")
	_check(state.record_death(11, Vector2i.ZERO, Faction.Type.PLAYER, "wolf").is_empty(), "death idempotent after consume")
	for bad: Dictionary in [raw.merged({"extra": true}, true), raw.merged({"schema_version": 2}, true), raw.merged({"next_fire_id": 0}, true), raw.merged({"fires": [1]}, true), raw.merged({"processed_deaths": [11, 11]}, true)]:
		_check(not CombatEnvironmentState.valid(bad), "malformed rejected")
	var no_mutation := state.to_dict()
	_check(state.record_death(0, Vector2i.ZERO, Faction.Type.PLAYER, "bad").is_empty() and state.to_dict() == no_mutation, "invalid death no mutation")
	for counter: int in [0, CombatEnvironmentState.MAX_ID - 1]:
		state.next_fire_id = counter; state.next_corpse_id = counter
		no_mutation = state.to_dict()
		_check(state.ignite(Vector2i.ZERO).is_empty() and state.record_death(99, Vector2i.ZERO, 0, "humanoid").is_empty() and state.to_dict() == no_mutation, "counter refusal atomic")
	for mode: String in ["float_id", "duplicate_fire_cell", "duplicate_source", "counter_behind", "wrong_faction", "missing_death", "oversize"]:
		var bad := raw.duplicate(true)
		match mode:
			"float_id": bad["corpses"][0]["id"] = 1.0
			"duplicate_fire_cell":
				bad["fires"].append(bad["fires"][0].duplicate(true)); bad["fires"][1]["id"] = 2; bad["next_fire_id"] = 3
			"duplicate_source": bad["corpses"][1]["source_unit_id"] = bad["corpses"][0]["source_unit_id"]
			"counter_behind": bad["next_corpse_id"] = 2
			"wrong_faction": bad["corpses"][0]["faction"] = 999
			"missing_death": bad["processed_deaths"] = []
			"oversize":
				for i in 1025: bad["fires"].append({"id": i + 2, "cell": Vector2i(i, 0), "damage": 8})
		_check(not CombatEnvironmentState.valid(bad), "boundary reject " + mode)
	var shuffled := raw.duplicate(true)
	shuffled["corpses"].reverse(); shuffled["processed_deaths"].reverse()
	_check(CombatEnvironmentState.from_dict(shuffled).to_dict() == raw, "canonical reordered collections")
	print("D5 STATE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(label)
