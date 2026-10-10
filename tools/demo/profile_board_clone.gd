extends "res://tools/demo/profile_board_audit.gd"

## Проверяем весь допуск, включая состояния, которые нельзя собрать через add_unit.
const CloneProbe = preload("res://tools/demo/board_clone_probe.gd")

func _initialize() -> void:
	call_deferred("_run_exact")

func direct_board(source: BattleBoard) -> BattleBoard:
	return CloneProbe.copy_board_unchecked(source)

func _compare(board: BattleBoard, label: String, ids: Array[StringName] = [], _clone_safe: bool = false) -> void:
	var before := _bytes(board)
	var counter := UnitId.get_counter()
	var expected := SimulationSnapshot.capture_board(board, ids)
	var actual := CloneProbe.clone_board(board, ids)
	var parity := actual.admission.code == expected.code and actual.admission.reason == expected.reason and actual.admission.unsupported_ids == expected.unsupported_ids
	_check(parity, label + "/admission and reasons")
	_check(actual.admission.snapshot == null, label + "/no DTO publication")
	_check(_bytes(board) == before and UnitId.get_counter() == counter, label + "/capture and clone purity")
	if expected.code == BoardSnapshotResult.Code.OK and actual.board != null:
		_verify_exact(actual.board, board, expected.snapshot.to_dict(), label)
		var restored := expected.snapshot.instantiate_board()
		_check(restored != null, label + "/reference restore")
		if restored != null:
			_verify_behaviour(actual.board, restored, label)
			_close_checked(restored, label + "/reference")
		_close_checked(actual.board, label)
		# Новый вызов обязан увидеть текущий граф и создать новые объекты.
		var again := CloneProbe.clone_board(board, ids)
		_check(again.admission.code == expected.code and again.board != null and again.board != actual.board, label + "/fresh clone")
		if again.board != null:
			if again.board.get_unit_by_id(1) != null:
				_verify_nested_isolation(again.board, board, label)
			_close_checked(again.board, label + "/second")
	else:
		_check(expected.code != BoardSnapshotResult.Code.OK and actual.board == null, label + "/refusal publishes no board")
		if actual.board != null: _close_checked(actual.board, label + "/unexpected")
	_check(_bytes(board) == before and UnitId.get_counter() == counter, label + "/source and UnitId unchanged after lifecycle")
	_cases_checked += 1
	print(JSON.stringify({"case": label, "code": expected.code, "reason": expected.reason, "unsupported_ids": expected.unsupported_ids, "parity": parity}))

func _verify_exact(clone: BattleBoard, source: BattleBoard, expected: Dictionary, label: String) -> void:
	var captured := SimulationSnapshot.capture_board(clone, [])
	_check(captured.code == BoardSnapshotResult.Code.OK, label + "/clone admitted")
	if captured.snapshot != null: _check(captured.snapshot.to_dict() == expected, label + "/canonical DTO parity")
	_check(clone != source and clone._occupancy == source._occupancy and clone.board_version == source.board_version, label + "/occupancy and version")
	_check(clone._death_callbacks.size() == clone._units.size(), label + "/one callback per registration")
	_check(clone.board_changed.get_connections().is_empty(), label + "/external board subscribers not copied")
	for unit: UnitState in clone.get_all_units():
		var original := source.get_unit_by_id(unit.id)
		_check(unit != original and unit.vitals != original.vitals and unit.stats != original.stats and unit.vitals._stats == unit.stats, label + "/unit ownership/%d" % unit.id)
		_check(unit.cell == original.cell and unit.height == original.height, label + "/position/%d" % unit.id)
		_check(unit.vitals.died.get_connections().size() == 1, label + "/own death callback/%d" % unit.id)
		for key: int in unit.stats._stats:
			var stat: Stat = unit.stats._stats[key]
			var original_stat: Stat = original.stats._stats[key]
			_check(stat != original_stat and stat._modifier_slots == original_stat._modifier_slots and stat._next_modifier_slot == original_stat._next_modifier_slot, label + "/stat slots/%d/%d" % [unit.id, key])
			_check(stat._cache_dirty, label + "/fresh cache/%d/%d" % [unit.id, key])
			for i: int in stat._modifiers.size():
				_check(stat._modifiers[i] != original_stat._modifiers[i] and stat._modifiers[i].to_dict() == original_stat._modifiers[i].to_dict(), label + "/modifier order/%d/%d/%d" % [unit.id, key, i])

func _verify_behaviour(clone: BattleBoard, restored: BattleBoard, label: String) -> void:
	_verify_moves(clone, restored, label)
	var clone_events: Array = []
	var restored_events: Array = []
	_record_events(clone, clone_events)
	_record_events(restored, restored_events)
	for unit: UnitState in clone.get_all_units():
		var reference := restored.get_unit_by_id(unit.id)
		for key: int in unit.stats._stats:
			var stat: Stat = unit.stats._stats[key]
			var ref_stat: Stat = reference.stats._stats[key]
			_check(stat.get_value() == ref_stat.get_value(), label + "/evaluation order/%d/%d" % [unit.id, key])
		# Смерть до движения различает пустую, частичную и чужую occupancy той же клетки.
		unit.vitals.set_hp(0.0)
		reference.vitals.set_hp(0.0)
		unit.vitals.died.emit()
		reference.vitals.died.emit()
		_check(clone.to_snapshot_dict() == restored.to_snapshot_dict() and clone_events == restored_events, label + "/death and repeated signal/%d" % unit.id)
		clone.remove_unit(unit)
		restored.remove_unit(reference)
		var version := clone.board_version
		unit.vitals.died.emit()
		reference.vitals.died.emit()
		_check(clone.board_version == version and unit.vitals.died.get_connections().is_empty() and reference.vitals.died.get_connections().is_empty(), label + "/remove disconnect/%d" % unit.id)
		_check(clone.to_snapshot_dict() == restored.to_snapshot_dict() and clone_events == restored_events, label + "/remove parity/%d" % unit.id)

func _verify_moves(clone: BattleBoard, restored: BattleBoard, label: String) -> void:
	# Отдельная пара сохраняет исходную occupancy для последующей проверки смерти.
	var moving := CloneProbe.copy_board_unchecked(clone)
	var reference := BattleBoard.from_snapshot_dict(restored.to_snapshot_dict())
	var events: Array = []
	var ref_events: Array = []
	_record_events(moving, events)
	_record_events(reference, ref_events)
	for unit: UnitState in moving.get_all_units():
		if not unit.is_alive(): continue
		var destination := Vector2i(moving.width - 1, moving.height - 1)
		var ref_unit := reference.get_unit_by_id(unit.id)
		_check(moving.move_unit(unit, destination) == reference.move_unit(ref_unit, destination), label + "/move result/%d" % unit.id)
		var state := moving.to_snapshot_dict()
		_check(not state.is_empty() and state == reference.to_snapshot_dict() and events == ref_events, label + "/move state and events/%d" % unit.id)
	_close_checked(moving, label + "/moving")
	_close_checked(reference, label + "/moving reference")

func _record_events(board: BattleBoard, events: Array) -> void:
	board.board_changed.connect(func() -> void: events.append(["board"]))
	board.unit_position_changed.connect(func(unit: UnitState, from: Vector2i, to: Vector2i) -> void: events.append(["move", unit.id, from, to]))

func _close_checked(board: BattleBoard, label: String) -> void:
	var units := board.get_all_units()
	board.resize(0, 0)
	_check(board._death_callbacks.is_empty(), label + "/callback registry cleanup")
	for unit: UnitState in units:
		_check(unit.vitals.died.get_connections().is_empty(), label + "/signal cleanup/%d" % unit.id)

func _extra_cases() -> void:
	for occupied_id: int in [0, 1, 2]:
		for dead_second: bool in [false, true]:
			if occupied_id == 2 and dead_second: continue
			_case("duplicate/%d/dead=%s" % [occupied_id, dead_second], func(b: BattleBoard, u: UnitState) -> void:
				var second := _unit(127)
				second.id = 2
				second.action_resources._owner_unit_id = 2
				second.height = -17
				second.vitals._is_alive = not dead_second
				if dead_second: second.vitals._hp = 0.0
				b._units[2] = second
				b._occupancy.clear()
				if occupied_id > 0: b._occupancy[Vector2i.ZERO] = occupied_id
				u.height = 2147483648
				b._heights[0] = -3
				b._height_half_steps[0] = 1
				b.board_version = 123456)
	_case("partial occupancy different cells", func(b: BattleBoard, _u: UnitState) -> void:
		var second := _unit()
		second.id = 2
		second.cell = Vector2i(1, 0)
		b._units[2] = second)
	_case("slot gaps and non-slot evaluation order", func(_b: BattleBoard, u: UnitState) -> void:
		var stat := _hp(u)
		stat._modifier_slots.assign([7, 2, 4])
		stat._next_modifier_slot = 19)
	_case("external signal subscribers", func(b: BattleBoard, u: UnitState) -> void:
		b.board_changed.connect(func() -> void: pass)
		u.vitals.died.connect(func() -> void: pass))
	_case("unarmored fractional hp above max", func(_b: BattleBoard, u: UnitState) -> void:
		u.vitals._hp = 100.125
		u.vitals._balance = 17.25, 1)
	_case("dead positive hp admitted", func(b: BattleBoard, u: UnitState) -> void:
		u.vitals._is_alive = false
		b._occupancy.clear())
	_case("live zero hp admitted", func(_b: BattleBoard, u: UnitState) -> void: u.vitals._hp = 0.0)
	_case("shared runtime stats and components", func(b: BattleBoard, u: UnitState) -> void:
		var second := _unit(127)
		second.id = 2
		second.action_resources._owner_unit_id = 2
		second.cell = Vector2i(1, 0)
		second.stats = u.stats
		second.vitals = Vitals.new(u.stats, false)
		second.vitals._hp = 10.0
		second.vitals._is_alive = true
		second.armor = u.armor
		second.bleeding = u.bleeding
		second.control = u.control
		second.combat_perks = u.combat_perks
		second.elemental = u.elemental
		b._units[2] = second)
	_freshness_case()

func _freshness_case() -> void:
	var board := BattleBoard.new(3, 2)
	var unit := _unit(127)
	assert(board.add_unit(unit))
	var first := CloneProbe.clone_board(board)
	var first_state := first.board.to_snapshot_dict()
	# Прямые изменения не повышают board_version; revision-only кэш их пропустит.
	unit.vitals._hp = 7.0
	unit.height = 31
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 4.0)
	unit.action_resources._main_left = 0
	board._occupancy.clear()
	var changed := _bytes(board)
	var second := CloneProbe.clone_board(board)
	var expected := SimulationSnapshot.capture_board(board, [])
	_check(second.admission.code == BoardSnapshotResult.Code.OK and second.board != null, "fresh graph admitted")
	if second.board != null:
		_check(SimulationSnapshot.capture_board(second.board, []).snapshot.to_dict() == expected.snapshot.to_dict() and second.board.to_snapshot_dict() != first_state, "fresh graph copied without version change")
		second.board.get_unit_by_id(1).stats.set_base_value(StatTypes.StatType.STRENGTH, 99.0)
		_close_checked(second.board, "fresh/second")
	_check(first.board.to_snapshot_dict() == first_state and _bytes(board) == changed, "prior clone and source detached from later clone")
	_close_checked(first.board, "fresh/first")
	_close_checked(board, "fresh/source")

func _run_exact() -> void:
	var id_before := UnitId.get_counter()
	_admission_cases()
	_extra_cases()
	_check(UnitId.get_counter() == id_before, "matrix UnitId unchanged")
	var args := OS.get_cmdline_user_args()
	if _failed == 0 and not args.has("--verify-only"): _benchmark(args.has("--reverse"))
	print(JSON.stringify({"verification": {"passed": _passed, "failed": _failed, "cases": _cases_checked}}))
	print("BOARD CLONE PROBE RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("BOARD CLONE PROBE DONE")
	quit(0 if _failed == 0 else 1)
