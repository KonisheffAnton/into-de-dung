extends Command
class_name ArmorEndBattleCommand

var _unit_id: int
func _init(unit_id: int = 0) -> void: _unit_id = unit_id
func get_kind() -> StringName: return &"armor_end_battle"
func copy_for_queue() -> Command: return ArmorEndBattleCommand.new(_unit_id)

static func battle_over(context: ActionContext) -> bool:
	var players := false
	var enemies := false
	var capability := false
	for unit: UnitState in context.get_state().get_board().get_all_units():
		capability = capability or (unit.armor != null and unit.armor.in_battle)
		if not unit.is_alive(): continue
		players = players or unit.faction == Faction.Type.PLAYER
		enemies = enemies or unit.faction == Faction.Type.ENEMY
	return capability and (not players or not enemies)

func validate(context: ActionContext) -> StringName:
	if context == null or not battle_over(context): return &"armor/battle_not_over"
	var unit := context.get_state().get_board().get_unit_by_id(_unit_id)
	return &"" if unit != null and unit.armor != null and unit.armor.in_battle else &"armor/battle_not_over"

func execute(context: ActionContext) -> CommandStepResult:
	if validate(context) != &"": return CommandStepResult.faulted(&"armor/battle_not_over")
	var state := context.get_state()
	var board := state.get_board()
	var units := board._units.duplicate()
	var owners := state._owners.duplicate()
	var inventories := state._inventories.duplicate()
	var equipment := state._equipment.duplicate()
	var identities: Array[Dictionary] = []
	for unit: UnitState in units.values():
		var unit_owner := state.get_owner(unit.id)
		if unit_owner == null: return CommandStepResult.faulted(&"armor/invalid_expiry")
		identities.append({"unit": unit, "owner": unit_owner, "stats": unit.stats, "vitals": unit.vitals, "resources": unit.action_resources, "armor": ArmorRuntime.references(unit_owner)})
	var rng := context.get_rng()
	var rng_before := rng.to_dict().duplicate(true)
	var counters := context.simulation_counters()
	var admission := SummonAdmission.values(context)
	var owner := state.get_owner(_unit_id)
	var armor := owner._owner.armor
	var refs := ArmorRuntime.references(owner)
	var captured := ItemSimulationSnapshot.capture(state, [])
	if captured.code != ItemSnapshotResult.Code.OK: return CommandStepResult.faulted(&"armor/invalid_expiry")
	var expected := captured.snapshot.to_dict()
	var remaining: Array[Dictionary] = []
	var changes: Array[Dictionary] = []
	for grant: Dictionary in armor.grants:
		if grant["expires"] == "persistent": remaining.append(grant.duplicate(true))
		elif grant["remaining"] > 0: changes.append({"id": grant["grant_id"], "before": grant["remaining"], "after": 0})
	for unit: Dictionary in expected["board_snapshot"]["board"]["units"]:
		if unit["id"] == _unit_id:
			unit["armor"]["grants"] = remaining.duplicate(true)
			unit["armor"]["in_battle"] = false
			SpellShield.write_state(unit["armor"], {})
			if unit["armor"].has("raised_shield"): RaisedShield.write_state(unit["armor"], RaisedShield.expired(unit["armor"].raised_shield))
	var step := CommandStepResult.faulted(&"armor/invalid_expiry")
	armor.grants = remaining
	armor.in_battle = false
	armor.shield = {}
	if not armor.raised_shield.is_empty(): armor.raised_shield = RaisedShield.expired(armor.raised_shield)
	step.state_changed = true
	if not changes.is_empty():
		step.events.append({"kind": &"armor_changed", "actor_unit_id": 0, "target_unit_id": _unit_id, "source": DamageSource.new(&"status",0,owner._owner.cell,0,0).to_dict(), "grants": changes, "items": []})
	var check := func() -> bool:
		if context.get_state() != state or state.get_board() != board or board._units != units or state.get_owner(_unit_id) != owner or not ArmorRuntime.same_references(owner,refs): return false
		if context.get_rng() != rng or rng.to_dict() != rng_before or context.simulation_counters() != counters or SummonAdmission.values(context) != admission: return false
		if state._owners != owners or state._inventories != inventories or state._equipment != equipment: return false
		for identity: Dictionary in identities:
			var unit: UnitState = identity["unit"]
			var unit_owner: ItemOwnerState = identity["owner"]
			if unit_owner._owner != unit or state.get_owner(unit.id) != unit_owner or unit.stats != identity["stats"] or unit.vitals != identity["vitals"] or unit.action_resources != identity["resources"] or unit.vitals._stats != unit.stats or not ArmorRuntime.same_references(unit_owner, identity["armor"]): return false
		var after := ItemSimulationSnapshot.capture(state,[])
		return after.code == ItemSnapshotResult.Code.OK and after.snapshot.to_dict() == expected
	if not check.call(): return step
	for change: Dictionary in changes:
		armor.changed.emit(&"expired",change["id"],change["before"],0)
		if not check.call(): return step
	step.status = &"APPLIED"; step.reason = &""
	return step
