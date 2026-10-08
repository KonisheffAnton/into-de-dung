extends Command
class_name CollapseCellCommand

var _cell: Vector2i
var _cell_seal: Vector2i
var _guard: SpatialRules.Guard

func _init(cell: Vector2i = Vector2i(-1, -1), guard: SpatialRules.Guard = null) -> void:
	_cell = cell
	_cell_seal = cell
	_guard = guard.copy() if guard != null else null

func get_kind() -> StringName: return &"support_collapse"
func copy_for_queue() -> Command:
	var result := CollapseCellCommand.new(_cell, _guard)
	result._cell_seal = _cell_seal
	return result

func validate(context: ActionContext) -> StringName:
	if _cell != _cell_seal or _guard == null or not _guard.check(context): return &"collapse/invalid_binding"
	var board: BattleBoard = _guard.refs["board"]
	if not board.is_in_bounds(_cell) or board.get_terrain(_cell) != TerrainType.Type.FLOOR or board.board_version > ActionContext.MAX_ID - 2: return &"collapse/invalid_cell"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var board: BattleBoard = _guard.refs["board"]
	var environment: CombatEnvironmentState = _guard.refs["environment"]
	var occupant := board.occupant_at(_cell)
	var next_environment := environment.to_dict()
	# Шипы и лежащие тела теряют опору вместе с клеткой; processed_deaths остаётся.
	for key: String in ["fires", "corpses"]:
		var kept: Array[Dictionary] = []
		for record: Dictionary in next_environment[key]:
			if record["cell"] != _cell: kept.append(record.duplicate(true))
		next_environment[key] = kept
	if next_environment.has("hazards"): next_environment.hazards = BattleHazards.remove_support(next_environment.hazards, _cell)
	var expected := _guard.copy()
	expected.values["environment"] = next_environment
	expected.values["geometry"][_cell][1] = TerrainType.Type.VOID
	expected.values["expected_board_version"] += 1
	expected.seal()
	environment.fires.assign(next_environment["fires"])
	environment.corpses.assign(next_environment["corpses"])
	if next_environment.has("hazards"): environment.hazards = next_environment.hazards.duplicate(true)
	board.set_terrain(_cell, TerrainType.Type.VOID)
	var events: Array[Dictionary] = [{"kind": &"support_collapsed", "actor_unit_id": 0, "target_unit_id": 0, "cell": _cell}]
	# Callback после смены terrain не может подменить жертву или ожидаемую геометрию.
	if _cell != _cell_seal or not expected.check(context): return CommandStepResult._make(CommandStepResult.FAULTED, &"collapse/invalid_binding", events, [], [], null, true)
	var children: Array[Command] = []
	if occupant != null:
		var binding := MoveFallCommand.make_binding(expected, occupant.id, _cell, _cell, 0, 0.0, true)
		children.append(DeathCommand.new(occupant.id, binding.source, binding))
	return CommandStepResult.applied(events, children, [], null, true)
