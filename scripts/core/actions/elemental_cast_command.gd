extends Command
class_name ElementalCastCommand

const RANGE: float = 3.0
const FIRE_DAMAGE: int = 4
var _actor_id: int
var _target_id: int
var _effect: StringName
var _revision: int
var _ticks: int

func _init(actor: int = 0, target: int = 0, effect: StringName = &"", revision: int = 0, ticks: int = 1) -> void:
	_actor_id = actor; _target_id = target; _effect = effect; _revision = revision; _ticks = ticks
func get_kind() -> StringName: return &"elemental_cast"
func copy_for_queue() -> Command: return ElementalCastCommand.new(_actor_id, _target_id, _effect, _revision, _ticks)
func _values() -> Array: return [_actor_id, _target_id, _effect, _revision, _ticks]
func validate(context: ActionContext) -> StringName: return _prepare(context).get("reason", &"")

func _prepare(context: ActionContext) -> Dictionary:
	if context == null or _revision < 0 or _revision > ActionContext.MAX_ID - 2 or _revision != context.get_revision(): return {"reason": &"status/stale_revision"}
	if _effect not in [&"burning", &"wet", &"freeze"] or _ticks < 1: return {"reason": &"status/invalid_effect"}
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(_actor_id)
	var target := board.get_unit_by_id(_target_id)
	if not ElementalRules.valid_unit(actor) or not ElementalRules.valid_unit(target) or actor.armor == null or target.armor == null: return {"reason": &"status/capability_required"}
	if not actor.is_alive() or not target.is_alive(): return {"reason": &"status/dead_target"}
	if context.get_state().is_summon_pending(actor.id): return {"reason": &"summon/pending"}
	var reason := ControlRules.action_reason(actor)
	if reason != &"": return {"reason": reason}
	if context.get_move_rules() == null or context.get_move_rules().validate() != &"" or not context.get_move_rules().allows(actor.id): return {"reason": &"status/not_admitted"}
	if actor.action_resources == null or actor.action_resources.get_main_left() < 1: return {"reason": &"status/insufficient_main"}
	if actor != target:
		reason = AttackReachCheck.inspect_spatial_cells(board, actor.cell, actor.faction, target.cell, RANGE)
		if reason != &"": return {"reason": reason}
	var participants: Array[UnitState] = [actor]
	if actor != target: participants.append(target)
	var guard := SpatialRules.capture_guard(context, participants, [actor.cell, target.cell], {target.id: [StatTypes.StatType.HP_MAX]})
	if guard == null: return {"reason": &"status/invalid_runtime"}
	var source := DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	var view: Dictionary = guard.values["participants"][target.id]["armor"]
	var request: DamageRequest
	var eligible := true
	if _effect == &"burning":
		var extras: Array[Dictionary] = [{"type": "fire", "policy": "standard", "source": "ignite", "numerator": FIRE_DAMAGE, "denominator": 1, "factor_num": 1, "factor_den": 1}]
		var height := board.get_height_steps(actor.cell) - board.get_height_steps(target.cell)
		var raw := ArmorAttack.components(0.0, 0.0, height, target.guard_stance, extras, 0, 2 if ElementalRules.is_frozen(target) else 1)
		# Нулевую оружейную базу не переносим в объяснение чисто огненной способности.
		if not raw.is_empty(): raw.remove_at(0)
		request = ArmorAttack.request(target.id, raw, source)
		request.attack_group_id = context.damage_attack_group()
		var plan := ArmorHitExecutor.prepare(request, view, target.vitals.get_hp(), ActionHpExecutor._stat_value(target, StatTypes.StatType.HP_MAX), context.get_rng(), ElementalRules.is_frozen(target), context)
		if plan.get("reason", &"") != &"": return plan
		if plan["hp_after"] == 0 and board.board_version >= ActionContext.MAX_ID: return {"reason": &"push/board_version_exhausted"}
		eligible = actor.combat_perks != null and actor.combat_perks.definition.burning_bypass_hp_gate
		for row: Dictionary in plan["rows"]:
			if row["type"] == &"fire" and row["hp_damage"] > 0: eligible = true
		# Мёртвую цель уже не меняем; overflow её статуса не запрещает летальный hit.
		if plan["hp_after"] == 0: eligible = false
	var transition := ElementalRules.transition(target.elemental.to_dict(), _effect, _ticks, source.to_dict(), ElementalRules.freeze_gate(view)) if eligible else {"reason": &"", "after": target.elemental.to_dict()}
	if transition["reason"] != &"": return transition
	return {"reason": &"", "actor": actor, "target": target, "guard": guard, "source": source, "request": request, "after": transition["after"], "eligible": eligible}

func execute(context: ActionContext) -> CommandStepResult:
	var planned := _prepare(context)
	if planned["reason"] != &"": return CommandStepResult.faulted(planned["reason"])
	var seal := _values()
	var actor: UnitState = planned["actor"]
	var target: UnitState = planned["target"]
	var guard: SpatialRules.Guard = planned["guard"]
	var before := actor.action_resources.get_main_left()
	var result := CommandStepResult.applied([], [], [], null, true)
	guard = guard.debit(actor.id, 1, 0.0)
	var spent := actor.action_resources.try_spend_main(1)
	result.events.append({"kind": &"elemental_cast", "actor_unit_id": actor.id, "target_unit_id": target.id, "effect": _effect, "main_before": before, "main_after": before - 1})
	if not spent or _values() != seal or not guard.check(context):
		result.status = &"FAULTED"; result.reason = &"status/checkpoint"
		return result
	guard = guard.stance(actor.id, false)
	actor.guard_stance = false
	actor.has_attacked = true
	if planned["request"] != null:
		var hit := ArmorHitExecutor.execute(planned["request"], guard, context, func() -> bool: return _values() == seal)
		var hit_result: CommandStepResult = hit["result"]
		result.events.append_array(hit_result.events)
		result.status = hit_result.status; result.reason = hit_result.reason
		if hit_result.status != &"APPLIED" or not target.is_alive(): return result
		guard = hit["guard"]
	if planned["eligible"]:
		var write := ElementalRules.write(target, planned["after"], guard, context, _effect, actor.id)
		var write_result: CommandStepResult = write["result"]
		result.events.append_array(write_result.events)
		result.status = write_result.status; result.reason = write_result.reason
	if _values() != seal:
		result.status = &"FAULTED"; result.reason = &"status/checkpoint"
	return result
