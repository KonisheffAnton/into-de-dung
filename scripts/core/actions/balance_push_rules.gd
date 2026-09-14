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
		return result
	func seal() -> void: _seal = values.duplicate(true)
	func sealed() -> bool: return values == _seal

static func _empty() -> Dictionary:
	return {"reason": &"", "binding": null}

static func prepare_attack(context: ActionContext, actor: UnitState, target: UnitState, raw_attack: float, hit_amount: float, main_after: int) -> Dictionary:
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
	return left.source.to_dict() == right.source.to_dict()
