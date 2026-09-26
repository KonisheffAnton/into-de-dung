extends Command
class_name CollapsePhaseCommand

var _revision: int

func _init(revision: int = 0) -> void:
	_revision = revision

func get_kind() -> StringName: return &"environment_turn"
func copy_for_queue() -> Command: return CollapsePhaseCommand.new(_revision)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_revision() != _revision: return &"collapse/stale_phase"
	var state := context.get_state()
	var environment := state.environment
	if environment == null or environment.collapse.is_empty(): return &"collapse/unsupported"
	var capture := ItemSimulationSnapshot.capture(state, context.get_unsupported_runtime_ids())
	if capture.code != ItemSnapshotResult.Code.OK: return StringName(capture.reason)
	if environment.collapse["turn"] >= ActionContext.MAX_ID - 2: return &"collapse/turn_limit"
	if context.get_rng() == null or context.get_rng().get_script() != CombatRng: return &"collapse/unsupported_rng"
	var board := state.get_board()
	# Исчезновение опоры и смерть требуют по одной версии доски.
	if not environment.collapse["marked"].is_empty() and board.board_version > ActionContext.MAX_ID - 2: return &"collapse/board_limit"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var state := context.get_state()
	var environment := state.environment
	var board := state.get_board()
	var old_cells: Array[Vector2i] = []
	old_cells.assign(environment.collapse["marked"])
	var cells: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	var participants: Array[UnitState] = []
	var stats: Dictionary = {}
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			cells.append(cell)
			if board.get_terrain(cell) == TerrainType.Type.FLOOR and not old_cells.has(cell): candidates.append(cell)
	for unit: UnitState in board.get_all_units():
		if unit.is_alive():
			participants.append(unit)
			stats[unit.id] = [StatTypes.StatType.HP_MAX]
	var guard := SpatialRules.capture_guard(context, participants, cells, stats)
	if guard == null: return CommandStepResult.faulted(&"collapse/invalid_runtime")
	var rng := context.get_rng()
	guard.refs["armor_rng"] = rng
	guard.values["armor_rng"] = rng.to_dict().duplicate(true)
	guard.seal()
	var next_cells: Array[Vector2i] = []
	var next_rng := rng.clone()
	if not candidates.is_empty():
		var index := next_rng.next_int(&"combat", candidates.size())
		if index < 0 or index >= candidates.size(): return CommandStepResult.faulted(&"collapse/rng_exhausted")
		next_cells.append(candidates[index])
	var turn: int = environment.collapse["turn"] + 1
	var next_environment := environment.to_dict()
	next_environment["collapse"] = {"turn": turn, "marked": next_cells.duplicate()}
	var expected := guard.rng_phase(next_rng.to_dict())
	expected.values["environment"] = next_environment
	expected.seal()
	if not guard.check(context): return CommandStepResult.faulted(&"collapse/invalid_runtime")
	# RNG планируется на копии; отказ до этой границы не расходует живой поток.
	if not rng.from_dict(next_rng.to_dict()): return CommandStepResult.faulted(&"collapse/invalid_rng")
	environment.collapse = next_environment["collapse"].duplicate(true)
	var events: Array[Dictionary] = [{"kind": &"environment_turn", "actor_unit_id": 0, "target_unit_id": 0, "turn": turn, "marked": next_cells.duplicate()}]
	if not expected.check(context): return CommandStepResult._make(CommandStepResult.FAULTED, &"collapse/invalid_runtime", events, [], [], null, true)
	var children: Array[Command] = []
	# Только отметка прошлого хода входит в последствия; новая ждёт полный круг.
	for cell: Vector2i in old_cells: children.append(CollapseCellCommand.new(cell, expected))
	return CommandStepResult.applied(events, children, [], null, true)

static func valid_draft(event: Dictionary) -> bool:
	if event.get("kind") == &"support_collapsed":
		return ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "cell": TYPE_VECTOR2I}) and event["actor_unit_id"] == 0 and event["target_unit_id"] == 0
	if not ItemSimulationSnapshot._shape(event, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "turn": TYPE_INT, "marked": TYPE_ARRAY}): return false
	if event["kind"] != &"environment_turn" or event["actor_unit_id"] != 0 or event["target_unit_id"] != 0 or event["turn"] < 1 or event["turn"] >= ActionContext.MAX_ID - 1 or event["marked"].size() > 1: return false
	return event["marked"].is_empty() or typeof(event["marked"][0]) == TYPE_VECTOR2I
