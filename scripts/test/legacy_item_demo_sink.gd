extends EventSink
class_name LegacyItemDemoSink

## Временный мост существует только для сохранения клика debug-панели до P04.
## Он не слушает шину: реакция получает уже инжектированный поток событий.
var _state: ItemOwnerState
var _downstream: EventSink

func _init(state: ItemOwnerState, downstream: EventSink) -> void:
	_state = state
	_downstream = downstream if downstream != null else EventSink.new()

func unit_damaged(unit: UnitState, amount: float, source: Variant) -> void:
	_downstream.unit_damaged(unit, amount, source)
	if _state == null or _state.is_closed() or unit != _state.get_owner() or amount <= 0.0 or not unit.is_alive(): return
	for runtime in _state.get_active_heal_effects():
		if not runtime.is_active() or _state.is_closed() or not unit.is_alive(): continue
		var healed := unit.vitals.heal(runtime.get_heal_amount())
		if healed > 0.0:
			_downstream.unit_healed(unit, healed, {
				"owner_unit_id": runtime.get_owner_unit_id(),
				"item_instance_id": runtime.get_item_instance_id(),
				"effect_instance_id": runtime.get_effect_instance_id(),
				"definition_id": _state.get_definition_id_for_item(runtime.get_item_instance_id()),
			})

func unit_healed(unit: UnitState, amount: float, source: Variant) -> void: _downstream.unit_healed(unit, amount, source)
func unit_died(unit: UnitState, source: Variant) -> void: _downstream.unit_died(unit, source)
func unit_balance_changed(unit: UnitState, old_value: float, new_value: float) -> void: _downstream.unit_balance_changed(unit, old_value, new_value)
func unit_balance_broken(unit: UnitState) -> void: _downstream.unit_balance_broken(unit)
func unit_pushed(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void: _downstream.unit_pushed(unit, from_cell, to_cell)
func unit_moved(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i) -> void: _downstream.unit_moved(unit, from_cell, to_cell)
func turn_started(unit: UnitState) -> void: _downstream.turn_started(unit)
func turn_ended(unit: UnitState) -> void: _downstream.turn_ended(unit)
func round_started(round_number: int) -> void: _downstream.round_started(round_number)
func round_ended(round_number: int) -> void: _downstream.round_ended(round_number)
