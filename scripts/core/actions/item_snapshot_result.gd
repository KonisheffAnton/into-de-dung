extends RefCounted
class_name ItemSnapshotResult

enum Code { OK, SNAPSHOT_UNSUPPORTED, SNAPSHOT_INVALID, SNAPSHOT_BUSY }

var code: Code = Code.SNAPSHOT_INVALID
var reason: String = ""
var _unsupported_ids: Array[StringName] = []
var unsupported_ids: Array[StringName]:
	get:
		# Диагностика не должна отдавать вызывающему внутренний изменяемый массив.
		return _unsupported_ids.duplicate()
	set(value):
		_unsupported_ids = value.duplicate()
var snapshot: ItemSimulationSnapshot = null
var state: ItemSimulationState = null

static func ok_snapshot(value: ItemSimulationSnapshot) -> ItemSnapshotResult:
	var result := ItemSnapshotResult.new()
	result.code = Code.OK
	result.snapshot = value
	return result

static func ok_state(value: ItemSimulationState) -> ItemSnapshotResult:
	var result := ItemSnapshotResult.new()
	result.code = Code.OK
	result.state = value
	return result

static func failure(p_code: Code, p_reason: String, ids: Array[StringName] = []) -> ItemSnapshotResult:
	var result := ItemSnapshotResult.new()
	result.code = p_code
	result.reason = p_reason
	result.unsupported_ids = ids
	return result
