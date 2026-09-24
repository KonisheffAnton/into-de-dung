extends RefCounted
class_name AttackForecast

## Значения результата одного полного submit; изолированный runtime не выходит наружу.
var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var units: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}

static func rejected(value: StringName) -> AttackForecast:
	var result := AttackForecast.new()
	result.reason = value
	return result

static func build(context: ActionContext, queue: ActionQueue, command: AttackCommand) -> AttackForecast:
	if context == null or queue == null: return rejected(&"session/closed")
	if context.is_busy() or queue._busy: return rejected(&"BUSY")
	if context.is_faulted() or queue._faulted: return rejected(&"CONTEXT_FAULTED")
	if context.get_script() != ActionContext or queue.get_script() != ActionQueue: return rejected(&"preview/unsupported_context")
	if command == null or command.get_script() != AttackCommand: return rejected(&"preview/unsupported_command")
	var simulation := ForecastSimulation.run(context, queue, command)
	var result := AttackForecast.new()
	result.status = simulation.status
	result.reason = simulation.reason
	result.events = simulation.events
	result.steps = simulation.steps
	result.snapshot_before = simulation.snapshot_before
	result.snapshot_after = simulation.snapshot_after
	result.rng_after = simulation.rng_after
	result.counters_after = simulation.counters_after
	if result.status == ActionReceipt.APPLIED:
		for id: int in simulation.units_before:
			result.units[id] = {"before": simulation.units_before[id], "after": simulation.units_after[id]}
	return result

static func _unit_values(board: BattleBoard, state: ItemSimulationState = null) -> Dictionary:
	return ForecastSimulation.unit_values(board, state)

static func _close(state: ItemSimulationState) -> void:
	ForecastSimulation.close(state)
