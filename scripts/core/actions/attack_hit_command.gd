extends DamageCommand
class_name AttackHitCommand

var _seal: DamageRequest
var _actor: UnitState
var _target: UnitState
var _resources: ActionResources
var _actor_cell: Vector2i
var _target_cell: Vector2i
var _main_after: int
var _p07_binding: BalancePushRules.Binding
var _has_p07_binding: bool
var _target_guard_stance: bool
var _bleeding_policy: StringName = &""
var _definition_id: StringName = &""
var _bleeding_seal: Array = [&"", &""]
var _entangle_on_physical_hp: bool = false
var _entangle_seal: bool = false

func bind_entangle(enabled: bool) -> void:
	_entangle_on_physical_hp = enabled
	_entangle_seal = enabled

func bind_bleeding(policy: StringName, definition_id: StringName) -> void:
	_bleeding_policy = policy
	_definition_id = definition_id
	_bleeding_seal = [policy, definition_id]

func _init(prepared_request: DamageRequest = null, actor: UnitState = null, target: UnitState = null, resources: ActionResources = null, actor_cell: Vector2i = Vector2i.ZERO, target_cell: Vector2i = Vector2i.ZERO, main_after: int = 0, p07_binding: BalancePushRules.Binding = null) -> void:
	super(prepared_request.copy() if prepared_request != null else null)
	_seal = prepared_request.copy() if prepared_request != null else null
	_actor = actor
	_target = target
	_resources = resources
	_actor_cell = actor_cell
	_target_cell = target_cell
	_main_after = main_after
	_p07_binding = p07_binding.copy() if p07_binding != null else null
	_has_p07_binding = p07_binding != null
	_target_guard_stance = target.guard_stance if target != null else false

func get_kind() -> StringName: return &"attack_hit"

func copy_for_queue() -> Command:
	var copy := AttackHitCommand.new(request.copy() if request != null else null, _actor, _target, _resources, _actor_cell, _target_cell, _main_after, _p07_binding)
	copy._seal = _seal.copy() if _seal != null else null
	copy._has_p07_binding = _has_p07_binding
	copy._target_guard_stance = _target_guard_stance
	copy._bleeding_policy = _bleeding_policy
	copy._definition_id = _definition_id
	copy._bleeding_seal = _bleeding_seal.duplicate()
	copy._entangle_on_physical_hp = _entangle_on_physical_hp
	copy._entangle_seal = _entangle_seal
	return copy

func validate(context: ActionContext) -> StringName:
	var reason := _binding_reason(context)
	if reason != &"": return reason
	if request.armor_mode == &"armor": return &""
	return &"" if ActionHpExecutor.validate_damage(request, context) == &"" else &"attack/invalid_hit"

func execute(context: ActionContext) -> CommandStepResult:
	var reason := _binding_reason(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	if _p07_binding != null and _p07_binding.values.get("spatial", false):
		var hp := BalancePushRules.spatial_hp(_p07_binding, request, context, &"attack/invalid_hit")
		var spatial_result: CommandStepResult = hp["result"]
		var next: BalancePushRules.Binding = hp["binding"]
		if spatial_result.status == &"APPLIED" and next.values["expected_alive"] and float(next.values["impact"]) > 0.0 and float(next.values["balance_max"]) > 0.0:
			spatial_result.mandatory.append(BalanceCommand.new(next))
		if spatial_result.status == &"APPLIED" and (_bleeding_policy != &"" or _entangle_on_physical_hp):
			for event: Dictionary in spatial_result.events:
				if event["kind"] != &"hit_resolved": continue
				var physical_hp: int = 0
				for row: Dictionary in event["hit"]["rows"]:
					if row["type"] == &"physical": physical_hp += int(row["hp_damage"])
				# Sibling после Balance завершает всё mandatory spatial-поддерево.
				if _bleeding_policy != &"":
					var eligible := physical_hp > 0 or _bleeding_policy == &"bypass_hp_gate"
					event["hit"]["bleeding"] = {"policy": _bleeding_policy, "physical_hp_damage": physical_hp, "eligible": eligible}
					spatial_result.mandatory.append(BleedingApplyCommand.new(_actor, _target, request.source, event["hit_id"], _definition_id, _bleeding_policy, eligible))
				if _entangle_on_physical_hp:
					spatial_result.mandatory.append(EntangleApplyCommand.new(_actor, _target, request.source, event["hit_id"], _definition_id, physical_hp > 0))
		return spatial_result
	var result := super.execute(context)
	# Для legacy HP pipeline также сохраняем отказ с реальным префиксом урона.
	if result.status == &"APPLIED" and (_actor.guard_stance or _target.guard_stance != _target_guard_stance):
		result.status = &"FAULTED"
		result.reason = &"attack/invalid_hit"
	if result.status == &"APPLIED" and _p07_binding != null and _target.is_alive() and float(_p07_binding.values.get("impact", 0.0)) > 0.0 and float(_p07_binding.values.get("balance_max", 0.0)) > 0.0:
		result.mandatory.append(BalanceCommand.new(_p07_binding))
	return result

func _binding_reason(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null or request == null or _seal == null or _actor == null or _target == null or _resources == null:
		return &"attack/invalid_hit"
	if not _same_request(request, _seal): return &"attack/invalid_hit"
	if [_bleeding_policy, _definition_id] != _bleeding_seal: return &"bleeding/invalid_source"
	if _entangle_on_physical_hp != _entangle_seal: return &"control/invalid_source"
	if _entangle_on_physical_hp:
		var definition := context.get_attack_rules().get_definition(_definition_id)
		if definition == null or not definition.entangle_on_physical_hp or request.armor_mode != &"armor": return &"control/invalid_source"
	if _bleeding_policy != &"":
		var definition := context.get_attack_rules().get_definition(_definition_id)
		if definition == null or definition.bleeding_policy != _bleeding_policy or request.armor_mode != &"armor": return &"bleeding/invalid_source"
	if _actor.guard_stance or _target.guard_stance != _target_guard_stance: return &"attack/invalid_hit"
	if _has_p07_binding:
		if _p07_binding == null: return &"attack/invalid_hit"
		var p07_reason := BalancePushRules.binding_reason(_p07_binding, context, &"balance", true)
		if p07_reason != &"": return &"attack/invalid_hit"
	elif _p07_binding != null:
		return &"attack/invalid_hit"
	var armor_hit: bool = _p07_binding != null and _p07_binding.values.get("armor", false)
	if armor_hit and (request.armor_mode != &"armor" or request.armor_components != _p07_binding.values["armor_plan"]["raw"]): return &"attack/invalid_hit"
	if request.target_unit_id != _target.id or request.damage_type != &"physical" or (not armor_hit and (request.armor_mode != &"bypass" or request.amount < 1.0)) or not is_finite(request.amount) or request.source == null:
		return &"attack/invalid_hit"
	var source := request.source
	if source.kind != &"attack" or source.source_instance_id != 0 or source.origin_cell != _actor_cell or source.instigator_unit_id != _actor.id or source.credit_unit_id != _actor.id:
		return &"attack/invalid_hit"
	var board := context.get_state().get_board()
	if _actor.get_script() != UnitState or _target.get_script() != UnitState or _actor.stats == null or _target.stats == null or _actor.vitals == null or _target.vitals == null or _actor.stats.get_script() != StatsBag or _target.stats.get_script() != StatsBag or _actor.vitals.get_script() != Vitals or _target.vitals.get_script() != Vitals or _actor.vitals._stats != _actor.stats or _target.vitals._stats != _target.stats:
		return &"attack/invalid_hit"
	if board.get_unit_by_id(_actor.id) != _actor or board.get_unit_by_id(_target.id) != _target or not _actor.is_alive() or not _target.is_alive() or _actor.cell != _actor_cell or _target.cell != _target_cell or board.occupant_at(_actor_cell) != _actor or board.occupant_at(_target_cell) != _target or _actor.action_resources != _resources or _resources.get_script() != ActionResources or _resources.validate(_actor.id) != &"" or _resources.get_main_left() != _main_after:
		return &"attack/invalid_hit"
	if _target.is_alive() and request.amount >= _target.vitals.get_hp() and (board.board_version < 0 or board.board_version > AttackCommand.MAX_ID - 1):
		return &"attack/board_version_exhausted"
	return &""

static func _same_request(left: DamageRequest, right: DamageRequest) -> bool:
	if left.target_unit_id != right.target_unit_id or left.amount != right.amount or left.damage_type != right.damage_type or left.armor_mode != right.armor_mode or left.armor_components != right.armor_components or left.source == null or right.source == null: return false
	return left.source.kind == right.source.kind and left.source.source_instance_id == right.source.source_instance_id and left.source.origin_cell == right.source.origin_cell and left.source.instigator_unit_id == right.source.instigator_unit_id and left.source.credit_unit_id == right.source.credit_unit_id
