extends RefCounted
class_name GuardForecast

var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var actor_id: int = 0
var units: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_before: Dictionary = {}
var admission_after: Dictionary = {}

static func rejected(value: StringName) -> GuardForecast:
	var result := GuardForecast.new()
	result.reason = value
	return result

static func build(context: ActionContext, queue: ActionQueue, command: Command) -> GuardForecast:
	if command == null or command.get_script() != GuardCommand: return rejected(&"preview/unsupported_command")
	var simulation := ForecastSimulation.run(context, queue, command)
	return from_simulation(simulation, (command as GuardCommand)._actor_id)

static func from_simulation(simulation: ForecastSimulation, actor_id: int) -> GuardForecast:
	var result := GuardForecast.new()
	result.status = simulation.status
	result.reason = simulation.reason
	result.actor_id = actor_id
	result.events = simulation.events
	result.steps = simulation.steps
	result.snapshot_before = simulation.snapshot_before
	result.snapshot_after = simulation.snapshot_after
	result.rng_after = simulation.rng_after
	result.counters_after = simulation.counters_after
	result.admission_before = simulation.admission_before
	result.admission_after = simulation.admission_after
	if result.status == ActionReceipt.APPLIED:
		for id: int in simulation.units_after:
			result.units[id] = {"before": simulation.units_before.get(id), "after": simulation.units_after[id]}
	return result
