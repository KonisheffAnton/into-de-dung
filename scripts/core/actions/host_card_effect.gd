extends RefCounted
class_name HostCardEffect

static func host_dead(state: ItemSimulationState) -> bool:
	if state == null or state.card_effects == null or state.card_effects.host_unit_id == 0: return false
	var host := state.get_board().get_unit_by_id(state.card_effects.host_unit_id)
	return host == null or not host.is_alive()

static func prepare(context: ActionContext, target_id: int, effect: StringName, source: DamageSource, paid: Dictionary, effects_after: Dictionary) -> Dictionary:
	var state := context.get_state()
	var board := state.get_board()
	var host := board.get_unit_by_id(state.card_effects.host_unit_id)
	if host == null or host.faction != Faction.Type.PLAYER: return {"reason": &"host_card/no_host"}
	var anchor := HostBinding.anchor(state)
	if anchor.is_empty(): return {"reason":&"host_card/no_host"}
	var target := board.get_unit_by_id(target_id)
	var participants: Array[UnitState] = [host]
	var cells: Array[Vector2i] = [anchor.cell]
	var enemies: Array[int] = []
	if effect == &"light_step":
		if not host.is_alive() and anchor.kind == "spirit": return {"reason":&"host_card/no_body"}
		if target_id != host.id: return {"reason": &"host_card/host_only"}
		if state.card_effects.light_step_serial == state.abilities.serials[0]: return {"reason": &"host_card/already_used"}
		if host.is_alive() and not is_finite(host.move_points_left + 2.0): return {"reason": &"host_card/movement_overflow"}
		effects_after = effects_after.duplicate(true)
		effects_after.light_step_serial = state.abilities.serials[0]
	else:
		var excluded: Array[int] = []
		for summon: Dictionary in state.get_summons(): excluded.append(summon.unit_id)
		var geometry := HostCardGeometry.binding_thread_from(board,anchor.cell,anchor.height,target_id,excluded,host.id)
		if geometry.reason != &"": return geometry
		cells.assign(geometry.cells); enemies.assign(geometry.enemy_ids)
		participants.append(target)
		for id: int in enemies: participants.append(board.get_unit_by_id(id))
	var stats: Dictionary = {}
	for unit: UnitState in participants: stats[unit.id] = [StatTypes.StatType.HP_MAX]
	var guard := SpatialRules.capture_guard(context, participants, cells, stats, true)
	if guard == null: return {"reason": &"host_card/invalid_runtime"}
	var requests: Array[DamageRequest] = []
	for id: int in enemies:
		var enemy := board.get_unit_by_id(id)
		if enemy.armor == null: return {"reason": &"host_card/invalid_runtime"}
		var extras: Array[Dictionary] = [{"type":"fire","policy":"standard","source":"card.binding_thread","numerator":4,"denominator":1,"factor_num":1,"factor_den":1}]
		var raw := ArmorAttack.components(0.0, 0.0, 0, enemy.guard_stance, extras, 0, 2 if ElementalRules.is_frozen(enemy) else 1)
		raw.remove_at(0)
		var request := ArmorAttack.request(id, raw, source)
		request.attack_group_id = context.damage_attack_group()
		var hit := ArmorHitExecutor.prepare(request, guard.values.participants[id].armor, enemy.vitals.get_hp(), ActionHpExecutor._stat_value(enemy, StatTypes.StatType.HP_MAX), context.get_rng(), ElementalRules.is_frozen(enemy), context)
		if hit.get("reason", &"") != &"": return hit
		requests.append(request)
	if board.board_version > ActionContext.MAX_ID - enemies.size(): return {"reason": &"push/board_version_exhausted"}
	return {"reason":&"", "target":target, "host_id":host.id, "guard":guard, "source":source, "paid":paid, "effect":effect, "effects_after":effects_after, "host_requests":requests,"host_movement":host.is_alive() and not state.is_summon_pending(host.id)}

static func apply(context: ActionContext, plan: Dictionary, guard: SpatialRules.Guard, seal_check: Callable) -> CommandStepResult:
	var result := CommandStepResult.applied([], [], [], null, true)
	if plan.effect == &"light_step":
		if not plan.host_movement: return result
		var host := context.get_state().get_board().get_unit_by_id(plan.host_id)
		var expected := guard.debit(host.id, 0, -2.0)
		host.move_points_left += 2.0
		if not expected.check(context) or not seal_check.call():
			result.status = &"FAULTED"; result.reason = &"host_card/checkpoint"
		return result
	# Один общий guard удерживает ещё не поражённые цели и уже записанный prefix.
	for request: DamageRequest in plan.host_requests:
		var hit := ArmorHitExecutor.execute(request, guard, context, seal_check)
		var step: CommandStepResult = hit.result
		result.events.append_array(step.events)
		if step.status != &"APPLIED":
			result.status = step.status; result.reason = step.reason
			return result
		guard = hit.guard
	return result
