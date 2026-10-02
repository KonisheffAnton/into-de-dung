extends SceneTree

const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL SAFE RETREAT: " + label)

func _session() -> BattleCoreReactionsSession:
	var s := PlayerTurnFixture.create()
	s.state.environment.fires.clear()
	for y: int in s.board.height:
		for x: int in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in 6:
		var unit := s.units[index]
		if unit.is_alive(): check(s.board.move_unit(unit, Vector2i(index, 7)), "park unit")
	return s

func _run() -> void:
	_opportunist()
	_payment_and_preview()
	_refusals()
	print("SAFE RETREAT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _opportunist() -> void:
	var s := _session()
	var tank := s.units[1]
	var mover := s.units[2]
	check(s.board.move_unit(tank, Vector2i(2, 2)) and s.board.move_unit(mover, Vector2i(3, 2)), "place opportunity fixture")
	tank.control = null
	mover.control = null
	check(s._queue.submit(GuardCommand.new(tank.id, s.context.get_revision(), CombatPerksState.Mode.OPPORTUNIST), s.context).status == ActionReceipt.APPLIED, "arm opportunity")
	var path: Array[Vector2i] = [mover.cell, Vector2i(4, 2)]
	var ordinary_command := MoveCommand.new(mover.id, path, s.context.get_revision())
	var ordinary := s._queue.submit(ordinary_command, s.context)
	check(ordinary.status == ActionReceipt.INTERRUPTED and mover.cell == path[0], "ordinary movement still intercepts")
	# Возвращаем заряд и снимаем метку реакции, чтобы проверить отдельный отход.
	tank.action_resources._set_for_refill(tank.action_resources.get_main_left(), 1)
	mover.combat_perks.movement_stopped = false
	mover.action_resources._set_for_refill(2, mover.action_resources.get_bonus_left())
	var retreat_command := MoveCommand.new(mover.id, path, s.context.get_revision(), &"safe_retreat")
	var retreat := s._queue.submit(retreat_command, s.context)
	var moves: Array[Dictionary] = retreat.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"moved")
	check(retreat.status == ActionReceipt.APPLIED and mover.cell == path[-1], "safe retreat completes")
	check(moves.size() == 1 and moves[0].get("movement_kind") == &"safe_retreat" and moves[0].get("main_cost") == 1 and moves[0].get("main_after") == moves[0].get("main_before") - 1, "safe movement event records one main payment")
	check(tank.action_resources.get_bonus_left() == 1 and not mover.combat_perks.movement_stopped, "opportunist suppressed without spending charge or stopping")
	s.close()

func _payment_and_preview() -> void:
	var s := _session()
	var actor := s.units[0]
	check(s.board.move_unit(actor, Vector2i(0, 0)), "place payment actor")
	actor.action_resources._set_for_refill(2, actor.action_resources.get_bonus_left())
	check(s.board.move_unit(actor, Vector2i(0, 1)), "place payment actor")
	var path: Array[Vector2i] = [actor.cell, Vector2i(1, 1), Vector2i(2, 1)]
	var command := MoveCommand.new(actor.id, path, s.context.get_revision(), &"safe_retreat")
	var preview := MoveForecast.build(s.context, s._queue, command)
	check(preview.status == ActionReceipt.APPLIED and actor.cell == path[0] and actor.action_resources.get_main_left() == 2, "preview is isolated and accepts retreat")
	var receipt := s._queue.submit(command, s.context)
	check(receipt.status == preview.status and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, "preview matches live receipt")
	check(actor.cell == path[-1] and actor.action_resources.get_main_left() == 1, "multi-edge route pays main once")
	var move_events: Array[Dictionary] = receipt.get_events().filter(func(event: Dictionary) -> bool: return event.get("kind") == &"moved")
	check(move_events.size() == 2 and move_events[0]["main_cost"] == 1 and move_events[1]["main_cost"] == 0, "later movement segment does not charge main")
	s.close()

func _refusals() -> void:
	var s := _session()
	var actor := s.units[0]
	check(s.board.move_unit(actor, Vector2i(0, 1)), "place refusal actor")
	actor.action_resources._set_for_refill(0, actor.action_resources.get_bonus_left())
	var path: Array[Vector2i] = [actor.cell, Vector2i(1, 1)]
	check(MoveCommand.new(actor.id, path, s.context.get_revision(), &"safe_retreat").validate(s.context) == &"move/insufficient_main", "insufficient main rejected before movement")
	check(MoveCommand.new(actor.id, path, s.context.get_revision(), &"unknown").validate(s.context) == &"move/unknown_movement_kind", "unknown movement kind rejected")
	var safe := MoveCommand.new(actor.id, path, s.context.get_revision(), &"safe_retreat")
	var copied := safe.copy_for_queue() as MoveCommand
	var continuation := MoveCommand._make_continuation(safe, 2, actor)
	check(safe.get_movement_kind() == &"safe_retreat" and copied.get_movement_kind() == &"safe_retreat" and continuation.get_movement_kind() == &"safe_retreat", "kind survives getter, queue copy, and continuation")
	actor.action_resources._set_for_refill(1, actor.action_resources.get_bonus_left())
	var original_move := actor.move_points_left
	actor.move_points_left = 0.0
	check(safe.validate(s.context) == &"move/insufficient_move", "insufficient movement budget rejected")
	actor.move_points_left = original_move
	actor.control = ControlState.new()
	actor.control.stunned_turns = 1
	check(safe.validate(s.context) == &"control/stunned", "control still blocks retreat")
	actor.control = null
	actor.combat_perks = CombatPerksState.new()
	actor.combat_perks.uses_bonus_actions = true
	actor.combat_perks.movement_stopped = true
	check(safe.validate(s.context) == &"perks/movement_stopped", "movement stopped still blocks retreat")
	actor.combat_perks.movement_stopped = false
	var legacy := ActionContext.new(s.state, s.context.get_rng(), ActionEventSink.new(), [], MoveRules.new([actor.id], 0, &"legacy_move_v1"), s.context.get_attack_rules())
	check(MoveCommand.new(actor.id, path, legacy.get_revision(), &"safe_retreat").validate(legacy) == &"move/retreat_unsupported", "legacy movement profile refuses retreat")
	s.close()
