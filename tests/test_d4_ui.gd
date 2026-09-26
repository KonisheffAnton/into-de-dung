extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: D4Expedition
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL D4 UI: " + label)

func _run() -> void:
	demo = (load("res://scenes/demo/expedition_d4.tscn") as PackedScene).instantiate()
	demo.save_path = "user://d4-ui/%d.save" % Time.get_ticks_usec()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(demo)
	viewport.notify_mouse_entered()
	await process_frame; await process_frame
	check(demo.run.phase == D4RunState.HUB, "opens preparation")
	await capture("d4-01-preparation")
	await press("unequip_1")
	check(demo.run.item(1).place == "warehouse", "input unequips without duplicate")
	await press("hero_2")
	await press("equip_1")
	check(demo.run.item(1).hero == 2 and demo.run.item(4).place == "warehouse", "input transfers and replaces gear")
	await press("hero_1")
	await press("equip_10")
	check(demo._item_text(demo.run.item(13)).contains("пробивание 50%"), "warehouse explains piercing weapon")
	await press("equip_13")
	check(demo.run.item(13).hero == 1, "input equips piercing weapon")
	var scroll := demo.find_child("RunScroll", true, false) as ScrollContainer
	await motion(scroll.global_position + Vector2(80, 180))
	for _index: int in 9:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = scroll.global_position + Vector2(80, 180)
		viewport.push_input(wheel, true)
		wheel.pressed = false
		viewport.push_input(wheel, true)
	await process_frame
	check(scroll.scroll_vertical > 0, "real wheel scrolls warehouse")
	await capture("d4-02-warehouse")
	await press("start")
	check(demo.run.phase == D4RunState.BATTLE and demo.battle != null, "input starts saved battle")
	if demo.battle == null:
		printerr("D4 START phase=%s error=%s message=%s" % [demo.run.phase, demo._storage_error, demo._message])
		quit(1)
		return
	var checkpoint := demo.run.to_dict()
	await key(KEY_R)
	check(demo.run.to_dict() == checkpoint and demo.battle.round_number == 1, "R cannot bypass expedition")
	# Фикстура приводит врага к соседней клетке; удар исполняется настоящим вводом.
	var s := demo.battle
	var actor: UnitState = s.hero_units[1]
	var target: UnitState = s.units[3]
	check(actor.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT) == 50, "equipped piercing reaches battle")
	check(demo.battle_view._inspection_text(actor).contains("Пробивание 50%"), "inspection shows effective piercing")
	s.board.move_unit(actor, Vector2i(3,3))
	s.board.move_unit(target, Vector2i(4,3))
	demo.battle_view._refresh()
	await key(KEY_A)
	var point := demo.battle_view.board_view.global_position + demo.battle_view.board_view.cell_center(target.cell)
	await motion(point)
	check(demo.battle_view._forecast != null and demo.battle_view._forecast.status == ActionReceipt.APPLIED, "real input D4 attack forecast")
	check(demo.battle_view._forecast_panel.text.contains("Физический · в обход брони"), "forecast explains separate piercing row")
	await capture("d4-03-battle")
	var live_before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var rng_before: Dictionary = s.context.get_rng().to_dict()
	var counters_before: Dictionary = s.context.simulation_counters()
	var revision_before: int = s.context.get_revision()
	var receipt_before: ActionReceipt = s.last_receipt
	var panel := demo.battle_view._forecast_panel
	var forecast := demo.battle_view._forecast
	var target_id := demo.battle_view._forecast_target_id
	var scroll_bar := panel.get_v_scroll_bar()
	var target_point := point
	await wheel_at(target_point, MOUSE_BUTTON_WHEEL_DOWN, 0.0)
	var scrolled_value := scroll_bar.value
	check(scrolled_value > 0.0 and demo.battle_view._forecast == forecast and demo.battle_view._forecast_target_id == target_id, "wheel over target scrolls details and retains forecast identity")
	await wheel_at(target_point, MOUSE_BUTTON_WHEEL_UP, 0.0)
	check(scroll_bar.value < scrolled_value and demo.battle_view._forecast == forecast and demo.battle_view._forecast_target_id == target_id, "wheel up over target restores details without hover motion")
	await wheel_at(target_point, MOUSE_BUTTON_WHEEL_DOWN, 2.0)
	var scroll_end := maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	check(is_equal_approx(scroll_bar.value, minf(scrolled_value * 2.0, scroll_end)), "double wheel factor advances by two steps")
	await wheel_at(target_point, MOUSE_BUTTON_WHEEL_DOWN, 1000.0)
	check(is_equal_approx(scroll_bar.value, scroll_end), "target wheel clamps at bottom")
	await capture("d4-03-target-wheel")
	await wheel_at(target_point, MOUSE_BUTTON_WHEEL_UP, 1000.0)
	check(scroll_bar.value == scroll_bar.min_value, "positive wheel factor clamps at top")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == live_before and s.context.get_rng().to_dict() == rng_before and s.context.simulation_counters() == counters_before and s.context.get_revision() == revision_before and s.last_receipt == receipt_before, "target wheel preserves snapshot/resources, RNG, counters, revision and receipt")
	await motion(panel.global_position + Vector2(35, 40))
	for _index: int in 5: await wheel_at(panel.global_position + Vector2(35, 40), MOUSE_BUTTON_WHEEL_DOWN, 1.0)
	check(panel.get_v_scroll_bar().value > 0 and demo.battle_view._forecast == forecast, "wheel over forecast panel still scrolls normally")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == live_before, "forecast scroll preserves live")
	await capture("d4-03-piercing-details")
	var other_point := demo.battle_view.board_view.global_position + demo.battle_view.board_view.cell_center(actor.cell)
	await motion(other_point)
	check(demo.battle_view._forecast != forecast and scroll_bar.value == 0.0, "hovering another real cell rebuilds forecast from top")
	await motion(target_point)
	check(demo.battle_view._forecast != null and demo.battle_view._forecast_target_id == target_id and scroll_bar.value == 0.0, "returning to target builds its forecast from top")
	demo.battle_view.set_attack_mode(false)
	check(demo.battle_view._forecast == null and scroll_bar.value == 0.0, "changing mode clears forecast scroll")
	demo.battle_view.set_attack_mode(true)
	await motion(target_point)
	check(demo.battle_view._forecast != null and scroll_bar.value == 0.0, "rebuilt forecast starts at top")
	await click(point)
	check(actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 1, "click after scrolling executes exactly one attack for one main")
	# Проверка маршрута UI использует команды смерти; полные партии — integration runner.
	_finish(s, Faction.Type.ENEMY)
	await process_frame; await process_frame
	check(demo.run.phase == D4RunState.LOOT and demo.battle == null, "terminal automatically commits loot phase")
	await capture("d4-04-loot")
	await press("collect_1")
	check(demo.run.phase == D4RunState.COURIER, "post battle collection reaches courier")
	var loot_id: int = -1
	for record: Dictionary in demo.run.items:
		if record.place == "backpack": loot_id = record.id; break
	await press("send_%d" % loot_id)
	check(demo.run.item(loot_id).place == "warehouse", "courier input sends item")
	await capture("d4-05-courier")
	var disk: D4RunState = D4RunStore.read_run(demo.save_path).run
	check(disk != null and disk.to_dict() == demo.run.to_dict(), "courier persisted exactly")
	await press("continue")
	_finish(demo.battle, Faction.Type.PLAYER)
	await process_frame; await process_frame
	check(demo.run.phase == D4RunState.RESULT and demo.run.last_result == "defeat", "second defeat reaches result")
	check(demo.run.item(loot_id).place == "warehouse" and demo.run.lost_ids.size() == 6, "sent gear protected; remaining eleven lose six")
	await capture("d4-06-defeat")
	await press("return")
	check(demo.run.phase == D4RunState.HUB, "return to preparation")
	var armor_id: int = -1
	for record: Dictionary in demo.run.items:
		if record.kind == "coat": armor_id = record.id; break
	await press("equip_%d" % armor_id)
	# Износ задаётся только в тестовой подготовке, кнопка ремонта работает штатно.
	demo.run.items[demo.run._find_item_index(armor_id)].armor = 10
	demo._render_panel()
	await process_frame; await process_frame
	var before_materials := demo.run.materials
	await press("repair_%d" % armor_id)
	check(demo.run.item(armor_id).armor == 60 and demo.run.materials == before_materials - 50, "repair input pays actual deficit")
	await capture("d4-07-repaired")
	# Второй проход UI до победы проверяет повторное начисление/возвращение.
	await press("start")
	_finish(demo.battle, Faction.Type.ENEMY)
	await process_frame; await process_frame
	await press("collect_1")
	await press("continue")
	_finish(demo.battle, Faction.Type.ENEMY)
	await process_frame; await process_frame
	await press("collect_1")
	check(demo.run.phase == D4RunState.RESULT and demo.run.last_result == "victory" and demo.run.materials == before_materials + 10, "full UI route awards victory once")
	await capture("d4-08-victory")
	var final_state := demo.run.to_dict()
	check(D4RunStore.read_run(demo.save_path).run.to_dict() == final_state, "final save matches result")
	var save_path := demo.save_path
	demo.save_path = "user://d4-ui"
	await press("return")
	check(demo.run.to_dict() == final_state and demo._pending != null and not demo._storage_error.is_empty(), "failed write keeps result and blocks transition")
	demo.save_path = save_path
	await press("retry")
	check(demo.run.phase == D4RunState.HUB and demo._pending == null and demo._storage_error.is_empty(), "retry commits same pending transition")
	viewport.queue_free()
	await process_frame; await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://d4-ui.tmp"))
	print("D4 UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _finish(s: D4BattleSession, faction: Faction.Type) -> void:
	for id: int in s.living_ids(faction):
		s._submit(DeathCommand.new(id, DamageSource.new(&"test", 0, s.board.get_unit_by_id(id).cell)))

func press(button_name: String) -> void:
	var button := demo.find_child(button_name, true, false) as Button
	check(button != null, "button exists " + button_name)
	if button == null: return
	var scroll := demo.find_child("RunScroll", true, false) as ScrollContainer
	if scroll != null: scroll.ensure_control_visible(button)
	await process_frame; await process_frame
	await click(button.global_position + button.size * 0.5)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo.battle_view)

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	viewport.push_input(event, true)
	await process_frame; await process_frame
	await preload("res://tests/fixtures/attack_forecast_wait.gd").settle(self, demo.battle_view)

func click(position: Vector2) -> void:
	await motion(position)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame; await process_frame

func wheel_at(position: Vector2, direction: int, factor: float) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = direction
	event.factor = factor
	event.position = position; event.global_position = position; event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false; viewport.push_input(event, true)
	await process_frame

func capture(label: String) -> void:
	if captures.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)
