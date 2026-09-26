extends RefCounted
class_name ItemUseForecast

## Результат M3 содержит только значения. Новый участник имеет before = null.
var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var units: Dictionary = {}
var items: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_before: Dictionary = {}
var admission_after: Dictionary = {}

static func rejected(value: StringName) -> ItemUseForecast:
	var result := ItemUseForecast.new()
	result.reason = value
	return result

static func build(context: ActionContext, queue: ActionQueue, command: Command) -> ItemUseForecast:
	if command == null or command.get_script() not in [UseHealingItemCommand, UseSummoningItemCommand]: return rejected(&"preview/unsupported_command")
	var simulation := ForecastSimulation.run(context, queue, command)
	return from_simulation(simulation)

static func from_simulation(simulation: ForecastSimulation) -> ItemUseForecast:
	var result := ItemUseForecast.new()
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
	result.items = simulation.items
	if result.status == ActionReceipt.APPLIED:
		for id: int in simulation.units_after:
			result.units[id] = {"before": simulation.units_before.get(id), "after": simulation.units_after[id]}
	return result
