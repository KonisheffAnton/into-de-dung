extends DamageCommand
class_name PushDamageCommand

var _binding: BalancePushRules.Binding
var _request_seal: DamageRequest
func _init(request: DamageRequest = null, binding: BalancePushRules.Binding = null) -> void:
	super(request); _binding = binding.copy() if binding != null else null; _request_seal = request.copy() if request != null else null
func get_kind() -> StringName: return &"push_damage"
func copy_for_queue() -> Command:
	var result := PushDamageCommand.new(request, _binding); result._request_seal = _request_seal.copy() if _request_seal != null else null; return result
func validate(context: ActionContext) -> StringName:
	if _binding == null or _binding.context != context or request == null or _request_seal == null or not _same_request(request, _request_seal): return &"push/invalid_binding"
	if not BalancePushRules.requests_sealed(_binding) or not BalancePushRules._same_request(request, _binding.first): return &"push/invalid_binding"
	var phase: StringName = _binding.values.get("phase", &"")
	if phase != &"push" and phase != &"push_damage": return &"push/invalid_binding"
	if BalancePushRules.binding_reason(_binding, context, phase) != &"": return &"push/invalid_binding"
	var target := context.get_state().get_board().get_unit_by_id(request.target_unit_id)
	if target == null or (request.amount >= target.vitals.get_hp() and (context.get_state().get_board().board_version < 0 or context.get_state().get_board().board_version > ActionContext.MAX_ID - 1)):
		return &"push/board_version_exhausted"
	return &"" if request.armor_mode == &"armor" and _binding.values.get("armor", false) else ActionHpExecutor.validate_damage(request, context)

static func _same_request(a: DamageRequest, b: DamageRequest) -> bool:
	return BalancePushRules._same_request(a, b)
func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason == &"" and _binding.values.get("spatial", false):
		return BalancePushRules.spatial_hp(_binding, request, context, &"push/invalid_binding")["result"]
	return CommandStepResult.faulted(reason) if reason != &"" else ActionHpExecutor.damage(request, context)
