extends Command
class_name MoveCommand

const MAX_ID: int = 9223372036854775807
const MAX_PATH_CELLS: int = 33

var _actor_unit_id: int
var _path: Array[Vector2i] = []
var _expected_revision: int
var _invalid_length: bool = false
var _continuation_index: int = 0
var _is_continuation_flag: bool = false
var _bound_actor: UnitState = null

func _init(actor_unit_id: int = 0, path: Array[Vector2i] = [], expected_revision: int = 0) -> void:
	_actor_unit_id = actor_unit_id
	_expected_revision = expected_revision
	if path.size() > MAX_PATH_CELLS:
		_invalid_length = true
		return
	_path = path.duplicate()

static func _make_continuation(source: MoveCommand, next_index: int, actor: UnitState) -> MoveCommand:
	var result := MoveCommand.new(source._actor_unit_id, source._path, source._expected_revision)
	result._invalid_length = source._invalid_length
	result._continuation_index = next_index
	result._is_continuation_flag = true
	result._bound_actor = actor
	return result

func get_kind() -> StringName:
	return &"move"

func copy_for_queue() -> Command:
	var result := MoveCommand.new(_actor_unit_id, _path, _expected_revision)
	result._invalid_length = _invalid_length
	result._continuation_index = _continuation_index
	result._is_continuation_flag = _is_continuation_flag
	result._bound_actor = _bound_actor
	return result

func get_actor_unit_id() -> int:
	return _actor_unit_id

func get_path() -> Array[Vector2i]:
	return _path.duplicate()

func get_expected_revision() -> int:
	return _expected_revision

func _is_continuation() -> bool:
	return _is_continuation_flag

func validate(context: ActionContext) -> StringName:
	# После принятия root повреждённый payload continuation — нарушение runtime-инварианта,
	# а не публичная ошибка нового root. Курсор и identity остаются отдельным контрактом.
	if _is_continuation_flag and (_invalid_length or _path.size() < 2 or _path.size() > MAX_PATH_CELLS or _actor_unit_id <= 0 or _actor_unit_id >= MAX_ID or _expected_revision < 0 or _expected_revision > MAX_ID - 2):
		return &"move/invalid_runtime"
	if _invalid_length or _path.size() < 2 or _path.size() > MAX_PATH_CELLS:
		return &"move/path_length"
	if _actor_unit_id <= 0 or _actor_unit_id >= MAX_ID:
		return &"move/invalid_actor_id"
	if _expected_revision < 0 or _expected_revision > MAX_ID - 2:
		return &"move/invalid_revision"
	if _is_continuation_flag:
		if _bound_actor == null or _bound_actor.id != _actor_unit_id or _continuation_index < 2 or _continuation_index > _path.size():
			return &"move/invalid_continuation"
		return &""
	if context == null or context.get_state() == null or context.get_state().get_board() == null:
		return &"move/invalid_runtime"
	var rules := context.get_move_rules()
	if rules == null:
		return &"move/rules_missing"
	var rules_reason := rules.validate()
	if rules_reason != &"":
		return &"move/invalid_rules"
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(_actor_unit_id)
	if actor == null:
		return &"move/missing_actor"
	if not actor.is_alive():
		return &"move/dead_actor"
	if actor.armor != null and rules.get_profile() != &"spatial_move_v1": return &"armor/legacy_unsupported"
	if actor.stats == null or actor.vitals == null:
		return &"move/invalid_runtime"
	if _expected_revision != context.get_revision():
		return &"move/stale_revision"
	if not rules.allows(_actor_unit_id):
		return &"move/not_admitted"
	if _path[0] != actor.cell:
		return &"move/start_mismatch"
	if board.occupant_at(actor.cell) != actor:
		return &"move/actor_not_placed"
	var check := MovePathCheck.inspect(board, actor, _path, rules.get_max_height_step(), actor.move_points_left, rules.get_profile())
	if check.get_reason() != &"":
		return check.get_reason()
	var required: int = _path.size() - 1
	if rules.get_profile() == &"spatial_move_v1":
		if actor.action_resources == null or SpatialRules.capture_guard(context, [actor], _path, {}) == null: return &"move/invalid_runtime"
		if actor.armor != null:
			var armor_reason := _armor_path_reason(context, actor)
			if armor_reason != &"": return armor_reason
		for index in range(1, _path.size()):
			var drop := maxi(0, board.get_height_steps(_path[index - 1]) - board.get_height_steps(_path[index]))
			if board.is_lethal(_path[index]):
				required = _path.size()
			elif drop > 2:
				var fall := _fall_for(actor, drop)
				if not is_finite(fall): return &"move/invalid_runtime"
				required = _path.size()
	for index in range(1, _path.size()):
		var cell: Vector2i = _path[index]
		if board.is_lethal(cell):
			required = _path.size() - 1 + 1
			break
	if board.board_version < 0 or board.board_version > MAX_ID - required:
		return &"move/board_version_exhausted"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	if context == null or context.get_state() == null or context.get_state().get_board() == null:
		return CommandStepResult.faulted(&"move/invalid_runtime")
	var board := context.get_state().get_board()
	if _is_continuation_flag:
		if _invalid_length or _path.size() < 2 or _path.size() > MAX_PATH_CELLS or _actor_unit_id <= 0 or _actor_unit_id >= MAX_ID or _expected_revision < 0 or _expected_revision > MAX_ID - 2:
			return CommandStepResult.faulted(&"move/invalid_runtime")
		if _bound_actor == null or _bound_actor.id != _actor_unit_id or _continuation_index < 2 or _continuation_index > _path.size():
			return CommandStepResult.faulted(&"move/invalid_continuation")
		return _execute_continuation(context, board)
	var validation := validate(context)
	if validation != &"":
		return CommandStepResult.faulted(&"move/invalid_runtime")
	var actor := board.get_unit_by_id(_actor_unit_id)
	if actor == null or not actor.is_alive() or actor.cell != _path[0] or board.occupant_at(actor.cell) != actor:
		return CommandStepResult.faulted(&"move/invalid_runtime")
	_bound_actor = actor
	_continuation_index = 1
	return _execute_edge(context, board, actor)

func _execute_continuation(context: ActionContext, board: BattleBoard) -> CommandStepResult:
	var actor := board.get_unit_by_id(_actor_unit_id)
	if actor == null:
		return CommandStepResult.interrupted(&"move/actor_missing")
	if actor != _bound_actor:
		return CommandStepResult.interrupted(&"move/actor_replaced")
	if not actor.is_alive():
		return CommandStepResult.interrupted(&"move/actor_dead")
	if actor.cell != _path[_continuation_index - 1]:
		return CommandStepResult.interrupted(&"move/actor_displaced")
	if board.occupant_at(actor.cell) != actor:
		return CommandStepResult.faulted(&"move/invalid_runtime")
	if _continuation_index == _path.size():
		return CommandStepResult.applied([], [], [], null, false)
	return _execute_edge(context, board, actor)

func _execute_edge(context: ActionContext, board: BattleBoard, actor: UnitState) -> CommandStepResult:
	var rules := context.get_move_rules()
	if rules == null or rules.validate() != &"":
		return CommandStepResult.faulted(&"move/invalid_runtime")
	if rules.get_profile() == &"spatial_move_v1": return _execute_spatial_edge(context, board, actor, rules)
	var edge_path: Array[Vector2i] = [_path[_continuation_index - 1], _path[_continuation_index]]
	var check := MovePathCheck.inspect(board, actor, edge_path, rules.get_max_height_step(), actor.move_points_left)
	if check.get_reason() != &"":
		var reason := check.get_reason()
		if reason == &"move/out_of_bounds" or reason == &"move/blocked": return CommandStepResult.interrupted(&"move/path_blocked")
		if reason == &"move/height_step": return CommandStepResult.interrupted(&"move/path_height")
		if reason == &"move/insufficient_move": return CommandStepResult.interrupted(&"move/budget_exhausted")
		return CommandStepResult.faulted(&"move/invalid_runtime")
	var cost := check.get_costs()[0]
	var from_cell := actor.cell
	var to_cell := _path[_continuation_index]
	var is_hazard: bool = board.is_lethal(to_cell)
	var required: int = 1 + (1 if is_hazard else 0)
	if board.board_version < 0 or board.board_version > MAX_ID - required:
		return CommandStepResult.faulted(&"move/board_version_exhausted")
	var before := actor.move_points_left
	var stance_before := actor.guard_stance
	actor.guard_stance = false
	if not board.move_unit(actor, to_cell):
		actor.guard_stance = stance_before
		return CommandStepResult.faulted(&"move/board_move_failed")
	actor.spend_move_points(cost)
	var after := actor.move_points_left
	var event: Dictionary = {"kind": &"moved", "actor_unit_id": actor.id, "target_unit_id": actor.id, "from_cell": from_cell, "to_cell": to_cell, "movement_kind": &"voluntary", "move_cost": cost, "move_before": before, "move_after": after}
	# Legacy callback не вправе вернуть добровольно снятую стойку; вход уже оплачен.
	if actor.guard_stance:
		var failure := CommandStepResult.faulted(&"move/invalid_runtime")
		failure.events = [event]
		failure.state_changed = true
		return failure
	_continuation_index += 1
	var mandatory: Array[Command] = []
	if is_hazard:
		mandatory.append(DeathCommand.new(actor.id, DamageSource.new(&"cell", 0, to_cell, 0, 0)))
	var continuation := MoveCommand._make_continuation(self, _continuation_index, actor)
	return CommandStepResult.applied([event], mandatory, [], continuation, true)

static func _fall_for(actor: UnitState, drop: int) -> float:
	if drop <= 2: return 0.0
	var stats_copy := StatsBag.from_snapshot_dict(actor.stats.to_snapshot_dict())
	if stats_copy == null or not stats_copy.has_stat(StatTypes.StatType.HP_MAX) or not stats_copy.has_stat(StatTypes.StatType.ARMOR): return NAN
	if actor.armor != null:
		var raw := ArmorAttack.fall(stats_copy.get_value(StatTypes.StatType.HP_MAX), drop, true)
		return float(raw.numerator) / float(raw.denominator) if raw.valid else NAN
	return SpatialRules.fall_amount(stats_copy.get_value(StatTypes.StatType.HP_MAX), stats_copy.get_value(StatTypes.StatType.ARMOR), drop, true)

static func _armor_fall_plan(context: ActionContext, actor: UnitState, drop: int) -> Dictionary:
	var maximum := ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX)
	var raw := ArmorRuntime.physical(ArmorAttack.fall(maximum, drop, true), "fall")
	return ArmorRuntime.plan(ArmorRuntime.capture(context.get_state().get_owner(actor.id)), raw, actor.vitals.get_hp(), maximum, context.get_rng())

func _armor_path_reason(context: ActionContext, actor: UnitState) -> StringName:
	# До первого шага переносим расход E/a_i и RNG вдоль всей известной цепи падений.
	var board := context.get_state().get_board()
	var maximum := ActionHpExecutor._stat_value(actor, StatTypes.StatType.HP_MAX)
	var simulation := {"views": {actor.id: ArmorRuntime.capture(context.get_state().get_owner(actor.id))}, "hp": {actor.id: actor.vitals.get_hp()}, "rng": context.get_rng()}
	# Между гранями очередь исполняет нынешние item-heal реакции. Читаем их настоящим
	# collector, чтобы не оборвать admission по смерти, предотвращённой прошлым лечением.
	var reactions := ItemReactionCollector.collect_damage(context.get_state(), {"event_seq": 1, "target_unit_id": actor.id, "dealt": 1.0})
	if reactions.code != ItemReactionResult.Code.OK: return &"armor/invalid_move_reactions"
	for index in range(1, _path.size()):
		if board.is_lethal(_path[index]): break
		var drop := maxi(0, board.get_height_steps(_path[index - 1]) - board.get_height_steps(_path[index]))
		if drop <= 2: continue
		var raw := ArmorRuntime.physical(ArmorAttack.fall(maximum, drop, true), "fall")
		var plan := ArmorRuntime.plan(simulation["views"][actor.id], raw, simulation["hp"][actor.id], maximum, simulation["rng"])
		if plan.get("reason", &"") != &"": return plan["reason"]
		if not ArmorSpatial._advance_rng(simulation, plan): return &"armor/rng_not_cloneable"
		simulation["views"][actor.id] = plan["after"]
		simulation["hp"][actor.id] = float(plan["hp_after"])
		if plan["hp_after"] == 0: break
		if plan["hp_loss"] > 0:
			for reaction: Dictionary in reactions.descriptions:
				simulation["hp"][actor.id] = minf(maximum, simulation["hp"][actor.id] + float(reaction["heal_amount"]))
	return &""

func _execute_spatial_edge(context: ActionContext, board: BattleBoard, actor: UnitState, rules: MoveRules) -> CommandStepResult:
	var edge: Array[Vector2i] = [_path[_continuation_index - 1], _path[_continuation_index]]
	var check := MovePathCheck.inspect(board, actor, edge, rules.get_max_height_step(), actor.move_points_left, rules.get_profile())
	if check.get_reason() != &"":
		var reason := check.get_reason()
		if reason in [&"move/out_of_bounds", &"move/blocked"]: return CommandStepResult.interrupted(&"move/path_blocked")
		if reason == &"move/height_step": return CommandStepResult.interrupted(&"move/path_height")
		if reason == &"move/insufficient_move": return CommandStepResult.interrupted(&"move/budget_exhausted")
		return CommandStepResult.faulted(&"move/invalid_runtime")
	var from := edge[0]
	var to := edge[1]
	var drop := maxi(0, board.get_height_steps(from) - board.get_height_steps(to))
	var lethal := board.is_lethal(to)
	var fall := 0.0 if lethal else _fall_for(actor, drop)
	if not is_finite(fall): return CommandStepResult.faulted(&"move/invalid_runtime")
	var types: Dictionary = {}
	if fall > 0.0: types[actor.id] = [StatTypes.StatType.HP_MAX, StatTypes.StatType.ARMOR]
	var guard := SpatialRules.capture_guard(context, [actor], edge, types)
	if guard == null or actor.action_resources == null: return CommandStepResult.faulted(&"move/invalid_runtime")
	var required := 1 + (1 if lethal or (fall > 0.0 and fall >= actor.vitals.get_hp()) else 0)
	if actor.armor != null and fall > 0.0:
		var plan := _armor_fall_plan(context, actor, drop)
		if plan.get("reason", &"") != &"": return CommandStepResult.faulted(plan["reason"])
		required = 1 + (1 if plan["hp_after"] == 0 else 0)
	if board.board_version > MAX_ID - required: return CommandStepResult.faulted(&"move/board_version_exhausted")
	var before := actor.move_points_left
	var cost := check.get_costs()[0]
	var after := before - cost
	var id := actor.id
	var moved := guard.debit(id, 0, cost).stance(id, false).moved(id, to)
	# Callback положения должен уже видеть оплату; между этими операциями нет внешнего кода.
	actor.spend_move_points(cost)
	var stance_before := actor.guard_stance
	actor.guard_stance = false
	if not board.move_unit(actor, to):
		actor.move_points_left = before
		actor.guard_stance = stance_before
		return CommandStepResult.faulted(&"move/board_move_failed")
	var event := {"kind": &"moved", "actor_unit_id": id, "target_unit_id": id, "from_cell": from, "to_cell": to, "movement_kind": &"voluntary", "move_cost": cost, "move_before": before, "move_after": after}
	if not moved.check(context):
		var fault := CommandStepResult.faulted(&"move/invalid_runtime")
		fault.events = [event]; fault.state_changed = true
		return fault
	var mandatory: Array[Command] = []
	if lethal or fall > 0.0:
		var binding := MoveFallCommand.make_binding(moved, id, from, to, drop, fall, lethal)
		if lethal: mandatory.append(DeathCommand.new(id, binding.source, binding))
		else: mandatory.append(MoveFallCommand.new(binding))
	return CommandStepResult.applied([event], mandatory, [], MoveCommand._make_continuation(self, _continuation_index + 1, actor), true)
