extends RefCounted
class_name TurnForecast

var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var phase_after: int = -1
var transitioned: bool = false
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var units_before: Dictionary = {}
var units_after: Dictionary = {}
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_after: Dictionary = {}

class Prepared extends RefCounted:
	var reason: StringName = &""
	var consumed: bool = false
	var snapshot: ItemSimulationSnapshot
	var definitions: Dictionary = {}
	var context: ActionContext
	var queue: ActionQueue
	var phase: int = -1
	var round_number: int = 0
	var selected_id: int = UnitId.NONE
	var rune_selected: bool = false
	var entangle_selected: bool = false
	var stun_selected: bool = false
	var elemental_selected: StringName = &""
	var deployment_enabled: bool = false
	var setup_revision: int = -1
	var enemy_ids: Array[int] = []
	var enemy_index: int = 0
	var enemy_actions: int = 0

	static func rejected(value: StringName) -> Prepared:
		var result := Prepared.new()
		result.reason = value
		return result

static func prepare(session: BattleCoreReactionsSession) -> Prepared:
	if session == null or session.get_script() != BattleCoreReactionsSession:
		return Prepared.rejected(&"turn/unsupported_session")
	if session.context == null or session._queue == null or session.state == null:
		return Prepared.rejected(&"session/closed")
	if session.phase != BattleTacticalSession.Phase.PLAYER_TURN:
		return Prepared.rejected(&"turn/unsupported_phase")
	if session.context.is_busy() or session._queue._busy or session._transitioning:
		return Prepared.rejected(&"BUSY")
	if session.context.is_faulted() or session._queue._faulted:
		return Prepared.rejected(&"CONTEXT_FAULTED")
	if not AbilityCatalog.attack_references_valid(session.context): return Prepared.rejected(&"ability/attack_catalog")
	# Проверка графа отклоняет callbacks и неизвестные runtime до копирования.
	if not BattleExecutionWorker.can_transfer(session):
		return Prepared.rejected(&"turn/unsupported_runtime")
	var capture := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	if capture.code != ItemSnapshotResult.Code.OK:
		return Prepared.rejected(StringName(capture.reason))
	var live_rng := session.context.get_rng()
	if live_rng == null or live_rng.get_script() not in [ActionRngPort, CombatRng]:
		return Prepared.rejected(&"preview/unsupported_rng")
	var rng_copy := ActionRngPort.new() if live_rng.get_script() == ActionRngPort else live_rng.clone()
	if rng_copy == null or rng_copy == live_rng or rng_copy.get_script() != live_rng.get_script() or rng_copy.to_dict() != live_rng.to_dict():
		return Prepared.rejected(&"preview/rng_not_cloneable")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions:
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var prepared := Prepared.new()
	prepared.snapshot = capture.snapshot
	prepared.definitions = definitions
	prepared.context = session.context.copy_for_simulation(ItemSimulationState.new(null, [], [], []), rng_copy)
	prepared.queue = session._queue.copy_for_simulation()
	prepared.phase = session.phase
	prepared.round_number = session.round_number
	prepared.selected_id = session.selected_id
	prepared.rune_selected = session.rune_selected
	prepared.entangle_selected = session.entangle_selected
	prepared.stun_selected = session.stun_selected
	prepared.elemental_selected = session.elemental_selected
	prepared.deployment_enabled = session.deployment_enabled
	prepared.setup_revision = session._setup_revision
	prepared.enemy_ids = session._enemy_ids.duplicate()
	prepared.enemy_index = session._enemy_index
	prepared.enemy_actions = session._enemy_actions
	if prepared.context == null or prepared.queue == null:
		return Prepared.rejected(&"preview/context_copy_failed")
	return prepared

static func run_prepared(prepared: Prepared) -> TurnForecast:
	if prepared == null or prepared.consumed:
		return rejected(&"preview/request_consumed")
	prepared.consumed = true
	if prepared.reason != &"":
		return rejected(prepared.reason)
	if prepared.snapshot == null or prepared.context == null or prepared.queue == null:
		return rejected(&"preview/context_copy_failed")
	var restored := prepared.snapshot.instantiate(prepared.definitions)
	if restored.code != ItemSnapshotResult.Code.OK:
		return rejected(StringName(restored.reason))
	var simulation := SimulationSession.new()
	simulation.board = restored.state.get_board()
	simulation.state = restored.state
	simulation.units = simulation.board.get_all_units()
	simulation.context = prepared.context
	simulation.context._state = simulation.state
	simulation._queue = prepared.queue
	simulation.phase = prepared.phase
	simulation.round_number = prepared.round_number
	simulation.selected_id = prepared.selected_id
	simulation.rune_selected = prepared.rune_selected
	simulation.entangle_selected = prepared.entangle_selected
	simulation.stun_selected = prepared.stun_selected
	simulation.elemental_selected = prepared.elemental_selected
	simulation.deployment_enabled = prepared.deployment_enabled
	simulation._setup_revision = prepared.setup_revision
	simulation._enemy_ids = prepared.enemy_ids.duplicate()
	simulation._enemy_index = prepared.enemy_index
	simulation._enemy_actions = prepared.enemy_actions
	var result := TurnForecast.new()
	result.snapshot_before = prepared.snapshot.to_dict()
	result.units_before = ForecastSimulation.unit_values(simulation.board, simulation.state, true)
	var old_phase: int = simulation.phase
	simulation.end_player_turn()
	result.phase_after = simulation.phase
	result.transitioned = simulation.phase != old_phase
	result.receipts = simulation.trace.duplicate(true)
	for receipt: Dictionary in result.receipts:
		result.events.append_array(receipt.get("events", []))
		result.steps.append_array(receipt.get("steps", []))
	var trace_faulted := false
	var any_applied := false
	var first_failure: StringName = &""
	for receipt: Dictionary in result.receipts:
		var receipt_status: StringName = receipt.get("status", ActionReceipt.REJECTED)
		trace_faulted = trace_faulted or receipt_status == ActionReceipt.FAULTED
		any_applied = any_applied or receipt_status == ActionReceipt.APPLIED
		if receipt_status != ActionReceipt.APPLIED and first_failure == &"": first_failure = receipt.get("reason", &"")
	var simulation_faulted := simulation.context.is_faulted() or simulation.phase == BattleTacticalSession.Phase.FAULTED
	result.status = ActionReceipt.FAULTED if simulation_faulted or trace_faulted else ActionReceipt.APPLIED if result.transitioned or any_applied else ActionReceipt.REJECTED
	result.reason = first_failure if result.status == ActionReceipt.FAULTED and first_failure != &"" else &"turn/faulted" if result.status == ActionReceipt.FAULTED else first_failure if result.status == ActionReceipt.REJECTED and first_failure != &"" else &"turn/not_transitioned" if result.status == ActionReceipt.REJECTED else &""
	var after_capture := ItemSimulationSnapshot.capture(simulation.state, [])
	if after_capture.code == ItemSnapshotResult.Code.OK:
		result.snapshot_after = after_capture.snapshot.to_dict()
	else:
		result.status = ActionReceipt.FAULTED
		result.reason = StringName(after_capture.reason)
	result.units_after = ForecastSimulation.unit_values(simulation.board, simulation.state, true)
	result.rng_after = simulation.context.get_rng().to_dict().duplicate(true)
	result.counters_after = simulation.context.simulation_counters()
	result.admission_after = SummonAdmission.values(simulation.context)
	simulation.close()
	return result

static func build(session: BattleCoreReactionsSession) -> TurnForecast:
	return run_prepared(prepare(session))

static func rejected(value: StringName) -> TurnForecast:
	var result := TurnForecast.new()
	result.reason = value
	return result

class SimulationSession extends BattleCoreReactionsSession:
	var trace: Array[Dictionary] = []

	func _init() -> void:
		super(false)

	func _record_receipt(receipt: ActionReceipt) -> void:
		trace.append({"status": receipt.status, "reason": receipt.reason, "events": receipt.get_events(), "steps": receipt.get_steps()})
