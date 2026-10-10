extends RefCounted

const Audit = preload("res://tools/demo/board_audit_probe.gd")

class Result extends RefCounted:
	var admission: BoardSnapshotResult
	var board: BattleBoard

static func clone_board(source: BattleBoard, unsupported_runtime_ids: Array[StringName] = []) -> Result:
	var result := Result.new()
	result.admission = Audit.audit(source, unsupported_runtime_ids)
	if result.admission.code == BoardSnapshotResult.Code.OK:
		result.board = copy_board_unchecked(source)
	return result

static func copy_board_unchecked(source: BattleBoard) -> BattleBoard:
	return CheckedBoardClone.copy_board_unchecked(source)

static func copy_unit_unchecked(source: UnitState) -> UnitState:
	return CheckedBoardClone.copy_unit_unchecked(source)
