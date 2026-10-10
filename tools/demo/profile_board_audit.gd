extends "res://tools/demo/profile_snapshot_strategies.gd"

## Только эксперимент: аудит не публикует снимок и не является разрешением
## копировать произвольную доску старым fixture-only direct_board.
const Audit = preload("res://tools/demo/board_audit_probe.gd")

class DerivedBoard extends BattleBoard: pass
class DerivedUnit extends UnitState: pass
class DerivedBag extends StatsBag: pass
class DerivedVitals extends Vitals: pass
class DerivedStat extends Stat: pass
class DerivedModifier extends StatModifier: pass
class DerivedActions extends ActionResources: pass
class DerivedArmor extends ArmorState: pass
class DerivedBleeding extends BleedingState: pass
class DerivedControl extends ControlState: pass
class DerivedPerks extends CombatPerksState: pass
class DerivedDefinition extends CombatPerksDefinition: pass
class DerivedElemental extends ElementalState: pass

var _passed: int = 0
var _failed: int = 0
var _cases_checked: int = 0

func _initialize() -> void:
	call_deferred("_run_audit")

func _check(condition: bool, label: String) -> void:
	if condition: _passed += 1
	else:
		_failed += 1
		printerr("FAIL BOARD AUDIT: " + label)

func _unit(mask: int = 0) -> UnitState:
	var unit := UnitState.new()
	unit.id = 1
	unit.faction = Faction.Type.PLAYER
	unit.stats = StatsBag.new()
	unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	unit.stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"z", StatModifier.Operation.ADD_PERCENT, 0.5))
	unit.stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"a", StatModifier.Operation.ADD_FLAT, 2.0))
	unit.stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"z", StatModifier.Operation.MULTIPLY, 1.0))
	unit.vitals = Vitals.new(unit.stats, false)
	unit.vitals._hp = 10.0
	unit.vitals._is_alive = true
	if mask & 1: unit.action_resources = ActionResources.new(1)
	unit.guard_stance = (mask & 2) != 0
	if mask & 4: unit.armor = ArmorState.new()
	if mask & 8:
		unit.bleeding = BleedingState.new()
		if mask & 64:
			unit.bleeding.stacked = true
			unit.bleeding.stacks = 1
			unit.bleeding.ticks_left = 1
			unit.bleeding.hit_id = "probe"
			unit.bleeding.source = _source(1)
	if mask & 16: unit.control = ControlState.new()
	if mask & 32: unit.combat_perks = CombatPerksState.new()
	if mask & 64: unit.elemental = ElementalState.new()
	return unit

func _source(id: int) -> Dictionary:
	return {"kind": &"attack", "source_instance_id": 0, "origin_cell": Vector2i.ZERO,
		"instigator_unit_id": id, "credit_unit_id": id}

func _hp(unit: UnitState) -> Stat:
	return unit.stats._stats[StatTypes.StatType.HP_MAX]

func _signature(value: Variant, seen: Dictionary) -> Variant:
	# Независимая от snapshot producer запись обнаруживает также прогрев cache,
	# замену runtime-ссылок и изменение подписок при успешном/отказанном аудите.
	if value is Object:
		if value == null: return null
		var identity: int = value.get_instance_id()
		if seen.has(identity): return ["ref", identity]
		seen[identity] = true
		var properties: Array = []
		for property: Dictionary in value.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				properties.append([property["name"], _signature(value.get(property["name"]), seen)])
		var connections: Array = []
		for signal_data: Dictionary in value.get_signal_list():
			for connection: Dictionary in value.get_signal_connection_list(signal_data["name"]):
				connections.append([signal_data["name"], str(connection["callable"]), connection["flags"]])
		return ["object", identity, properties, connections]
	if value is Dictionary:
		var entries: Array = []
		for key: Variant in value: entries.append([_signature(key, seen), _signature(value[key], seen)])
		return ["dictionary", entries]
	if value is Array:
		var entries: Array = []
		for child: Variant in value: entries.append(_signature(child, seen))
		return ["array", entries]
	if value is Callable: return str(value)
	return value

func _bytes(board: BattleBoard) -> PackedByteArray:
	return var_to_bytes(_signature(board, {}))

func _compare(board: BattleBoard, label: String, ids: Array[StringName] = [], clone_safe: bool = false) -> void:
	var before := _bytes(board)
	var counter := UnitId.get_counter()
	var expected := SimulationSnapshot.capture_board(board, ids)
	_check(_bytes(board) == before, label + "/capture purity")
	var actual := Audit.audit(board, ids)
	_check(actual.code == expected.code and actual.reason == expected.reason and actual.unsupported_ids == expected.unsupported_ids, label + "/admission")
	_check(actual.snapshot == null, label + "/no snapshot publication")
	_check(_bytes(board) == before and UnitId.get_counter() == counter, label + "/audit purity")
	var repeated := Audit.audit(board, ids)
	_check(repeated.code == actual.code and repeated.reason == actual.reason and repeated.unsupported_ids == actual.unsupported_ids and _bytes(board) == before, label + "/repeat fresh audit")
	if clone_safe and expected.code == BoardSnapshotResult.Code.OK:
		var clone := direct_board(board)
		_verify_nested_isolation(clone, board, label)
		clone.resize(0, 0)
		clone = direct_board(board)
		_verify_and_close_clone(clone, board, expected.snapshot.to_dict())
		_check(_bytes(board) == before, label + "/clone isolation")
	_cases_checked += 1
	print(JSON.stringify({"case": label, "code": expected.code, "reason": expected.reason,
		"unsupported_ids": expected.unsupported_ids, "parity": actual.code == expected.code and actual.reason == expected.reason and actual.unsupported_ids == expected.unsupported_ids}))

func _verify_nested_isolation(clone: BattleBoard, source: BattleBoard, label: String) -> void:
	var before := _bytes(source)
	var unit := clone.get_unit_by_id(1)
	var original := source.get_unit_by_id(1)
	_check(unit.stats != original.stats and unit.vitals != original.vitals and unit.vitals._stats == unit.stats, label + "/stats-vitals ownership")
	for key: int in unit.stats._stats:
		var stat: Stat = unit.stats._stats[key]
		var source_stat: Stat = original.stats._stats[key]
		_check(stat != source_stat, label + "/stat ownership")
		for i: int in stat._modifiers.size():
			_check(stat._modifiers[i] != source_stat._modifiers[i], label + "/modifier ownership")
			stat._modifiers[i].value += 0.25
		stat.base_value += 1.0
	for field: String in ["action_resources", "armor", "bleeding", "control", "combat_perks", "elemental"]:
		if unit.get(field) != null: _check(unit.get(field) != original.get(field), label + "/" + field + " ownership")
	if unit.action_resources != null: unit.action_resources._main_left += 1
	if unit.armor != null:
		unit.armor.natural["physical"] += 1
		for grant: Dictionary in unit.armor.grants: grant["remaining"] += 1
		for perk: Dictionary in unit.armor.perks: perk["source"] = "changed"
	if unit.bleeding != null: unit.bleeding.source["credit_unit_id"] = 123
	if unit.control != null: unit.control.stunned_turns = 1 - unit.control.stunned_turns
	if unit.combat_perks != null:
		_check(unit.combat_perks.definition != original.combat_perks.definition, label + "/perks definition ownership")
		unit.combat_perks.definition.sneak_attack = not unit.combat_perks.definition.sneak_attack
	if unit.elemental != null:
		unit.elemental.burning_source["credit_unit_id"] = 123
		unit.elemental.wet_turns += 1
	clone._heights[0] += 1
	clone._terrain[0] = (clone._terrain[0] + 1) % 4
	clone._height_half_steps[0] = 1 - clone._height_half_steps[0]
	clone._occupancy.clear()
	_check(_bytes(source) == before, label + "/nested mutations isolated")

func _case(label: String, mutate: Callable, mask: int = 127, clone_safe: bool = false) -> void:
	var board := BattleBoard.new(3, 2)
	var unit := _unit(mask)
	assert(board.add_unit(unit))
	# Отказы могут намеренно разорвать live ownership. Сохраняем исходную связь
	# для очистки fixture, не исправляя граф перед сравнением аудиторов.
	var vitals := unit.vitals
	var callback: Callable = board._death_callbacks[1]
	mutate.call(board, unit)
	_compare(board, label, [], clone_safe)
	if vitals.died.is_connected(callback): vitals.died.disconnect(callback)
	board._death_callbacks.clear()
	board._units.clear()
	board.resize(0, 0)

func _admission_cases() -> void:
	_compare(null, "null")
	_compare(null, "unsupported-list-first", [&"z", &"a", &"z"])
	var derived := DerivedBoard.new(1, 1)
	_compare(derived, "board subclass")
	derived.resize(0, 0)
	var empty := BattleBoard.new()
	_compare(empty, "empty")
	empty.resize(1024, 0)
	_compare(empty, "zero area boundary")
	empty.resize(256, 256)
	_compare(empty, "max cells")
	empty.resize(0, 0)
	for mask: int in 128:
		_case("composition/%d" % mask, func(_b: BattleBoard, _u: UnitState) -> void: pass, mask, true)
	var cases := {
		"key type": func(b: BattleBoard, _u: UnitState) -> void: b._units["x"] = null,
		"value type": func(b: BattleBoard, _u: UnitState) -> void: b._units[2] = 1,
		"null unit": func(b: BattleBoard, _u: UnitState) -> void: b._units[2] = null,
		"unit subclass": func(b: BattleBoard, _u: UnitState) -> void: b._units[2] = DerivedUnit.new(),
		"ai profile": func(_b: BattleBoard, u: UnitState) -> void: u.ai_profile = AIBehaviorProfile.new(),
		"null stats": func(_b: BattleBoard, u: UnitState) -> void: u.stats = null,
		"null vitals": func(_b: BattleBoard, u: UnitState) -> void: u.vitals = null,
		"stats subclass": func(_b: BattleBoard, u: UnitState) -> void: u.stats = DerivedBag.new(),
		"vitals subclass": func(_b: BattleBoard, u: UnitState) -> void: u.vitals = DerivedVitals.new(u.stats, false),
		"vitals owner": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._stats = StatsBag.new(),
		"actions subclass": func(_b: BattleBoard, u: UnitState) -> void: u.action_resources = DerivedActions.new(1),
		"armor subclass": func(_b: BattleBoard, u: UnitState) -> void: u.armor = DerivedArmor.new(),
		"bleeding subclass": func(_b: BattleBoard, u: UnitState) -> void: u.bleeding = DerivedBleeding.new(),
		"control subclass": func(_b: BattleBoard, u: UnitState) -> void: u.control = DerivedControl.new(),
		"perks subclass": func(_b: BattleBoard, u: UnitState) -> void: u.combat_perks = DerivedPerks.new(),
		"definition subclass": func(_b: BattleBoard, u: UnitState) -> void: u.combat_perks.definition = DerivedDefinition.new(),
		"null definition": func(_b: BattleBoard, u: UnitState) -> void: u.combat_perks.definition = null,
		"elemental subclass": func(_b: BattleBoard, u: UnitState) -> void: u.elemental = DerivedElemental.new(),
		"stat key": func(_b: BattleBoard, u: UnitState) -> void: u.stats._stats["bad"] = Stat.new(),
		"stat value": func(_b: BattleBoard, u: UnitState) -> void: u.stats._stats[0] = 2,
		"stat null": func(_b: BattleBoard, u: UnitState) -> void: u.stats._stats[0] = null,
		"stat subclass": func(_b: BattleBoard, u: UnitState) -> void: u.stats._stats[0] = DerivedStat.new(),
		"modifier subclass": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifiers[0] = DerivedModifier.new(),
		"modifier null": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifiers[0] = null,
		"slot count": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifier_slots.clear(),
		"slot negative": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifier_slots[0] = -1,
		"slot duplicate": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifier_slots[1] = 0,
		"slot beyond next": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifier_slots[0] = 3,
		"next negative": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._next_modifier_slot = -1,
		"base inf": func(_b: BattleBoard, u: UnitState) -> void: _hp(u).base_value = INF,
		"base nan": func(_b: BattleBoard, u: UnitState) -> void: _hp(u).base_value = NAN,
		"modifier inf": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifiers[0].value = INF,
		"operation invalid": func(_b: BattleBoard, u: UnitState) -> void: _hp(u)._modifiers[0].set("operation", 4),
		"faction": func(_b: BattleBoard, u: UnitState) -> void: u.set("faction", 3),
		"id mismatch": func(_b: BattleBoard, u: UnitState) -> void: u.id = 2,
		"negative id": func(_b: BattleBoard, u: UnitState) -> void: u.id = -1,
		"cell": func(_b: BattleBoard, u: UnitState) -> void: u.cell = Vector2i(-1, 0),
		"move inf": func(_b: BattleBoard, u: UnitState) -> void: u.move_points_left = INF,
		"move negative": func(_b: BattleBoard, u: UnitState) -> void: u.move_points_left = -1.0,
		"hp fractional": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = 1.5,
		"hp inf": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = INF,
		"hp negative": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = -1.0,
		"hp above max": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = 19.0,
		"hp exact limit": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = 9007199254740992.0,
		"balance nan": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._balance = NAN,
		"balance negative": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._balance = -1.0,
		"max fractional": func(_b: BattleBoard, u: UnitState) -> void: _hp(u).base_value = 10.5,
		"max exact limit": func(_b: BattleBoard, u: UnitState) -> void: _hp(u).base_value = 9007199254740992.0,
		"actions owner": func(_b: BattleBoard, u: UnitState) -> void: u.action_resources._owner_unit_id = 2,
		"actions counter": func(_b: BattleBoard, u: UnitState) -> void: u.action_resources._main_left = -1,
		"control value": func(_b: BattleBoard, u: UnitState) -> void: u.control.stunned_turns = 2,
		"armor value": func(_b: BattleBoard, u: UnitState) -> void: u.armor.natural["physical"] = "bad",
		"perks self cover": func(_b: BattleBoard, u: UnitState) -> void:
			u.combat_perks.mode = CombatPerksState.Mode.COVER
			u.combat_perks.cover_target_id = 1,
		"bleeding value": func(_b: BattleBoard, u: UnitState) -> void: u.bleeding.stacks = -1,
		"bleeding source missing": func(_b: BattleBoard, u: UnitState) -> void: u.bleeding.source = _source(2),
		"elemental value": func(_b: BattleBoard, u: UnitState) -> void: u.elemental.wet_turns = 4,
		"width negative": func(b: BattleBoard, _u: UnitState) -> void: b.width = -1,
		"width limit": func(b: BattleBoard, _u: UnitState) -> void: b.width = 1025,
		"area limit": func(b: BattleBoard, _u: UnitState) -> void:
			b.width = 257
			b.height = 256,
		"board version": func(b: BattleBoard, _u: UnitState) -> void: b.board_version = -1,
		"heights size": func(b: BattleBoard, _u: UnitState) -> void: b._heights.clear(),
		"terrain size": func(b: BattleBoard, _u: UnitState) -> void: b._terrain.clear(),
		"terrain value": func(b: BattleBoard, _u: UnitState) -> void: b._terrain[0] = 4,
		"half size": func(b: BattleBoard, _u: UnitState) -> void: b._height_half_steps.clear(),
		"half value": func(b: BattleBoard, _u: UnitState) -> void: b._height_half_steps[0] = 2,
		"half valid": func(b: BattleBoard, _u: UnitState) -> void: b._height_half_steps[0] = 1,
		"occupancy key": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy["bad"] = 1,
		"occupancy value": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy[Vector2i.ZERO] = "bad",
		"occupancy outside": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy[Vector2i(9, 9)] = 1,
		"occupancy unknown": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy[Vector2i.ZERO] = 2,
		"occupancy wrong cell": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy[Vector2i(1, 0)] = 1,
		"occupancy dead": func(_b: BattleBoard, u: UnitState) -> void: u.vitals._is_alive = false,
		"missing occupancy accepted": func(b: BattleBoard, _u: UnitState) -> void: b._occupancy.clear(),
		"height mismatch accepted": func(_b: BattleBoard, u: UnitState) -> void: u.height = 100,
	}
	for label: String in cases: _case(label, cases[label])
	_case("clean cache", func(_b: BattleBoard, u: UnitState) -> void: _hp(u).get_value(), 127, true)
	_case("stale cache", func(_b: BattleBoard, u: UnitState) -> void:
		_hp(u).get_value()
		_hp(u)._cached_value += 1.0)
	_case("subtype before stale", func(b: BattleBoard, u: UnitState) -> void:
		_hp(u).get_value()
		_hp(u)._cached_value += 1.0
		b._units[2] = DerivedUnit.new())
	_case("absent HP max", func(_b: BattleBoard, u: UnitState) -> void:
		u.stats._stats.clear()
		u.vitals._hp = 0.0, 127, true)
	_case("burning source missing", func(_b: BattleBoard, u: UnitState) -> void:
		u.bleeding = BleedingState.new()
		u.bleeding.stacked = true
		u.elemental.burning_stacks = 1
		u.elemental.burning_ticks = 1
		u.elemental.burning_source = _source(2))
	_case("legacy bleeding absent source accepted", func(_b: BattleBoard, u: UnitState) -> void:
		u.bleeding.ticks_left = 1
		u.bleeding.hit_id = "legacy"
		u.bleeding.source = _source(2), 13, true)
	_case("burning plus bleeding", func(_b: BattleBoard, u: UnitState) -> void:
		u.elemental.burning_stacks = 1
		u.elemental.burning_ticks = 1
		u.elemental.burning_source = _source(1))
	_case("dead valid", func(b: BattleBoard, u: UnitState) -> void:
		u.vitals._hp = 0.0
		u.vitals._is_alive = false
		b._occupancy.clear(), 127, true)
	# Оба состояния допускаются capture, но прежний direct_board меняет данные.
	# Фиксируем границу прототипа, не ужесточая допуска экспериментального аудита.
	_case("duplicate cell without occupancy", func(b: BattleBoard, _u: UnitState) -> void:
		var second := _unit()
		second.id = 2
		b._units[2] = second
		b._occupancy.clear())
	_case("fresh invalidation and repair", func(b: BattleBoard, u: UnitState) -> void:
		_compare(b, "fresh/before")
		u.action_resources._owner_unit_id = 9
		_compare(b, "fresh/invalid")
		u.action_resources._owner_unit_id = 1)
	_case("populated armor", func(_b: BattleBoard, u: UnitState) -> void:
		u.armor.next_grant_id = 2
		u.armor.grants.append({"grant_id": 1, "source": "fixture", "remaining": 3, "expires": "battle", "battle_id": 1})
		u.armor.perks.append({"id": "fixture", "kind": "persistent_armor", "source": "fixture"})
		u.armor.natural["physical"] = -1, 127, true)
	_case("computed overflow", func(_b: BattleBoard, u: UnitState) -> void:
		_hp(u).base_value = 1.0e308
		_hp(u)._modifiers[2].value = 1.0e308)
	_case("evaluation order cancellation", func(_b: BattleBoard, u: UnitState) -> void:
		var stat := Stat.new(10.0)
		stat.add_modifier(StatModifier.new(&"z", StatModifier.Operation.ADD_FLAT, 1.0e16))
		stat.add_modifier(StatModifier.new(&"a", StatModifier.Operation.ADD_FLAT, -1.0e16))
		stat.add_modifier(StatModifier.new(&"m", StatModifier.Operation.ADD_FLAT, 2.0))
		u.stats._stats[StatTypes.StatType.HP_MAX] = stat, 127, true)
	_case("source errors sorted by id", func(b: BattleBoard, u: UnitState) -> void:
		b._units.erase(1)
		var second := _unit(127)
		second.id = 2
		second.action_resources._owner_unit_id = 2
		second.cell = Vector2i(1, 0)
		second.bleeding.source = _source(999)
		b._units[2] = second
		b._units[1] = u
		u.bleeding.source = _source(999))

func _probe_clone_sample(board: BattleBoard) -> Dictionary:
	var start := Time.get_ticks_usec()
	assert(Audit.audit(board, []).code == BoardSnapshotResult.Code.OK)
	var audit_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var clone := direct_board(board)
	var build_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	clone.resize(0, 0)
	return {"audit_us": audit_us, "build_us": build_us, "cleanup_us": Time.get_ticks_usec() - start}

func _audit_sample(label: String, board: BattleBoard) -> Dictionary:
	var start := Time.get_ticks_usec()
	var phases: Dictionary
	match label:
		"capture_restore": phases = _capture_restore_sample(board)
		"capture_audited_clone": phases = _audited_clone_sample(board)
		_: phases = _probe_clone_sample(board)
	phases["total_us"] = Time.get_ticks_usec() - start
	return phases

func _benchmark(reverse: bool) -> void:
	var hub := HeroHubState.create(73191, 2)
	hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub, "start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	var session: BattleCoreReactionsSession = bundle.session
	var state_before := ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict()
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var id_before := UnitId.get_counter()
	var counts: Array[int] = [6, 24, 96]
	if reverse: counts.reverse()
	var labels: Array[String] = ["capture_restore", "capture_audited_clone", "runtime_audited_clone"]
	for count: int in counts:
		var board := _make_fixture(session, count)
		_compare(board, "benchmark/%d" % count, [], true)
		var before := _bytes(board)
		for label: String in labels:
			for warmup: int in 3: _audit_sample(label, board)
		var records: Array[Dictionary] = []
		for sample: int in SAMPLES:
			# Все шесть перестановок уравновешивают соседство и порядок стратегий.
			var orders := [[0, 1, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0], [1, 0, 2], [0, 2, 1]]
			var order: Array = orders[(sample + (3 if reverse else 0)) % 6]
			for position: int in 3:
				var label: String = labels[order[position]]
				var record := _audit_sample(label, board)
				record.merge({"label": label, "count": count, "sample": sample, "order": position})
				records.append(record)
		for record: Dictionary in records: print(JSON.stringify(record))
		for label: String in labels:
			var matching: Array[Dictionary] = []
			for record: Dictionary in records:
				if record["label"] == label: matching.append(record)
			_print_breakdown_summary(label, count, matching)
		_check(_bytes(board) == before, "benchmark live graph unchanged/%d" % count)
		board.resize(0, 0)
		_check(board._death_callbacks.is_empty(), "benchmark cleanup/%d" % count)
	_check(ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == state_before, "full source unchanged")
	_check(session.context.get_rng().to_dict() == rng_before, "RNG unchanged")
	_check(session.context.simulation_counters() == counters_before, "counters unchanged")
	_check(UnitId.get_counter() == id_before, "UnitId unchanged")
	session.close()

func _run_audit() -> void:
	var id_before := UnitId.get_counter()
	_admission_cases()
	_check(UnitId.get_counter() == id_before, "matrix UnitId unchanged")
	var args := OS.get_cmdline_user_args()
	if _failed == 0 and not args.has("--verify-only"): _benchmark(args.has("--reverse"))
	print(JSON.stringify({"verification": {"passed": _passed, "failed": _failed, "cases": _cases_checked}}))
	print("BOARD AUDIT PROBE RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("BOARD AUDIT PROBE DONE")
	quit(0 if _failed == 0 else 1)
