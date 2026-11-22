extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST CARD GEOMETRY: " + label)

func _run() -> void:
	var board := BattleBoard.new(10, 10)
	var host := _unit(1, Faction.Type.PLAYER, Vector2i(1, 1))
	var target := _unit(2, Faction.Type.PLAYER, Vector2i(5, 1))
	var enemy := _unit(3, Faction.Type.ENEMY, Vector2i(3, 1))
	board.add_unit(host); board.add_unit(target); board.add_unit(enemy)
	var result := HostCardGeometry.binding_thread(board, 1, 2)
	_check(result.reason == &"" and result.cells.size() == 5 and result.cells[0] == host.cell and result.cells[4] == target.cell and result.enemy_ids == [3], "row distance four and ordered enemy")
	var before := board.board_version
	HostCardGeometry.binding_thread(board, 1, 2)
	_check(board.board_version == before and board.occupant_at(enemy.cell) == enemy, "query leaves board unchanged")
	_check(_fails(board, Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 2)), "column distance two")
	_check(_fails(board, Vector2i(1, 5), Vector2i(3, 3), Vector2i(2, 4)), "diagonal distance two")
	_check(_bad(board, Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 0), &"host_card/invalid_distance"), "distance one rejected")
	_check(_bad(board, Vector2i(1, 1), Vector2i(1, 6), Vector2i(1, 3), &"host_card/invalid_distance"), "distance five rejected")
	var slope_board := _setup(Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 1))
	slope_board.set_height_steps(Vector2i(2, 1), 1)
	_check(HostCardGeometry.binding_thread(slope_board, 1, 2).reason == &"host_card/uneven_height", "slope rejected")
	var wall_board := _setup(Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 1))
	wall_board.set_terrain(Vector2i(2, 1), TerrainType.Type.WALL)
	_check(HostCardGeometry.binding_thread(wall_board, 1, 2).reason == &"host_card/wall_blocked", "wall rejected")
	var ally_board := _setup(Vector2i(1, 1), Vector2i(4, 1), Vector2i(2, 1))
	ally_board.add_unit(_unit(4, Faction.Type.PLAYER, Vector2i(3, 1)))
	_check(HostCardGeometry.binding_thread(ally_board, 1, 2).enemy_ids == [3], "allied intermediate harmless")
	_check(HostCardGeometry.binding_thread(board, 1, 3, [3]).reason == &"host_card/excluded_endpoint", "excluded target rejected")
	var enemy_endpoint := BattleBoard.new(8, 8)
	enemy_endpoint.add_unit(_unit(1, Faction.Type.PLAYER, Vector2i(1, 1)))
	enemy_endpoint.add_unit(_unit(2, Faction.Type.ENEMY, Vector2i(3, 1)))
	enemy_endpoint.add_unit(_unit(3, Faction.Type.ENEMY, Vector2i(2, 1)))
	_check(HostCardGeometry.binding_thread(enemy_endpoint, 1, 2).reason == &"host_card/target_not_player", "enemy endpoint rejected")
	var dead_board := _setup(Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 1))
	var dead_target: UnitState = dead_board.get_unit_by_id(2)
	dead_target.vitals._is_alive = false
	_check(HostCardGeometry.binding_thread(dead_board, 1, 2).reason == &"host_card/invalid_target", "dead endpoint rejected")
	var no_enemy := BattleBoard.new(8, 8)
	no_enemy.add_unit(_unit(1, Faction.Type.PLAYER, Vector2i(1, 1)))
	no_enemy.add_unit(_unit(2, Faction.Type.PLAYER, Vector2i(3, 1)))
	_check(HostCardGeometry.binding_thread(no_enemy, 1, 2).reason == &"host_card/no_enemy_intermediate", "missing intermediate enemy rejected")
	print("HOST CARD GEOMETRY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _unit(id: int, faction: Faction.Type, cell: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.id = id; unit.faction = faction; unit.cell = cell
	unit.stats = StatsBag.new()
	unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	unit.vitals = Vitals.new(unit.stats, true)
	return unit

func _setup(host_cell: Vector2i, target_cell: Vector2i, enemy_cell: Vector2i) -> BattleBoard:
	var board := BattleBoard.new(8, 8)
	board.add_unit(_unit(1, Faction.Type.PLAYER, host_cell))
	board.add_unit(_unit(2, Faction.Type.PLAYER, target_cell))
	board.add_unit(_unit(3, Faction.Type.ENEMY, enemy_cell))
	return board

func _fails(_board: BattleBoard, host_cell: Vector2i, target_cell: Vector2i, enemy_cell: Vector2i) -> bool:
	var configured := BattleBoard.new(10, 10)
	configured.add_unit(_unit(1, Faction.Type.PLAYER, host_cell))
	configured.add_unit(_unit(2, Faction.Type.PLAYER, target_cell))
	configured.add_unit(_unit(3, Faction.Type.ENEMY, enemy_cell))
	var result := HostCardGeometry.binding_thread(configured, 1, 2)
	return result.reason == &""

func _bad(_board: BattleBoard, host_cell: Vector2i, target_cell: Vector2i, enemy_cell: Vector2i, reason: StringName) -> bool:
	var configured := _setup(host_cell, target_cell, enemy_cell)
	return HostCardGeometry.binding_thread(configured, 1, 2).reason == reason
