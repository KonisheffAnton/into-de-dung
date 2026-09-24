extends RefCounted
class_name MoveForecast

## DTO одного полного исполнения движения на изолированной копии.
var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var units: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_before: Dictionary = {}
var admission_after: Dictionary = {}
var actor_id: int = 0
var requested_path: Array[Vector2i] = []
var traversed_path: Array[Vector2i] = []

static func rejected(value: StringName) -> MoveForecast:
	var result := MoveForecast.new()
	result.reason = value
	return result

static func build(context: ActionContext, queue: ActionQueue, command: Command) -> MoveForecast:
	if command == null or command.get_script() != MoveCommand: return rejected(&"preview/unsupported_command")
	return _from_simulation(command as MoveCommand, ForecastSimulation.run(context, queue, command))

static func build_prepared(prepared: ForecastSimulation.Prepared) -> MoveForecast:
	if prepared == null: return rejected(&"preview/request_consumed")
	if prepared.reason != &"": return rejected(prepared.reason)
	if prepared.command == null or prepared.command.get_script() != MoveCommand: return rejected(&"preview/unsupported_command")
	return _from_simulation(prepared.command as MoveCommand, ForecastSimulation.run_prepared(prepared))

static func _from_simulation(move: MoveCommand, simulation: ForecastSimulation) -> MoveForecast:
	var result := MoveForecast.new()
	result.actor_id = move.get_actor_unit_id()
	result.requested_path = move.get_path()
	result.status = simulation.status
	result.reason = simulation.reason
	result.events = simulation.events
	result.steps = simulation.steps
	result.snapshot_before = simulation.snapshot_before
	result.snapshot_after = simulation.snapshot_after
	result.rng_after = simulation.rng_after
	result.counters_after = simulation.counters_after
	result.admission_before = simulation.admission_before
	result.admission_after = simulation.admission_after
	if result.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		for id: int in simulation.units_after:
			result.units[id] = {"before": simulation.units_before[id], "after": simulation.units_after[id]}
		# Только события уже исполненных граней задают маршрут; остаток команды не пройден.
		if not result.requested_path.is_empty(): result.traversed_path.append(result.requested_path[0])
		for event: Dictionary in result.events:
			if event.get("kind") != &"moved" or int(event.get("actor_unit_id", 0)) != result.actor_id: continue
			var transit: Variant = event.get("transit_path")
			if typeof(transit) == TYPE_ARRAY:
				for index in range(1, (transit as Array).size()):
					var cell: Variant = (transit as Array)[index]
					if typeof(cell) == TYPE_VECTOR2I: result.traversed_path.append(cell)
			elif typeof(event.get("to_cell")) == TYPE_VECTOR2I:
				result.traversed_path.append(event["to_cell"])
	return result
