extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: BattleDemo

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CLICK ATTACK: " + label)

func _run() -> void:
	await _adjacent_attack()
	await _approach_and_capture()
	await _safe_hazard_detour()
	await _rejections()
	await _control_and_range()
	await _worker_parity()
	await _ui_click_routes()
	print("CLICK ATTACK RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _session() -> BattleCoreReactionsSession:
	var result := PlayerTurnFixture.create()
	result.state.environment.fires.clear()
	return result

func _place_pair(session: BattleCoreReactionsSession, actor_cell: Vector2i, target_cell: Vector2i) -> void:
	# Освобождаем нижнюю полосу одним набором фигур, чтобы fixture не перекрывал маршрут подхода.
	var reserve_cells: Array[Vector2i] = [Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7)]
	for index: int in range(1, 5):
		check(session.board.move_unit(session.units[index], reserve_cells[index - 1]), "fixture moves reserve %d" % index)
	check(session.board.move_unit(session.units[0], actor_cell), "fixture places actor")
	check(session.board.move_unit(session.units[5], target_cell), "fixture places target")
	check(session.select_unit(session.units[0].id), "fixture selects actor")

func _state(session: BattleCoreReactionsSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(session.state, [])
	var units: Array[Dictionary] = []
	for unit: UnitState in session.units:
		units.append({"id": unit.id, "cell": unit.cell, "alive": unit.is_alive(), "hp": unit.vitals.get_hp(),
			"move": unit.move_points_left, "main": unit.action_resources.get_main_left(),
			"bonus": unit.action_resources.get_bonus_left(), "attacked": unit.has_attacked,
			"stunned": unit.control.stunned_turns if unit.control != null else 0,
			"entangled": unit.control.entangled_turns if unit.control != null else 0})
	return {"capture_code": captured.code, "snapshot": captured.snapshot.to_dict() if captured.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"selected": session.selected_id, "phase": session.phase, "units": units}

func _attack_command(session: BattleCoreReactionsSession, target: UnitState) -> AttackCommand:
	var actor := session.selected_unit()
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())

func _receipt_data(receipt: ActionReceipt) -> Dictionary:
	return {"status": receipt.status, "reason": receipt.reason, "root_id": receipt.root_id,
		"before": receipt.revision_before, "after": receipt.revision_after,
		"steps": receipt.get_steps(), "events": receipt.get_events()}

func _root_kinds(roots: Array[Dictionary]) -> Array[Array]:
	var result: Array[Array] = []
	for root_entry: Dictionary in roots:
		var kinds: Array = []
		for frame: Dictionary in root_entry.get("frames", []):
			var step: Dictionary = frame.get("step", {})
			kinds.append(step.get("kind", &""))
		result.append(kinds)
	return result

func _adjacent_attack() -> void:
	var session := _session()
	_place_pair(session, Vector2i(2, 3), Vector2i(3, 3))
	var actor := session.selected_unit()
	var target := session.units[5]
	var origin := actor.cell
	var move_before := actor.move_points_left
	var main_before: int = actor.action_resources.get_main_left()
	var hp_before := target.vitals.get_hp()
	session.begin_presentation_capture()
	var receipt := session.click_attack(target.id)
	var roots := session.take_presentation_capture()
	check(receipt.status == ActionReceipt.APPLIED and receipt.reason == &"", "adjacent click attack applies")
	var adjacent_steps := receipt.get_steps()
	check(adjacent_steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"attack") and not adjacent_steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"move"), "adjacent click attacks without a movement step")
	check(actor.cell == origin and is_equal_approx(actor.move_points_left, move_before), "adjacent attack spends no movement")
	check(actor.action_resources.get_main_left() == main_before - 1, "adjacent attack spends exactly one main action")
	check(roots.size() == 1 and roots[0].root_id == receipt.root_id and _root_kinds(roots)[0].has(&"attack"), "adjacent action captures one attack root")
	session.close()

func _approach_and_capture() -> void:
	var session := _session()
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	var actor := session.selected_unit()
	var target := session.units[5]
	var attack := _attack_command(session, target)
	var reachable := session.reachable_cells()
	var minimum_cost := INF
	for value: Variant in reachable.values(): minimum_cost = minf(minimum_cost, float(value))
	var eligible_cost := INF
	for cell: Vector2i in reachable:
		if cell == actor.cell or session.board.is_lethal(cell) or session.board.occupant_at(cell) != null: continue
		if AttackReachCheck.inspect_spatial_cells(session.board, cell, actor.faction, target.cell, actor.get_stat(StatTypes.StatType.ATTACK_RANGE)) == &"":
			eligible_cost = minf(eligible_cost, float(reachable[cell]))
	var before_plan := _state(session)
	var allocator_before := UnitId.get_counter()
	var destination := BattleClickAttack.destination_for(session, attack)
	check(destination.x >= 0 and is_equal_approx(float(reachable.get(destination, INF)), eligible_cost), "planner chooses a reachable attack cell at minimum movement cost")
	check(_state(session) == before_plan and UnitId.get_counter() == allocator_before, "candidate planning preserves board snapshot, RNG, counters, resources, selection and ids")
	check(eligible_cost <= actor.move_points_left and minimum_cost >= 0.0, "fixture has an in-budget legal approach")
	var origin := actor.cell
	var movement_before := actor.move_points_left
	var main_before: int = actor.action_resources.get_main_left()
	session.begin_presentation_capture()
	var receipt := session.click_attack(target.id)
	var roots := session.take_presentation_capture()
	var kinds := _root_kinds(roots)
	check(receipt.status == ActionReceipt.APPLIED and actor.cell == destination and actor.cell != origin, "distant click moves actor to planned cell")
	var attack_steps := receipt.get_steps()
	check(actor.move_points_left < movement_before and actor.action_resources.get_main_left() == main_before - 1, "approach spends movement and one main action")
	check(attack_steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"attack" and step.get("status") == ActionReceipt.APPLIED), "approach completes its follow-up attack")
	check(roots.size() == 2 and int(roots[0].root_id) < int(roots[1].root_id) and kinds.size() == 2 and kinds[0].has(&"move") and not kinds[0].has(&"attack") and kinds[1].has(&"attack") and not kinds[1].has(&"move"), "capture records distinct ordered move then attack roots")
	check(receipt.root_id == int(roots[1].root_id), "returned receipt belongs to final attack root")
	session.close()

func _safe_hazard_detour() -> void:
	var session := _session()
	_place_pair(session, Vector2i(0, 2), Vector2i(3, 2))
	var actor := session.selected_unit()
	var target := session.units[5]
	actor.move_points_left = 6.0
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(1, 3), Vector2i(3, 1), Vector2i(3, 3), Vector2i(4, 2)]:
		session.board.set_terrain(cell, TerrainType.Type.WALL)
	session.board.set_terrain(Vector2i(1, 2), TerrainType.Type.HAZARD)
	var attack := _attack_command(session, target)
	var path := BattleClickAttack.path_for(session, attack)
	var has_hazard := path.has(Vector2i(1, 2))
	check(not path.is_empty() and not has_hazard and path.size() - 1 == 6 and path.back() == Vector2i(2, 2), "planner takes the six-step safe route around the lethal shortest route")
	var main_before: int = actor.action_resources.get_main_left()
	var receipt := session.click_attack(target.id)
	var attack_steps := receipt.get_steps()
	check(receipt.status == ActionReceipt.APPLIED and actor.cell == Vector2i(2, 2) and actor.is_alive() and not session.board.is_lethal(actor.cell), "live click follows the safe route and actor survives")
	check(actor.action_resources.get_main_left() == main_before - 1 and attack_steps.any(func(step: Dictionary) -> bool: return step.get("kind") == &"attack" and step.get("status") == ActionReceipt.APPLIED), "safe detour completes the attack and spends one main action")
	session.close()

func _rejected_without_live_prefix(session: BattleCoreReactionsSession, reason: StringName, label: String) -> void:
	var before := _state(session)
	var actor := session.selected_unit()
	var origin := actor.cell
	var receipt := session.click_attack(session.units[5].id)
	check(receipt.status == ActionReceipt.REJECTED and receipt.reason == reason, label + " rejects with expected reason")
	check(_state(session) == before and actor.cell == origin, label + " leaves live runtime and action resources unchanged")
	session.close()

func _rejections() -> void:
	var session := _session()
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	session.selected_unit().move_points_left = 0.0
	_rejected_without_live_prefix(session, &"attack/no_reachable_position", "out-of-budget approach")

	session = _session()
	_place_pair(session, Vector2i(0, 2), Vector2i(2, 2))
	for cell: Vector2i in [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)]:
		session.board.set_terrain(cell, TerrainType.Type.WALL)
	_rejected_without_live_prefix(session, &"attack/no_reachable_position", "blocked attack positions")

	session = _session()
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	session.selected_unit().action_resources.try_spend_main(1)
	_rejected_without_live_prefix(session, &"attack/insufficient_main", "empty main-action budget")

	session = _session()
	_place_pair(session, Vector2i(0, 2), Vector2i(2, 2))
	for y: int in range(session.board.height):
		if y != 2: session.board.set_terrain(Vector2i(1, y), TerrainType.Type.WALL)
	session.board.set_terrain(Vector2i(1, 2), TerrainType.Type.HAZARD)
	_rejected_without_live_prefix(session, &"attack/no_reachable_position", "lethal-only approach")

	session = _session()
	_place_pair(session, Vector2i(2, 2), Vector2i(6, 2))
	var actor := session.selected_unit()
	var opportunist := session.units[1]
	session.board.move_unit(opportunist, Vector2i(2, 3))
	opportunist.control.stunned_turns = 0
	opportunist.combat_perks.definition.tank_reactions = true
	opportunist.combat_perks.mode = CombatPerksState.Mode.OPPORTUNIST
	opportunist.guard_stance = true
	opportunist.action_resources._set_for_refill(opportunist.action_resources.get_main_left(), 1)
	_rejected_without_live_prefix(session, &"attack/no_reachable_position", "opportunist-interrupted approach")

func _control_and_range() -> void:
	var session := _session()
	_place_pair(session, Vector2i(2, 3), Vector2i(3, 3))
	var actor := session.selected_unit()
	var target := session.units[5]
	actor.control.entangled_turns = 1
	var origin := actor.cell
	var adjacent := session.click_attack(target.id)
	check(adjacent.status == ActionReceipt.APPLIED and actor.cell == origin, "entangled actor can still attack an adjacent target")
	session.close()

	session = _session()
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	actor = session.selected_unit()
	target = session.units[5]
	actor.control.entangled_turns = 1
	_rejected_without_live_prefix(session, &"control/entangled", "entangled approach")

	session = _session()
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	actor = session.selected_unit()
	actor.control.stunned_turns = 1
	_rejected_without_live_prefix(session, &"control/stunned", "stunned approach")

func _worker_parity() -> void:
	var initial_id := UnitId.get_counter()
	UnitId.set_counter(initial_id)
	var sync := _session()
	_place_pair(sync, Vector2i(0, 1), Vector2i(5, 1))
	var sync_result := sync.click_attack(sync.units[5].id)
	var expected_receipt := _receipt_data(sync_result)
	var expected_state := _state(sync)
	sync.close()
	UnitId.set_counter(initial_id)
	var threaded := _session()
	_place_pair(threaded, Vector2i(0, 1), Vector2i(5, 1))
	var allocator := UnitId.get_counter()
	var worker := BattleExecutionWorker.new()
	check(BattleExecutionWorker.can_transfer(threaded), "click-attack fixture graph is worker-owned")
	check(worker.start(threaded, &"click_attack", [threaded.units[5].id], true), "worker accepts click_attack request")
	var completed: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 10000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		completed = worker.take_finished()
		if completed.is_empty(): await process_frame
	if completed.is_empty():
		check(false, "click_attack worker finishes before timeout")
		completed = worker.take_finished(true)
	if not completed.is_empty():
		check(_receipt_data(completed.result as ActionReceipt) == expected_receipt, "worker click_attack matches sync receipt/events/roots")
		check(_state(threaded) == expected_state, "worker click_attack matches sync state, RNG, counters and resources")
		check(UnitId.get_counter() == allocator, "worker click_attack preserves global unit-id counter")
	check(not worker.is_started() and worker.take_finished().is_empty(), "worker click_attack reports one completion")
	threaded.close()

func _ui_click_routes() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var scene := load("res://scenes/demo/core_reactions_battle.tscn") as PackedScene
	demo = scene.instantiate() as BattleDemo
	demo.deployment_enabled = false
	viewport.add_child(demo)
	PlayerTurnFixture.enter_player_turn(demo)
	await process_frame
	await process_frame
	demo.set_process(false)
	var session := demo.session as BattleCoreReactionsSession
	_place_pair(session, Vector2i(0, 1), Vector2i(5, 1))
	demo._refresh()
	var actor := session.selected_unit()
	var target := session.units[5]
	var origin := actor.cell
	var main_before := actor.action_resources.get_main_left()
	var point := demo.board_view.global_position + demo.board_view.cell_center(target.cell)
	await _click(point)
	await _wait_for_worker(demo)
	var roots := demo._presentation_roots.duplicate(true)
	var kinds := _root_kinds(roots)
	check(not demo.attack_mode and actor.cell != origin and actor.action_resources.get_main_left() == main_before - 1 and session.last_receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("kind") == &"attacked" and event.get("target_unit_id") == target.id), "real movement-mode enemy click moves then attacks without leaving move mode")
	check(roots.size() == 2 and kinds.size() == 2 and kinds[0].has(&"move") and not kinds[0].has(&"attack") and kinds[1].has(&"attack") and not kinds[1].has(&"move"), "UI captures separate ordered move and attack roots")
	if demo.is_presentation_pending(): demo.skip_presentation()
	await process_frame
	check(not demo.is_execution_pending(), "default click presentation settles")

	demo.reset_demo()
	PlayerTurnFixture.enter_player_turn(demo)
	await process_frame
	await process_frame
	session = demo.session as BattleCoreReactionsSession
	_place_pair(session, Vector2i(2, 3), Vector2i(3, 3))
	session.action_slot_overrides[session.selected_id] = [&"opportunity_guard", &"stunning_strike"]
	demo._refresh()
	var stun_button := _button_for(&"stunning_strike")
	check(stun_button != null, "existing explicit stun ability remains available")
	if stun_button != null:
		await _click(stun_button.global_position + stun_button.size * 0.5)
		check(session.stun_selected and demo.attack_mode, "action-bar stun still enters explicit target mode")
		var stun_target := session.units[5]
		var stun_point := demo.board_view.global_position + demo.board_view.cell_center(stun_target.cell)
		await _click(stun_point)
		await _wait_for_worker(demo)
		check(session.last_receipt.get_events().any(func(event: Dictionary) -> bool: return event.get("attack_definition_id") == &"stunning_strike" and event.get("target_unit_id") == stun_target.id) and session.selected_unit().cell == Vector2i(2, 3), "explicit stun click uses skill attack without approach")
		if demo.is_presentation_pending(): demo.skip_presentation()
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame

func _button_for(action_id: StringName) -> Button:
	var action_bar := demo.get("_action_bar") as BattleActionBar
	for button: Button in action_bar._buttons:
		if button.visible and StringName(button.get_meta("action_id", &"")) == action_id: return button
	return null

func _wait_for_worker(current: BattleDemo) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while current._execution_worker.is_started() and Time.get_ticks_msec() < deadline:
		current._poll_execution()
		await process_frame
	check(not current._execution_worker.is_started(), "UI worker completes")
	check(current.is_presentation_pending(), "UI publishes true presentation capture")

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)
	await process_frame
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await process_frame
