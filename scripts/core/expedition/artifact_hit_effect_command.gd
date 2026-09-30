extends Command
class_name ArtifactHitEffectCommand

var _actor: int
var _target: int
var _attack: StringName
var _effect: String
var _eligible: bool
var _source: DamageSource
var _hit_id: String
var _artifacts: Dictionary
var _seal: Array

func _init(actor: int = 0, target: int = 0, attack: StringName = &"", effect: String = "", eligible: bool = false, source: DamageSource = null, hit_id: String = "", artifacts: Dictionary = {}) -> void:
	_actor = actor; _target = target; _attack = attack; _effect = effect; _eligible = eligible
	_source = source.copy() if source != null else null; _hit_id = hit_id; _artifacts = artifacts.duplicate(true)
	_seal = _values().duplicate(true)

func _values() -> Array:
	return [_actor, _target, _attack, _effect, _eligible, _source.to_dict() if _source != null else {}, _hit_id, _artifacts]

func get_kind() -> StringName: return &"artifact_hit_effect"
func copy_for_queue() -> Command:
	var result := ArtifactHitEffectCommand.new(_actor, _target, _attack, _effect, _eligible, _source, _hit_id, _artifacts)
	result._seal = _seal.duplicate(true)
	return result

func validate(context: ActionContext) -> StringName:
	if _values() != _seal or not BattleArtifactRules.references_valid(context): return &"artifact/invalid_source"
	var artifacts := context.get_state().artifacts
	if artifacts.to_dict() != _artifacts or not artifacts.ordinary(_actor, _attack) or _effect not in ["ember","ice","harvest"] or artifacts.stacks(_actor, _effect) != 1 or not artifacts.effect_allowed(_actor, _effect): return &"artifact/invalid_source"
	if _source == null or _source.validate(context) != &"" or _source.kind != &"attack" or _source.instigator_unit_id != _actor or _source.credit_unit_id != _actor or _source.source_instance_id != 0 or _hit_id.is_empty(): return &"artifact/invalid_source"
	if context.get_state().get_board().get_unit_by_id(_target) == null: return &"artifact/invalid_target"
	return &""

func execute(context: ActionContext) -> CommandStepResult:
	var reason := validate(context)
	if reason != &"": return CommandStepResult.faulted(reason)
	var board := context.get_state().get_board()
	var actor := board.get_unit_by_id(_actor)
	var target := board.get_unit_by_id(_target)
	if not _eligible or not actor.is_alive(): return CommandStepResult.skipped(&"artifact/ineligible")
	if _effect == "harvest":
		if target.is_alive(): return CommandStepResult.faulted(&"artifact/invalid_kill")
		return ActionHpExecutor.heal(actor.id, ExpeditionCatalog.HARVEST_HEAL, _source, context)
	if not target.is_alive(): return CommandStepResult.skipped(&"artifact/dead_target")
	if not ElementalRules.valid_unit(target): return CommandStepResult.faulted(&"artifact/invalid_target")
	if _effect == "ice" and target.elemental.wet_turns == 0 and target.elemental.frozen_turns == 0: return CommandStepResult.skipped(&"artifact/dry_target")
	var effect: StringName = &"burning" if _effect == "ember" else &"freeze"
	var transition := ElementalRules.transition(target.elemental.to_dict(), effect, 1, _source.to_dict(), _eligible)
	if transition.reason != &"": return CommandStepResult.faulted(transition.reason)
	var guard := SpatialRules.capture_guard(context, [target], [target.cell], {})
	if guard == null: return CommandStepResult.faulted(&"artifact/invalid_state")
	var write := ElementalRules.write(target, transition.after, guard, context, effect, actor.id)
	var result: CommandStepResult = write.result
	if validate(context) != &"": result.status = &"FAULTED"; result.reason = &"artifact/checkpoint"
	return result
