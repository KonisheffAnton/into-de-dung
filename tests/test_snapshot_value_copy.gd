extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SNAPSHOT VALUE COPY: " + label)

func _run() -> void:
	var shared_array: Array[int] = [1, 2]
	var shared_dictionary: Dictionary[String, Variant] = {"nested": ["before"]}
	var reference := RefCounted.new()
	var packed := PackedByteArray([7, 9])
	var values: Array = [
		shared_array, shared_array,
		shared_dictionary, shared_dictionary,
		&"typed-name", Vector2i(3, -4), true, 17, 2.5, "text", null,
		reference, packed,
	]
	var copied: Variant = SimulationSnapshot._copy_value(values)
	check(typeof(copied) == TYPE_ARRAY and copied.get_typed_builtin() == TYPE_NIL, "root typedness is erased")
	check(typeof(copied[0]) == TYPE_ARRAY and copied[0].get_typed_builtin() == TYPE_NIL, "typed child array becomes untyped")
	check(typeof(copied[2]) == TYPE_DICTIONARY and copied[2].get_typed_key_builtin() == TYPE_NIL and copied[2].get_typed_value_builtin() == TYPE_NIL, "typed child dictionary becomes untyped")
	check(not is_same(copied[0], copied[1]) and not is_same(copied[2], copied[3]), "aliases are copied independently")
	copied[0][0] = 99
	copied[2]["nested"][0] = "changed"
	check(shared_array == [1, 2] and copied[1] == [1, 2], "array copies are isolated from source and sibling alias")
	check(shared_dictionary["nested"] == ["before"] and copied[3]["nested"] == ["before"], "dictionary copies are isolated from source and sibling alias")
	check(typeof(copied[4]) == TYPE_STRING_NAME and copied[4] == &"typed-name" and copied[5] == Vector2i(3, -4), "StringName and Vector2i values are preserved")
	check(typeof(copied[6]) == TYPE_BOOL and typeof(copied[7]) == TYPE_INT and typeof(copied[8]) == TYPE_FLOAT and typeof(copied[9]) == TYPE_STRING and copied[10] == null, "scalar and null types are preserved")
	check(is_same(copied[11], reference), "opaque Object reference is preserved")
	check(typeof(copied[12]) == TYPE_PACKED_BYTE_ARRAY and copied[12] == packed, "PackedArray value is preserved")
	var dictionary_key := RefCounted.new()
	var keyed: Dictionary = {dictionary_key: shared_array}
	var keyed_copy: Dictionary = SimulationSnapshot._copy_value(keyed)
	check(keyed_copy.has(dictionary_key) and is_same(keyed_copy.keys()[0], dictionary_key), "dictionary key identity is preserved")
	check(not is_same(keyed_copy[dictionary_key], shared_array), "dictionary values are copied")
	print("SNAPSHOT VALUE COPY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
