extends SceneTree

## Изолированный эксперимент, не production clone API. Прямой клон пока покрывает
## только доску; время полного снимка предметов измеряется отдельно.
const SAMPLES := 21

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--clone-breakdown"):
		call_deferred("run_breakdown", args.has("--reverse"))
	else:
		call_deferred("run")

func summary(values: Array[float]) -> Dictionary:
	values.sort()
	return {"count": values.size(), "median_ms": values[values.size() / 2], "p95_ms": values[ceili(values.size() * 0.95) - 1], "max_ms": values[-1]}

func measure(label: String, operation: Callable) -> void:
	for i: int in 3: operation.call()
	var values: Array[float] = []
	for i: int in SAMPLES:
		var start := Time.get_ticks_usec()
		operation.call()
		values.append((Time.get_ticks_usec() - start) / 1000.0)
	print(JSON.stringify({"label": label, "timing": summary(values)}))

func direct_unit(source: UnitState) -> UnitState:
	var unit := UnitState.new()
	unit.id = source.id
	unit.faction = source.faction
	unit.cell = source.cell
	unit.height = source.height
	unit.debug_name = source.debug_name
	unit.move_points_left = source.move_points_left
	unit.has_attacked = source.has_attacked
	unit.guard_stance = source.guard_stance
	unit.stats = StatsBag.new()
	for key: int in source.stats._stats:
		var original: Stat = source.stats._stats[key]
		var stat := Stat.new(original.base_value)
		stat._next_modifier_slot = original._next_modifier_slot
		stat._modifier_slots.assign(original._modifier_slots)
		for modifier: StatModifier in original._modifiers:
			stat._modifiers.append(StatModifier.new(modifier.source_id, modifier.operation, modifier.value))
		unit.stats._stats[key] = stat
	unit.vitals = Vitals.from_dict(source.vitals.to_dict(), unit.stats)
	if source.action_resources != null: unit.action_resources = ActionResources.from_snapshot_dict(source.action_resources.to_snapshot_dict(), unit.id)
	if source.armor != null: unit.armor = ArmorState.from_dict(source.armor.to_dict())
	if source.bleeding != null: unit.bleeding = BleedingState.from_dict(source.bleeding.to_dict())
	if source.control != null: unit.control = ControlState.from_dict(source.control.to_dict())
	if source.combat_perks != null: unit.combat_perks = CombatPerksState.from_dict(source.combat_perks.to_dict())
	if source.elemental != null: unit.elemental = ElementalState.from_dict(source.elemental.to_dict())
	return unit

func direct_board(source: BattleBoard) -> BattleBoard:
	var board := BattleBoard.new(source.width, source.height)
	board._heights = source._heights.duplicate()
	board._height_half_steps = source._height_half_steps.duplicate()
	board._terrain = source._terrain.duplicate()
	for unit: UnitState in source.get_all_units():
		assert(board.add_unit(direct_unit(unit)))
	board.board_version = source.board_version
	return board

func run() -> void:
	var hub := HeroHubState.create(73191, 2)
	hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub, "start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	var session: BattleCoreReactionsSession = bundle.session
	var state := session.state
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var unit_id_before := UnitId.get_counter()
	var before := ItemSimulationSnapshot.capture(state, []).snapshot.to_dict()
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = owner._definitions[id].duplicate(true)
	var saved := ItemSimulationSnapshot.capture(state, []).snapshot
	var fingerprint := saved.fingerprint()
	measure("production_capture", func() -> void:
		assert(ItemSimulationSnapshot.capture(state, []).code == ItemSnapshotResult.Code.OK))
	measure("production_instantiate", func() -> void:
		var result := saved.instantiate(definitions)
		assert(result.code == ItemSnapshotResult.Code.OK)
		ForecastSimulation.close(result.state))
	measure("production_capture_and_instantiate", func() -> void:
		var capture := ItemSimulationSnapshot.capture(state, [])
		var result := capture.snapshot.instantiate(definitions)
		assert(result.code == ItemSnapshotResult.Code.OK)
		ForecastSimulation.close(result.state))
	# Сравнение полного DTO для проверки кэша само требует свежего capture.
	measure("production_fingerprint_guard", func() -> void:
		assert(ItemSimulationSnapshot.capture(state, []).snapshot.fingerprint() == fingerprint))
	for count: int in [6, 24, 96]:
		var board := BattleBoard.new(16, 8)
		for i: int in count:
			var unit := direct_unit(session.units[i % session.units.size()])
			unit.id = i + 1
			unit.action_resources._owner_unit_id = unit.id
			unit.cell = Vector2i(i % 16, i / 16)
			assert(board.add_unit(unit))
		var expected := SimulationSnapshot.capture_board(board, []).snapshot
		assert(expected != null)
		var direct := direct_board(board)
		assert(SimulationSnapshot.capture_board(direct, []).snapshot.to_dict() == expected.to_dict())
		var first := direct.get_unit_by_id(1)
		first.stats.set_base_value(StatTypes.StatType.STRENGTH, 999.0)
		first.vitals.set_hp(1.0)
		assert(SimulationSnapshot.capture_board(board, []).snapshot.to_dict() == expected.to_dict())
		direct.resize(0, 0)
		measure("board_%d_capture_restore" % count, func() -> void:
			var capture := SimulationSnapshot.capture_board(board, [])
			var clone := capture.snapshot.instantiate_board()
			assert(clone != null)
			clone.resize(0, 0))
		measure("board_%d_audited_direct_clone" % count, func() -> void:
			# Стоимость допуска включена: сравнение не выдаёт unchecked copy за ускорение.
			assert(SimulationSnapshot.capture_board(board, []).code == BoardSnapshotResult.Code.OK)
			var clone := direct_board(board)
			clone.resize(0, 0))
		board.resize(0, 0)
	assert(ItemSimulationSnapshot.capture(state, []).snapshot.to_dict() == before)
	assert(session.context.get_rng().to_dict() == rng_before)
	assert(session.context.simulation_counters() == counters_before)
	assert(UnitId.get_counter() == unit_id_before)
	session.close()
	print("SNAPSHOT STRATEGIES DONE")
	quit()

func _make_fixture(session: BattleCoreReactionsSession, count: int) -> BattleBoard:
	var board := BattleBoard.new(16, 8)
	for i: int in count:
		var unit := direct_unit(session.units[i % session.units.size()])
		unit.id = i + 1
		unit.action_resources._owner_unit_id = unit.id
		unit.cell = Vector2i(i % 16, i / 16)
		assert(board.add_unit(unit))
	return board

func _capture_restore_sample(board: BattleBoard) -> Dictionary:
	var start := Time.get_ticks_usec()
	var capture := SimulationSnapshot.capture_board(board, [])
	var capture_us := Time.get_ticks_usec() - start
	assert(capture.code == BoardSnapshotResult.Code.OK)
	start = Time.get_ticks_usec()
	var clone := capture.snapshot.instantiate_board()
	assert(clone != null)
	var build_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	clone.resize(0, 0)
	var cleanup_us := Time.get_ticks_usec() - start
	return {"capture_us": capture_us, "build_us": build_us, "cleanup_us": cleanup_us}

func _audited_clone_sample(board: BattleBoard) -> Dictionary:
	var start := Time.get_ticks_usec()
	assert(SimulationSnapshot.capture_board(board, []).code == BoardSnapshotResult.Code.OK)
	var capture_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var clone := direct_board(board)
	var build_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	clone.resize(0, 0)
	var cleanup_us := Time.get_ticks_usec() - start
	return {"capture_us": capture_us, "build_us": build_us, "cleanup_us": cleanup_us}

func _verify_and_close_clone(clone: BattleBoard, source: BattleBoard, expected: Dictionary) -> void:
	# Проверки удерживают ссылки и меняют стоимость освобождения: они вынесены из замера.
	assert(SimulationSnapshot.capture_board(clone, []).snapshot.to_dict() == expected)
	var units := clone.get_all_units()
	assert(clone._death_callbacks.size() == units.size())
	for unit: UnitState in units:
		assert(unit != source.get_unit_by_id(unit.id))
		assert(unit.vitals._stats == unit.stats)
		assert(unit.vitals.died.get_connections().size() == 1)
	var first := clone.get_unit_by_id(1)
	first.stats.set_base_value(StatTypes.StatType.STRENGTH, 999.0)
	first.vitals.set_hp(1.0)
	assert(SimulationSnapshot.capture_board(source, []).snapshot.to_dict() == expected)
	clone.resize(0, 0)
	assert(clone._death_callbacks.is_empty())
	for unit: UnitState in units:
		assert(unit.vitals.died.get_connections().is_empty())

func _direct_parts_sample(source: BattleBoard, verify: bool = false) -> Dictionary:
	# Отдельная проба локализует build; её таймеры в цикле не входят в парное сравнение.
	var start := Time.get_ticks_usec()
	var board := BattleBoard.new(source.width, source.height)
	board._heights = source._heights.duplicate()
	board._height_half_steps = source._height_half_steps.duplicate()
	board._terrain = source._terrain.duplicate()
	var setup_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var units := source.get_all_units()
	var enumeration_us := Time.get_ticks_usec() - start
	var units_us: int = 0
	var add_us: int = 0
	for unit: UnitState in units:
		start = Time.get_ticks_usec()
		var copied := direct_unit(unit)
		units_us += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		assert(board.add_unit(copied))
		add_us += Time.get_ticks_usec() - start
	board.board_version = source.board_version
	if verify:
		_verify_and_close_clone(board, source, SimulationSnapshot.capture_board(source, []).snapshot.to_dict())
	start = Time.get_ticks_usec()
	board.resize(0, 0)
	var cleanup_us := Time.get_ticks_usec() - start
	return {"setup_us": setup_us, "enumeration_us": enumeration_us, "units_us": units_us, "add_us": add_us, "cleanup_us": cleanup_us}

func _record_sample(label: String, count: int, order: int, sample: int, board: BattleBoard) -> Dictionary:
	var start := Time.get_ticks_usec()
	var phases := _capture_restore_sample(board) if label == "capture_restore" else _audited_clone_sample(board)
	var total_us := Time.get_ticks_usec() - start
	var record := {"label": label, "count": count, "order": order, "sample": sample, "total_us": total_us}
	for key: String in phases:
		record[key] = phases[key]
	return record

func _print_breakdown_summary(label: String, count: int, records: Array[Dictionary]) -> void:
	var totals: Array[float] = []
	for record: Dictionary in records:
		totals.append(float(record["total_us"]) / 1000.0)
	print(JSON.stringify({"label": label, "count": count, "timing": summary(totals)}))

func run_breakdown(reverse: bool = false) -> void:
	var hub := HeroHubState.create(73191, 2)
	hub.enable_mage_deck()
	hub = ExpeditionTransitions.apply(hub, "start").profile
	var bundle := HeroHubBattleFactory.create(hub)
	var session: BattleCoreReactionsSession = bundle.session
	var state := session.state
	var rng_before := session.context.get_rng().to_dict()
	var counters_before := session.context.simulation_counters()
	var unit_id_before := UnitId.get_counter()
	var state_before := ItemSimulationSnapshot.capture(state, []).snapshot.to_dict()
	var counts: Array[int] = [6, 24, 96]
	if reverse: counts.reverse()
	for count: int in counts:
		var board := _make_fixture(session, count)
		var expected := SimulationSnapshot.capture_board(board, []).snapshot
		assert(expected != null)
		_verify_and_close_clone(direct_board(board), board, expected.to_dict())
		_verify_and_close_clone(expected.instantiate_board(), board, expected.to_dict())
		_direct_parts_sample(board, true)
		# Чередование пар ниже уменьшает связь стратегии с изменениями нагрузки процесса.
		for label: String in ["capture_restore", "audited_direct_clone"]:
			for warmup: int in 3:
				if label == "capture_restore": _capture_restore_sample(board)
				else: _audited_clone_sample(board)
		var capture_records: Array[Dictionary] = []
		var direct_records: Array[Dictionary] = []
		for sample: int in SAMPLES:
			var capture_first := (sample + int(reverse)) % 2 == 0
			for order_index: int in 2:
				var is_capture := (order_index == 0) == capture_first
				var label := "capture_restore" if is_capture else "audited_direct_clone"
				var record := _record_sample(label, count, order_index, sample, board)
				if label == "capture_restore": capture_records.append(record)
				else: direct_records.append(record)
		for record: Dictionary in capture_records + direct_records:
			print(JSON.stringify(record))
		_print_breakdown_summary("capture_restore", count, capture_records)
		_print_breakdown_summary("audited_direct_clone", count, direct_records)
		for warmup: int in 3: _direct_parts_sample(board)
		var parts_records: Array[Dictionary] = []
		for sample: int in SAMPLES:
			var start := Time.get_ticks_usec()
			var parts := _direct_parts_sample(board)
			parts["total_us"] = Time.get_ticks_usec() - start
			parts["label"] = "direct_parts"
			parts["count"] = count
			parts["sample"] = sample
			parts_records.append(parts)
		for parts: Dictionary in parts_records: print(JSON.stringify(parts))
		assert(SimulationSnapshot.capture_board(board, []).snapshot.to_dict() == expected.to_dict())
		board.resize(0, 0)
		assert(board._death_callbacks.is_empty())
	assert(ItemSimulationSnapshot.capture(state, []).snapshot.to_dict() == state_before)
	assert(session.context.get_rng().to_dict() == rng_before)
	assert(session.context.simulation_counters() == counters_before)
	assert(UnitId.get_counter() == unit_id_before)
	session.close()
	print("SNAPSHOT CLONE BREAKDOWN DONE")
	quit()
