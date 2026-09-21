extends RefCounted
class_name BalancePushRules

## Preflight хранит ссылки и снимок значений, чтобы дочерние команды не доверяли
## изменяемому payload после оплаты атаки.
class Binding extends RefCounted:
	var values: Dictionary = {}
	var _seal: Dictionary = {}
	var context: ActionContext
	var state: ItemSimulationState
	var board: BattleBoard
	var actor: UnitState
	var target: UnitState
	var blocker: UnitState
	var actor_stats: StatsBag
	var target_stats: StatsBag
	var actor_vitals: Vitals
	var target_vitals: Vitals
	var blocker_stats: StatsBag
	var blocker_vitals: Vitals
	var actor_owner: ItemOwnerState
	var target_owner: ItemOwnerState
	var blocker_owner: ItemOwnerState
	var actor_resources: ActionResources
	var attack_source: DamageSource
	var first: DamageRequest
	var second: DamageRequest
	var first_seal: DamageRequest
	var second_seal: DamageRequest
	var spatial_guard: SpatialRules.Guard
	var _spatial_ref_seal: Array = []
	func copy() -> Binding:
		var result := Binding.new()
		result.values = values.duplicate(true)
		result._seal = _seal.duplicate(true)
		result.context = context; result.state = state; result.board = board
		result.actor = actor; result.target = target; result.blocker = blocker
		result.actor_stats = actor_stats; result.target_stats = target_stats; result.actor_vitals = actor_vitals; result.target_vitals = target_vitals
		result.blocker_stats = blocker_stats; result.blocker_vitals = blocker_vitals
		result.actor_owner = actor_owner; result.target_owner = target_owner; result.blocker_owner = blocker_owner; result.actor_resources = actor_resources
		result.attack_source = attack_source.copy() if attack_source != null else null
		result.first = first.copy() if first != null else null
		result.second = second.copy() if second != null else null
		result.first_seal = first_seal.copy() if first_seal != null else null
		result.second_seal = second_seal.copy() if second_seal != null else null
		result.spatial_guard = spatial_guard.copy() if spatial_guard != null else null
		result._spatial_ref_seal = _spatial_ref_seal.duplicate()
		return result
	func seal() -> void:
		_seal = values.duplicate(true)
		if values.get("spatial", false): _spatial_ref_seal = _spatial_refs()
	func _spatial_refs() -> Array:
		return [context, state, board, actor, target, blocker, actor_stats, target_stats, actor_vitals, target_vitals, blocker_stats, blocker_vitals, actor_owner, target_owner, blocker_owner, actor_resources]
	func sealed() -> bool:
		return values == _seal and (not _seal.get("spatial", false) or (_spatial_refs() == _spatial_ref_seal and spatial_guard != null and spatial_guard.sealed()))

static func _empty() -> Dictionary:
	return {"reason": &"", "binding": null}

static func prepare_attack(context: ActionContext, actor: UnitState, target: UnitState, raw_attack: float, hit_amount: float, main_after: int, spatial: bool = false, armor_request: DamageRequest = null) -> Dictionary:
	if spatial: return _prepare_spatial_attack(context, actor, target, raw_attack, hit_amount, main_after, armor_request)
	var out := _empty()
	if context == null or context.get_state() == null or context.get_state().get_board() == null or actor == null or target == null or actor.get_script() != UnitState or target.get_script() != UnitState:
		out["reason"] = &"balance/invalid_binding"; return out
	if not is_finite(raw_attack) or not is_finite(hit_amount) or hit_amount < 1.0 or main_after < 0:
		out["reason"] = &"balance/invalid_stat"; return out
	if actor.stats == null or target.stats == null or actor.vitals == null or target.vitals == null or actor.stats.get_script() != StatsBag or target.stats.get_script() != StatsBag or actor.vitals.get_script() != Vitals or target.vitals.get_script() != Vitals or actor.vitals._stats != actor.stats or target.vitals._stats != target.stats:
		out["reason"] = &"balance/invalid_binding"; return out
	var actor_copy := StatsBag.from_snapshot_dict(actor.stats.to_snapshot_dict())
	var target_copy := StatsBag.from_snapshot_dict(target.stats.to_snapshot_dict())
	if actor_copy == null or target_copy == null or not actor_copy.has_stat(StatTypes.StatType.IMPACT_POWER) or not target_copy.has_stat(StatTypes.StatType.BALANCE_MAX):
		out["reason"] = &"balance/missing_stat"; return out
	var impact := actor_copy.get_value(StatTypes.StatType.IMPACT_POWER)
	var maximum := target_copy.get_value(StatTypes.StatType.BALANCE_MAX)
	var before := target.vitals.get_balance()
	var hp_before := target.vitals.get_hp()
	if not is_finite(impact) or impact < 0.0 or not is_finite(maximum) or not is_finite(before) or before < 0.0 or not is_finite(hp_before) or hp_before < 0.0:
		out["reason"] = &"balance/invalid_stat"; return out
	# Иммунитет и нулевой impact не вычисляют сумму: импортированный over-max
	# balance остаётся наблюдаемым и не отклоняет постороннюю атаку.
	var sum := before
	if target.guard_stance: impact *= 0.5
	if impact > 0.0 and maximum > 0.0:
		sum = before + impact
		if not is_finite(sum): out["reason"] = &"balance/nonfinite_sum"; return out
	var broke := impact > 0.0 and maximum > 0.0 and sum >= maximum
	var after := 0.0 if broke else sum
	var binding := Binding.new()
	binding.context = context; binding.state = context.get_state(); binding.board = binding.state.get_board(); binding.actor = actor; binding.target = target
	binding.actor_stats = actor.stats; binding.target_stats = target.stats; binding.actor_vitals = actor.vitals; binding.target_vitals = target.vitals; binding.actor_owner = binding.state.get_owner(actor.id); binding.target_owner = binding.state.get_owner(target.id); binding.actor_resources = actor.action_resources
	binding.attack_source = DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	binding.values = {"raw_attack": raw_attack, "hit_amount": hit_amount, "impact": impact, "balance_before": before, "balance_max": maximum, "balance_after": after, "broke": broke, "expected_hp_before": hp_before, "expected_hp": maxf(0.0, hp_before - hit_amount), "expected_alive": hp_before > hit_amount, "actor_id": actor.id, "target_id": target.id, "actor_cell": actor.cell, "target_cell": target.cell, "main_after": main_after, "phase": &"balance"}
	# Запечатываем до admission-resolve: prepare_push не принимает незапечатанный
	# payload только потому, что он ещё находится внутри root preflight.
	binding.seal()
	if binding_reason(binding, context, &"balance", true, true) != &"":
		out["reason"] = &"balance/invalid_binding"
		return out
	if broke and target.vitals.get_hp() > hit_amount and maximum > 0.0:
		var pushed := prepare_push(binding, context, true)
		if pushed.get("reason", &"") != &"":
			out["reason"] = pushed["reason"]
			return out
		binding.values["admission_board_touches"] = int(pushed.get("board_touches", 0))
		binding.seal()
	out["binding"] = binding
	return out

static func prepare_push(binding: Binding, context: ActionContext, admission: bool = false) -> Dictionary:
	if binding != null and binding.values.get("spatial", false): return _prepare_spatial_push(binding, context, admission)
	var out := {"reason": &"", "outcome": PushResult.Outcome.MOVED, "blocked_reason": &"", "from_cell": Vector2i.ZERO, "attempted_cell": Vector2i.ZERO, "fall_height": 0, "first": null, "second": null, "binding": null, "board_touches": 0}
	if binding == null or not binding.sealed() or context == null or binding.context != context or binding.board == null or binding.actor == null or binding.target == null:
		return _push_failure(&"push/invalid_binding")
	var board := binding.board
	var target := binding.target
	var actor := binding.actor
	var phase: StringName = &"balance" if admission else StringName(binding.values.get("phase", &""))
	if binding_reason(binding, context, phase, admission, admission) != &"": return _push_failure(&"push/invalid_binding")
	var from_cell: Vector2i = binding.values.get("target_cell", target.cell)
	var actor_cell: Vector2i = binding.values.get("actor_cell", actor.cell)
	var direction := from_cell - actor_cell
	if absi(direction.x) + absi(direction.y) != 1: return _push_failure(&"push/invalid_direction")
	var resolved := PushResolver.resolve_push(board, target, from_cell, direction, 0)
	var attempted := from_cell + direction
	out["outcome"] = resolved.outcome; out["blocked_reason"] = resolved.blocked_reason; out["from_cell"] = from_cell; out["attempted_cell"] = attempted; out["fall_height"] = resolved.fall_height
	var impact := float(binding.values.get("raw_attack", 0.0))
	var armor_target := NAN
	# Armor требуется только в ветках с числовым HP damage; lethal terrain и
	# обычный forced move не зависят от отсутствующего либо испорченного stat.
	if resolved.outcome == PushResult.Outcome.BLOCKED or resolved.outcome == PushResult.Outcome.COLLISION or (resolved.outcome == PushResult.Outcome.MOVED and resolved.fall_height > 0):
		armor_target = _stat(target, StatTypes.StatType.ARMOR)
		if not is_finite(armor_target): return _push_failure(&"push/invalid_stat")
	var source_kind: StringName = &"collision" if resolved.outcome == PushResult.Outcome.BLOCKED or resolved.outcome == PushResult.Outcome.COLLISION else &"fall"
	var source := DamageSource.new(source_kind, 0, attempted, actor.id, actor.id)
	var future_entry_kills := false
	if resolved.outcome == PushResult.Outcome.BLOCKED:
		var raw_amount := impact - armor_target
		if not is_finite(raw_amount): return _push_failure(&"push/nonfinite_damage")
		var amount := maxf(1.0, raw_amount)
		out["first"] = DamageRequest.new(target.id, amount, &"physical", &"bypass", source)
	elif resolved.outcome == PushResult.Outcome.COLLISION:
		var blocker: UnitState = resolved.blocker
		if blocker == null: return _push_failure(&"push/invalid_binding")
		var armor_blocker := _stat(blocker, StatTypes.StatType.ARMOR)
		if not is_finite(armor_blocker): return _push_failure(&"push/invalid_stat")
		var target_raw := impact - armor_target
		var blocker_raw := impact - armor_blocker
		if not is_finite(target_raw) or not is_finite(blocker_raw): return _push_failure(&"push/nonfinite_damage")
		out["first"] = DamageRequest.new(target.id, maxf(1.0, target_raw), &"physical", &"bypass", source)
		out["second"] = DamageRequest.new(blocker.id, maxf(1.0, blocker_raw), &"physical", &"bypass", source)
		var stage := binding.copy()
		stage.blocker = blocker
		stage.blocker_stats = blocker.stats
		stage.blocker_vitals = blocker.vitals
		stage.blocker_owner = context.get_state().get_owner(blocker.id)
		stage.values["blocker_id"] = blocker.id
		stage.values["blocker_cell"] = blocker.cell
		stage.values["blocker_hp"] = blocker.vitals.get_hp()
		stage.values["blocker_alive"] = blocker.is_alive()
		stage.seal()
		out["binding"] = stage
		# Admission резервирует возможный вход на одну клетку после смерти blocker.
		# Resolver не проходит сквозь живого blocker, поэтому смотрим topology
		# этой клетки без временного изменения occupancy доски.
		var target_after := float(binding.values.get("expected_hp", 0.0)) - float((out["first"] as DamageRequest).amount)
		var blocker_after := blocker.vitals.get_hp() - float((out["second"] as DamageRequest).amount)
		if target_after > 0.0 and blocker_after <= 0.0:
			var delta64: int = int(board.get_height(attempted)) - int(board.get_height(from_cell))
			if delta64 < 0 and not TerrainType.is_lethal(board.get_terrain(attempted)):
				var future_max := _stat(target, StatTypes.StatType.HP_MAX)
				var scaled := future_max * 0.25
				var future_amount := scaled * float(-delta64) - armor_target
				if not is_finite(future_max) or future_max < 0.0 or not is_finite(scaled) or not is_finite(future_amount) or not is_finite(maxf(1.0, future_amount)):
					return _push_failure(&"push/nonfinite_damage")
				future_entry_kills = target_after <= maxf(1.0, future_amount)
	elif resolved.outcome == PushResult.Outcome.MOVED and resolved.fall_height > 0:
		var hp_max := _stat(target, StatTypes.StatType.HP_MAX)
		var scaled := hp_max * 0.25
		var raw_amount := scaled * float(resolved.fall_height) - armor_target
		if not is_finite(hp_max) or hp_max < 0.0 or not is_finite(scaled) or not is_finite(raw_amount): return _push_failure(&"push/nonfinite_damage")
		var amount := maxf(1.0, raw_amount)
		out["first"] = DamageRequest.new(target.id, amount, &"physical", &"bypass", source)
	if out["first"] != null and ActionHpExecutor.validate_damage(out["first"], context) != &"":
		# Запросы уже содержат armor-free amount; validation требуется только для формы/цели.
		return _push_failure(&"push/invalid_request")
	if out["second"] != null and ActionHpExecutor.validate_damage(out["second"], context) != &"":
		return _push_failure(&"push/invalid_request")
	# Сохраняем identity collision из stage выше. Сборка от исходного binding
	# стирала blocker и делала каждое столкновение stale при исполнении.
	var result_binding: Binding = out["binding"] as Binding
	if result_binding == null:
		result_binding = binding.copy()
	result_binding.first = (out["first"] as DamageRequest).copy() if out["first"] != null else null
	result_binding.second = (out["second"] as DamageRequest).copy() if out["second"] != null else null
	result_binding.first_seal = result_binding.first.copy() if result_binding.first != null else null
	result_binding.second_seal = result_binding.second.copy() if result_binding.second != null else null
	result_binding.values["phase"] = &"push"
	result_binding.values["from_cell"] = from_cell
	result_binding.values["attempted_cell"] = attempted
	result_binding.values["outcome"] = resolved.outcome
	result_binding.values["fall_height"] = resolved.fall_height
	result_binding.values["expected_target_hp"] = target.vitals.get_hp()
	result_binding.values["expected_target_alive"] = target.is_alive()
	result_binding.seal()
	out["binding"] = result_binding
	if resolved.outcome == PushResult.Outcome.BLOCKED:
		out["board_touches"] = 1 if float(binding.values.get("expected_hp", 0.0)) - float((out["first"] as DamageRequest).amount) <= 0.0 else 0
	elif resolved.outcome == PushResult.Outcome.MOVED:
		out["board_touches"] = 2 if out["first"] != null and float(binding.values.get("expected_hp", 0.0)) - float((out["first"] as DamageRequest).amount) <= 0.0 else 1
	elif resolved.outcome == PushResult.Outcome.FELL:
		out["board_touches"] = 1 if not board.is_in_bounds(attempted) else 2
	elif resolved.outcome == PushResult.Outcome.COLLISION and out["second"] != null:
		var target_after_collision := float(binding.values.get("expected_hp", 0.0)) - float((out["first"] as DamageRequest).amount)
		var blocker_after_collision := (resolved.blocker as UnitState).vitals.get_hp() - float((out["second"] as DamageRequest).amount)
		if target_after_collision > 0.0 and blocker_after_collision <= 0.0:
			# cleanup blocker и вход, плюс cleanup при lethal entry.
			out["board_touches"] = 3 if TerrainType.is_lethal(board.get_terrain(attempted)) or future_entry_kills else 2
		elif target_after_collision <= 0.0 and blocker_after_collision <= 0.0:
			out["board_touches"] = 2
		elif target_after_collision <= 0.0 or blocker_after_collision <= 0.0:
			out["board_touches"] = 1
	return out

static func _push_failure(reason: StringName = &"push/invalid_binding") -> Dictionary:
	return {"reason": reason, "outcome": PushResult.Outcome.MOVED, "blocked_reason": &"", "from_cell": Vector2i.ZERO, "attempted_cell": Vector2i.ZERO, "fall_height": 0, "first": null, "second": null, "binding": null, "board_touches": 0}

static func _stat(unit: UnitState, type: StatTypes.StatType) -> float:
	if unit == null or unit.stats == null: return NAN
	var copy := StatsBag.from_snapshot_dict(unit.stats.to_snapshot_dict())
	return NAN if copy == null or not copy.has_stat(type) else copy.get_value(type)

static func binding_reason(binding: Binding, context: ActionContext, phase: StringName, before_hit: bool = false, admission: bool = false) -> StringName:
	if binding != null and binding._seal.get("spatial", false):
		return &"" if spatial_valid(binding, context, phase, admission) else &"push/invalid_binding"
	if binding == null or not binding.sealed() or context == null or binding.context != context or binding.state != context.get_state() or binding.board == null or binding.state == null or binding.state.get_board() != binding.board:
		return &"push/invalid_binding"
	if context.get_script() != ActionContext or binding.state.get_script() != ItemSimulationState or binding.board.get_script() != BattleBoard:
		return &"push/invalid_binding"
	var actor := binding.actor
	var target := binding.target
	if actor == null or target == null or actor.get_script() != UnitState or target.get_script() != UnitState or actor.id != int(binding.values.get("actor_id", 0)) or target.id != int(binding.values.get("target_id", 0)) or actor.id == target.id:
		return &"push/invalid_binding"
	if binding.board.get_unit_by_id(actor.id) != actor or binding.board.get_unit_by_id(target.id) != target or not actor.is_alive() or not target.is_alive() or actor.cell != binding.values.get("actor_cell", Vector2i.ZERO) or target.cell != binding.values.get("target_cell", Vector2i.ZERO) or binding.board.occupant_at(actor.cell) != actor or binding.board.occupant_at(target.cell) != target:
		return &"push/invalid_binding"
	if actor.stats != binding.actor_stats or target.stats != binding.target_stats or actor.vitals != binding.actor_vitals or target.vitals != binding.target_vitals or actor.stats == null or target.stats == null or actor.vitals == null or target.vitals == null or actor.vitals._stats != actor.stats or target.vitals._stats != target.stats:
		return &"push/invalid_binding"
	if actor.stats.get_script() != StatsBag or target.stats.get_script() != StatsBag or actor.vitals.get_script() != Vitals or target.vitals.get_script() != Vitals:
		return &"push/invalid_binding"
	if binding.state.get_owner(actor.id) != binding.actor_owner or binding.state.get_owner(target.id) != binding.target_owner or binding.actor_owner == null or binding.target_owner == null or binding.actor_owner.get_owner() != actor or binding.target_owner.get_owner() != target:
		return &"push/invalid_binding"
	if binding.actor_owner.get_script() != ItemOwnerState or binding.target_owner.get_script() != ItemOwnerState:
		return &"push/invalid_binding"
	var source := binding.attack_source
	if source == null or source.kind != &"attack" or source.source_instance_id != 0 or source.origin_cell != binding.values.get("actor_cell") or source.instigator_unit_id != actor.id or source.credit_unit_id != actor.id or not requests_sealed(binding):
		return &"push/invalid_binding"
	var expected_main := int(binding.values.get("main_after", -1)) + (1 if admission else 0)
	if actor.action_resources != binding.actor_resources or binding.actor_resources == null or binding.actor_resources.get_script() != ActionResources or binding.actor_resources.validate(actor.id) != &"" or binding.actor_resources.get_main_left() != expected_main:
		return &"push/invalid_binding"
	if not is_finite(float(binding.values.get("raw_attack", NAN))) or not is_finite(float(binding.values.get("impact", NAN))) or float(binding.values.get("impact", -1.0)) < 0.0 or not is_finite(float(binding.values.get("hit_amount", NAN))) or float(binding.values.get("hit_amount", 0.0)) < 1.0 or binding.values.get("phase", &"") != phase:
		return &"push/invalid_binding"
	# Даже отказ admission не должен прогревать или исправлять живой stat cache.
	var maximum := _stat(target, StatTypes.StatType.BALANCE_MAX)
	if phase == &"balance" and (target.vitals.get_balance() != float(binding.values.get("balance_before", NAN)) or maximum != float(binding.values.get("balance_max", NAN))):
		return &"push/invalid_binding"
	if (phase == &"push" or phase == &"after_collision" or phase == &"push_damage") and (target.vitals.get_balance() != float(binding.values.get("balance_after", NAN)) or maximum != float(binding.values.get("balance_max", NAN))):
		return &"push/invalid_binding"
	if before_hit:
		return &"" if target.vitals.get_hp() == float(binding.values.get("expected_hp_before", NAN)) else &"push/invalid_binding"
	if target.vitals.get_hp() != float(binding.values.get("expected_hp", NAN)) or target.is_alive() != bool(binding.values.get("expected_alive", false)):
		return &"push/invalid_binding"
	return &""

static func requests_sealed(binding: Binding) -> bool:
	return _same_request(binding.first, binding.first_seal) and _same_request(binding.second, binding.second_seal)

static func _same_request(left: DamageRequest, right: DamageRequest) -> bool:
	if left == null and right == null: return true
	if left == null or right == null or left.target_unit_id != right.target_unit_id or left.amount != right.amount or left.damage_type != right.damage_type or left.armor_mode != right.armor_mode or left.source == null or right.source == null: return false
	return left.source.to_dict() == right.source.to_dict() and left.armor_components == right.armor_components

static func spatial_valid(binding: Binding, context: ActionContext, phase: StringName, admission: bool = false) -> bool:
	if not binding.sealed() or binding.context != context or binding.values.get("phase") != phase or not requests_sealed(binding): return false
	var guard := binding.spatial_guard
	if guard.refs["context"] != context or guard.refs["state"] != binding.state or guard.refs["board"] != binding.board: return false
	if binding.values.get("board_origin_version") != guard.values["board_origin_version"] or binding.values.get("expected_board_version") != guard.values["expected_board_version"]: return false
	if binding.attack_source == null or binding.attack_source.to_dict() != binding.values.get("attack_source"): return false
	for role: String in ["actor", "target", "blocker"]:
		var unit: UnitState = binding.get(role)
		if unit == null:
			if role != "blocker": return false
			continue
		var id: int = binding.values.get(role + "_id", 0)
		if not guard.refs["participants"].has(id): return false
		var pinned: Dictionary = guard.refs["participants"][id]
		if pinned["unit"] != unit or pinned["stats"] != binding.get(role + "_stats") or pinned["vitals"] != binding.get(role + "_vitals") or pinned["owner"] != binding.get(role + "_owner"): return false
	return guard.debit(binding.actor.id, -1, 0.0).stance(binding.actor.id, binding.values["actor_guard_before"]).check(context) if admission else guard.check(context)

static func spatial_phase(binding: Binding, guard: SpatialRules.Guard, phase: StringName) -> Binding:
	var next := binding.copy()
	next.spatial_guard = guard.copy()
	next.values["phase"] = phase
	next.values["board_origin_version"] = guard.values["board_origin_version"]
	next.values["expected_board_version"] = guard.values["expected_board_version"]
	for role: String in ["actor", "target", "blocker"]:
		if next.get(role) == null: continue
		var v: Dictionary = guard.values["participants"][next.values[role + "_id"]]
		next.values[role + "_cell"] = v["cell"]
		next.values[role + "_height_steps"] = v["height_steps"]
	var target: Dictionary = guard.values["participants"][next.values["target_id"]]
	next.values["expected_hp"] = target["hp"]
	next.values["expected_alive"] = target["alive"]
	next.seal()
	return next

static func spatial_hp(binding: Binding, request: DamageRequest, context: ActionContext, reason: StringName, explicit_death: bool = false) -> Dictionary:
	var failed := {"result": CommandStepResult.faulted(reason), "binding": binding}
	if binding == null or not spatial_valid(binding, context, binding.values.get("phase", &"")) or request == null: return failed
	var id := request.target_unit_id
	var guard := binding.spatial_guard
	if not guard.values["participants"].has(id): return failed
	var before: Dictionary = guard.values["participants"][id]
	if not before["alive"]: return failed
	if request.armor_mode == &"armor" and not explicit_death:
		var seal_check := func() -> bool: return binding.sealed() and requests_sealed(binding)
		var hit := ArmorHitExecutor.execute(request, guard, context, seal_check)
		var result: CommandStepResult = hit["result"]
		return {"result": result, "binding": spatial_phase(binding, hit["guard"], binding.values["phase"]) if result.status == &"APPLIED" else binding}
	var amount := maxf(float(before["hp"]), 1.0) if explicit_death else request.amount
	var lethal := amount > 0.0 and amount >= float(before["hp"])
	if lethal and int(guard.values["expected_board_version"]) >= ActionContext.MAX_ID:
		failed["result"] = CommandStepResult.faulted(&"push/board_version_exhausted")
		return failed
	var written := guard.hp_phase(id, amount, false)
	var done := guard.hp_phase(id, amount, lethal)
	var checkpoint := func(stage: StringName) -> StringName:
		if not binding.sealed() or not requests_sealed(binding): return reason
		var expected := written if stage == &"hp_written" else done
		return &"" if expected.check(context) else reason
	var result := ActionHpExecutor.death_spatial(id, request.source, context, checkpoint) if explicit_death else ActionHpExecutor.damage_spatial(request, context, checkpoint)
	if result.status == &"APPLIED" and (not binding.sealed() or not done.check(context)):
		result.status = &"FAULTED"; result.reason = reason
	if result.status != &"APPLIED":
		result.reason = reason
		return {"result": result, "binding": binding}
	return {"result": result, "binding": spatial_phase(binding, done, binding.values["phase"])}

static func _prepare_spatial_attack(context: ActionContext, actor: UnitState, target: UnitState, raw_attack: float, hit_amount: float, main_after: int, armor_request: DamageRequest = null) -> Dictionary:
	var out := _empty()
	if context == null or context.get_state() == null or context.get_state().get_board() == null or actor == null or target == null or actor.vitals == null or target.vitals == null or actor.stats == null or target.stats == null:
		out["reason"] = &"balance/invalid_binding"; return out
	if not is_finite(raw_attack) or not is_finite(hit_amount) or (hit_amount < 1.0 and armor_request == null) or main_after < 0:
		out["reason"] = &"balance/invalid_stat"; return out
	var state := context.get_state()
	var board := state.get_board()
	if not board.is_in_bounds(actor.cell) or not board.is_in_bounds(target.cell) or actor.cell == target.cell or (actor.cell.x != target.cell.x and actor.cell.y != target.cell.y):
		out["reason"] = &"balance/invalid_binding"; return out
	var impact := _stat(actor, StatTypes.StatType.IMPACT_POWER)
	var maximum := _stat(target, StatTypes.StatType.BALANCE_MAX)
	var before := target.vitals.get_balance()
	var multiplier := SpatialRules.height_multiplier(board.get_height_steps(actor.cell) - board.get_height_steps(target.cell))
	if not is_finite(impact) or impact < 0.0 or not is_finite(maximum) or not is_finite(before) or before < 0.0:
		out["reason"] = &"balance/invalid_stat"; return out
	if impact > 0.0:
		impact *= multiplier
		if not is_finite(impact): out["reason"] = &"balance/invalid_stat"; return out
		impact = maxf(1.0, impact)
	if target.guard_stance: impact *= 0.5
	var total := before + impact if impact > 0.0 and maximum > 0.0 else before
	if not is_finite(total): out["reason"] = &"balance/nonfinite_sum"; return out
	var broke := impact > 0.0 and maximum > 0.0 and total >= maximum
	var direction := PushResolver.compute_push_direction(actor.cell, target.cell)
	var destination := target.cell + direction
	var cells: Array[Vector2i] = []
	var cell := actor.cell
	while cell != target.cell:
		cells.append(cell); cell += direction
	cells.append(target.cell)
	if board.is_in_bounds(destination): cells.append(destination)
	var units: Array[UnitState] = [actor, target]
	var types := {actor.id: [StatTypes.StatType.STRENGTH, StatTypes.StatType.WEAPON_DAMAGE, StatTypes.StatType.ATTACK_RANGE, StatTypes.StatType.IMPACT_POWER, StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX], target.id: [StatTypes.StatType.ARMOR, StatTypes.StatType.BALANCE_MAX]}
	var blocker: UnitState = null
	if broke and target.vitals.get_hp() > hit_amount:
		var resolved := PushResolver.resolve_push_steps(board, target, target.cell, direction, 1)
		if resolved.outcome == PushResult.Outcome.COLLISION:
			blocker = resolved.blocker
			if armor_request != null and blocker.armor == null:
				out["reason"] = &"armor/capability_required"; return out
			units.append(blocker)
			types[blocker.id] = [StatTypes.StatType.ARMOR]
		if resolved.outcome in [PushResult.Outcome.COLLISION, PushResult.Outcome.MOVED] and board.is_in_bounds(destination) and not board.is_lethal(destination) and board.get_height_steps(target.cell) - board.get_height_steps(destination) >= 2:
			types[target.id].append(StatTypes.StatType.HP_MAX)
	if armor_request != null:
		for participant: UnitState in units:
			if not types[participant.id].has(StatTypes.StatType.HP_MAX): types[participant.id].append(StatTypes.StatType.HP_MAX)
	var guard := SpatialRules.capture_guard(context, units, cells, types)
	if guard == null or actor.action_resources == null: out["reason"] = &"balance/invalid_binding"; return out
	var binding := Binding.new()
	binding.context = context; binding.state = state; binding.board = board; binding.actor = actor; binding.target = target; binding.blocker = blocker
	binding.actor_stats = actor.stats; binding.target_stats = target.stats; binding.actor_vitals = actor.vitals; binding.target_vitals = target.vitals
	binding.actor_owner = state.get_owner(actor.id); binding.target_owner = state.get_owner(target.id); binding.actor_resources = actor.action_resources
	if blocker != null:
		binding.blocker_stats = blocker.stats; binding.blocker_vitals = blocker.vitals; binding.blocker_owner = state.get_owner(blocker.id)
	binding.attack_source = DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	binding.spatial_guard = guard.debit(actor.id, 1, 0.0).stance(actor.id, false)
	binding.values = {"spatial": true, "phase": &"balance", "actor_id": actor.id, "target_id": target.id, "blocker_id": blocker.id if blocker != null else 0, "raw_attack": raw_attack, "hit_amount": hit_amount, "impact": impact, "multiplier": multiplier, "balance_before": before, "balance_after": 0.0 if broke else total, "balance_max": maximum, "broke": broke, "main_after": main_after, "direction": direction, "attack_source": binding.attack_source.to_dict(), "expected_hp_before": target.vitals.get_hp()}
	binding.values["actor_guard_before"] = actor.guard_stance
	if armor_request != null:
		# Collision получает ту же точную базу до высоты/стойки, без сложения через float.
		var armor_raw := ArmorFraction.from_decimal(_stat(actor, StatTypes.StatType.STRENGTH)).add(ArmorFraction.from_decimal(_stat(actor, StatTypes.StatType.WEAPON_DAMAGE)))
		if not armor_raw.valid: out["reason"] = &"armor/invalid_component"; return out
		binding.values["armor_raw"] = {"numerator": maxi(0, armor_raw.numerator), "denominator": armor_raw.denominator}
		var plan := ArmorHitExecutor.prepare(armor_request, guard.values["participants"][target.id]["armor"], target.vitals.get_hp(), _stat(target, StatTypes.StatType.HP_MAX), context.get_rng())
		if plan.get("reason", &"") != &"": out["reason"] = plan["reason"]; return out
		binding.values["armor"] = true
		binding.values["armor_plan"] = plan
	binding = spatial_phase(binding, binding.spatial_guard, &"balance")
	if not spatial_valid(binding, context, &"balance", true): out["reason"] = &"balance/invalid_binding"; return out
	if broke and target.vitals.get_hp() > hit_amount:
		var pushed := _prepare_spatial_push(binding, context, true)
		if pushed.get("reason", &"") != &"": return pushed
		binding.values["admission_board_touches"] = pushed["board_touches"]
		binding.seal()
	out["binding"] = binding
	return out

static func _spatial_stat(binding: Binding, id: int, type: int) -> float:
	return binding.spatial_guard.values["participants"][id]["stats"].get(type, NAN)

static func _prepare_spatial_push(binding: Binding, context: ActionContext, admission: bool) -> Dictionary:
	if not spatial_valid(binding, context, binding.values.get("phase", &""), admission): return _push_failure()
	if binding.values.get("armor", false): return ArmorSpatial.prepare_push(binding, context, admission)
	var target_id: int = binding.values["target_id"]
	var target_values: Dictionary = binding.spatial_guard.values["participants"][target_id]
	var from: Vector2i = target_values["cell"]
	var direction: Vector2i = binding.values["direction"]
	var to := from + direction
	var board := binding.board
	var resolved := PushResolver.resolve_push_steps(board, binding.target, from, direction, 1)
	var target_hp := float(target_values["hp"]) - (float(binding.values["hit_amount"]) if admission else 0.0)
	var touches := 0
	var first: DamageRequest = null
	var second: DamageRequest = null
	var armor := _spatial_stat(binding, target_id, StatTypes.StatType.ARMOR)
	var raw: float = binding.values["raw_attack"]
	var source := DamageSource.new(&"collision" if resolved.outcome in [PushResult.Outcome.BLOCKED, PushResult.Outcome.COLLISION] else &"fall", 0, to, binding.actor.id, binding.actor.id)
	if resolved.outcome in [PushResult.Outcome.BLOCKED, PushResult.Outcome.COLLISION]:
		var amount := raw - armor
		if not is_finite(amount): return _push_failure(&"push/nonfinite_damage")
		first = DamageRequest.new(target_id, maxf(1.0, amount), &"physical", &"bypass", source)
		touches = 1 if target_hp <= first.amount else 0
	if resolved.outcome == PushResult.Outcome.COLLISION:
		if binding.blocker == null or binding.blocker != resolved.blocker: return _push_failure()
		var blocker_id: int = binding.values["blocker_id"]
		var amount := raw - _spatial_stat(binding, blocker_id, StatTypes.StatType.ARMOR)
		if not is_finite(amount): return _push_failure(&"push/nonfinite_damage")
		second = DamageRequest.new(blocker_id, maxf(1.0, amount), &"physical", &"bypass", source)
		var blocker_hp: float = binding.spatial_guard.values["participants"][blocker_id]["hp"]
		if blocker_hp <= second.amount:
			touches += 1
			if target_hp > first.amount:
				touches += 1
				if board.is_lethal(to): touches += 1
				else:
					var fall := SpatialRules.fall_amount(_spatial_stat(binding, target_id, StatTypes.StatType.HP_MAX), armor, maxi(0, board.get_height_steps(from) - board.get_height_steps(to)), false)
					if not is_finite(fall): return _push_failure(&"push/nonfinite_damage")
					if fall > 0.0 and target_hp - first.amount <= fall: touches += 1
	elif resolved.outcome == PushResult.Outcome.MOVED:
		var fall := SpatialRules.fall_amount(_spatial_stat(binding, target_id, StatTypes.StatType.HP_MAX), armor, resolved.fall_steps, false)
		if not is_finite(fall): return _push_failure(&"push/nonfinite_damage")
		touches = 1
		if fall > 0.0:
			first = DamageRequest.new(target_id, fall, &"physical", &"bypass", source)
			if target_hp <= fall: touches += 1
	elif resolved.outcome == PushResult.Outcome.FELL:
		touches = 2 if board.is_in_bounds(to) else 1
	var stage := binding.copy()
	stage.first = first; stage.first_seal = first.copy() if first != null else null
	stage.second = second; stage.second_seal = second.copy() if second != null else null
	stage.values["from_cell"] = from; stage.values["attempted_cell"] = to
	stage.values["outcome"] = resolved.outcome; stage.values["fall_steps"] = resolved.fall_steps; stage.values["fall_height"] = resolved.fall_height
	stage.values["phase"] = &"push"
	stage.seal()
	return {"reason": &"", "outcome": resolved.outcome, "blocked_reason": resolved.blocked_reason, "from_cell": from, "attempted_cell": to, "fall_height": resolved.fall_height, "fall_steps": resolved.fall_steps, "first": first, "second": second, "binding": stage, "board_touches": touches}
