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
	var check := MovePathCheck.inspect(board, actor, _path, rules.get_max_height_step(), actor.move_points_left)
	if check.get_reason() != &"":
		return check.get_reason()
	var required: int = _path.size() - 1
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
	if not board.move_unit(actor, to_cell):
		return CommandStepResult.faulted(&"move/board_move_failed")
	actor.spend_move_points(cost)
	var after := actor.move_points_left
	var event: Dictionary = {"kind": &"moved", "actor_unit_id": actor.id, "target_unit_id": actor.id, "from_cell": from_cell, "to_cell": to_cell, "movement_kind": &"voluntary", "move_cost": cost, "move_before": before, "move_after": after}
	_continuation_index += 1
	var mandatory: Array[Command] = []
	if is_hazard:
		mandatory.append(DeathCommand.new(actor.id, DamageSource.new(&"cell", 0, to_cell, 0, 0)))
	var continuation := MoveCommand._make_continuation(self, _continuation_index, actor)
	return CommandStepResult.applied([event], mandatory, [], continuation, true)
