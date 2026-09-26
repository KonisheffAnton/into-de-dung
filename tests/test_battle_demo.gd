extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _demo: BattleDemo
var _captures: String = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): _captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		printerr("FAIL DEMO: " + label)

func _run() -> void:
	var scene := load("res://scenes/demo/battle_demo.tscn") as PackedScene
	_check(scene != null, "scene loads")
	if scene == null:
		quit(1)
		return
	_demo = scene.instantiate() as BattleDemo
	root.add_child(_demo)
	await process_frame
	await process_frame
	await _test_isometric_view()
	var session: BattleDemoSession = _demo.session
	_check(session.board.width == 8 and session.board.height == 8 and session.units.size() == 6, "common 8x8 board with ready chasm pair")
	_check(session.board.get_height_steps(Vector2i(3, 2)) == 3 and session.units[1].height == 1, "half heights synchronize on placement")
	_check(session.selected_id == session.units[0].id, "initial selection")
	await _capture("01-initial")
	var before := session.board.to_snapshot_dict()
	var revision := session.context.get_revision()
	var move_left := session.units[0].move_points_left
	# Hover/path queries и переключение не должны выдавать ресурсы или менять бой.
	for i in 4:
		session.path_to(Vector2i(3, 2))
		session.reachable_cells()
		session.select_unit(session.units[i].id)
	session.select_unit(session.units[0].id)
	_check(session.context.get_revision() == revision and session.units[0].move_points_left == move_left, "queries and selection preserve resources/revision")
	_check(session.board.to_snapshot_dict() == before, "queries preserve board snapshot")
	var rejected := session.attack_unit(session.units[1].id)
	_check(rejected.status == ActionReceipt.REJECTED and session.context.get_revision() == revision, "distant attack rejected before payment")
	_check(session.units[0].action_resources.get_main_left() == 1, "rejected attack keeps main")
	_check(session.move_to(Vector2i(4, 5)).status == ActionReceipt.REJECTED, "wall movement rejected")
	_check(session.move_to(Vector2i(6, 2)).status == ActionReceipt.REJECTED, "void movement rejected")
	_check(session.move_to(Vector2i(-1, 2)).status == ActionReceipt.REJECTED, "out of bounds rejected")
	_check(session.attack_unit(session.selected_id).status == ActionReceipt.REJECTED, "self attack rejected")
	# Посылаем мышь в viewport, чтобы проверить hit testing и GUI dispatch сцены.
	await _click_cell(Vector2i(3, 2))
	_check(session.last_receipt.status == ActionReceipt.APPLIED, "mouse Move applies")
	_check(session.units[0].cell == Vector2i(3, 2) and session.units[0].move_points_left == 5.0, "stairs consume three movement points")
	await _key(KEY_A)
	_check(_demo.attack_mode, "A key selects attack")
	await _click_cell(Vector2i(4, 2))
	var result := session.last_receipt
	_check(result.status == ActionReceipt.APPLIED, "mouse high attack applies: " + String(result.reason))
	_check(session.units[1].cell == Vector2i(5, 2), "target pushed down to landing")
	_check(is_equal_approx(session.units[1].vitals.get_hp(), 57.0), "high hit9 + fall18 then two heals2 => HP57")
	_check(session.units[1].vitals.get_balance() == 0.0, "break resets balance")
	_check(session.units[0].action_resources.get_main_left() == 0 and session.units[0].action_resources.get_bonus_left() == 1 and session.units[0].move_points_left == 5.0, "one main paid, move and bonus preserved")
	var kinds: Array[StringName] = []
	for event in result.get_events(): kinds.append(event.kind)
	_check(kinds == [&"attacked", &"damaged", &"balance_broken", &"moved", &"damaged", &"healed", &"healed"], "ordered real attack/fall/item chain: " + str(kinds))
	_check(_demo._log.text.contains("−9.0 HP") and _demo._log.text.contains("−18.0 HP от падения") and _demo._log.text.contains("+2.0 HP"), "journal displays actual event amounts")
	await _capture("02-high-hit")
	_demo.select_character(session.units[2].id)
	_demo.select_character(session.units[0].id)
	_check(session.units[0].action_resources.get_main_left() == 0, "reselect cannot refill")
	_check(session.attack_unit(session.units[1].id).status == ActionReceipt.REJECTED, "second attack rejected")
	_check(session.move_to(Vector2i(3, 3)).status == ActionReceipt.APPLIED, "remaining move after attack")
	# Второй готовый сценарий: цель получает hit и wall damage, остаётся на клетке.
	_demo.reset_demo()
	_demo.select_character(session.units[2].id)
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(3, 5))
	_check(session.last_receipt.status == ActionReceipt.APPLIED, "wall attack applies")
	_check(session.units[3].cell == Vector2i(3, 5) and session.units[3].vitals.get_hp() == 64.0, "wall hit8 plus collision8 without movement")
	_check(_demo._log.text.contains("препятствие"), "wall consequence visible")
	await _capture("03-wall")
	# Test-only расстановка через доску проверяет collateral и смерть в той же сцене.
	_demo.reset_demo()
	session.board.move_unit(session.units[0], Vector2i(1, 4))
	session.board.move_unit(session.units[2], Vector2i(2, 4))
	session.board.move_unit(session.units[3], Vector2i(3, 4))
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(2, 4))
	_check(session.last_receipt.status == ActionReceipt.APPLIED, "character collision applies")
	_check(session.units[2].vitals.get_hp() == 64.0 and session.units[3].vitals.get_hp() == 72.0, "collision damages both participants")
	_check(session.units[2].cell == Vector2i(2, 4), "living blocker prevents move")
	_demo.reset_demo()
	session.board.move_unit(session.units[0], Vector2i(4, 3))
	session.board.move_unit(session.units[1], Vector2i(5, 3))
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(5, 3))
	_check(session.last_receipt.status == ActionReceipt.APPLIED and not session.units[1].is_alive(), "push into void kills")
	_check(session.board.occupant_at(Vector2i(5, 3)) == null and session.board.occupant_at(Vector2i(6, 3)) == null, "death releases occupancy")
	_check(not session.select_unit(session.units[1].id), "dead selection refused")
	_check((_demo._roster.get_child(1) as Button).disabled, "dead roster button disabled")
	_check(_demo._log.text.contains("погиб"), "death journal visible")
	var heal_count := 0
	for event in session.last_receipt.get_events():
		if event.kind == &"healed": heal_count += 1
	_check(heal_count == 0, "no item heal after lethal push")
	_demo.set_attack_mode(false)
	await _click_cell(Vector2i(5, 3))
	_check(session.units[0].cell == Vector2i(5, 3), "mouse moves into released cell")
	var old_owner := session.state.get_owner(session.units[1].id)
	var old_board := session.board
	await _key(KEY_R)
	_check(not _demo.attack_mode and session.units[0].cell == Vector2i(0, 2) and session.units[1].is_alive(), "R resets mode/map/life")
	_check(old_board.width == 0 and old_owner.is_closed(), "reset closes previous state")
	_check(session.context.get_revision() == 0 and session.units[0].action_resources.get_main_left() == 1 and session.units[0].move_points_left == 8.0, "reset creates fresh resources")
	_check(not _demo._log.text.contains("погиб"), "reset clears old journal")
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(0, 2), MOUSE_BUTTON_RIGHT)
	_check(not _demo.attack_mode, "right click on board cancels attack")
	_check(session.move_to(Vector2i(6, 7)).reason == &"move/insufficient_move", "over-budget path rejects")
	_check(session.units[0].cell == Vector2i(0, 2) and session.units[0].move_points_left == 8.0, "over-budget rejection preserves state")
	for i in 5: _demo.reset_demo()
	_check(session.state.get_owners().size() == 6, "repeat reset keeps one owner graph")
	_demo.select_character(session.units[4].id)
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(6, 6))
	var doomed := session.units[5]
	_check(session.last_receipt.status == ActionReceipt.APPLIED and not doomed.is_alive(), "ready chasm pair dies with one click")
	_check(doomed.cell == Vector2i(7, 6) and doomed.vitals.get_hp() == 0.0 and session.board.occupant_at(Vector2i(6, 6)) == null, "ready chasm death/cell release happens before visual effect")
	_check(_demo.board_view.is_fall_animating(doomed.id), "chasm death starts presentation animation")
	await create_timer(0.18).timeout
	await _capture("04-falling")
	await create_timer(0.8).timeout
	_check(not _demo.board_view.is_fall_animating(doomed.id), "falling figure disappears after animation")
	_check(not doomed.is_alive() and doomed.vitals.get_hp() == 0.0, "animation never revives or mutates death")
	await _capture("05-chasm")
	_demo.reset_demo()
	_demo.select_character(session.units[4].id)
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(6, 6))
	var old_id := session.units[5].id
	_demo.reset_demo()
	_check(not _demo.board_view.is_fall_animating(old_id) and session.units[5].is_alive(), "reset cancels in-flight fall visual")
	session.board.move_unit(session.units[0], Vector2i(6, 0))
	session.board.move_unit(session.units[1], Vector2i(7, 0))
	_demo.set_attack_mode(true)
	await _click_cell(Vector2i(7, 0))
	_check(not session.units[1].is_alive() and _demo.board_view.is_fall_animating(session.units[1].id), "boundary fall animates while core retains last cell")
	_demo.set_attack_mode(false)
	_check(_demo.board_view.is_fall_animating(session.units[1].id), "mode refresh preserves active fall")
	var corpse_visible := false
	for visual in _demo.board_view._entity_visuals:
		if visual.unit != null and visual.unit.id == session.units[1].id: corpse_visible = true
	_check(not corpse_visible, "boundary fall leaves no corpse figure on retained logical cell")
	_demo.queue_free()
	await process_frame
	await process_frame
	_check(session.board == null and session.context == null, "scene exit closes session")
	print("DEMO RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_isometric_view() -> void:
	var view := BattleDemoBoard.new()
	var probe := BattleDemoSession.new()
	# Отдельная пустая доска отделяет проверку проекции от перекрытия персонажами.
	for unit in probe.units: probe.board.remove_unit(unit)
	probe.units.clear()
	for y in 8:
		for x in 8:
			probe.board.set_height_steps(Vector2i(x, y), 0)
			probe.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	view.session = probe
	root.add_child(view)
	view.size = Vector2(820, 540)
	view.refresh()
	await process_frame
	var config := view.grid_config
	var origin := view.cell_center(Vector2i.ZERO)
	var x_axis := view.cell_center(Vector2i.RIGHT) - origin
	var y_axis := view.cell_center(Vector2i.DOWN) - origin
	_check(x_axis.x > 0 and x_axis.y > 0 and y_axis.x < 0 and y_axis.y > 0, "ISO logical axes become opposing diagonals")
	_check(is_equal_approx(x_axis.x, 2.0 * x_axis.y) and is_equal_approx(-y_axis.x, 2.0 * y_axis.y), "ISO 2:1 projection")
	_check(origin.is_equal_approx(IsoGridUtils.grid_to_screen(Vector2i.ZERO, config, 0)), "ISO reuses original core projection")
	for y in 8:
		for x in 8:
			var cell := Vector2i(x, y)
			_check(view.cell_at(view.cell_center(cell)) == cell, "ISO flat center pick %s" % str(cell))
	for point: Vector2 in [Vector2(1, 1), Vector2(view.size.x - 1, 1), Vector2(-30, 200), Vector2(view.size.x + 30, 200)]:
		_check(view.cell_at(point) == Vector2i(-1, -1), "ISO outside diamond rejects rectangular corner")
	var cell := Vector2i(3, 2)
	var flat_center := view.cell_center(cell)
	probe.board.set_height_steps(cell, 1)
	view.refresh()
	_check(is_equal_approx(view.cell_center(cell).y, flat_center.y - config.height_step * 0.5), "ISO half-level translates half visual height")
	_check(view.cell_at(view.cell_center(cell)) == cell, "ISO raised top pick")
	probe.board.set_height_steps(cell, -1)
	view.refresh()
	_check(is_equal_approx(view.cell_center(cell).y, flat_center.y + config.height_step * 0.5), "ISO negative half-level projects below ground")
	_check(view.cell_at(view.cell_center(cell)) == cell, "ISO lowered top pick")
	probe.board.set_height_steps(cell, 3)
	view.refresh()
	await process_frame
	var entities: Node2D = null
	for child in view.get_children():
		if child is Node2D and child.z_index == RenderLayers.z_index_for(RenderLayers.Layer.ENTITIES): entities = child
	_check(entities != null and entities.y_sort_enabled, "ISO native ENTITIES Y-sort")
	var platform_found := false
	if entities != null:
		for child in entities.get_children():
			if child is YSortable and child.grid_anchor == cell:
				var base := IsoGridUtils.grid_to_screen(cell, config, 0)
				platform_found = absf(child.position.y - base.y) <= 1.01 and is_equal_approx(child.position.x, base.x)
				_check(child.get_visual_offset().is_equal_approx(Vector2(0, -1.5 * config.height_step)), "ISO platform height stays in visual offset")
	_check(platform_found, "ISO platform sorting anchor ignores elevation")
	var foreground := cell + Vector2i.DOWN
	var foreground_point := view.cell_center(foreground) + Vector2(config.tile_size.x * 0.275, -config.tile_size.y * 0.1)
	_check(view.cell_at(foreground_point) == foreground, "ISO foreground low top covers farther elevated side face")
	var wall_cell := Vector2i(4, 4)
	probe.board.set_terrain(wall_cell, TerrainType.Type.WALL)
	view.refresh()
	var wall_top := view.cell_center(wall_cell) - Vector2(0, config.height_step)
	_check(view.cell_at(wall_top) == wall_cell, "ISO wall raised roof picks wall")
	_check(view.cell_at(view.cell_center(wall_cell) + Vector2(config.tile_size.x * 0.15, 0)) == wall_cell, "ISO wall front face occludes underlying floor")
	view.size = Vector2(620, 580)
	view.refresh()
	await process_frame
	_check(view.cell_at(view.cell_center(cell)) == cell and view.cell_center(cell).x < view.size.x, "ISO resized projection and picking agree")
	view.session = null
	view.queue_free()
	probe.close()
	await process_frame

func _click_cell(cell: Vector2i, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var view: BattleDemoBoard = _demo.board_view
	var position := view.global_position + view.cell_center(cell)
	# У стены точка опоры может быть закрыта её гранью; кликаем по видимому телу.
	if _demo.session.board.occupant_at(cell) != null:
		position.y -= 25.0 * view.grid_config.tile_size.x / 128.0
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event, true)
	await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _capture(label: String) -> void:
	if _captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and image.save_png(_captures.path_join(label + ".png")) == OK, "capture " + label)
