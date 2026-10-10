extends RefCounted

const BoardClone = preload("res://tools/demo/board_clone_probe.gd")

class Result extends RefCounted:
	var admission: ItemSnapshotResult
	var state: ItemSimulationState = null
	var phases_usec: Dictionary = {}

static func clone_state(source: ItemSimulationState, unsupported_runtime_ids: Array[StringName] = []) -> Result:
	var result := Result.new()
	var total_started := Time.get_ticks_usec()
	var capture_started := total_started
	var captured := ItemSimulationSnapshot.capture(source, unsupported_runtime_ids)
	result.phases_usec["capture"] = Time.get_ticks_usec() - capture_started
	result.admission = captured
	if captured.code != ItemSnapshotResult.Code.OK:
		result.phases_usec["total"] = Time.get_ticks_usec() - total_started
		return result

	# Capture синхронно проверил и зафиксировал live-граф; доска копируется сразу,
	# чтобы последующая сборка целиком читала собственный DTO и каталог.
	var board_started := Time.get_ticks_usec()
	var board := BoardClone.copy_board_unchecked(source.get_board())
	var board_usec := Time.get_ticks_usec() - board_started
	var catalogue_started := Time.get_ticks_usec()
	var catalogue: Dictionary = {}
	for owner: ItemOwnerState in source.get_owners():
		for id: StringName in owner._definitions:
			catalogue[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	result.phases_usec["catalogue"] = Time.get_ticks_usec() - catalogue_started

	var build_started := Time.get_ticks_usec()
	result.state = ItemSimulationSnapshot._build_checked_state(captured.snapshot._data, catalogue, board)
	result.phases_usec["build"] = board_usec + Time.get_ticks_usec() - build_started
	result.admission = ItemSnapshotResult.new()
	result.admission.code = ItemSnapshotResult.Code.OK
	result.phases_usec["total"] = Time.get_ticks_usec() - total_started
	return result
