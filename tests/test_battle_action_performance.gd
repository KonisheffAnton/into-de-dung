extends SceneTree

const HERO_BATTLE_SCENE = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const UNIT_COUNT: int = 24
const WIDTH: int = BiomeShowcaseLayout.SIZE.x
const HEIGHT: int = BiomeShowcaseLayout.SIZE.y
const SAMPLE_COUNT: int = 40
const IDLE_FRAME_COUNT: int = 120

var passed: int = 0
var failed: int = 0
var metrics: Dictionary = {}
var demo: HeroHubBattleView
var session: BattleCoreReactionsSession
var stress_actor_id: int = UnitId.NONE
var stress_target_id: int = UnitId.NONE
var stress_move_cell := Vector2i(-1, -1)
var move_preview: MoveForecast
var attack_preview: AttackForecast

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE ACTION PERFORMANCE: " + label)

func _run() -> void:
	var uncapped := OS.get_cmdline_user_args().has("--uncapped")
	if uncapped:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = HERO_BATTLE_SCENE.instantiate() as HeroHubBattleView
	session = _make_stress_session()
	check(session != null, "seeded expedition fixture builds through production factory")
	if session == null:
		demo.free()
		quit(1)
		return
	demo.supplied_session = session
	demo.expedition_battle = true
	root.add_child(demo)
	await process_frame
	check(demo.session == session and demo.board_view != null, "actual HeroHubBattleView owns stress session")
	check(session.board.width == WIDTH and session.board.height == HEIGHT, "expedition showcase dimensions are 24x16")
	check(session.units.size() == UNIT_COUNT and session.living_ids(Faction.Type.PLAYER).size() + session.living_ids(Faction.Type.ENEMY).size() == UNIT_COUNT,
		"fixture contains 24 live registered units")
	check(session.state.deck != null and session.state.abilities != null and not session.actor_loadouts.is_empty()
		and not session.unit_visual_classes.is_empty(), "production expedition retains deck, hero loadouts, and visual classes")
	_check_lifecycle()
	await _measure_idle_frames("startup_frames")
	_measure_refresh_costs()
	for _warmup: int in 10: await process_frame
	await _measure_idle_frames("steady_idle_frames")
	for _warmup: int in 10: await process_frame
	move_preview = session.preview_move(stress_move_cell)
	check(move_preview.status == ActionReceipt.APPLIED, "move preview accepts the live action request")
	for _warmup: int in 10: await process_frame
	await _exercise_action(&"move_to", [stress_move_cell], "movement", stress_move_cell)
	check(session.last_receipt.get_events() == move_preview.events and session.last_receipt.get_steps() == move_preview.steps
		and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == move_preview.snapshot_after,
		"worker movement receipt and final snapshot match isolated preview")
	attack_preview = session.preview_attack(stress_target_id)
	check(attack_preview.status == ActionReceipt.APPLIED, "attack preview accepts the live action request")
	for _warmup: int in 10: await process_frame
	await _exercise_action(&"attack_unit", [stress_target_id], "attack", stress_move_cell)
	check(session.last_receipt.get_events() == attack_preview.events and session.last_receipt.get_steps() == attack_preview.steps
		and ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict() == attack_preview.snapshot_after,
		"worker attack receipt and final snapshot match isolated preview")
	_write_report()
	demo.set_process(false)
	demo.queue_free()
	session.close()
	await process_frame
	print("BATTLE ACTION PERFORMANCE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _measure_idle_frames(metric_name: String) -> void:
	var samples: Array[float] = []
	var trace: Array[Dictionary] = []
	for _frame: int in IDLE_FRAME_COUNT:
		var frame_started: int = Time.get_ticks_usec()
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - frame_started) / 1000.0
		samples.append(elapsed)
		trace.append({"process_frame": Engine.get_process_frames(), "phase": "idle", "ms": elapsed})
	metrics[metric_name] = _summarize(samples)
	metrics[metric_name]["trace"] = trace
	check(samples.size() >= 120, "idle frame window measures at least 120 frames with 24 live units")

func _make_stress_session() -> BattleCoreReactionsSession:
	# Фабрика задаёт настоящие способности, колоду, экипировку и классификацию рисунков экспедиции.
	var hub := HeroHubState.create(9404)
	hub.enable_mage_deck()
	var started := ExpeditionTransitions.apply(hub, "start", {})
	if not started.is_ok(): return null
	var bundle := HeroHubBattleFactory.create(started.profile)
	if bundle.is_empty(): return null
	var value: BattleCoreReactionsSession = bundle.session
	if value.board.width != WIDTH or value.board.height != HEIGHT: value.close(); return null
	var original_units := value.units.duplicate()
	var player_source: UnitState
	var enemy_source: UnitState
	for unit: UnitState in original_units:
		if player_source == null and unit.faction == Faction.Type.PLAYER: player_source = unit
		if enemy_source == null and unit.faction == Faction.Type.ENEMY: enemy_source = unit
	if player_source == null or enemy_source == null: value.close(); return null
	var route := _find_attack_route(value, original_units)
	if route.is_empty(): value.close(); return null
	stress_actor_id = route.actor_id
	stress_move_cell = route.move_cell
	var owners := value.state.get_owners()
	var inventories := value.state.get_inventories()
	var equipment := value.state.get_equipment_facades()
	var target_cell: Vector2i = route.target_cell
	var target_unit := _clone_unit(enemy_source, target_cell, owners, inventories, equipment, value)
	if target_unit == null: value.close(); return null
	stress_target_id = target_unit.id
	while value.units.size() < UNIT_COUNT:
		var exemplar: UnitState = enemy_source
		var cell := _find_free_cell(value, target_cell)
		if cell.x < 0: value.close(); return null
		if _clone_unit(exemplar, cell, owners, inventories, equipment, value) == null: value.close(); return null
	value.state = _replace_state(value.state, owners, inventories, equipment)
	var ids: Array[int] = []
	for unit: UnitState in value.units: ids.append(unit.id)
	var pairs: Array[Dictionary] = []
	for actor_id: int in ids:
		for target_id: int in ids:
			if actor_id != target_id: pairs.append({"actor_unit_id": actor_id, "target_unit_id": target_id})
	var prior_rules := value.context.get_attack_rules()
	value.context = ActionContext.new(value.state, value.context.get_rng(), value.context.get_sink(),
		value.context.get_unsupported_runtime_ids(), MoveRules.new(ids, 1, &"spatial_move_v1"),
		AttackRules.new(ids, pairs, prior_rules.get_definitions()))
	value._enemy_ids = value.living_ids(Faction.Type.ENEMY)
	# Подтверждаем штатную расстановку/руку и используем командный переход к ходу отряда.
	if not value.confirm_mage_deployment() or value.confirm_mage_mulligan([]).status != ActionReceipt.APPLIED or not value.start_battle():
		value.close(); return null
	if not value._refill(Faction.Type.PLAYER): value.close(); return null
	value.selected_id = stress_actor_id
	value.select_unit(stress_actor_id)
	value._setup_revision = value.context.get_revision()
	if value.state.deck != null and not MageDeckRules.references_valid(value.context): value.close(); return null
	return value

func _clone_unit(source: UnitState, cell: Vector2i, owners: Array[ItemOwnerState], inventories: Array[InventoryState],
	equipment: Array[EquipmentState], battle: BattleCoreReactionsSession) -> UnitState:
	var snapshot := source.to_snapshot_dict().duplicate(true)
	var new_id := UnitId.next()
	snapshot.id = new_id
	snapshot.cell_x = cell.x
	snapshot.cell_y = cell.y
	snapshot.debug_name = "Стресс %d" % new_id
	if snapshot.has("action_resources"): snapshot.action_resources.owner_unit_id = new_id
	var clone := UnitState.from_snapshot_dict(snapshot)
	if clone == null or not battle.board.add_unit(clone): return null
	battle.units.append(clone)
	var owner := ItemOwnerState.new(clone)
	owners.append(owner)
	inventories.append(InventoryState.new(owner))
	equipment.append(EquipmentState.new(owner))
	if battle.actor_loadouts.has(source.id):
		battle.actor_loadouts[new_id] = battle.actor_loadouts[source.id].duplicate(true)
		if battle.unit_visual_classes.has(source.id): battle.unit_visual_classes[new_id] = battle.unit_visual_classes[source.id]
	if battle.state.card_effects != null:
		var attack_id: StringName = battle.actor_loadouts[new_id].attack_id if battle.actor_loadouts.has(new_id) else &"demo_strike"
		battle.state.card_effects.ordinary_attacks.append({"unit_id": new_id, "attack_id": String(attack_id)})
	return clone

func _replace_state(old: ItemSimulationState, owners: Array[ItemOwnerState], inventories: Array[InventoryState],
	equipment: Array[EquipmentState]) -> ItemSimulationState:
	var replacement := ItemSimulationState.new(old.get_board(), owners, inventories, equipment)
	replacement.abilities = old.abilities
	replacement.environment = old.environment
	replacement.artifacts = old.artifacts
	replacement.deck = old.deck
	replacement.card_effects = old.card_effects
	return replacement

func _find_attack_route(battle: BattleCoreReactionsSession, units: Array[UnitState]) -> Dictionary:
	for actor: UnitState in units:
		if actor.faction != Faction.Type.PLAYER or not battle.actor_loadouts.has(actor.id): continue
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var move_cell := actor.cell + offset
			var target_cell := actor.cell + offset * 2
			if _valid_free_floor(battle.board, move_cell) and _valid_free_floor(battle.board, target_cell) \
				and absi(battle.board.get_height_steps(move_cell) - actor.height) <= 1 \
				and absi(battle.board.get_height_steps(target_cell) - battle.board.get_height_steps(move_cell)) <= 1 \
				and battle.state.environment.fire_at(move_cell).is_empty() and battle.state.environment.fire_at(target_cell).is_empty():
				return {"actor_id": actor.id, "move_cell": move_cell, "target_cell": target_cell}
	return {}

func _find_free_cell(battle: BattleCoreReactionsSession, excluded: Vector2i) -> Vector2i:
	var board := battle.board
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			if cell != excluded and _valid_free_floor(board, cell) and battle.state.environment.fire_at(cell).is_empty(): return cell
	return Vector2i(-1, -1)

func _valid_free_floor(board: BattleBoard, cell: Vector2i) -> bool:
	return board.is_in_bounds(cell) and board.get_terrain(cell) == TerrainType.Type.FLOOR and not board.is_lethal(cell) \
		and not board.is_occupied(cell)

func _check_lifecycle() -> void:
	var board := demo.board_view
	var first_ids := _unit_instance_ids(board)
	var first_counts := board.visual_lifecycle_counts()
	board.refresh()
	board.refresh()
	check(_unit_instance_ids(board) == first_ids and board.visual_lifecycle_counts() == first_counts,
		"24 unit visual instance IDs and lifecycle counters survive repeated refresh")

func _unit_instance_ids(board: BattleDemoBoard) -> Dictionary:
	var ids: Dictionary = {}
	for id: int in board._unit_visuals: ids[id] = board._unit_visuals[id].get_instance_id()
	return ids

func _measure_refresh_costs() -> void:
	var board := demo.board_view
	var refresh_mage: Array[float] = []
	var board_refresh: Array[float] = []
	var rebuild: Array[float] = []
	var can_transfer: Array[float] = []
	var capture: Array[float] = []
	var full_refresh: Array[float] = []
	for _sample: int in SAMPLE_COUNT:
		refresh_mage.append(_time_call(func() -> void: demo._refresh_mage()))
		board_refresh.append(_time_call(func() -> void: board.refresh()))
		rebuild.append(_time_call(func() -> void: board._rebuild_visuals()))
		can_transfer.append(_time_call(func() -> void: BattleExecutionWorker.can_transfer(session)))
		capture.append(_time_call(func() -> void: ActionPresentationState.capture(session.state)))
		full_refresh.append(_time_call(func() -> void: demo._refresh()))
	# Метрики операций хранятся отдельно: вложенные refresh/capture времена нельзя складывать.
	metrics["scenario"] = "HeroHubBattleView expedition showcase stress"
	metrics["board"] = {"width": WIDTH, "height": HEIGHT, "live_units": UNIT_COUNT}
	metrics["sample_count"] = SAMPLE_COUNT
	metrics["operations_ms"] = {
		"refresh_mage": _summarize(refresh_mage), "board_refresh": _summarize(board_refresh),
		"board_rebuild_visuals": _summarize(rebuild), "worker_can_transfer": _summarize(can_transfer),
		"presentation_capture": _summarize(capture), "demo_full_refresh": _summarize(full_refresh),
	}
	metrics["actions"] = {}
	metrics["runtime"] = _runtime_metadata()

func _runtime_metadata() -> Dictionary:
	var uncapped := OS.get_cmdline_user_args().has("--uncapped")
	return {
		"uncapped_requested": uncapped,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine_version": Engine.get_version_info(),
	}

func _time_call(callback: Callable) -> float:
	var started: int = Time.get_ticks_usec()
	callback.call()
	return float(Time.get_ticks_usec() - started) / 1000.0

func _summarize(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	var over_17_5: int = 0
	var over_20: int = 0
	var over_25: int = 0
	var over_50: int = 0
	for sample: float in ordered:
		if sample > 17.5: over_17_5 += 1
		if sample > 20.0: over_20 += 1
		if sample > 25.0: over_25 += 1
		if sample > 50.0: over_50 += 1
	var middle := ordered.size() / 2
	return {"median_ms": _median(ordered), "p95_ms": ordered[ceili(float(ordered.size()) * 0.95) - 1],
		"p99_ms": ordered[ceili(float(ordered.size()) * 0.99) - 1], "max_ms": ordered.back(),
		"over_17_5ms": over_17_5, "over_20ms": over_20, "over_25ms": over_25,
		"over_50ms": over_50, "samples": ordered.size()}

func _median(sorted: Array[float]) -> float:
	var middle := sorted.size() / 2
	return (sorted[middle - 1] + sorted[middle]) * 0.5 if sorted.size() % 2 == 0 else sorted[middle]

func _exercise_action(method: StringName, args: Array, label: String, expected_cell: Vector2i) -> void:
	var board := demo.board_view
	var ids_before := _unit_instance_ids(board)
	var attack_target := session.board.get_unit_by_id(stress_target_id)
	var attack_target_hp: float = attack_target.vitals.get_hp() if attack_target != null else 0.0
	var samples: Array[float] = []
	var started := Time.get_ticks_msec()
	var requested := false
	var accepted := false
	var dispatch_ms := 0.0
	var trace: Array[Dictionary] = []
	var deadline := started + 15000
	while Time.get_ticks_msec() < deadline and (not requested or demo.is_execution_pending()):
		var frame_started: int = Time.get_ticks_usec()
		var phase := "worker" if demo._execution_worker.is_started() else "presentation" if demo.is_presentation_pending() else "dispatch"
		if not requested:
			requested = true
			demo._execute_live(method, args)
			dispatch_ms = float(Time.get_ticks_usec() - frame_started) / 1000.0
			accepted = demo.is_execution_pending()
		await process_frame
		var frame_ms := float(Time.get_ticks_usec() - frame_started) / 1000.0
		samples.append(frame_ms)
		trace.append({"process_frame": Engine.get_process_frames(), "phase": phase, "ms": frame_ms,
			"presentation_index": demo._presentation_player._index})
		if accepted and not demo.is_execution_pending(): break
	check(accepted, label + " entered worker/presentation execution")
	check(not demo._execution_worker.is_started() and not demo.is_presentation_pending(), label + " worker and presentation completed")
	check(session.units[0].cell == expected_cell, label + " mutated the real live unit through worker")
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.APPLIED,
		label + " produced an applied action receipt")
	if label == "attack":
		var live_target := session.board.get_unit_by_id(stress_target_id)
		check(live_target != null and live_target.vitals.get_hp() < attack_target_hp, "attack reduced its live target HP")
	check(_unit_instance_ids(board) == ids_before, label + " retained all unit lifecycle instance IDs")
	metrics.actions[label] = _summarize(samples)
	metrics.actions[label]["dispatch_ms"] = dispatch_ms
	metrics.actions[label]["trace"] = trace

func _write_report() -> void:
	var report := {"passed": passed, "failed": failed, "diagnostic_only": true, "measurements": metrics}
	var file := FileAccess.open("user://battle-action-performance.json", FileAccess.WRITE)
	if file == null:
		check(false, "machine-readable JSON report opens in user data directory")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
