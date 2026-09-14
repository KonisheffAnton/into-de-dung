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
	var session: BattleDemoSession = _demo.session
	_check(session.board.width == 8 and session.board.height == 8 and session.units.size() == 4, "common 8x8 board")
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
	_check(session.move_to(Vector2i(7, 7)).reason == &"move/insufficient_move", "over-budget path rejects")
	_check(session.units[0].cell == Vector2i(0, 2) and session.units[0].move_points_left == 8.0, "over-budget rejection preserves state")
	for i in 5: _demo.reset_demo()
	_check(session.state.get_owners().size() == 4, "repeat reset keeps one owner graph")
	_demo.queue_free()
	await process_frame
	await process_frame
	_check(session.board == null and session.context == null, "scene exit closes session")
	print("DEMO RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _click_cell(cell: Vector2i, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var view: BattleDemoBoard = _demo.board_view
	var position := view.global_position + view.cell_center(cell)
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
