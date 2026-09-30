extends Command
class_name AttackCommand

const MAX_ID: int = 9223372036854775807

var _actor_unit_id: int
var _target_unit_id: int
var _expected_actor_cell: Vector2i
var _expected_target_cell: Vector2i
var _attack_definition_id: StringName
var _expected_revision: int
var _reaction: bool = false
var _counter: bool = false

static func opportunity(actor: UnitState, target: UnitState, revision: int) -> AttackCommand:
	var result := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"opportunity_strike", revision)
	result._reaction = true
	return result

static func counterattack(actor: UnitState, target: UnitState, revision: int) -> AttackCommand:
	var result := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"counter_strike", revision)
	result._reaction = true
	result._counter = true
	return result

func is_reaction() -> bool: return _reaction

func _init(actor_unit_id: int = 0, target_unit_id: int = 0, expected_actor_cell: Vector2i = Vector2i.ZERO, expected_target_cell: Vector2i = Vector2i.ZERO, attack_definition_id: StringName = &"", expected_revision: int = 0) -> void:
	_actor_unit_id = actor_unit_id
	_target_unit_id = target_unit_id
	_expected_actor_cell = expected_actor_cell
	_expected_target_cell = expected_target_cell
	_attack_definition_id = attack_definition_id
	_expected_revision = expected_revision

func get_kind() -> StringName:
	if _counter: return &"counterattack"
	return &"opportunity_attack" if _reaction else &"attack"

func copy_for_queue() -> Command:
	var result := AttackCommand.new(_actor_unit_id, _target_unit_id, _expected_actor_cell, _expected_target_cell, _attack_definition_id, _expected_revision)
	result._reaction = _reaction
	result._counter = _counter
	return result

func get_actor_unit_id() -> int: return _actor_unit_id
func get_target_unit_id() -> int: return _target_unit_id
func get_expected_actor_cell() -> Vector2i: return _expected_actor_cell
func get_expected_target_cell() -> Vector2i: return _expected_target_cell
func get_attack_definition_id() -> StringName: return _attack_definition_id
func get_expected_revision() -> int: return _expected_revision

func validate(context: ActionContext) -> StringName:
	return _prepare(context).get("reason", &"")

func execute(context: ActionContext) -> CommandStepResult:
	var prepared := _prepare(context)
	if prepared.get("reason", &"") != &"":
		return CommandStepResult.faulted(&"attack/invalid_runtime")
	var actor: UnitState = prepared["actor"]
	var resources: ActionResources = prepared["resources"]
	var main_before := resources.get_main_left()
	var main_cost := 0 if _reaction else 1
	var main_after := main_before - main_cost
	var target: UnitState = prepared["target"]
	var cover: UnitState = prepared.get("cover")
	var binding: BalancePushRules.Binding = prepared.get("p07_binding")
	var changes: Dictionary = {}
	var stopped: CombatPerksState = target.combat_perks
	var reaction_events: Array[Dictionary] = []
	if _reaction:
		var actor_value := actor.combat_perks.to_dict()
		actor_value["reaction_left"] = 0
		binding.spatial_guard = binding.spatial_guard.perks_phase(actor.id, actor.combat_perks, actor_value)
		if not _counter:
			if stopped == null: stopped = CombatPerksState.new()
			var target_value := stopped.to_dict()
			target_value["movement_stopped"] = true
			binding.spatial_guard = binding.spatial_guard.perks_phase(target.id, stopped, target_value)
		reaction_events.append(_reaction_event(actor.id, target.id, CombatPerksState.Mode.COUNTERATTACK if _counter else CombatPerksState.Mode.OPPORTUNIST))
	if cover != null:
		var cover_value := cover.combat_perks.to_dict()
		cover_value["reaction_left"] = 0
		binding.spatial_guard = binding.spatial_guard.perks_phase(cover.id, cover.combat_perks, cover_value)
		reaction_events.append(_reaction_event(cover.id, target.id, CombatPerksState.Mode.COVER))
	# Готовим весь child до единственной мутации: между оплатой и Hit новых данных уже нет.
	var attack_kind: StringName = &"counterattacked" if _counter else (&"opportunity_attacked" if _reaction else &"attacked")
	var event := {"kind": attack_kind, "actor_unit_id": actor.id, "target_unit_id": target.id, "attack_definition_id": _attack_definition_id, "actor_cell": actor.cell, "target_cell": target.cell, "main_cost": main_cost, "main_before": main_before, "main_after": main_after}
	if prepared.has("modifiers"): event["modifiers"] = prepared["modifiers"]
	var hit := AttackHitCommand.new(prepared["request"] as DamageRequest, actor, target, resources, actor.cell, target.cell, main_after, binding)
	hit.bind_bleeding(prepared.get("bleeding_policy", &""), _attack_definition_id)
	hit.bind_entangle(prepared.get("entangle_on_physical_hp", false))
	hit.bind_stun(prepared.get("stun_on_physical_hp", false))
	hit.bind_artifacts(prepared.get("artifact_values", {}), prepared.get("artifact_freeze_gate", false))
	if main_cost > 0 and not resources.try_spend_main(main_cost):
		return CommandStepResult.faulted(&"attack/invalid_runtime")
	if _reaction:
		actor.combat_perks.reaction_left = 0
		changes[actor.id] = CombatPerkGuard.record(actor, actor.combat_perks)
		if not _counter:
			target.combat_perks = stopped
			stopped.movement_stopped = true
			changes[target.id] = CombatPerkGuard.record(target, stopped)
	else:
		actor.has_attacked = true
		actor.guard_stance = false
	if cover != null:
		cover.combat_perks.reaction_left = 0
		changes[cover.id] = CombatPerkGuard.record(cover, cover.combat_perks)
	var events: Array[Dictionary] = [event]
	events.append_array(reaction_events)
	var result := CommandStepResult.applied(events, [hit], [], null, true)
	result.combat_perk_changes = changes
	return result

static func _reaction_event(actor_id: int, target_id: int, mode: int) -> Dictionary:
	return {"kind": &"reaction_used", "actor_unit_id": actor_id, "target_unit_id": target_id, "mode": mode, "charge_before": 1, "charge_after": 0}

func _prepare(context: ActionContext) -> Dictionary:
	var result: Dictionary = {"reason": &""}
	if _actor_unit_id <= 0 or _actor_unit_id >= MAX_ID:
		result["reason"] = &"attack/invalid_actor_id"; return result
	if _target_unit_id <= 0 or _target_unit_id >= MAX_ID:
		result["reason"] = &"attack/invalid_target_id"; return result
	if _actor_unit_id == _target_unit_id:
		result["reason"] = &"attack/self_target"; return result
	if _attack_definition_id == &"" or String(_attack_definition_id).to_utf8_buffer().size() > AttackRules.MAX_DEFINITION_ID_BYTES:
		result["reason"] = &"attack/invalid_definition_id"; return result
	if _expected_revision < 0 or _expected_revision > MAX_ID - 2:
		result["reason"] = &"attack/invalid_revision"; return result
	if context == null or context.get_state() == null or context.get_state().get_board() == null:
		result["reason"] = &"attack/invalid_runtime"; return result
	var rules := context.get_attack_rules()
	if rules == null:
		result["reason"] = &"attack/rules_missing"; return result
	if rules.validate() != &"":
		result["reason"] = &"attack/invalid_rules"; return result
	var definition := rules.get_definition(_attack_definition_id)
	if definition == null:
		result["reason"] = &"attack/unknown_definition"; return result
	if definition.reaction_strike != _reaction or (_counter and not _reaction):
		result["reason"] = &"reaction/internal_definition"; return result
	var state := context.get_state()
	var board := state.get_board()
	var armor_profile := definition.profile == AttackRules.ARMOR_PROFILE
	var spatial := definition.profile in [AttackRules.SPATIAL_PROFILE, AttackRules.ARMOR_PROFILE]
	if not spatial and board.has_half_heights():
		result["reason"] = &"attack/height_units_unsupported"; return result
	var actor := board.get_unit_by_id(_actor_unit_id)
	if actor == null:
		result["reason"] = &"attack/missing_actor"; return result
	if actor.id != _actor_unit_id:
		result["reason"] = &"attack/invalid_runtime"; return result
	if not actor.is_alive():
		result["reason"] = &"attack/dead_actor"; return result
	var control_reason := ControlRules.action_reason(actor)
	if control_reason != &"": result["reason"] = control_reason; return result
	var target := board.get_unit_by_id(_target_unit_id)
	if target == null:
		result["reason"] = &"attack/missing_target"; return result
	if target.id != _target_unit_id:
		result["reason"] = &"attack/invalid_runtime"; return result
	if not target.is_alive():
		result["reason"] = &"attack/dead_target"; return result
	if not spatial and (actor.control != null or target.control != null):
		result["reason"] = &"control/spatial_required"; return result
	if target.control != null and (target.control.get_script() != ControlState or not ControlState.valid(target.control.to_dict())):
		result["reason"] = &"control/invalid_state"; return result
	if definition.stun_on_physical_hp and not ControlRules.has_stunning_strike(actor):
		result["reason"] = &"perks/stunning_strike_required"; return result
	if (definition.entangle_on_physical_hp or definition.stun_on_physical_hp) and target.control == null:
		result["reason"] = &"control/capability_required"; return result
	if armor_profile and (actor.armor == null or target.armor == null):
		result["reason"] = &"armor/capability_required"; return result
	if definition.bleeding_policy != &"" and (target.bleeding == null or not BleedingState.valid(target.bleeding.to_dict())):
		result["reason"] = &"bleeding/capability_required"; return result
	if not armor_profile and (actor.armor != null or target.armor != null):
		result["reason"] = &"armor/legacy_unsupported"; return result
	if actor.get_script() != UnitState or target.get_script() != UnitState or actor.stats == null or target.stats == null or actor.vitals == null or target.vitals == null or actor.stats.get_script() != StatsBag or target.stats.get_script() != StatsBag or actor.vitals.get_script() != Vitals or target.vitals.get_script() != Vitals or actor.vitals._stats != actor.stats or target.vitals._stats != target.stats or state.get_owner(actor.id) == null or state.get_owner(target.id) == null or state.get_owner(actor.id).get_owner() != actor or state.get_owner(target.id).get_owner() != target:
		result["reason"] = &"attack/invalid_runtime"; return result
	if not _reaction and _expected_revision != context.get_revision():
		result["reason"] = &"attack/stale_revision"; return result
	if _expected_actor_cell != actor.cell:
		result["reason"] = &"attack/actor_cell_mismatch"; return result
	if _expected_target_cell != target.cell:
		result["reason"] = &"attack/target_cell_mismatch"; return result
	if board.occupant_at(actor.cell) != actor:
		result["reason"] = &"attack/actor_not_placed"; return result
	if board.occupant_at(target.cell) != target:
		result["reason"] = &"attack/target_not_placed"; return result
	if not rules.allows(actor.id, target.id):
		result["reason"] = &"attack/not_admitted"; return result
	if _reaction:
		var mode: int = CombatPerksState.Mode.COUNTERATTACK if _counter else CombatPerksState.Mode.OPPORTUNIST
		var reaction_id: StringName = &"counter_strike" if _counter else &"opportunity_strike"
		if _attack_definition_id != reaction_id or not MeleeThreat.reaction_ready(context, actor, mode) or not MeleeThreat.threatens(context, actor, target):
			result["reason"] = &"reaction/not_eligible"; return result
	var resources := actor.action_resources
	if resources == null:
		result["reason"] = &"attack/resources_missing"; return result
	if resources.get_script() != ActionResources or resources.validate(actor.id) != &"":
		result["reason"] = &"attack/invalid_resources"; return result
	for stat_type in [StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX, StatTypes.StatType.WEAPON_DAMAGE, StatTypes.StatType.ATTACK_RANGE]:
		if not actor.stats.has_stat(stat_type):
			result["reason"] = &"attack/missing_stat"; return result
	var actor_copy := StatsBag.from_snapshot_dict(actor.stats.to_snapshot_dict())
	var target_copy := StatsBag.from_snapshot_dict(target.stats.to_snapshot_dict())
	if actor_copy == null or target_copy == null:
		result["reason"] = &"attack/invalid_stat"; return result
	# Старый снимок без нового stat означает ноль; чтение клона не трогает live cache.
	var piercing := actor_copy.get_value(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT)
	if not is_finite(piercing) or piercing != floorf(piercing) or piercing < 0.0 or piercing > 100.0:
		result["reason"] = &"attack/invalid_piercing"; return result
	if piercing != 0.0 and not armor_profile:
		result["reason"] = &"attack/piercing_requires_armor"; return result
	var main_max := actor_copy.get_value(StatTypes.StatType.MAIN_ACTIONS_MAX)
	var bonus_max := actor_copy.get_value(StatTypes.StatType.BONUS_ACTIONS_MAX)
	var weapon := actor_copy.get_value(StatTypes.StatType.WEAPON_DAMAGE)
	if not _valid_maximum(main_max) or not _valid_maximum(bonus_max) or not is_finite(weapon):
		result["reason"] = &"attack/invalid_stat"; return result
	var reach := actor_copy.get_value(StatTypes.StatType.ATTACK_RANGE)
	var reach_reason := AttackReachCheck.inspect_spatial(board, actor, target, reach) if spatial else AttackReachCheck.inspect(board, actor, target, reach)
	if reach_reason != &"":
		result["reason"] = reach_reason; return result
	if not _reaction and resources.get_main_left() < 1:
		result["reason"] = &"attack/insufficient_main"; return result
	var strength := actor_copy.get_value(StatTypes.StatType.STRENGTH)
	var armor := target_copy.get_value(StatTypes.StatType.ARMOR)
	if not is_finite(strength) or not is_finite(armor):
		result["reason"] = &"attack/nonfinite_damage"; return result
	var signed_height_steps := board.get_height_steps(actor.cell) - board.get_height_steps(target.cell) if spatial else 0
	var backstab_percent: int = definition.backstab_bonus_percent if AttackModifiers.is_backstab(actor.cell, target.cell, target.faction) else 0
	var threats: Array[int] = []
	if definition.sneak_attack_enabled and MeleeThreat.has_sneak(actor): threats = MeleeThreat.participants(context, target)
	var sneak_percent := 50 if threats.size() >= 2 and threats.has(actor.id) else 0
	var critical: bool = (definition.critical_on_control and ControlRules.critical_target(target)) or ElementalRules.is_frozen(target)
	var critical_multiplier: int = 2 if critical else 1
	if definition.backstab_bonus_percent > 0 or definition.critical_on_control or definition.sneak_attack_enabled or ElementalRules.is_frozen(target):
		result["modifiers"] = {"backstab_percent": backstab_percent, "critical": critical}
		if definition.sneak_attack_enabled:
			result["modifiers"]["sneak_percent"] = sneak_percent
			result["modifiers"]["threat_ids"] = threats
	if armor_profile:
		var cover := MeleeThreat.cover_for(context, target)
		var extras: Array[Dictionary] = definition.damage_components.duplicate(true)
		if state.artifacts != null:
			if not BattleArtifactRules.references_valid(context): return {"reason": &"artifact/invalid_state"}
			if not _reaction and state.artifacts.ordinary(actor.id, _attack_definition_id):
				result["artifact_values"] = state.artifacts.to_dict()
				result["artifact_freeze_gate"] = ElementalRules.freeze_gate(ArmorRuntime.capture(state.get_owner(target.id)))
				var stacks := state.artifacts.stacks(actor.id, "spark")
				if stacks > 0 and state.artifacts.effect_allowed(actor.id, "spark"): extras.append({"type":"fire","policy":"standard","numerator":ExpeditionCatalog.SPARK_DAMAGE * stacks,"denominator":1,"source":"artifact:spark","factor_num":1,"factor_den":1})
		var raw := ArmorAttack.components(strength, weapon, signed_height_steps, target.guard_stance, extras, backstab_percent + sneak_percent, critical_multiplier, int(piercing), 30 if cover != null else 0)
		var request := ArmorAttack.request(target.id, raw, DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id))
		var plan := ArmorHitExecutor.prepare(request, ArmorRuntime.capture(state.get_owner(target.id)), target.vitals.get_hp(), target_copy.get_value(StatTypes.StatType.HP_MAX), context.get_rng(), ElementalRules.is_frozen(target))
		if plan.get("reason", &"") != &"": result["reason"] = plan["reason"]; return result
		request.amount = float(plan["hp_before"] - plan["hp_after"])
		var binding_result := BalancePushRules.prepare_attack(context, actor, target, strength + weapon, request.amount, resources.get_main_left() - (0 if _reaction else 1), true, request, critical_multiplier, _reaction, cover, definition.chain_push)
		if binding_result.get("reason", &"") != &"": return binding_result
		var binding: BalancePushRules.Binding = binding_result["binding"]
		var touches: int = int(binding.values.get("admission_board_touches", 0)) + (1 if plan["hp_after"] == 0 else 0)
		if board.board_version < 0 or board.board_version > MAX_ID - touches:
			result["reason"] = &"push/board_version_exhausted"; return result
		result.merge({"actor": actor, "target": target, "resources": resources, "request": request, "p07_binding": binding, "bleeding_policy": definition.bleeding_policy, "entangle_on_physical_hp": definition.entangle_on_physical_hp, "stun_on_physical_hp": definition.stun_on_physical_hp, "cover": cover})
		return result
	var calculation := AttackDamageCalculation.calculate(strength, weapon, armor, spatial, signed_height_steps, target.guard_stance, backstab_percent, critical_multiplier)
	if calculation.reason != &"":
		result["reason"] = calculation.reason; return result
	var amount := calculation.hit_amount
	var source := DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id)
	var request := DamageRequest.new(target.id, amount, &"physical", &"bypass", source)
	if ActionHpExecutor.validate_damage(request, context) != &"":
		result["reason"] = &"attack/invalid_damage_request"; return result
	if board.board_version < 0 or (target.is_alive() and amount >= target.vitals.get_hp() and board.board_version > MAX_ID - 1):
		result["reason"] = &"attack/board_version_exhausted"; return result
	var p07_binding: BalancePushRules.Binding = null
	if definition.profile == AttackRules.BALANCE_PROFILE or spatial:
		var impact := actor_copy.get_value(StatTypes.StatType.IMPACT_POWER)
		var max_balance := target_copy.get_value(StatTypes.StatType.BALANCE_MAX)
		if not actor_copy.has_stat(StatTypes.StatType.IMPACT_POWER) or not target_copy.has_stat(StatTypes.StatType.BALANCE_MAX):
			result["reason"] = &"balance/missing_stat"; return result
		var p07 := BalancePushRules.prepare_attack(context, actor, target, calculation.raw_attack, amount, resources.get_main_left() - 1, spatial, null, critical_multiplier)
		if p07.get("reason", &"") != &"": return p07
		var binding_for_touches := p07.get("binding") as BalancePushRules.Binding
		var touches: int = int(binding_for_touches.values.get("admission_board_touches", 0)) if binding_for_touches != null else 0
		if touches > 0 and (board.board_version < 0 or board.board_version > MAX_ID - touches):
			result["reason"] = &"push/board_version_exhausted"; return result
		p07_binding = p07.get("binding") as BalancePushRules.Binding
	result.merge({"actor": actor, "target": target, "resources": resources, "request": request, "p07_binding": p07_binding})
	return result

static func _valid_maximum(value: float) -> bool:
	return is_finite(value) and value == floorf(value) and value >= 0.0 and value <= 4096.0
