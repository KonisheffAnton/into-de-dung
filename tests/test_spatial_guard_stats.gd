extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL SPATIAL GUARD STATS: " + label)

func _capture(session: BattleDemoSession, unit: UnitState, types: Array[int]) -> SpatialRules.Guard:
	var selection: Array[UnitState] = [unit]
	var cells: Array[Vector2i] = [unit.cell]
	return SpatialRules.capture_guard(session.context, selection, cells, {unit.id: types})

func _run() -> void:
	var session := BattleDemoSession.new()
	var unit := session.units[0]
	var strength: int = StatTypes.StatType.STRENGTH
	var weapon: int = StatTypes.StatType.WEAPON_DAMAGE
	var piercing: int = StatTypes.StatType.PHYSICAL_PIERCING_PERCENT
	var live_stat: Stat = unit.stats._stats[strength]
	var cache_before := [live_stat._cache_dirty, live_stat._cached_value]
	var guard := _capture(session, unit, [strength, weapon, piercing])
	check(guard != null, "capture real session guard")
	check(guard._validated_stats_snapshots[unit.id] == unit.stats.to_snapshot_dict(), "capture stores canonical stats DTO in private cache")
	check(guard.values["participants"][unit.id]["stats"][piercing] == null, "optional piercing absence is represented explicitly")
	check([live_stat._cache_dirty, live_stat._cached_value] == cache_before, "capture does not write live stat cache")
	check(guard.check(session.context), "equal canonical DTO accepts without changing guard baseline")
	check([live_stat._cache_dirty, live_stat._cached_value] == cache_before, "equality check does not write live stat cache")

	var selected_change := _capture(session, unit, [strength])
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, unit.stats.get_base_value(StatTypes.StatType.STRENGTH) + 1.0)
	check(not selected_change.check(session.context), "selected stat change rejects")
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 6.0)

	var unselected_change := _capture(session, unit, [strength])
	var baseline: Dictionary = unselected_change._validated_stats_snapshots[unit.id].duplicate(true)
	unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, unit.stats.get_base_value(StatTypes.StatType.WEAPON_DAMAGE) + 2.0)
	check(unselected_change.check(session.context), "valid unselected stat change is accepted by prior selected-stat fallback")
	check(unselected_change._validated_stats_snapshots[unit.id] == baseline, "fallback does not advance the capture-time stats baseline")
	unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 4.0)
	var neutral_change := _capture(session, unit, [strength])
	unit.stats.add_modifier(StatTypes.StatType.WEAPON_DAMAGE, StatModifier.new(&"neutral_guard_test", StatModifier.Operation.ADD_FLAT, 0.0))
	check(neutral_change.check(session.context), "valid neutral modifier change is accepted by fallback")
	unit.stats.remove_modifiers_by_source(&"neutral_guard_test")

	var missing_piercing := _capture(session, unit, [piercing])
	unit.stats.set_base_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT, 0.0)
	check(not missing_piercing.check(session.context), "adding previously absent optional piercing is detected")

	var invalid_dto := _capture(session, unit, [strength])
	var strength_stat: Stat = unit.stats._stats[strength]
	strength_stat.get_value()
	strength_stat._cached_value += 3.0
	check(not invalid_dto.check(session.context), "invalid live canonical DTO rejects")
	strength_stat._cache_dirty = true
	strength_stat.get_value()

	var tampered_values := _capture(session, unit, [strength])
	tampered_values.values["participants"][unit.id]["stats"][strength] += 1.0
	tampered_values.seal()
	check(not tampered_values.check(session.context), "selected baseline change rejected after reseal by fallback")
	var fake_snapshot := _capture(session, unit, [strength])
	fake_snapshot.values["participants"][unit.id]["stats_snapshot"] = {"unrelated": true}
	fake_snapshot.seal()
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, unit.stats.get_base_value(StatTypes.StatType.STRENGTH) + 1.0)
	check(not fake_snapshot.check(session.context), "unrelated public fake snapshot cannot bypass selected-stat validation")
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 6.0)

	var legacy := _capture(session, unit, [strength])
	legacy._validated_stats_snapshots.erase(unit.id)
	check(legacy.check(session.context), "guard without capture-time stats cache uses fallback")

	session.close()
	print("SPATIAL GUARD STATS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
