extends RefCounted
class_name ActionContext

const MAX_ID: int = 9223372036854775807
var _state: ItemSimulationState
var _rng: ActionRngPort
var _sink: ActionEventSink
var _unsupported_runtime_ids: Array[StringName]
var _busy: bool = false
var _faulted: bool = false
var _next_root_id: int = 1
var _next_command_seq: int = 1
var _next_event_seq: int = 1
var _revision: int = 0

func _init(state: ItemSimulationState, rng: ActionRngPort, sink: ActionEventSink, unsupported_runtime_ids: Array[StringName]) -> void:
	_state = state
	_rng = rng
	_sink = sink
	_unsupported_runtime_ids = unsupported_runtime_ids.duplicate()

func get_state() -> ItemSimulationState: return _state
func get_rng() -> ActionRngPort: return _rng
func get_sink() -> ActionEventSink: return _sink
func get_unsupported_runtime_ids() -> Array[StringName]: return _unsupported_runtime_ids.duplicate()
func get_revision() -> int: return _revision
func is_busy() -> bool: return _busy
func is_faulted() -> bool: return _faulted

func _take_root_id() -> int:
	if _next_root_id >= MAX_ID: return 0
	var value := _next_root_id
	_next_root_id += 1
	return value

func _take_command_seq() -> int:
	if _next_command_seq >= MAX_ID: return 0
	var value := _next_command_seq
	_next_command_seq += 1
	return value

func _take_event_seq() -> int:
	if _next_event_seq >= MAX_ID: return 0
	var value := _next_event_seq
	_next_event_seq += 1
	return value

func _bump_revision() -> void: _revision += 1
