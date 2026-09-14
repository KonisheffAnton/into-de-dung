extends DamageCommand
class_name AttackHitCommand

var _seal: DamageRequest
var _actor: UnitState
var _target: UnitState
var _resources: ActionResources
var _actor_cell: Vector2i
var _target_cell: Vector2i
var _main_after: int

func _init(prepared_request: DamageRequest = null, actor: UnitState = null, target: UnitState = null, resources: ActionResources = null, actor_cell: Vector2i = Vector2i.ZERO, target_cell: Vector2i = Vector2i.ZERO, main_after: int = 0) -> void:
	super(prepared_request.copy() if prepared_request != null else null)
	_seal = prepared_request.copy() if prepared_request != null else null
	_actor = actor
	_target = target
	_resources = resources
	_actor_cell = actor_cell
	_target_cell = target_cell
	_main_after = main_after

func get_kind() -> StringName: return &"attack_hit"

func copy_for_queue() -> Command:
	var copy := AttackHitCommand.new(request.copy() if request != null else null, _actor, _target, _resources, _actor_cell, _target_cell, _main_after)
	copy._seal = _seal.copy() if _seal != null else null
	return copy

func validate(context: ActionContext) -> StringName:
	var reason := _binding_reason(context)
	if reason != &"": return reason
	return &"" if ActionHpExecutor.validate_damage(request, context) == &"" else &"attack/invalid_hit"

func execute(context: ActionContext) -> CommandStepResult:
	var reason := _binding_reason(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	return super.execute(context)

func _binding_reason(context: ActionContext) -> StringName:
	if context == null or context.get_state() == null or context.get_state().get_board() == null or request == null or _seal == null or _actor == null or _target == null or _resources == null:
		return &"attack/invalid_hit"
	if not _same_request(request, _seal): return &"attack/invalid_hit"
	if request.target_unit_id != _target.id or request.damage_type != &"physical" or request.armor_mode != &"bypass" or not is_finite(request.amount) or request.amount < 1.0 or request.source == null:
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
	if left.target_unit_id != right.target_unit_id or left.amount != right.amount or left.damage_type != right.damage_type or left.armor_mode != right.armor_mode or left.source == null or right.source == null: return false
	return left.source.kind == right.source.kind and left.source.source_instance_id == right.source.source_instance_id and left.source.origin_cell == right.source.origin_cell and left.source.instigator_unit_id == right.source.instigator_unit_id and left.source.credit_unit_id == right.source.credit_unit_id
