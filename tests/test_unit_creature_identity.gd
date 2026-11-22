extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL UNIT CREATURE IDENTITY: " + label)

func _unit() -> UnitState:
	var stats := StatsBag.new()
	var unit := UnitState.new()
	unit.id = 1201
	unit.faction = Faction.Type.ENEMY
	unit.stats = stats
	unit.vitals = Vitals.from_dict({"hp": 17.0, "balance": 3.0, "is_alive": true}, stats)
	unit.debug_name = "Identity fixture"
	unit.move_points_left = 2.0
	return unit

func _run() -> void:
	var ordinary := _unit()
	var ordinary_snapshot := ordinary.to_snapshot_dict()
	check(ordinary_snapshot.get("creature_kind") == "living" and ordinary_snapshot.get("archetype_id") == "",
		"ordinary units default to living with no archetype")
	var ordinary_copy := UnitState.from_snapshot_dict(ordinary_snapshot)
	check(ordinary_copy != null and ordinary_copy.creature_kind == &"living" and ordinary_copy.archetype_id == &"",
		"default identity roundtrips through snapshot")
	ordinary.creature_kind = &"undead"
	ordinary.archetype_id = &"tamed_troglodyte"
	var encoded := ordinary.to_snapshot_dict()
	check(encoded.get("creature_kind") == "undead" and encoded.get("archetype_id") == "tamed_troglodyte",
		"snapshot writes both identity fields as strings")
	var restored := UnitState.from_snapshot_dict(encoded)
	check(restored != null and restored.creature_kind == &"undead" and restored.archetype_id == &"tamed_troglodyte"
		and restored.faction == Faction.Type.ENEMY, "undead identity roundtrips independently of faction")
	var utf8_boundary := _unit()
	utf8_boundary.archetype_id = StringName("я".repeat(32))
	check(not utf8_boundary.to_snapshot_dict().is_empty(), "archetype id accepts the 64-byte UTF-8 boundary")
	var clone := CheckedBoardClone.copy_unit_unchecked(ordinary)
	ordinary.creature_kind = &"living"
	ordinary.archetype_id = &"changed_after_clone"
	check(clone.creature_kind == &"undead" and clone.archetype_id == &"tamed_troglodyte",
		"runtime clone preserves independent identity values")
	var legacy := _unit()
	legacy.creature_kind = &"undead"
	legacy.archetype_id = &"tamed_troglodyte"
	var legacy_roundtrip := UnitState.from_dict(legacy.to_dict())
	check(legacy_roundtrip != null and legacy_roundtrip.creature_kind == &"undead"
		and legacy_roundtrip.archetype_id == &"tamed_troglodyte", "legacy unit DTO roundtrips identity")
	var old_legacy := legacy.to_dict()
	old_legacy.erase("creature_kind")
	old_legacy.erase("archetype_id")
	var defaulted_legacy := UnitState.from_dict(old_legacy)
	check(defaulted_legacy != null and defaulted_legacy.creature_kind == &"living" and defaulted_legacy.archetype_id == &"",
		"legacy DTO without new fields receives defaults")
	var bad := encoded.duplicate(true)
	bad.erase("creature_kind")
	check(not UnitState.validate_snapshot_dict(bad) and UnitState.from_snapshot_dict(bad) == null,
		"snapshot missing a required identity field is rejected")
	bad = encoded.duplicate(true)
	bad["schema_version"] = 9
	check(UnitState.from_snapshot_dict(bad) == null, "version 9 snapshot is not migrated")
	for invalid_value: Variant in ["ghost", 1, ""]:
		bad = encoded.duplicate(true)
		bad["creature_kind"] = invalid_value
		check(UnitState.from_snapshot_dict(bad) == null, "invalid creature kind rejected: " + str(invalid_value))
	for invalid_value: Variant in [1, "x".repeat(65)]:
		bad = encoded.duplicate(true)
		bad["archetype_id"] = invalid_value
		check(UnitState.from_snapshot_dict(bad) == null, "invalid archetype id rejected: " + str(invalid_value))
	var invalid_runtime := _unit()
	invalid_runtime.creature_kind = &"ghost"
	check(invalid_runtime.to_snapshot_dict().is_empty() and invalid_runtime.to_reference_dict().is_empty(),
		"invalid runtime creature kind rejects capture and reference")
	invalid_runtime.creature_kind = &"living"
	invalid_runtime.archetype_id = StringName("я".repeat(33))
	check(invalid_runtime.to_snapshot_dict().is_empty() and invalid_runtime.to_reference_dict().is_empty(),
		"archetype byte limit rejects invalid runtime values")
	var invalid_legacy := _unit().to_dict()
	invalid_legacy["creature_kind"] = "ghost"
	check(UnitState.from_dict(invalid_legacy) == null, "legacy DTO rejects invalid identity strings")
	print("UNIT CREATURE IDENTITY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
