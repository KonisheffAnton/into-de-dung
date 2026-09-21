extends Command
class_name MoveFallCommand

class Binding extends RefCounted:
	var guard: SpatialRules.Guard
	var values: Dictionary = {}
	var _seal: Dictionary = {}
	var _refs: Dictionary = {}
	var request: DamageRequest
	var request_seal: DamageRequest
	var source: DamageSource
	var source_seal: DamageSource

	func copy() -> Binding:
		var result := Binding.new()
		result.guard = guard.copy() if guard != null else null
		result.values = values.duplicate(true); result._seal = _seal.duplicate(true); result._refs = _refs.duplicate(true)
		result.request = request.copy() if request != null else null
		result.request_seal = request_seal.copy() if request_seal != null else null
		result.source = source.copy() if source != null else null
		result.source_seal = source_seal.copy() if source_seal != null else null
		return result

	func sealed(mode: StringName) -> bool:
		if guard == null or not guard.sealed() or guard.refs != _refs or values != _seal or values.get("mode") != mode: return false
		if values.get("board_origin_version") != guard.values["board_origin_version"] or values.get("expected_board_version") != guard.values["expected_board_version"]: return false
		if source == null or source_seal == null or source.to_dict() != source_seal.to_dict() or source.to_dict() != values.get("source"): return false
		var id: int = values.get("target_id", 0)
		if not guard.refs["participants"].has(id) or guard.values["participants"][id]["cell"] != values.get("to_cell"): return false
		if source.source_instance_id != 0 or source.instigator_unit_id != 0 or source.credit_unit_id != 0 or source.origin_cell != values["to_cell"]: return false
		if mode == &"cell_death":
			return request == null and request_seal == null and source.kind == &"cell" and values.get("lethal", false) and TerrainType.is_lethal(guard.values["geometry"][values["to_cell"]][1])
		if mode != &"fall" or source.kind != &"fall" or request == null or request_seal == null: return false
		if request.armor_mode == &"armor":
			return guard.values["participants"][id].has("armor") and BalancePushRules._same_request(request, request_seal) and request.target_unit_id == id and request.source.to_dict() == source.to_dict()
		return BalancePushRules._same_request(request, request_seal) and request.target_unit_id == id and request.damage_type == &"physical" and request.armor_mode == &"bypass" and is_finite(request.amount) and request.amount > 0.0 and request.source.to_dict() == source.to_dict() and request.amount == values.get("amount")

	func check(context: ActionContext, mode: StringName) -> bool:
		return sealed(mode) and guard.check(context)

var _binding: Binding

func _init(binding: Binding = null) -> void:
	_binding = binding.copy() if binding != null else null

func get_kind() -> StringName: return &"move_fall"
func copy_for_queue() -> Command: return MoveFallCommand.new(_binding)
func validate(context: ActionContext) -> StringName:
	return &"" if _binding != null and _binding.check(context, &"fall") else &"move/fall_binding"

func execute(context: ActionContext) -> CommandStepResult:
	return execute_binding(_binding, context, &"fall")

static func make_binding(guard: SpatialRules.Guard, id: int, from: Vector2i, to: Vector2i, drop: int, amount: float, lethal: bool) -> Binding:
	var binding := Binding.new()
	binding.guard = guard.copy()
	var mode: StringName = &"cell_death" if lethal else &"fall"
	binding.source = DamageSource.new(&"cell" if lethal else &"fall", 0, to, 0, 0)
	binding.source_seal = binding.source.copy()
	if not lethal:
		binding.request = DamageRequest.new(id, amount, &"physical", &"bypass", binding.source)
		if guard.values["participants"][id].has("armor"):
			var maximum: float = guard.values["participants"][id]["stats"][StatTypes.StatType.HP_MAX]
			binding.request = ArmorAttack.request(id, ArmorRuntime.physical(ArmorAttack.fall(maximum, drop, true), "fall"), binding.source)
		binding.request_seal = binding.request.copy()
	binding.values = {"mode": mode, "target_id": id, "from_cell": from, "to_cell": to, "drop_steps": drop, "amount": amount, "lethal": lethal, "source": binding.source.to_dict(), "board_origin_version": guard.values["board_origin_version"], "expected_board_version": guard.values["expected_board_version"]}
	binding._seal = binding.values.duplicate(true); binding._refs = binding.guard.refs.duplicate(true)
	return binding

static func execute_binding(binding: Binding, context: ActionContext, mode: StringName) -> CommandStepResult:
	if binding == null or not binding.check(context, mode): return CommandStepResult.faulted(&"move/fall_binding")
	if mode == &"fall" and binding.request.armor_mode == &"armor":
		var seal_check := func() -> bool: return binding.sealed(mode)
		return ArmorHitExecutor.execute(binding.request, binding.guard, context, seal_check)["result"]
	var id: int = binding.values["target_id"]
	var hp: float = binding.guard.values["participants"][id]["hp"]
	var amount := maxf(hp, 1.0) if mode == &"cell_death" else binding.request.amount
	var lethal := amount >= hp
	if lethal and int(binding.guard.values["expected_board_version"]) >= ActionContext.MAX_ID: return CommandStepResult.faulted(&"move/fall_binding")
	var written := binding.guard.hp_phase(id, amount, false)
	var done := binding.guard.hp_phase(id, amount, lethal)
	var checkpoint := func(stage: StringName) -> StringName:
		if not binding.sealed(mode): return &"move/fall_binding"
		var expected := written if stage == &"hp_written" else done
		return &"" if expected.check(context) else &"move/fall_binding"
	var result := ActionHpExecutor.death_spatial(id, binding.source, context, checkpoint) if mode == &"cell_death" else ActionHpExecutor.damage_spatial(binding.request, context, checkpoint)
	if result.status != &"APPLIED" or not binding.sealed(mode) or not done.check(context):
		result.status = &"FAULTED"; result.reason = &"move/fall_binding"
	return result
