extends RefCounted
class_name RaiseCorpseForecast

## Прогноз содержит значения, чтобы UI не удерживал изолированный runtime.
var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var actor_id: int = 0
var corpse_id: int = 0
var units: Dictionary = {}
var corpses: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_before: Dictionary = {}
var admission_after: Dictionary = {}

static func rejected(value: StringName) -> RaiseCorpseForecast:
	var result := RaiseCorpseForecast.new()
	result.reason = value
	return result

static func build(context: ActionContext, queue: ActionQueue, command: Command) -> RaiseCorpseForecast:
	if command == null or command.get_script() != RaiseCorpseCommand: return rejected(&"preview/unsupported_command")
	var simulation := ForecastSimulation.run(context, queue, command)
	return from_simulation(simulation, (command as RaiseCorpseCommand)._actor_id, (command as RaiseCorpseCommand)._corpse_id)

static func from_simulation(simulation: ForecastSimulation, actor_id: int, corpse_id: int) -> RaiseCorpseForecast:
	var result := RaiseCorpseForecast.new()
	result.status = simulation.status
	result.reason = simulation.reason
	result.actor_id = actor_id
	result.corpse_id = corpse_id
	result.events = simulation.events
	result.steps = simulation.steps
	result.snapshot_before = simulation.snapshot_before
	result.snapshot_after = simulation.snapshot_after
	result.rng_after = simulation.rng_after
	result.counters_after = simulation.counters_after
	result.admission_before = simulation.admission_before
	result.admission_after = simulation.admission_after
	if result.status != ActionReceipt.APPLIED: return result
	for id: int in simulation.units_after:
		result.units[id] = {"before": simulation.units_before.get(id), "after": simulation.units_after[id]}
	var corpse_ids: Dictionary = simulation.corpses_before.duplicate()
	for id: int in simulation.corpses_after: corpse_ids[id] = true
	for id: int in corpse_ids:
		var before: Variant = simulation.corpses_before.get(id)
		var after: Variant = simulation.corpses_after.get(id)
		if before != after: result.corpses[id] = {"before": before, "after": after}
	return result
