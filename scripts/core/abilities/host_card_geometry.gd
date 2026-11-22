extends RefCounted
class_name HostCardGeometry

static func binding_thread(board: BattleBoard, host_id: int, target_id: int, excluded_ids: Array[int] = []) -> Dictionary:
	if board == null: return _failure(&"host_card/invalid_board")
	var host: UnitState = board.get_unit_by_id(host_id)
	var target: UnitState = board.get_unit_by_id(target_id)
	if host == null or not host.is_alive(): return _failure(&"host_card/invalid_host")
	if target == null or not target.is_alive(): return _failure(&"host_card/invalid_target")
	if host_id == target_id: return _failure(&"host_card/same_endpoint")
	if host_id in excluded_ids or target_id in excluded_ids: return _failure(&"host_card/excluded_endpoint")
	if host.faction != Faction.Type.PLAYER: return _failure(&"host_card/host_not_player")
	if target.faction != Faction.Type.PLAYER: return _failure(&"host_card/target_not_player")
	if not board.is_in_bounds(host.cell) or not board.is_in_bounds(target.cell): return _failure(&"host_card/out_of_bounds")
	var delta: Vector2i = target.cell - host.cell
	var distance: int = maxi(absi(delta.x), absi(delta.y))
	if distance < 2 or distance > 4: return _failure(&"host_card/invalid_distance")
	if delta.x != 0 and delta.y != 0 and absi(delta.x) != absi(delta.y): return _failure(&"host_card/invalid_direction")
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cells: Array[Vector2i] = []
	var enemy_ids: Array[int] = []
	var height_steps: int = board.get_height_steps(host.cell)
	for i: int in range(distance + 1):
		var cell: Vector2i = host.cell + step * i
		if not board.is_in_bounds(cell): return _failure(&"host_card/out_of_bounds")
		if board.get_height_steps(cell) != height_steps: return _failure(&"host_card/uneven_height")
		if board.get_terrain(cell) == TerrainType.Type.WALL: return _failure(&"host_card/wall_blocked")
		cells.append(cell)
		if i > 0 and i < distance:
			var occupant: UnitState = board.occupant_at(cell)
			if occupant != null and occupant.is_alive() and occupant.faction == Faction.Type.ENEMY: enemy_ids.append(occupant.id)
	if enemy_ids.is_empty(): return _failure(&"host_card/no_enemy_intermediate")
	return {"reason": &"", "cells": cells, "enemy_ids": enemy_ids}

static func _failure(reason: StringName) -> Dictionary:
	return {"reason": reason, "cells": [], "enemy_ids": []}
