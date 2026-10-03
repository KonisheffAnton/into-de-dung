extends Command
class_name BattleTurnRefill

## Граница хода проходит через очередь, чтобы пополнение инвалидировало старые команды.
const BALANCE_RECOVERY: float = 1.0
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
			var admission := SummonAdmission.for_pending(move, attack, id, context.get_state())
			if admission.is_empty(): return &"summon/invalid_admission"
			move = admission["move"]
			attack = admission["attack"]
		# Проверяем всю команду до первой записи; плохой максимум не даёт частичный refill.
		var copy := UnitState.from_snapshot_dict(unit.to_snapshot_dict())
		if copy == null: return &"turn/invalid_unit"
		var reason := copy.try_refill_turn_resources()
		if reason != &"": return reason
	if _needs_recovery(context):
		if _recovery_guard(context) == null or ItemSimulationSnapshot.capture(context.get_state(), []).code != ItemSnapshotResult.Code.OK: return &"turn/invalid_recovery"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var changed := false
	var perk_changes: Dictionary = {}
	# В старых боях без перков очередь не создаёт CombatPerkGuard и не принимает delta.
	var tracks_reactions := context.get_state().get_board().get_all_units().any(func(value: UnitState) -> bool: return value.combat_perks != null)
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
			if not unit.combat_perks.uses_bonus_actions:
				unit.combat_perks.reaction_left = 1 if MeleeThreat.has_reactions(unit) else 0
		# Дополнительные действия есть и у помощника без классовых перков.
		if tracks_reactions: perk_changes[id] = CombatPerkGuard.record(unit, unit.combat_perks)
		if context.get_state().is_summon_pending(id):
			var admission := SummonAdmission.for_pending(context.get_move_rules(), context.get_attack_rules(), id, context.get_state())
			context._move_rules = admission["move"]
			context._attack_rules = admission["attack"]
			for record: Dictionary in context.get_state()._summons:
				if record["unit_id"] == id: record["pending"] = false
	var result := CommandStepResult.applied([], [], [], null, true)
	result.combat_perk_changes = perk_changes
	if _needs_recovery(context): _recover_balance(context, result)
	return result

func _needs_recovery(context: ActionContext) -> bool:
	for id: int in _ids:
		if context.get_state().get_board().get_unit_by_id(id).vitals.get_balance() > 0.0: return true
	return false

func _recovery_guard(context: ActionContext) -> SpatialRules.Guard:
	var units: Array[UnitState] = []
	var stats: Dictionary = {}
	# Сигнал одного бойца не должен незаметно менять следующего получателя
	# восстановления, другие живые тела или состояние поля.
	for unit: UnitState in context.get_state().get_board().get_all_units():
		if not unit.is_alive(): continue
		if unit.stats == null: return null
		units.append(unit)
		stats[unit.id] = unit.stats._stats.keys()
	return SpatialRules.capture_guard(context, units, [], stats)

func _recover_balance(context: ActionContext, result: CommandStepResult) -> void:
	var guard := _recovery_guard(context)
	var snapshot := ItemSimulationSnapshot.capture(context.get_state(), [])
	if guard == null or snapshot.code != ItemSnapshotResult.Code.OK:
		result.status = CommandStepResult.FAULTED
		result.reason = &"turn/invalid_recovery"
		return
	var ids := _ids.duplicate()
	var faction := _faction
	var revision := _revision
	var counters := context.simulation_counters()
	var admission := SummonAdmission.values(context)
	var rng := context.get_rng()
	var rng_before := rng.to_dict().duplicate(true) if rng != null else {}
	var expected_values := snapshot.snapshot.to_dict()
	var item_refs := _item_refs(context.get_state())
	for id: int in ids:
		var unit: UnitState = guard.refs.participants[id].unit
		var before: float = guard.values.participants[id].balance
		var after := maxf(0.0, before - BALANCE_RECOVERY)
		if after == before: continue
		var expected := guard.balance_phase(id, after)
		for row: Dictionary in expected_values.board_snapshot.board.units:
			if int(row.id) == id: row.vitals.balance = after
		# set_balance не проверяет пробой: восстановление не запускает толчок,
		# даже если уменьшенный порог всё ещё ниже накопленного нарушения.
		unit.vitals.set_balance(after)
		if _ids != ids or _faction != faction or _revision != revision or not expected.check(context) or context.simulation_counters() != counters or SummonAdmission.values(context) != admission or context.get_rng() != rng or (rng != null and rng.to_dict() != rng_before):
			result.status = CommandStepResult.FAULTED
			result.reason = &"turn/invalid_recovery"
			return
		# Spatial guard защищает ссылки/боевые значения, но заряды и ledger обычных
		# предметов проверяются полным снимком, ожидаемым ДО сигнала получателя.
		var actual := ItemSimulationSnapshot.capture(context.get_state(), [])
		if actual.code != ItemSnapshotResult.Code.OK or actual.snapshot.to_dict() != expected_values or _item_refs(context.get_state()) != item_refs:
			result.status = CommandStepResult.FAULTED
			result.reason = &"turn/invalid_recovery"
			return
		guard = expected

func _item_refs(state: ItemSimulationState) -> Array:
	var result: Array = []
	for owner: ItemOwnerState in state.get_owners():
		result.append([owner, owner._items.duplicate(), owner._definitions.duplicate()])
		for item: ItemInstance in owner._items.values():
			result.append([item, item._definition, item._effects.duplicate()])
	return result
