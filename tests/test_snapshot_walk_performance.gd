extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SNAPSHOT WALK: " + label)

func parity(value: Variant, label: String, depth: int = 0, start_count: int = 0) -> void:
	var original_count: Array[int] = [start_count]
	var fast_count: Array[int] = [start_count]
	var original := ItemSimulationSnapshot._walk(value, depth, [], original_count, "envelope")
	var fast := ItemSimulationSnapshot._walk_valid(value, depth, [], fast_count)
	check(fast == original.is_empty(), label + " acceptance")
	if fast: check(original_count == fast_count, label + " node accounting")
	# На некорректной DTO вызывающий код возвращает прежний точный путь ошибки.
	if value is Dictionary and depth == 0 and start_count == 0 and not original.is_empty():
		check(ItemSimulationSnapshot.from_dict(value).reason == original, label + " diagnostic")

func run() -> void:
	for value: Variant in [true, 1, 0.25, &"name", Vector2i(2, 3), "", [], {}, [1, "x", false]]:
		parity(value, "valid primitive/container")
	for value: Variant in [null, NAN, INF, -INF, Vector2(2, 3), PackedByteArray([1]), RefCounted.new()]:
		parity({"z": value}, "invalid primitive")
	for char_value: String in ["a", "я", "界", "😀"]:
		for length_value: int in [1024, 1025, 2048, 2049, 4096, 4097]:
			parity({"text": char_value.repeat(length_value)}, "UTF8 boundary")
	parity({"я".repeat(2049): true}, "oversized key")
	parity({&"name": true}, "StringName key forbidden")
	parity({1: true}, "integer key forbidden")
	parity({"z": INF, "a": null}, "sorted diagnostic despite insertion order")
	var shared: Array = [1, 2]
	parity({"b": shared, "a": shared}, "shared container without cycle")
	var cycle: Array = []
	cycle.append(cycle)
	parity({"cycle": cycle}, "array cycle")
	cycle.clear()
	var dict_cycle: Dictionary = {}
	dict_cycle["self"] = dict_cycle
	parity(dict_cycle, "dictionary cycle")
	dict_cycle.clear()
	var deep: Array = [true]
	for level: int in 33:
		parity({"deep": deep}, "depth boundary %d" % level)
		deep = [deep]
	parity(1, "last depth accepted", ItemSimulationSnapshot.MAX_DEPTH)
	parity(1, "depth rejected", ItemSimulationSnapshot.MAX_DEPTH + 1)
	for value: Variant in [true, [], [true], {}, {"a": true}, {"z": 1, "a": 2}]:
		for remaining: int in range(0, 7):
			parity(value, "remaining node boundary", 0, ItemSimulationSnapshot.MAX_VALUE_NODES - remaining)
	check(ItemSimulationSnapshot.from_dict({}).reason == "envelope/schema", "raw-valid DTO still needs structure validation")
	var session := BattleCoreCombinationSession.new()
	var snapshot := ItemSimulationSnapshot.capture(session.state, []).snapshot
	var data := snapshot.to_dict()
	var before := data.duplicate(true)
	parity(data, "full K9 state")
	var decoded := ItemSimulationSnapshot.from_dict(data)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot.canonical_bytes() == snapshot.canonical_bytes(), "canonical roundtrip")
	check(data == before, "input stays untouched")
	session.close()
	print("SNAPSHOT WALK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
