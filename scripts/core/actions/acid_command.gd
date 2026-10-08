extends Command
class_name AcidCommand

const ARMOR_DAMAGE: int = 10

var _unit: UnitState
var _unit_id: int
var _tick: bool
var _standing: bool

func _init(unit: UnitState = null, tick: bool = false, standing: bool = false) -> void:
	_unit = unit
	_unit_id = unit.id if unit != null else UnitId.NONE
	_tick = tick
	_standing = standing

func get_kind() -> StringName: return &"acid_tick" if _tick else &"acid_apply"
func copy_for_queue() -> Command: return AcidCommand.new(_unit, _tick, _standing)

func validate(context: ActionContext) -> StringName:
	return _prepare(context).get("reason", &"")

func _binding_valid(context: ActionContext, unit: UnitState, unit_id: int, tick: bool, standing: bool) -> bool:
	if get_script() != AcidCommand or _unit != unit or _unit_id != unit_id or _tick != tick or _standing != standing: return false
	if context == null or context.get_script() != ActionContext or context.get_state() == null: return false
	if unit == null or unit.get_script() != UnitState or unit.id != unit_id: return false
	var board := context.get_state().get_board()
	return board != null and board.get_unit_by_id(unit_id) == unit

func _prepare(context: ActionContext) -> Dictionary:
	if get_script() != AcidCommand: return {"reason": &"acid/invalid_command"}
	if _standing and not _tick: return {"reason": &"acid/invalid_command"}
	if context == null or context.get_script() != ActionContext or context.get_state() == null: return {"reason": &"acid/invalid_command"}
	var state := context.get_state()
	var board := state.get_board()
	if state.get_script() != ItemSimulationState or board == null or board.get_script() != BattleBoard or _unit == null or _unit.get_script() != UnitState or _unit.id != _unit_id or board.get_unit_by_id(_unit_id) != _unit:
		return {"reason": &"acid/invalid_target"}
	if not ElementalRules.valid_unit(_unit): return {"reason": &"acid/invalid_target"}
	if not _unit.is_alive(): return {"reason": &"", "skip": &"status/dead_target"}
	if state.is_summon_pending(_unit_id): return {"reason": &"", "skip": &"summon/pending"}
	var before := _unit.elemental.to_dict()
	if _tick and not _standing and int(before.get("acid_ticks", 0)) == 0:
		return {"reason": &"", "skip": &"status/inactive"}
	var effect: StringName = &"acid_apply" if not _tick or _standing else &"acid_tick"
	var transition := ElementalRules.transition(before, effect, 1, {})
	if transition.get("reason", &"") != &"": return transition
	var guard := SpatialRules.capture_guard(context, [_unit], [_unit.cell], {})
	if guard == null: return {"reason": &"acid/invalid_runtime"}
	return {"reason": &"", "unit": _unit, "after": transition["after"], "guard": guard, "effect": effect}

func execute(context: ActionContext) -> CommandStepResult:
	var unit_seal: UnitState = _unit
	var id_seal: int = _unit_id
	var tick_seal: bool = _tick
	var standing_seal: bool = _standing
	var binding_check := func() -> bool: return _binding_valid(context, unit_seal, id_seal, tick_seal, standing_seal)
	var prepared := _prepare(context)
	if prepared.get("reason", &"") != &"": return CommandStepResult.faulted(prepared["reason"])
	if prepared.has("skip"): return CommandStepResult.skipped(prepared["skip"])
	var unit: UnitState = prepared["unit"]
	var guard: SpatialRules.Guard = prepared["guard"]
	if not guard.check(context) or not binding_check.call(): return CommandStepResult.faulted(&"acid/checkpoint")
	var written := ElementalRules.write(unit, prepared["after"], guard, context, prepared["effect"], 0, binding_check)
	var step: CommandStepResult = written["result"]
	guard = written["guard"]
	if step.status != &"APPLIED" or not _tick or not guard.check(context) or not binding_check.call(): return step
	var source := DamageSource.new(&"status", 0, unit.cell)
	if source.validate(context) != &"":
		step.status = &"FAULTED"; step.reason = &"acid/invalid_source"
		return step
	var owner := context.get_state().get_owner(unit.id)
	var state: ArmorState = unit.armor
	if state == null or owner == null: return step
	var original_armor: Dictionary = guard.values["participants"][unit.id].get("armor", {})
	var totals := ArmorRuntime.totals(original_armor)
	if totals.is_empty():
		step.status = &"FAULTED"; step.reason = &"acid/invalid_armor"
		return step
	var remaining: int = mini(ARMOR_DAMAGE, int(totals["current"]))
	if remaining <= 0: return step
	var changed_grants: Array[Dictionary] = []
	var changed_items: Array[Dictionary] = []
	var armor_event := {"kind": &"armor_changed", "actor_unit_id": 0, "target_unit_id": unit.id, "source": source.to_dict(), "items": changed_items, "grants": changed_grants}
	var armor_event_added: bool = false
	var grant_order: Array = original_armor["state"]["grants"].duplicate(true)
	grant_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["expires"] != b["expires"]: return a["expires"] == "battle"
		if a["battle_id"] != b["battle_id"]: return a["battle_id"] < b["battle_id"]
		return a["grant_id"] < b["grant_id"])
	for grant: Dictionary in grant_order:
		if remaining == 0: break
		var spent: int = mini(remaining, int(grant["remaining"]))
		if spent <= 0: continue
		var after_amount: int = int(grant["remaining"]) - spent
		var next_view: Dictionary = guard.values["participants"][unit.id]["armor"].duplicate(true)
		var next_grants: Array = next_view["state"]["grants"]
		for index: int in next_grants.size():
			if next_view["state"]["grants"][index]["grant_id"] == grant["grant_id"]:
				next_view["state"]["grants"][index]["remaining"] = after_amount
				break
		guard = guard.armor_phase(unit.id, next_view)
		for index: int in state.grants.size():
			if state.grants[index]["grant_id"] == grant["grant_id"]:
				state.grants[index]["remaining"] = after_amount
				break
		changed_grants.append({"id": grant["grant_id"], "before": grant["remaining"], "after": after_amount})
		remaining -= spent
		step.state_changed = true
		if not armor_event_added:
			step.events.append(armor_event)
			armor_event_added = true
		if not guard.check(context) or not binding_check.call():
			step.status = &"FAULTED"; step.reason = &"acid/checkpoint"
			return step
		state.changed.emit(&"extra", grant["grant_id"], int(grant["remaining"]), after_amount)
		if not guard.check(context) or not binding_check.call():
			step.status = &"FAULTED"; step.reason = &"acid/checkpoint"
			return step
	for item: Dictionary in original_armor["items"]:
		if remaining == 0: break
		if int(item["placement"]) < ItemOwnerState.EQUIPMENT_BASE or int(item["remaining"]) <= 0: continue
		var spent: int = mini(remaining, int(item["remaining"]))
		if spent <= 0: continue
		var after_amount: int = int(item["remaining"]) - spent
		var next_view: Dictionary = guard.values["participants"][unit.id]["armor"].duplicate(true)
		for view_item: Dictionary in next_view["items"]:
			if view_item["item_id"] == item["item_id"]:
				view_item["remaining"] = after_amount
				break
		guard = guard.armor_phase(unit.id, next_view)
		(owner._items[item["item_id"]] as ItemInstance).armor_remaining = after_amount
		changed_items.append({"id": item["item_id"], "before": item["remaining"], "after": after_amount})
		remaining -= spent
		step.state_changed = true
		if not armor_event_added:
			step.events.append(armor_event)
			armor_event_added = true
		if not guard.check(context) or not binding_check.call():
			step.status = &"FAULTED"; step.reason = &"acid/checkpoint"
			return step
		state.changed.emit(&"item", item["item_id"], int(item["remaining"]), after_amount)
		if not guard.check(context) or not binding_check.call():
			step.status = &"FAULTED"; step.reason = &"acid/checkpoint"
			return step
	step.status = &"APPLIED"; step.reason = &""
	return step
