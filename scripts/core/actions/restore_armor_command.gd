extends Command
class_name RestoreArmorCommand

var _target_id: int
var _volume: int
var _expected_revision: int
var _source: DamageSource

func _init(target_id: int = 0, volume: int = 20, expected_revision: int = 0, source: DamageSource = null) -> void:
	_target_id = target_id; _volume = volume; _expected_revision = expected_revision
	_source = source.copy() if source != null else DamageSource.new(&"item", 0, Vector2i.ZERO, target_id, target_id)

func get_kind() -> StringName: return &"restore_armor"
func copy_for_queue() -> Command: return RestoreArmorCommand.new(_target_id, _volume, _expected_revision, _source)
func validate(context: ActionContext) -> StringName: return _prepare(context).get("reason", &"")

func _prepare(context: ActionContext) -> Dictionary:
	if context == null or context.get_state() == null or _source == null or _source.validate(context) != &"": return {"reason": &"armor/invalid_restore"}
	if context.get_revision() != _expected_revision: return {"reason": &"armor/stale_revision"}
	var unit := context.get_state().get_board().get_unit_by_id(_target_id)
	if unit == null or not unit.is_alive() or unit.armor == null or unit.action_resources == null: return {"reason": &"armor/capability_required"}
	var control_reason := ControlRules.action_reason(unit)
	if control_reason != &"": return {"reason": control_reason}
	var rules := context.get_move_rules()
	if rules == null or rules.validate() != &"" or not rules.allows(unit.id): return {"reason": &"armor/not_admitted"}
	# Цена этой способности фиксирована: частичное восстановление не даёт скидку.
	var cost := 1
	if unit.action_resources.get_main_left() < cost: return {"reason": &"attack/insufficient_main"}
	var guard := SpatialRules.capture_guard(context, [unit], [unit.cell], {})
	if guard == null: return {"reason": &"armor/invalid_restore"}
	var persistent := false
	for perk: Dictionary in unit.armor.perks:
		if perk.get("kind") == "persistent_armor" and perk.get("source") in ["*", String(_source.kind)]: persistent = true
	var plan := ArmorRecovery.restore(guard.values["participants"][unit.id]["armor"], _volume, String(_source.kind), persistent)
	if plan.get("reason", &"") != &"": return plan
	return {"reason": &"", "guard": guard, "plan": plan, "unit": unit, "cost": cost}

func execute(context: ActionContext) -> CommandStepResult:
	var prepared := _prepare(context)
	if prepared["reason"] != &"": return CommandStepResult.faulted(prepared["reason"])
	var unit: UnitState = prepared["unit"]
	var owner := context.get_state().get_owner(unit.id)
	var guard: SpatialRules.Guard = prepared["guard"]
	var plan: Dictionary = prepared["plan"]
	var state := unit.armor
	var step := CommandStepResult.faulted(&"armor/invalid_restore")
	if prepared["cost"] > 0 and not unit.action_resources.try_spend_main(prepared["cost"]): return step
	guard = guard.debit(unit.id, prepared["cost"], 0.0)
	step.state_changed = prepared["cost"] > 0
	var item_changes: Array[Dictionary] = []
	var grant_changes: Array[Dictionary] = []
	var event := {"kind": &"armor_changed", "actor_unit_id": _source.instigator_unit_id, "target_unit_id": unit.id, "source": _source.to_dict(), "items": item_changes, "grants": grant_changes}
	if not guard.check(context): return step
	for delta: Dictionary in plan["items"]:
		var view: Dictionary = guard.values["participants"][unit.id]["armor"].duplicate(true)
		for item: Dictionary in view["items"]:
			if item["item_id"] == delta["id"]: item["remaining"] = delta["after"]
		guard = guard.armor_phase(unit.id, view)
		(owner._items[delta["id"]] as ItemInstance).armor_remaining = delta["after"]
		item_changes.append(delta.duplicate(true))
		step.state_changed = true
		if step.events.is_empty(): step.events.append(event)
		if not guard.check(context): return step
		state.changed.emit(&"item", delta["id"], delta["before"], delta["after"])
		if not guard.check(context): return step
	if not plan["grant"].is_empty():
		var grant: Dictionary = plan["grant"]
		var view: Dictionary = guard.values["participants"][unit.id]["armor"].duplicate(true)
		view["state"] = plan["after"]["state"].duplicate(true)
		guard = guard.armor_phase(unit.id, view)
		state.grants.append(grant.duplicate(true))
		state.next_grant_id += 1
		grant_changes.append({"id": grant["grant_id"], "before": 0, "after": grant["remaining"]})
		step.state_changed = true
		if step.events.is_empty(): step.events.append(event)
		if not guard.check(context): return step
		state.changed.emit(&"extra", grant["grant_id"], 0, grant["remaining"])
		if not guard.check(context): return step
	step.status = &"APPLIED"; step.reason = &""
	return step
