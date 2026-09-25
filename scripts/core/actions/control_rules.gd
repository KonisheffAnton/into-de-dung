extends RefCounted
class_name ControlRules

static func action_reason(unit: UnitState, moving: bool = false) -> StringName:
	if unit != null and unit.combat_perks != null:
		if unit.combat_perks.to_dict().is_empty(): return &"perks/invalid_runtime"
		if moving and unit.combat_perks.movement_stopped: return &"perks/movement_stopped"
	if unit == null or unit.control == null: return &""
	if unit.control.get_script() != ControlState or not ControlState.valid(unit.control.to_dict()): return &"control/invalid_state"
	if unit.control.stunned_turns > 0: return &"control/stunned"
	if moving and unit.control.entangled_turns > 0: return &"control/entangled"
	return &""

static func critical_target(unit: UnitState) -> bool:
	return unit != null and unit.control != null and unit.control.get_script() == ControlState and ControlState.valid(unit.control.to_dict()) and (unit.control.stunned_turns > 0 or unit.control.entangled_turns > 0)

static func balance_maximum(unit: UnitState, base: float) -> float:
	if unit == null or unit.control == null: return base
	if unit.control.get_script() != ControlState or not ControlState.valid(unit.control.to_dict()): return NAN
	return base * 2.0 if unit.control.entangled_turns > 0 and base != 0.0 else base
