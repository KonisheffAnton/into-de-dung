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
	for id in _ids:
		var unit := context.get_state().get_board().get_unit_by_id(id)
		if unit == null or not unit.is_alive() or unit.faction != _faction or seen.has(id): return &"turn/invalid_unit"
		seen[id] = true
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
	for id in _ids:
		var unit := context.get_state().get_board().get_unit_by_id(id)
		reason = unit.try_refill_turn_resources()
		if reason != &"":
			var failure := CommandStepResult.faulted(reason)
			failure.state_changed = changed
			return failure
		changed = true
	return CommandStepResult.applied([], [], [], null, true)
