extends Command
class_name BattleTurnRefill

## Граница хода проходит через очередь, чтобы пополнение инвалидировало старые команды.
var _ids: Array[int] = []
var _revision: int
var _faction: Faction.Type

func _init(ids: Array[int] = [], revision: int = 0, faction: Faction.Type = Faction.Type.PLAYER) -> void:
	_ids = ids.duplicate()
	_revision = revision
	_faction = faction

func get_kind() -> StringName: return &"battle_turn_refill"

func copy_for_queue() -> Command:
	return BattleTurnRefill.new(_ids, _revision, _faction)

func validate(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null: return &"turn/closed"
	if context.get_revision() != _revision: return &"turn/stale_revision"
	if _ids.is_empty(): return &"turn/empty_team"
	var seen: Dictionary = {}
	var move := context.get_move_rules()
	var attack := context.get_attack_rules()
	for id in _ids:
		var unit := context.get_state().get_board().get_unit_by_id(id)
		if unit == null or not unit.is_alive() or unit.faction != _faction or seen.has(id): return &"turn/invalid_unit"
		seen[id] = true
		if context.get_state().is_summon_pending(id):
			var admission := SummonAdmission.extend(move, attack, id, context.get_state().summon_owner_id(id), true)
			if admission.is_empty(): return &"summon/invalid_admission"
			move = admission["move"]
			attack = admission["attack"]
		# Проверяем всю команду до первой записи; плохой максимум не даёт частичный refill.
		var copy := UnitState.from_snapshot_dict(unit.to_snapshot_dict())
		if copy == null: return &"turn/invalid_unit"
		var reason := copy.try_refill_turn_resources()
		if reason != &"": return reason
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var changed := false
	var perk_changes: Dictionary = {}
	for id in _ids:
		var unit := context.get_state().get_board().get_unit_by_id(id)
		reason = unit.try_refill_turn_resources()
		if reason != &"":
			var failure := CommandStepResult.faulted(reason)
			failure.state_changed = changed
			return failure
		changed = true
		unit.guard_stance = false
		if unit.combat_perks != null:
			unit.combat_perks.movement_stopped = false
			unit.combat_perks.reaction_left = 1 if unit.combat_perks.definition.tank_reactions else 0
			perk_changes[id] = CombatPerkGuard.record(unit, unit.combat_perks)
		if context.get_state().is_summon_pending(id):
			var admission := SummonAdmission.extend(context.get_move_rules(), context.get_attack_rules(), id, context.get_state().summon_owner_id(id), true)
			context._move_rules = admission["move"]
			context._attack_rules = admission["attack"]
			for record: Dictionary in context.get_state()._summons:
				if record["unit_id"] == id: record["pending"] = false
	var result := CommandStepResult.applied([], [], [], null, true)
	result.combat_perk_changes = perk_changes
	return result
