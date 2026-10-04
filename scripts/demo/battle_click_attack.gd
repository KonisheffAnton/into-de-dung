extends RefCounted
class_name BattleClickAttack

## Удобство ввода: две прежние команды, с теми же очередью и ресурсами.
static func execute(session: BattleTacticalSession, target_id: int) -> ActionReceipt:
	if not session.can_player_act(): return session._reject(&"battle/input_locked")
	var actor := session.selected_unit()
	var target := session.board.get_unit_by_id(target_id)
	if actor == null or target == null or not target.is_alive() or not actor.is_hostile_to(target):
		return session._reject(&"attack/invalid_target")
	if actor.action_resources == null or actor.action_resources.get_main_left() < 1:
		return session._reject(&"attack/insufficient_main")
	var prepared := session.prepare_attack_forecast(target_id)
	if prepared.reason != &"": return session._reject(prepared.reason)
	var attack := prepared.command as AttackCommand
	if attack == null: return session._reject(&"attack/invalid_target")
	if attack.validate(session.context) == &"": return session.attack_unit(target_id)
	var movement_reason := ControlRules.action_reason(actor, true)
	if movement_reason != &"": return session._reject(movement_reason)
	var path := path_for(session, attack)
	if path.is_empty(): return session._reject(&"attack/no_reachable_position")
	var destination: Vector2i = path.back()
	var actor_id := actor.id
	var movement := session._submit(MoveCommand.new(actor.id, path, session.context.get_revision()))
	# Прерванный ход, смерть, fault и сдвиг не должны превращаться во второй приказ.
	if movement.status != ActionReceipt.APPLIED or not session.can_player_act(): return movement
	actor = session.selected_unit(); target = session.board.get_unit_by_id(target_id)
	if actor == null or actor.id != actor_id or actor.cell != destination or target == null or not target.is_alive(): return movement
	return session.attack_unit(target_id)

static func destination_for(session: BattleTacticalSession, attack: AttackCommand) -> Vector2i:
	var path := path_for(session, attack)
	return Vector2i(-1, -1) if path.is_empty() else path.back()

static func path_for(session: BattleTacticalSession, attack: AttackCommand) -> Array[Vector2i]:
	var actor := session.selected_unit()
	var target := session.board.get_unit_by_id(attack.get_target_unit_id())
	var provider := session.board.make_spatial_data_provider(actor)
	var original_walkable := provider.is_walkable
	# Нельзя выбирать короткую дорогу через провал, если есть доступный обход.
	provider.is_walkable = func(cell: Vector2i) -> bool: return not session.board.is_lethal(cell) and bool(original_walkable.call(cell))
	var finder := GridPathfinder.new()
	finder.configure(session.board.get_bounds(), provider, 1, &"spatial_move_v1")
	var reachable := finder.get_reachable_cells(actor.cell, actor.move_points_left)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in reachable:
		if cell == actor.cell or session.board.is_lethal(cell) or session.board.occupant_at(cell) != null: continue
		if AttackReachCheck.inspect_spatial_cells(session.board, cell, actor.faction, target.cell, actor.get_stat(StatTypes.StatType.ATTACK_RANGE)) == &"": cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if reachable[a] != reachable[b]: return reachable[a] < reachable[b]
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for cell: Vector2i in cells:
		var path := finder.find_path(actor.cell, cell)
		if _can_finish_approach(session, attack, path): return path
	return []

static func _can_finish_approach(session: BattleTacticalSession, attack: AttackCommand, path: Array[Vector2i]) -> bool:
	# Настоящее движение на изолированной копии учитывает шипы, реакции и остановку.
	if path.size() < 2: return false
	var cell: Vector2i = path.back()
	var command := MoveCommand.new(attack.get_actor_unit_id(), path, session.context.get_revision())
	var prepared := ForecastSimulation.prepare(session.context, session._queue, command)
	if prepared.reason != &"": return false
	var restored := prepared.snapshot.instantiate(prepared.definitions)
	if restored.code != ItemSnapshotResult.Code.OK: return false
	var context := prepared.context
	context._state = restored.state
	var movement := prepared.queue.submit(prepared.command, context)
	var actor := restored.state.get_board().get_unit_by_id(attack.get_actor_unit_id())
	var target := restored.state.get_board().get_unit_by_id(attack.get_target_unit_id())
	var allowed := false
	if movement.status == ActionReceipt.APPLIED and actor != null and actor.is_alive() and actor.cell == cell and target != null and target.is_alive():
		var after_move := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, attack.get_attack_definition_id(), context.get_revision())
		allowed = after_move.validate(context) == &""
	ForecastSimulation.close(restored.state)
	return allowed
