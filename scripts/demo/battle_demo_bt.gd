extends RefCounted
class_name BattleDemoBT

## Малое дерево выбора держит порядок поведения явным, а команды остаются единственным исполнителем.
## Эвристика толчка намеренно не является полным preview: она только приоритизирует цель.

var _nodes: Array[Callable] = []
var _session: BattleDemoSession
var _actor: UnitState


func _init() -> void:
	_nodes = [_reaction_guard, _attack, _summon, _advance, _wait]

func _reaction_guard() -> BattleAIIntent:
	if _session == null or not MeleeThreat.has_tank(_actor) or not _actor.can_attack(): return null
	# Чередование с обычным BT не оставляет двух последних защитников в вечной стойке.
	if _session is BattleTacticalSession and (_session as BattleTacticalSession).round_number % 2 == 0: return null
	var ally: UnitState = null
	var enemy_near := false
	for unit: UnitState in _session.board.get_alive_units():
		if _actor.is_hostile_to(unit) and MeleeThreat.threatens(_session.context, _actor, unit): enemy_near = true
		if MeleeThreat.cover_eligible(_session.context, _actor, unit) and (ally == null or unit.id < ally.id): ally = unit
	if ally == null and not enemy_near: return null
	var mode := CombatPerksState.Mode.COVER if ally != null else CombatPerksState.Mode.OPPORTUNIST
	var target_id := ally.id if ally != null else 0
	if GuardCommand.new(_actor.id, _session.context.get_revision(), mode, target_id).validate(_session.context) != &"": return null
	var result := BattleAIIntent.new()
	result.kind = BattleAIIntent.Kind.GUARD
	result.actor_id = _actor.id
	result.target_id = target_id
	result.reaction_mode = mode
	return result


func decide(session: BattleDemoSession, actor: UnitState) -> BattleAIIntent:
	_session = session
	_actor = actor
	for node in _nodes:
		var candidate: BattleAIIntent = node.call()
		if candidate != null:
			_session = null
			_actor = null
			return candidate
	_session = null
	_actor = null
	return BattleAIIntent.new()


func _attack() -> BattleAIIntent:
	if _session == null or _actor == null or not _actor.can_attack():
		return null
	var context := _session.context
	if context == null or context.is_busy() or context.is_faulted():
		return null
	var board := _session.board
	var valid: Array[Dictionary] = []
	for target in board.get_alive_units():
		if target == null or not _actor.is_hostile_to(target):
			continue
		var definition_id: StringName = &"demo_strike"
		# BT выбирает способность владельца; gate и последствия остаются у команды.
		if ControlRules.has_stunning_strike(_actor) and target.control != null and target.control.stunned_turns == 0 and not ControlRules.immune_to(target, &"stun") and context.get_attack_rules().get_definition(&"stunning_strike") != null:
			definition_id = &"stunning_strike"
		var command := AttackCommand.new(_actor.id, target.id, _actor.cell, target.cell, definition_id, context.get_revision())
		if command.validate(context) != &"":
			continue
		valid.append({"target": target, "push": _push_toward_void(target), "hp": target.vitals.get_hp(), "definition_id": definition_id})
	if valid.is_empty():
		return null
	valid.sort_custom(_attack_less)
	var chosen: UnitState = valid[0]["target"]
	var result := BattleAIIntent.new()
	result.kind = BattleAIIntent.Kind.ATTACK
	result.actor_id = _actor.id
	result.target_id = chosen.id
	result.attack_definition_id = valid[0]["definition_id"]
	return result


func _attack_less(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["push"]) != bool(b["push"]):
		return bool(a["push"])
	if float(a["hp"]) != float(b["hp"]):
		return float(a["hp"]) < float(b["hp"])
	var ac: UnitState = a["target"]
	var bc: UnitState = b["target"]
	if ac.cell.y != bc.cell.y:
		return ac.cell.y < bc.cell.y
	if ac.cell.x != bc.cell.x:
		return ac.cell.x < bc.cell.x
	return ac.id < bc.id


func _push_toward_void(target: UnitState) -> bool:
	var balance := target.vitals.get_balance() + _actor.get_stat(StatTypes.StatType.IMPACT_POWER)
	var maximum := target.get_stat(StatTypes.StatType.BALANCE_MAX)
	if not is_finite(balance) or not is_finite(maximum) or balance < maximum:
		return false
	var direction := target.cell - _actor.cell
	if direction.x != 0:
		direction = Vector2i(signi(direction.x), 0)
	else:
		direction = Vector2i(0, signi(direction.y))
	var landing := target.cell + direction
	return not _session.board.is_in_bounds(landing) or _session.board.get_terrain(landing) == TerrainType.Type.VOID


func _advance() -> BattleAIIntent:
	if _session == null or _actor == null or not _actor.can_attack():
		return null
	var context := _session.context
	var board := _session.board
	if context == null or board == null or context.is_busy() or context.is_faulted() or _actor.move_points_left <= 0.0:
		return null
	var finder := GridPathfinder.new()
	finder.configure(board.get_bounds(), board.make_spatial_data_provider(_actor), 1, &"spatial_move_v1")
	var candidates: Array[Dictionary] = []
	for target in board.get_alive_units():
		if target == null or not _actor.is_hostile_to(target):
			continue
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var goal: Vector2i = target.cell + offset
			if not board.is_in_bounds(goal) or board.occupant_at(goal) != null or not _attack_height_eligible(board, goal, target.cell):
				continue
			var full_path := finder.find_path(_actor.cell, goal)
			if full_path.size() < 2 or _has_large_drop(board, full_path):
				continue
			var affordable := _affordable_prefix(board, full_path, _actor.move_points_left)
			if affordable.size() < 2:
				continue
			var endpoint: Vector2i = affordable[affordable.size() - 1]
			# Прогресс измеряется по найденному пути: обход стены может временно удалять от цели.
			if endpoint == _actor.cell: continue
			candidates.append({"path": affordable, "cost": _path_cost(board, full_path), "goal": goal, "target_id": target.id})
	if candidates.is_empty():
		return null
	candidates.sort_custom(_advance_less)
	var chosen: Array[Vector2i] = candidates[0]["path"]
	var command := MoveCommand.new(_actor.id, chosen, context.get_revision())
	if command.validate(context) != &"":
		return null
	var result := BattleAIIntent.new()
	result.kind = BattleAIIntent.Kind.MOVE
	result.actor_id = _actor.id
	result.path = chosen.duplicate()
	return result


func _advance_less(a: Dictionary, b: Dictionary) -> bool:
	if float(a["cost"]) != float(b["cost"]):
		return float(a["cost"]) < float(b["cost"])
	var ac: Vector2i = a["goal"]
	var bc: Vector2i = b["goal"]
	if ac.y != bc.y:
		return ac.y < bc.y
	if ac.x != bc.x:
		return ac.x < bc.x
	return int(a["target_id"]) < int(b["target_id"])


func _attack_height_eligible(board: BattleBoard, from: Vector2i, target: Vector2i) -> bool:
	return absi(board.get_height_steps(from) - board.get_height_steps(target)) < 2


func _has_large_drop(board: BattleBoard, path: Array[Vector2i]) -> bool:
	for index in range(1, path.size()):
		if board.get_height_steps(path[index - 1]) - board.get_height_steps(path[index]) > 2:
			return true
	return false


func _affordable_prefix(board: BattleBoard, full_path: Array[Vector2i], budget: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = [full_path[0]]
	var spent := 0.0
	var provider := board.make_spatial_data_provider(_actor)
	for index in range(1, mini(full_path.size(), MoveCommand.MAX_PATH_CELLS)):
		var edge := SpatialRules.inspect_edge(provider, full_path[index - 1], full_path[index])
		if edge.reason != &"": break
		var cost := edge.cost
		if spent + cost > budget:
			break
		spent += cost
		result.append(full_path[index])
	# Недостаток ресурса может оставить хвост на союзнике-транзите; такой
	# endpoint нельзя передать команде как остановку.
	while result.size() > 1 and not provider.cell_can_stop(result[result.size() - 1]):
		result.pop_back()
	return result


func _path_cost(board: BattleBoard, path: Array[Vector2i]) -> float:
	var total := 0.0
	var provider := board.make_spatial_data_provider(_actor)
	for i in range(1, path.size()):
		var edge := SpatialRules.inspect_edge(provider, path[i - 1], path[i])
		if edge.reason != &"": return INF
		total += edge.cost
	return total


func _wait() -> BattleAIIntent:
	var result := BattleAIIntent.new()
	result.actor_id = _actor.id if _actor != null else UnitId.NONE
	return result

func _summon() -> BattleAIIntent:
	var battle := _session as BattleTacticalSession
	if battle == null or _actor == null or battle.context == null: return null
	var item := battle.summoning_item(_actor.id)
	if item == null: return null
	var action := item.get_use_action()
	if action == null or action.get_kind() != ItemUseAction.Kind.SUMMON_ADJACENT: return null
	for cell in battle.summoning_cells(_actor.id):
		# Сначала дешёвый отказ: при исчерпанном main не снимаем весь мир для каждой клетки.
		if action.hint_reason(battle.context, _actor.id, item.get_item_instance_id(), cell) != &"": continue
		# Подходящего кандидата подтверждаем, сохраняя выбор BT при повреждённом runtime.
		if action.availability_reason(battle.context, _actor.id, item.get_item_instance_id(), cell) != &"": continue
		var intent := BattleAIIntent.new()
		intent.kind = BattleAIIntent.Kind.SUMMON
		intent.actor_id = _actor.id
		intent.item_id = item.get_item_instance_id()
		intent.cell = cell
		return intent
	return null
