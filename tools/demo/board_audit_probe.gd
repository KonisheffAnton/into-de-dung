extends RefCounted

## Harness сохраняет прежний API; правила допуска принадлежат production.
static func audit(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult:
	return BoardSnapshotValidator.audit(board, unsupported_runtime_ids)
