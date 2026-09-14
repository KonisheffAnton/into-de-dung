extends RefCounted
class_name BoardSnapshotResult

enum Code { OK, SNAPSHOT_UNSUPPORTED, SNAPSHOT_INVALID }
var code: Code = Code.SNAPSHOT_INVALID
var reason: String = ""
var _unsupported_ids: Array[StringName] = []
var unsupported_ids: Array[StringName]:
	get:
		# Диагностика результата не должна становиться внешним mutable DTO.
		return _unsupported_ids.duplicate()
	set(value):
		_unsupported_ids = value.duplicate()
var snapshot: SimulationSnapshot = null

static func ok(value: SimulationSnapshot) -> BoardSnapshotResult:
	var result := BoardSnapshotResult.new()
	result.code = Code.OK
	result.snapshot = value
	return result

static func failure(p_code: Code, p_reason: String, ids: Array[StringName] = []) -> BoardSnapshotResult:
	var result := BoardSnapshotResult.new()
	result.code = p_code
	result.reason = p_reason
	result.unsupported_ids = ids.duplicate()
	return result
