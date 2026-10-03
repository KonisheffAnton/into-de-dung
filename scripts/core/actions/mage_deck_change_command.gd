class_name MageDeckChangeCommand
extends Command

var operation: StringName
var ids: Array[int]
var revision: int

func _init(op: StringName = &"", selected: Array[int] = [], rev: int = 0) -> void:
	operation = op; ids = selected.duplicate(); revision = rev

func get_kind() -> StringName: return &"deck_change"
func copy_for_queue() -> Command: return MageDeckChangeCommand.new(operation,ids,revision)

func projected_deck(context: ActionContext) -> Dictionary:
	if context == null or context.is_faulted() or context.get_revision() != revision or not MageDeckRules.references_valid(context): return {}
	var state := context.get_state()
	if state.deck == null: return {}
	var plan: Dictionary = {}
	if operation == &"mulligan" and state.abilities.stage == "setup": plan = state.deck.mulligan(ids)
	if operation == &"replace" and state.abilities.mage_allowed and ids.size() == 1:
		plan = state.deck.replace(ids[0],state.abilities.serials[0])
	return plan.get("after",{})

func validate(context: ActionContext) -> StringName:
	return &"deck/change_unavailable" if projected_deck(context).is_empty() else &""

func execute(context: ActionContext) -> CommandStepResult:
	var after := projected_deck(context)
	if after.is_empty(): return CommandStepResult.faulted(&"deck/change_unavailable")
	var guard := SpatialRules.capture_guard(context,[],[],{})
	if guard == null: return CommandStepResult.faulted(&"deck/invalid_runtime")
	var before := context.get_state().deck.to_dict()
	guard = guard.deck_phase(after)
	context.get_state().deck.apply_values(after)
	var result := CommandStepResult.applied([changed(before,after,String(operation))],[],[],null,true)
	if not guard.check(context): result.status = &"FAULTED"; result.reason = &"deck/checkpoint"
	return result

static func changed(before: Dictionary, after: Dictionary, reason: String) -> Dictionary:
	return {"kind":&"deck_changed","reason":reason,"before":before.duplicate(true),"after":after.duplicate(true)}

static func valid_draft(data: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(data,{"kind":TYPE_STRING_NAME,"reason":TYPE_STRING,"before":TYPE_DICTIONARY,"after":TYPE_DICTIONARY}): return false
	return data.reason in ["initial","mulligan","replace","draw","play"] and BattleDeckState.from_dict(data.before) != null and BattleDeckState.from_dict(data.after) != null
