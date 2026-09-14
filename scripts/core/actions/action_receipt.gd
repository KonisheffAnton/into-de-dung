extends RefCounted
class_name ActionReceipt

const APPLIED: StringName = &"APPLIED"
const REJECTED: StringName = &"REJECTED"
const FAULTED: StringName = &"FAULTED"
const INTERRUPTED: StringName = &"INTERRUPTED"
var status: StringName = &"REJECTED"
var reason: StringName = &""
var root_id: int = 0
var revision_before: int = 0
var revision_after: int = 0
var _steps: Array[Dictionary] = []
var _events: Array[Dictionary] = []

func get_steps() -> Array[Dictionary]:
	return _steps.duplicate(true)
func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)
