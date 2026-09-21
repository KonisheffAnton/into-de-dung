extends Command
class_name AttackCommand

const MAX_ID: int = 9223372036854775807

var _actor_unit_id: int
var _target_unit_id: int
var _expected_actor_cell: Vector2i
var _expected_target_cell: Vector2i
var _attack_definition_id: StringName
var _expected_revision: int

func _init(actor_unit_id: int = 0, target_unit_id: int = 0, expected_actor_cell: Vector2i = Vector2i.ZERO, expected_target_cell: Vector2i = Vector2i.ZERO, attack_definition_id: StringName = &"", expected_revision: int = 0) -> void:
	_actor_unit_id = actor_unit_id
	_target_unit_id = target_unit_id
	_expected_actor_cell = expected_actor_cell
	_expected_target_cell = expected_target_cell
	_attack_definition_id = attack_definition_id
	_expected_revision = expected_revision

func get_kind() -> StringName: return &"attack"

func copy_for_queue() -> Command:
	return AttackCommand.new(_actor_unit_id, _target_unit_id, _expected_actor_cell, _expected_target_cell, _attack_definition_id, _expected_revision)

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
	var main_after := main_before - 1
	var target: UnitState = prepared["target"]
	# Готовим весь child до единственной мутации: между оплатой и Hit новых данных уже нет.
	var event := {"kind": &"attacked", "actor_unit_id": actor.id, "target_unit_id": target.id, "attack_definition_id": _attack_definition_id, "actor_cell": actor.cell, "target_cell": target.cell, "main_cost": 1, "main_before": main_before, "main_after": main_after}
	var hit := AttackHitCommand.new(prepared["request"] as DamageRequest, actor, target, resources, actor.cell, target.cell, main_after, prepared.get("p07_binding") as BalancePushRules.Binding)
	if not resources.try_spend_main(1):
		return CommandStepResult.faulted(&"attack/invalid_runtime")
	actor.has_attacked = true
	actor.guard_stance = false
	return CommandStepResult.applied([event], [hit], [], null, true)

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
	var target := board.get_unit_by_id(_target_unit_id)
	if target == null:
		result["reason"] = &"attack/missing_target"; return result
	if target.id != _target_unit_id:
		result["reason"] = &"attack/invalid_runtime"; return result
	if not target.is_alive():
		result["reason"] = &"attack/dead_target"; return result
	if armor_profile and (actor.armor == null or target.armor == null):
		result["reason"] = &"armor/capability_required"; return result
	if not armor_profile and (actor.armor != null or target.armor != null):
		result["reason"] = &"armor/legacy_unsupported"; return result
	if actor.get_script() != UnitState or target.get_script() != UnitState or actor.stats == null or target.stats == null or actor.vitals == null or target.vitals == null or actor.stats.get_script() != StatsBag or target.stats.get_script() != StatsBag or actor.vitals.get_script() != Vitals or target.vitals.get_script() != Vitals or actor.vitals._stats != actor.stats or target.vitals._stats != target.stats or state.get_owner(actor.id) == null or state.get_owner(target.id) == null or state.get_owner(actor.id).get_owner() != actor or state.get_owner(target.id).get_owner() != target:
		result["reason"] = &"attack/invalid_runtime"; return result
	if _expected_revision != context.get_revision():
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
	var main_max := actor_copy.get_value(StatTypes.StatType.MAIN_ACTIONS_MAX)
	var bonus_max := actor_copy.get_value(StatTypes.StatType.BONUS_ACTIONS_MAX)
	var weapon := actor_copy.get_value(StatTypes.StatType.WEAPON_DAMAGE)
	if not _valid_maximum(main_max) or not _valid_maximum(bonus_max) or not is_finite(weapon):
		result["reason"] = &"attack/invalid_stat"; return result
	var reach := actor_copy.get_value(StatTypes.StatType.ATTACK_RANGE)
	var reach_reason := AttackReachCheck.inspect_spatial(board, actor, target, reach) if spatial else AttackReachCheck.inspect(board, actor, target, reach)
	if reach_reason != &"":
		result["reason"] = reach_reason; return result
	if resources.get_main_left() < 1:
		result["reason"] = &"attack/insufficient_main"; return result
	var strength := actor_copy.get_value(StatTypes.StatType.STRENGTH)
	var armor := target_copy.get_value(StatTypes.StatType.ARMOR)
	if not is_finite(strength) or not is_finite(armor):
		result["reason"] = &"attack/nonfinite_damage"; return result
	var signed_height_steps := board.get_height_steps(actor.cell) - board.get_height_steps(target.cell) if spatial else 0
	if armor_profile:
		var raw := ArmorAttack.components(strength, weapon, signed_height_steps, target.guard_stance, definition.damage_components)
		var request := ArmorAttack.request(target.id, raw, DamageSource.new(&"attack", 0, actor.cell, actor.id, actor.id))
		var plan := ArmorHitExecutor.prepare(request, ArmorRuntime.capture(state.get_owner(target.id)), target.vitals.get_hp(), target_copy.get_value(StatTypes.StatType.HP_MAX), context.get_rng())
		if plan.get("reason", &"") != &"": result["reason"] = plan["reason"]; return result
		request.amount = float(plan["hp_before"] - plan["hp_after"])
		var binding_result := BalancePushRules.prepare_attack(context, actor, target, strength + weapon, request.amount, resources.get_main_left() - 1, true, request)
		if binding_result.get("reason", &"") != &"": return binding_result
		var binding: BalancePushRules.Binding = binding_result["binding"]
		var touches: int = int(binding.values.get("admission_board_touches", 0)) + (1 if plan["hp_after"] == 0 else 0)
		if board.board_version < 0 or board.board_version > MAX_ID - touches:
			result["reason"] = &"push/board_version_exhausted"; return result
		result.merge({"actor": actor, "target": target, "resources": resources, "request": request, "p07_binding": binding})
		return result
	var calculation := AttackDamageCalculation.calculate(strength, weapon, armor, spatial, signed_height_steps, target.guard_stance)
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
		var p07 := BalancePushRules.prepare_attack(context, actor, target, calculation.raw_attack, amount, resources.get_main_left() - 1, spatial)
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
