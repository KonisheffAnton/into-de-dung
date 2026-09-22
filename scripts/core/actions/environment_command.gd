extends Command
class_name EnvironmentCommand

## Внутренняя команда строится только из завершённого события очереди.
var _target: UnitState
var _environment: CombatEnvironmentState
var _cell: Vector2i
var _death: bool = false
var _leaves_body: bool = false
var _faction: int
var _fire: Dictionary = {}
var _seal: Dictionary = {}

static func for_death(event: Dictionary, context: ActionContext) -> EnvironmentCommand:
	var result := EnvironmentCommand.new()
	var state := context.get_state()
	result._target = state.get_board().get_unit_by_id(event["target_unit_id"])
	result._environment = state.environment
	result._death = true
	if result._target == null: return result
	result._cell = result._target.cell
	result._faction = result._target.faction
	var source: Dictionary = event["source"]
	var fell_away: bool = source["kind"] == &"fall" and (not state.get_board().is_in_bounds(source["origin_cell"]) or state.get_board().is_lethal(source["origin_cell"]))
	result._leaves_body = not fell_away and state.summon_owner_id(result._target.id) == 0 and state.get_board().is_in_bounds(result._cell) and not state.get_board().is_lethal(result._cell)
	result._seal = result._values()
	return result

static func for_entry(id: int, cell: Vector2i, context: ActionContext) -> EnvironmentCommand:
	var result := EnvironmentCommand.new()
	result._target = context.get_state().get_board().get_unit_by_id(id)
	result._environment = context.get_state().environment
	result._cell = cell
	result._fire = result._environment.fire_at(cell)
	result._seal = result._values()
	return result

func _values() -> Dictionary:
	return {"target": _target, "environment": _environment, "cell": _cell, "death": _death, "leaves_body": _leaves_body, "faction": _faction, "fire": _fire.duplicate(true)}

func get_kind() -> StringName: return &"environment_death" if _death else &"fire_entry"

func copy_for_queue() -> Command:
	var copy := EnvironmentCommand.new()
	copy._target = _target; copy._environment = _environment; copy._cell = _cell
	copy._death = _death; copy._leaves_body = _leaves_body; copy._faction = _faction
	copy._fire = _fire.duplicate(true); copy._seal = _seal.duplicate(true)
	return copy

func validate(context: ActionContext) -> StringName:
	if context == null or _values() != _seal or _environment == null or _target == null: return &"environment/invalid_binding"
	if context.get_state().environment != _environment or context.get_state().get_board().get_unit_by_id(_target.id) != _target: return &"environment/invalid_binding"
	if _death:
		if _target.is_alive() or _target.cell != _cell or _target.faction != _faction: return &"environment/invalid_death"
	elif _environment.fire_at(_cell) != _fire or _fire.is_empty() or _target.armor == null:
		return &"environment/invalid_fire"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if _death:
		if _environment.processed_deaths.has(_target.id): return CommandStepResult.skipped(&"environment/death_recorded")
		if _environment.processed_deaths.size() >= 65536 or (_leaves_body and (_environment.corpses.size() >= CombatEnvironmentState.MAX_RECORDS or _environment.next_corpse_id >= ActionContext.MAX_ID - 1)): return CommandStepResult.faulted(&"environment/corpse_limit")
		var corpse := _environment.record_death(_target.id, _cell, _faction, "humanoid", _leaves_body)
		var events: Array[Dictionary] = []
		if not corpse.is_empty(): events.append({"kind": &"corpse_created", "actor_unit_id": 0, "target_unit_id": _target.id, "corpse": corpse})
		return CommandStepResult.applied(events, [], [], null, true)
	if not _target.is_alive(): return CommandStepResult.skipped(&"environment/dead_target")
	var guard := SpatialRules.capture_guard(context, [_target], [_target.cell, _cell], {_target.id: [StatTypes.StatType.HP_MAX]})
	if guard == null: return CommandStepResult.faulted(&"environment/invalid_fire")
	var source := DamageSource.new(&"cell", _fire["id"], _cell)
	var raw: Array[Dictionary] = [{"type": "fire", "policy": "standard", "source": "fire_cell", "numerator": _fire["damage"], "denominator": 1}]
	var request := ArmorAttack.request(_target.id, raw, source)
	var hit := ArmorHitExecutor.execute(request, guard, context)
	return hit["result"]
