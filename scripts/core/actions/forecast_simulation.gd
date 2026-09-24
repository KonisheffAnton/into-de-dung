extends RefCounted
class_name ForecastSimulation

## Общая изоляция только для трёх известных команд; это не executor произвольного кода.
var status: StringName = ActionReceipt.REJECTED
var reason: StringName = &""
var events: Array[Dictionary] = []
var steps: Array[Dictionary] = []
var snapshot_before: Dictionary = {}
var snapshot_after: Dictionary = {}
var rng_after: Dictionary = {}
var counters_after: Dictionary = {}
var admission_before: Dictionary = {}
var admission_after: Dictionary = {}
var units_before: Dictionary = {}
var units_after: Dictionary = {}
var items: Dictionary = {}

static func rejected(value: StringName) -> ForecastSimulation:
	var result := ForecastSimulation.new()
	result.reason = value
	return result

static func run(context: ActionContext, queue: ActionQueue, command: Command) -> ForecastSimulation:
	if context == null or queue == null: return rejected(&"session/closed")
	if context.is_busy() or queue._busy: return rejected(&"BUSY")
	if context.is_faulted() or queue._faulted: return rejected(&"CONTEXT_FAULTED")
	if context.get_script() != ActionContext or queue.get_script() != ActionQueue: return rejected(&"preview/unsupported_context")
	if command == null or command.get_script() not in [AttackCommand, UseHealingItemCommand, UseSummoningItemCommand]: return rejected(&"preview/unsupported_command")
	var capture := ItemSimulationSnapshot.capture(context.get_state(), context.get_unsupported_runtime_ids())
	if capture.code != ItemSnapshotResult.Code.OK: return rejected(StringName(capture.reason))
	var original_rng := context.get_rng()
	if original_rng == null: return rejected(&"preview/rng_missing")
	# Базовый порт не бросает случайных чисел; неизвестный порт обязан дать точную копию.
	var rng_copy := ActionRngPort.new() if original_rng.get_script() == ActionRngPort else original_rng.clone()
	if rng_copy == null or rng_copy == original_rng or rng_copy.get_script() != original_rng.get_script(): return rejected(&"preview/rng_not_cloneable")
	if rng_copy.to_dict() != original_rng.to_dict(): return rejected(&"preview/rng_state_mismatch")
	var definitions: Dictionary = {}
	for owner in context.get_state().get_owners():
		for id: StringName in owner._definitions:
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := capture.snapshot.instantiate(definitions)
	if restored.code != ItemSnapshotResult.Code.OK: return rejected(StringName(restored.reason))
	var state_copy := restored.state
	var context_copy := context.copy_for_simulation(state_copy, rng_copy)
	var queue_copy := queue.copy_for_simulation()
	if context_copy == null or queue_copy == null:
		close(state_copy)
		return rejected(&"preview/context_copy_failed")
	var result := ForecastSimulation.new()
	var item_use: bool = command.get_script() != AttackCommand
	result.units_before = unit_values(state_copy.get_board(), state_copy, item_use)
	result.snapshot_before = capture.snapshot.to_dict()
	result.admission_before = SummonAdmission.values(context_copy)
	var actor_id: int = 0
	var item_id: int = 0
	if command is UseHealingItemCommand:
		actor_id = (command as UseHealingItemCommand)._actor_id
		item_id = (command as UseHealingItemCommand)._item_id
	elif command is UseSummoningItemCommand:
		actor_id = (command as UseSummoningItemCommand)._actor_id
		item_id = (command as UseSummoningItemCommand)._item_id
	var item_before := _item_values(state_copy, actor_id, item_id)
	var receipt := queue_copy.submit(command, context_copy)
	result.status = receipt.status
	result.reason = receipt.reason
	result.events = receipt.get_events()
	result.steps = receipt.get_steps()
	result.rng_after = rng_copy.to_dict().duplicate(true)
	result.counters_after = context_copy.simulation_counters()
	result.admission_after = SummonAdmission.values(context_copy)
	var after_capture := ItemSimulationSnapshot.capture(state_copy, [])
	if after_capture.code == ItemSnapshotResult.Code.OK:
		result.snapshot_after = after_capture.snapshot.to_dict()
	elif result.status == ActionReceipt.APPLIED:
		result.status = ActionReceipt.FAULTED
		result.reason = &"preview/result_snapshot_failed"
	# FAULTED сохраняет prefix в снимках/журнале, но не выдаёт готовые полосы/помощника.
	if result.status == ActionReceipt.APPLIED:
		result.units_after = unit_values(state_copy.get_board(), state_copy, item_use)
		if not item_before.is_empty():
			result.items[item_id] = {"actor_id": actor_id, "before": item_before, "after": _item_values(state_copy, actor_id, item_id)}
	close(state_copy)
	return result

static func _item_values(state: ItemSimulationState, actor_id: int, item_id: int) -> Dictionary:
	var owner := state.get_owner(actor_id)
	var item: ItemInstance = owner._items.get(item_id) if owner != null else null
	return {"charges": item.get_charges_left()} if item != null else {}

static func unit_values(board: BattleBoard, state: ItemSimulationState = null, include_identity: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for unit in board.get_all_units():
		result[unit.id] = {"hp": unit.vitals.get_hp(), "hp_max": unit.get_stat(StatTypes.StatType.HP_MAX), "balance": unit.vitals.get_balance(), "balance_max": unit.get_stat(StatTypes.StatType.BALANCE_MAX), "cell": unit.cell, "alive": unit.is_alive(), "main": unit.action_resources.get_main_left() if unit.action_resources != null else 0, "bonus": unit.action_resources.get_bonus_left() if unit.action_resources != null else 0, "move": unit.move_points_left, "guard_stance": unit.guard_stance}
		if include_identity:
			result[unit.id].merge({"id": unit.id, "name": unit.debug_name, "owner_unit_id": state.summon_owner_id(unit.id), "pending": state.is_summon_pending(unit.id)})
		if unit.armor != null:
			result[unit.id]["armor_state"] = unit.armor.to_dict()
			var armor := ArmorRuntime.totals(ArmorRuntime.capture(state.get_owner(unit.id))) if state != null else {}
			if not armor.is_empty():
				result[unit.id]["armor_current"] = armor["current"]
				result[unit.id]["armor_max"] = armor["maximum"]
		if unit.bleeding != null:
			result[unit.id]["bleeding"] = unit.bleeding.to_dict()
		if unit.control != null:
			result[unit.id]["control"] = unit.control.to_dict()
			result[unit.id]["balance_max"] = ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX))
	return result

static func close(state: ItemSimulationState) -> void:
	for inventory in state.get_inventories(): inventory.close()
	for equipment in state.get_equipment_facades(): equipment.close()
	for owner in state.get_owners(): owner.close()
	state.get_board().resize(0, 0)
