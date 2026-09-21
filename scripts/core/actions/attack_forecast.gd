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
	var capture := ItemSimulationSnapshot.capture(context.get_state(), context.get_unsupported_runtime_ids())
	if capture.code != ItemSnapshotResult.Code.OK: return rejected(StringName(capture.reason))
	var original_rng := context.get_rng()
	if original_rng == null: return rejected(&"preview/rng_missing")
	# Базовый порт всегда возвращает отказ броска; не превращаем неизвестный RNG в него.
	var rng_copy := ActionRngPort.new() if original_rng.get_script() == ActionRngPort else original_rng.clone()
	if rng_copy == null or rng_copy == original_rng or rng_copy.get_script() != original_rng.get_script(): return rejected(&"preview/rng_not_cloneable")
	if rng_copy.to_dict() != original_rng.to_dict(): return rejected(&"preview/rng_state_mismatch")
	var definitions: Dictionary = {}
	for owner in context.get_state().get_owners():
		for id: StringName in owner._definitions:
			# Runtime снимка не разделяет даже Resource определений с живым боем.
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	if restored.code != ItemSnapshotResult.Code.OK: return rejected(StringName(restored.reason))
	var state_copy := restored.state
	var context_copy := context.copy_for_simulation(state_copy, rng_copy)
	var queue_copy := queue.copy_for_simulation()
	if context_copy == null or queue_copy == null:
		_close(state_copy)
		return rejected(&"preview/context_copy_failed")
	var before := _unit_values(state_copy.get_board(), state_copy)
	var receipt := queue_copy.submit(command, context_copy)
	var result := AttackForecast.new()
	result.status = receipt.status
	result.reason = receipt.reason
	result.events = receipt.get_events()
	result.steps = receipt.get_steps()
	result.snapshot_before = capture.snapshot.to_dict()
	result.rng_after = rng_copy.to_dict().duplicate(true)
	result.counters_after = context_copy.simulation_counters()
	var after_capture := ItemSimulationSnapshot.capture(state_copy, [])
	if after_capture.code == ItemSnapshotResult.Code.OK:
		result.snapshot_after = after_capture.snapshot.to_dict()
	elif result.status == ActionReceipt.APPLIED:
		result.status = ActionReceipt.FAULTED
		result.reason = &"preview/result_snapshot_failed"
	if result.status == ActionReceipt.APPLIED:
		var after := _unit_values(state_copy.get_board(), state_copy)
		for id: int in before:
			result.units[id] = {"before": before[id], "after": after[id]}
	_close(state_copy)
	return result

static func _unit_values(board: BattleBoard, state: ItemSimulationState = null) -> Dictionary:
	var result: Dictionary = {}
	for unit in board.get_all_units():
		result[unit.id] = {"hp": unit.vitals.get_hp(), "hp_max": unit.get_stat(StatTypes.StatType.HP_MAX), "balance": unit.vitals.get_balance(), "balance_max": unit.get_stat(StatTypes.StatType.BALANCE_MAX), "cell": unit.cell, "alive": unit.is_alive(), "main": unit.action_resources.get_main_left() if unit.action_resources != null else 0, "bonus": unit.action_resources.get_bonus_left() if unit.action_resources != null else 0, "move": unit.move_points_left, "guard_stance": unit.guard_stance}
		if unit.armor != null:
			# A берётся из snapshot/result в UI; здесь сохраняется capability и E.
			result[unit.id]["armor_state"] = unit.armor.to_dict()
			var armor := ArmorRuntime.totals(ArmorRuntime.capture(state.get_owner(unit.id))) if state != null else {}
			if not armor.is_empty():
				result[unit.id]["armor_current"] = armor["current"]
				result[unit.id]["armor_max"] = armor["maximum"]
	return result

static func _close(state: ItemSimulationState) -> void:
	for inventory in state.get_inventories(): inventory.close()
	for equipment in state.get_equipment_facades(): equipment.close()
	for owner in state.get_owners(): owner.close()
	state.get_board().resize(0, 0)
