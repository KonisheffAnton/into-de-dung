extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport
var demo: BattleDemo

class ForgedTransit extends Command:
	var actor_id: int
	func _init(id: int = 1) -> void: actor_id = id
	func get_kind() -> StringName: return &"forged_transit"
	func copy_for_queue() -> Command: return ForgedTransit.new(actor_id)
	func validate(_context: ActionContext) -> StringName: return &""
	func execute(_context: ActionContext) -> CommandStepResult:
		return CommandStepResult.applied([{"kind": &"moved", "actor_unit_id": actor_id, "target_unit_id": actor_id, "from_cell": Vector2i(0, 0), "to_cell": Vector2i(2, 0), "movement_kind": &"voluntary", "move_cost": 1.0, "move_before": 5.0, "move_after": 4.0, "transit_path": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]}])

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ALLY TRANSIT: " + label)

func setup(s: BattleDemoSession) -> void:
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_height_steps(Vector2i(x, y), 0)
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.WALL if y == 1 else TerrainType.Type.FLOOR)
	for index in s.units.size(): s.board.move_unit(s.units[index], Vector2i(index, 7))
	s.board.move_unit(s.units[0], Vector2i(0, 0))
	s.board.move_unit(s.units[2], Vector2i(1, 0))
	s.board.move_unit(s.units[4], Vector2i(2, 0))
	s.select_unit(s.units[0].id)

func fixture() -> BattleArmorSession:
	var s := BattleArmorSession.new()
	setup(s)
	return s

func snapshot(s: BattleDemoSession) -> Dictionary:
	return ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()

func _run() -> void:
	_test_paths_and_admission()
	_test_execution_and_copy()
	_test_costs_and_fall()
	_test_faults_and_limits()
	_test_ai_prefix()
	await _test_ui()
	print("ALLY TRANSIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_paths_and_admission() -> void:
	var s := fixture()
	var actor := s.units[0]
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	check(s.path_to(Vector2i(3, 0)) == path, "shortest path crosses two allies")
	var reachable := s.reachable_cells()
	check(reachable.has(Vector2i(3, 0)) and reachable[Vector2i(3, 0)] == 3.0, "range includes cells behind allies at full cost")
	check(not reachable.has(Vector2i(1, 0)) and not reachable.has(Vector2i(2, 0)), "range excludes occupied stopping cells")
	check(s.path_to(Vector2i(1, 0)).is_empty(), "cannot target allied occupied cell")
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict()
	var counters := s.context.simulation_counters()
	var occupied: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var rejected := s._queue.submit(MoveCommand.new(actor.id, occupied, 0), s.context)
	check(rejected.status == ActionReceipt.REJECTED and rejected.reason == &"move/blocked", "explicit occupied endpoint rejected")
	check(snapshot(s) == before and s.context.get_rng().to_dict() == rng and s.context.simulation_counters() == counters, "occupied rejection has no mutation")
	actor.move_points_left = 2.0
	check(not s.reachable_cells().has(Vector2i(3, 0)), "budget cannot finish inside allied chain")
	check(MoveCommand.new(actor.id, path, 0).validate(s.context) == &"move/insufficient_move", "admission charges all transit cells")
	actor.move_points_left = 5.0
	s.units[2].faction = Faction.Type.ENEMY
	check(s.path_to(Vector2i(3, 0)).is_empty() and MoveCommand.new(actor.id, path, 0).validate(s.context) == &"move/blocked", "enemy blocks search and command")
	s.units[2].faction = Faction.Type.NEUTRAL
	check(s.path_to(Vector2i(3, 0)).is_empty(), "non-allied neutral blocks")
	s.units[2].faction = Faction.Type.PLAYER
	s.board.set_height_steps(actor.cell, 4)
	check(s.path_to(Vector2i(3, 0)).is_empty(), "fall cannot land on occupied ally")
	s.board.set_height_steps(actor.cell, 0)
	s.board.set_terrain(Vector2i(1, 0), TerrainType.Type.HAZARD)
	check(s.path_to(Vector2i(3, 0)).is_empty(), "ally cannot bridge a lethal cell")
	s.close()

func _test_execution_and_copy() -> void:
	var s := fixture()
	var actor := s.units[0]
	actor.guard_stance = true
	var before := snapshot(s)
	var definitions: Dictionary = {}
	for owner in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := ItemSimulationSnapshot.capture(s.state, []).snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK, "clone before transit restores")
	var copy_rng := s.context.get_rng().clone()
	var copy_context := s.context.copy_for_simulation(restored.state, copy_rng)
	var command := MoveCommand.new(actor.id, s.path_to(Vector2i(3, 0)), 0)
	var preview := s._queue.copy_for_simulation().submit(command, copy_context)
	check(preview.status == ActionReceipt.APPLIED and snapshot(s) == before, "isolated execution passes without changing live")
	var callback_checks: Array[bool] = []
	var callback := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == actor:
			callback_checks.append(unit.cell == Vector2i(3, 0) and unit.move_points_left == 2.0 and s.board.occupant_at(Vector2i(1, 0)) == s.units[2] and s.board.occupant_at(Vector2i(2, 0)) == s.units[4] and ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.OK)
	s.board.unit_position_changed.connect(callback)
	var actual := s._queue.submit(command, s.context)
	s.board.unit_position_changed.disconnect(callback)
	check(actual.status == ActionReceipt.APPLIED and callback_checks == [true], "one paid board mutation preserves both allies during callback")
	check(actor.cell == Vector2i(3, 0) and actor.move_points_left == 2.0 and actor.action_resources.get_main_left() == 1 and not actor.guard_stance, "transit pays movement only and clears stance")
	check(actual.get_events() == preview.get_events() and actual.get_steps() == preview.get_steps(), "copy/live events and steps parity")
	check(snapshot(s) == ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict(), "copy/live full snapshot parity")
	check(s.context.get_rng().to_dict() == copy_rng.to_dict() and s.context.simulation_counters() == copy_context.simulation_counters(), "copy/live RNG and counters parity")
	check(actual.get_events()[0].get("transit_path") == command.get_path(), "event preserves traversed cells")
	AttackForecast._close(restored.state)
	s.close()

func _test_costs_and_fall() -> void:
	var s := fixture()
	# Подъём через союзника оплачивается; падение на свободном выходе остаётся настоящим hit.
	s.board.set_height_steps(Vector2i(1, 0), 2)
	s.board.set_height_steps(Vector2i(2, 0), 4)
	s.units[2].height = 1
	s.units[4].height = 2
	var actor := s.units[0]
	var armor_before: int = ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(actor.id)))["current"]
	var receipt := s._queue.submit(MoveCommand.new(actor.id, s.path_to(Vector2i(3, 0)), 0), s.context)
	check(receipt.status == ActionReceipt.APPLIED and actor.cell == Vector2i(3, 0) and actor.move_points_left == 0.0, "all ascent costs paid across transit")
	var fall_hit := false
	for event: Dictionary in receipt.get_events():
		if event.get("kind") == &"hit_resolved" and event["source"]["kind"] == &"fall": fall_hit = true
	check(fall_hit and ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(actor.id)))["current"] < armor_before, "free exit fall spends armor through normal resolver")
	s.close()
	s = fixture()
	s.board.set_terrain(Vector2i(3, 0), TerrainType.Type.HAZARD)
	var lethal_path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	receipt = s._queue.submit(MoveCommand.new(s.units[0].id, lethal_path, 0), s.context)
	check(receipt.status == ActionReceipt.INTERRUPTED and receipt.reason == &"move/actor_dead" and not s.units[0].is_alive() and s.board.occupant_at(Vector2i(3, 0)) == null, "lethal exit retains death and occupancy cleanup")
	check(s.board.occupant_at(Vector2i(1, 0)) == s.units[2] and s.board.occupant_at(Vector2i(2, 0)) == s.units[4], "lethal exit leaves allies in place")
	s.close()

func _test_faults_and_limits() -> void:
	var s := fixture()
	s.board.move_unit(s.units[4], Vector2i(2, 7))
	var before := snapshot(s)
	var forged := s._queue.submit(ForgedTransit.new(s.units[0].id), s.context)
	check(forged.status == ActionReceipt.FAULTED and forged.reason == &"malformed_event" and forged.get_events().is_empty(), "forged transit cannot underpay path length")
	check(snapshot(s) == before, "rejected forged event does not move or debit actor")
	s.close()
	s = fixture()
	var callback := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == s.units[0]: s.units[2].faction = Faction.Type.ENEMY
	s.board.unit_position_changed.connect(callback)
	var receipt := s._queue.submit(MoveCommand.new(s.units[0].id, s.path_to(Vector2i(3, 0)), 0), s.context)
	s.board.unit_position_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.FAULTED and s.units[0].cell == Vector2i(3, 0) and s.units[0].move_points_left == 2.0, "hostile callback retains paid prefix and faults")
	check(receipt.get_events().size() == 1 and s.board.occupant_at(Vector2i(1, 0)) == s.units[2], "fault publishes actual transit without corrupting ally occupancy")
	s.close()
	s = fixture()
	var geometry_callback := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == s.units[0]: s.board.set_height_steps(Vector2i(1, 0), 20)
	s.board.unit_position_changed.connect(geometry_callback)
	receipt = s._queue.submit(MoveCommand.new(s.units[0].id, s.path_to(Vector2i(3, 0)), 0), s.context)
	s.board.unit_position_changed.disconnect(geometry_callback)
	check(receipt.status == ActionReceipt.FAULTED and receipt.reason == &"move/invalid_runtime" and s.units[0].move_points_left == 2.0, "geometry callback faults after original segment payment")
	check(receipt.get_events().size() == 1 and receipt.get_events()[0]["move_cost"] == 3.0 and s.units[0].cell == Vector2i(3, 0), "geometry fault preserves real moved prefix at pre-callback cost")
	s.close()
	s = fixture()
	var limited := ActionQueue.new(1, 512, 32)
	receipt = limited.submit(MoveCommand.new(s.units[0].id, s.path_to(Vector2i(4, 0)), 0), s.context)
	check(receipt.status == ActionReceipt.FAULTED and s.units[0].cell == Vector2i(3, 0) and s.units[0].move_points_left == 2.0, "queue limit leaves actor at free paid prefix")
	check(ItemSimulationSnapshot.capture(s.state, []).code == ItemSnapshotResult.Code.OK, "fault prefix still has valid snapshot")
	s.close()

func _test_ai_prefix() -> void:
	var s := fixture()
	var ai := BattleDemoBT.new()
	ai._actor = s.units[0]
	var path := s.path_to(Vector2i(4, 0))
	check(ai._affordable_prefix(s.board, path, 2.0) == [Vector2i(0, 0)], "AI trims unaffordable transit chain")
	check(ai._affordable_prefix(s.board, path, 3.0) == path.slice(0, 4), "AI ends affordable chain on free cell")
	s.close()

func _test_ui() -> void:
	demo = (load("res://tests/fixtures/demo/armor_battle.tscn") as PackedScene).instantiate()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	setup(demo.session)
	# Стена коридора нужна поисковым тестам, но в изометрии закрывает соседний пол.
	for x in demo.session.board.width: demo.session.board.set_terrain(Vector2i(x, 1), TerrainType.Type.FLOOR)
	demo.select_character(demo.session.units[0].id)
	await process_frame
	check(not demo.attack_mode and not demo.summoning_mode and demo.board_view._reachable.has(Vector2i(3, 0)), "selection enables movement behind allies without M")
	await capture("ally-transit-01-range")
	var position := demo.board_view.global_position + demo.board_view.cell_center(Vector2i(3, 0))
	var motion := InputEventMouseMotion.new()
	motion.position = position; motion.global_position = position
	viewport.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await process_frame
	check(demo.session.units[0].cell == Vector2i(3, 0) and demo.session.units[0].move_points_left == 2.0, "real click moves through two allies")
	if demo.session.units[0].cell != Vector2i(3, 0): printerr("UI position=", position, " hover=", demo.board_view.hover_cell, " actor=", demo.session.units[0].cell, " status=", demo._status.text)
	await capture("ally-transit-02-arrived")
	viewport.queue_free()
	await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
