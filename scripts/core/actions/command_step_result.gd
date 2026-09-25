extends RefCounted
class_name CommandStepResult

const APPLIED: StringName = &"APPLIED"
const SKIPPED: StringName = &"SKIPPED"
const FAULTED: StringName = &"FAULTED"
const INTERRUPTED: StringName = &"INTERRUPTED"
var status: StringName = FAULTED
var reason: StringName = &""
var events: Array[Dictionary] = []
var mandatory: Array[Command] = []
var reactions: Array[Command] = []
var continuation: Command = null
var state_changed: bool = false
## Только известные команды оплаты/стойки/refill передают заранее записанную дельту.
var combat_perk_changes: Dictionary = {}

static func applied(p_events: Array[Dictionary] = [], p_mandatory: Array[Command] = [], p_reactions: Array[Command] = [], p_continuation: Command = null, p_state_changed: bool = false) -> CommandStepResult:
	return _make(APPLIED, &"", p_events, p_mandatory, p_reactions, p_continuation, p_state_changed)
static func skipped(p_reason: StringName = &"", p_mandatory: Array[Command] = [], p_reactions: Array[Command] = [], p_continuation: Command = null) -> CommandStepResult:
	return _make(SKIPPED, p_reason, [], p_mandatory, p_reactions, p_continuation, false)
static func faulted(p_reason: StringName) -> CommandStepResult:
	return _make(FAULTED, p_reason, [], [], [], null, false)
static func interrupted(p_reason: StringName) -> CommandStepResult:
	return _make(INTERRUPTED, p_reason, [], [], [], null, false)

static func _make(p_status: StringName, p_reason: StringName, p_events: Array[Dictionary], p_mandatory: Array[Command], p_reactions: Array[Command], p_continuation: Command, p_changed: bool) -> CommandStepResult:
	var result := CommandStepResult.new()
	result.status = p_status; result.reason = p_reason; result.state_changed = p_changed
	for event in p_events: result.events.append(ActionEventSink.copy_value(event) as Dictionary)
	result.mandatory = p_mandatory.duplicate(); result.reactions = p_reactions.duplicate(); result.continuation = p_continuation
	return result
