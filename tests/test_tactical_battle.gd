extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _demo: BattleDemo
var _captures: String = ""
var _viewport: SubViewport

class DrainProbe extends ActionEventSink:
	var battle: BattleTacticalSession
	var saw_last_death: bool = false
	var prematurely_terminal: bool = false
	func publish(event: Dictionary) -> void:
		if event.get("kind", &"") != &"died": return
		if battle.living_ids(Faction.Type.PLAYER).is_empty() or battle.living_ids(Faction.Type.ENEMY).is_empty():
			saw_last_death = true
			prematurely_terminal = not battle.context.is_busy() or battle.phase not in [BattleTacticalSession.Phase.PLAYER_TURN, BattleTacticalSession.Phase.ENEMY_TURN]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): _captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		printerr("FAIL BATTLE: " + label)

func _run() -> void:
	_test_flow()
	_test_ai()
	var packed := load("res://scenes/demo/tactical_battle.tscn") as PackedScene
	_demo = packed.instantiate() as BattleDemo
	# Самостоятельный viewport исполняет настоящий GUI picking без native mouse-exit окна.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 850)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.add_child(_demo)
	_viewport.notify_mouse_entered()
	await process_frame
	await process_frame
	var battle := _demo.session as BattleTacticalSession
	_check(battle != null and _demo.tactical_mode, "default tactical scene")
	_check(not _demo._attack_button.visible, "sandbox attack toolbar hidden in tactical mode")
	_check(_demo._phase_label.text.contains("Ваш ход") and not _demo._end_turn_button.disabled, "turn visible and enabled")
	_check(not (_demo._roster.get_child(1) as Button).disabled and not (_demo._roster.get_child(2) as Button).disabled, "enemy roster inspectable; allies selectable")
	await _test_action_bar()
	await _test_healing_item_viewport()
	await _test_item_use_description_viewport()
	await _test_summoning_item_viewport()
	await _test_action_return_to_movement()
	await _test_attack_forecast_viewport()
	await _test_enemy_inspection()
	battle = _demo.session as BattleTacticalSession
	await _capture("battle-01-start")
	_demo.select_character(battle.units[4].id)
	await _key(KEY_A)
	await _click_cell(Vector2i(6, 6))
	_check(not battle.units[5].is_alive() and _demo.board_view.is_fall_animating(battle.units[5].id), "tactical mouse attack retains fall animation")
	_demo.reset_demo()
	# Настоящие клавиши запускают компьютер, повторный Enter не пополняет его ресурсы.
	await _key(KEY_ENTER)
	_check(battle.phase == BattleTacticalSession.Phase.ENEMY_TURN, "Enter starts computer turn")
	var revision := battle.context.get_revision()
	await _key(KEY_ENTER)
	await _key(KEY_A)
	_check(battle.context.get_revision() == revision and not _demo.attack_mode, "repeated Enter/A locked during AI")
	var before := battle.board.to_snapshot_dict()
	_demo.handle_cell(Vector2i(1, 2))
	_check(battle.board.to_snapshot_dict() == before, "mouse handler locked during AI")
	await _capture("battle-02-enemy")
	await _key(KEY_R)
	var reset_board := battle.board
	await create_timer(0.8).timeout
	_check(battle.board == reset_board and battle.phase == BattleTacticalSession.Phase.PLAYER_TURN and battle.context.get_revision() == 0, "reset cancels old AI step")
	await _key(KEY_ENTER)
	for _frame in 500:
		if battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		# Ускоряем только интервал показа, сохраняя настоящий _process executor.
		_demo._ai_delay = 0.0
		await process_frame
	_check(battle.phase == BattleTacticalSession.Phase.PLAYER_TURN and battle.round_number == 2, "UI computer executes then returns control")
	_check(_demo._log.text.contains("атакует"), "computer attack journal visible")
	await _capture("battle-03-return")
	_demo.reset_demo()
	_demo.set_process(false)
	var victory := _play(battle, true)
	_demo._refresh()
	_check(victory == BattleTacticalSession.Phase.VICTORY, "full first scenario winnable through legal actions")
	_check(_demo._phase_label.text.contains("ПОБЕДА") and _demo._end_turn_button.disabled, "victory visible and controls locked")
	await _capture("battle-04-victory")
	_demo.reset_demo()
	var defeat := _play(battle, false)
	_demo._refresh()
	_check(defeat == BattleTacticalSession.Phase.DEFEAT, "passing turns leads to real defeat")
	_check(_demo._phase_label.text.contains("ПОРАЖЕНИЕ"), "defeat visible")
	await _capture("battle-05-defeat")
	_demo.reset_demo()
	_demo.set_process(true)
	_demo.end_turn()
	_demo.toggle_scenario()
	_check(_demo.session is BattleDemoSession and not _demo.session is BattleTacticalSession and _demo.session.units[0].vitals.get_hp() == 80.0, "original sandbox preserved")
	var sandbox := _demo.session
	await create_timer(0.8).timeout
	_check(sandbox.context.get_revision() == 0, "mode switch cancels old computer")
	_demo.toggle_scenario()
	_check(_demo.session is BattleTacticalSession and _demo.session.units[0].vitals.get_hp() == 32.0, "return starts fresh battle")
	_demo.end_turn()
	var closed := _demo.session
	_demo.queue_free()
	await process_frame
	await process_frame
	_check(closed.board == null and closed.context == null, "exit during AI closes runtime")
	print("BATTLE RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_action_bar() -> void:
	var bar := _demo._action_bar
	_check(bar != null and bar.visible and bar._buttons.size() == 8, "tactical action bar has fixed eight visible slots")
	_check(bar._up_button.disabled and bar._down_button.disabled, "single dynamic action page has disabled arrows")
	var requested: Array[StringName] = []
	var capture_request := func(action_id: StringName) -> void: requested.append(action_id)
	bar.action_requested.connect(capture_request)
	var before_pages := _demo.session.board.to_snapshot_dict()
	var descriptors: Array[Dictionary] = []
	for index in 13:
		descriptors.append({"action_id": StringName("synthetic_%d" % index), "label": "Слот %d" % index, "tooltip": "synthetic"})
	bar.set_dynamic_descriptors(descriptors)
	_check(bar._buttons[0].text.begins_with("1  Атака") and bar._buttons[0].text.contains("1 основное") and bar._buttons[1].text.contains("1 основное"), "fixed actions stay stable on dynamic pages")
	_check(not bar._down_button.disabled and bar._up_button.disabled, "dynamic descriptors enable forward page")
	await _click_control(bar._down_button)
	_check(bar._up_button.disabled == false and bar._buttons[2].text.contains("Слот 6"), "dynamic page advances with six slots")
	await _click_control(bar._down_button)
	_check(bar._down_button.disabled and bar._buttons[2].get_meta("action_id") == &"synthetic_12" and bar._buttons[3].disabled, "last page bounded with empty remaining slots")
	await _key(KEY_3)
	_check(requested == [&"synthetic_12"] and _demo.session.board.to_snapshot_dict() == before_pages, "numeric dynamic slot uses displayed descriptor without game mutation")
	_check(bar._buttons[0].get_meta("action_id") == &"attack" and bar._buttons[1].get_meta("action_id") == &"guard", "fixed actions persist on last page")
	await _click_control(bar._up_button)
	await _click_control(bar._up_button)
	_check(bar._up_button.disabled and bar._buttons[2].get_meta("action_id") == &"synthetic_0", "first page restores first dynamic action")
	bar.set_dynamic_descriptors([])
	var battle := _demo.session as BattleTacticalSession
	_demo.select_character(battle.units[0].id)
	_check(bar._buttons[0].text.contains("1 основное") and bar._buttons[1].text.contains("1 основное"), "fixed action costs remain visible")
	await _capture("battle-12-actions")
	await _click_control(bar._buttons[1])
	_check(battle.units[0].guard_stance and battle.units[0].action_resources.get_main_left() == 0, "GUI guard spends one main")
	await _key(KEY_2)
	_check(battle.units[0].action_resources.get_main_left() == 0 and _demo._status.text.contains("отклонено"), "repeated guard is refused with visible status")
	_demo.reset_demo()
	_demo.select_character(battle.units[0].id)
	await _key(KEY_1)
	_check(_demo.attack_mode, "numeric one matches A attack mode")
	await _mouse_motion(_demo.board_view.cell_center(battle.units[1].cell))
	_check(_demo._forecast != null, "guard starts with existing hover forecast")
	await _key(KEY_2)
	_check(battle.units[0].guard_stance, "numeric two activates guard")
	_check(not _demo.attack_mode and _demo.inspected_id == UnitId.NONE and _demo._forecast == null, "guard clears forecast and inspection")
	await _capture("battle-13-guard")
	_demo.reset_demo()
	_demo.select_character(battle.units[2].id)
	await _click_cell(battle.units[1].cell)
	_check(battle.selected_id == battle.units[2].id and _demo.inspected_id == battle.units[1].id, "enemy inspection preserves selected ally")
	await _key(KEY_2)
	_check(battle.units[2].guard_stance and not battle.units[1].guard_stance and _demo.inspected_id == UnitId.NONE, "guard targets selected ally during enemy inspection")
	_demo.select_character(battle.units[0].id)
	_check(not bar._buttons[1].disabled and battle.units[2].guard_stance, "switch preserves other guard and refreshes availability")
	_demo.select_character(battle.units[2].id)
	bar.set_dynamic_descriptors(descriptors)
	await _click_control(bar._down_button)
	_check(bar._buttons[1].disabled and bar._buttons[1].tooltip_text.contains("уже активна"), "page retains fixed disabled reason")
	bar.set_dynamic_descriptors([])
	_demo.reset_demo()
	await _key(KEY_ENTER)
	_check(bar._buttons[1].disabled, "guard disabled while enemy turn is locked")
	_demo.reset_demo()
	# Защита цели должна менять настоящий hover-результат, а не только подпись UI.
	battle._submit(GuardCommand.new(battle.units[3].id, battle.context.get_revision()))
	_demo.select_character(battle.units[2].id)
	await _key(KEY_1)
	await _mouse_motion(_demo.board_view.cell_center(battle.units[3].cell) - Vector2(0, 25.0 * _demo.board_view.grid_config.tile_size.x / 128.0))
	_check(_demo._forecast != null and _demo._forecast.status == ActionReceipt.APPLIED and is_equal_approx(_demo._forecast.units[battle.units[3].id]["after"]["hp"], 26.4), "UI forecast includes target stance")
	await _capture("battle-14-guard-forecast")
	_demo.reset_demo()
	bar.action_requested.disconnect(capture_request)

func _test_healing_item_viewport() -> void:
	var battle := _demo.session as BattleTacticalSession
	var bar := _demo._action_bar
	var actor := battle.units[0]
	var ally := battle.units[2]
	var enemy := battle.units[1]
	_demo.select_character(actor.id)
	var item := battle.healing_item()
	_check(item != null and item.get_charges_left() == 2 and bar._buttons[2].text.contains("2/2") and bar._buttons[2].disabled, "full HP disables healing slot with charges")
	await _key(KEY_3)
	_check(item.get_charges_left() == 2 and actor.action_resources.get_main_left() == 1 and _demo._status.text.contains("полное"), "key3 explains full HP refusal without spending")
	actor.vitals.apply_damage(20.0)
	_demo._refresh()
	_check(is_equal_approx(actor.vitals.get_hp(), 12.0) and not bar._buttons[2].disabled and bar._buttons[2].text.contains("2/2") and bar._buttons[2].text.contains("1 основное"), "damaged actor enables healing slot with cost")
	await _capture("battle-15-healing-ready")
	# Перед оплатой читаем прогноз через тот же hover-путь; исполнение предмета обязано его очистить.
	await _key(KEY_A)
	await _mouse_motion(_demo.board_view.cell_center(enemy.cell))
	_check(_demo._forecast != null, "healing starts with an existing attack forecast")
	await _click_control(bar._buttons[2])
	_check(is_equal_approx(actor.vitals.get_hp(), 24.0) and item.get_charges_left() == 1 and actor.action_resources.get_main_left() == 0, "slot3 heals twelve and spends one main and charge")
	_check(_demo._log.text.contains("использует флакон") and _demo._log.text.contains("+12.0 HP от предмета") and _demo._forecast == null, "healing journal is strict and forecast clears")
	await _capture("battle-16-healing-used")
	_demo.select_character(ally.id)
	var ally_item := battle.healing_item()
	_check(ally_item != null and ally_item.get_charges_left() == 2 and bar._buttons[2].text.contains("2/2"), "switching ally keeps independent charges")
	_demo.select_character(actor.id)
	_check(battle.healing_item().get_charges_left() == 1 and bar._buttons[2].text.contains("1/2"), "returning actor preserves spent charge")
	await _click_cell(enemy.cell)
	_check(battle.selected_id == actor.id and _demo.inspected_id == enemy.id and battle.healing_item().get_charges_left() == 1, "enemy inspection preserves selected flask")
	await _key(KEY_ESCAPE)
	_check(actor.try_refill_turn_resources() == &"" and actor.action_resources.get_main_left() == 1, "manual refill restores main for second item use")
	_demo._refresh()
	await _key(KEY_3)
	_check(is_equal_approx(actor.vitals.get_hp(), 32.0) and battle.healing_item().get_charges_left() == 0 and actor.action_resources.get_main_left() == 0, "second use heals remaining eight and empties flask")
	_demo._refresh()
	await _capture("battle-17-healing-empty")
	actor.vitals.apply_damage(20.0)
	_check(actor.try_refill_turn_resources() == &"", "refill remains available after empty flask")
	_demo._refresh()
	_check(bar._buttons[2].disabled and bar._buttons[2].tooltip_text.contains("заряды"), "empty flask stays disabled with reason")
	await _key(KEY_3)
	_check(battle.healing_item().get_charges_left() == 0 and _demo._status.text.contains("заряды"), "key3 explains empty flask without spending")
	_demo.reset_demo()
	actor = battle.units[0]
	item = battle.healing_item()
	_demo.select_character(actor.id)
	_demo._refresh()
	_check(item != null and is_equal_approx(actor.vitals.get_hp(), 32.0) and item.get_charges_left() == 2 and bar._buttons[2].text.contains("2/2"), "reset creates fresh full flask")
	_check(battle.end_player_turn(), "enemy phase starts for healing lock")
	_demo._refresh()
	var charges_before := item.get_charges_left()
	await _key(KEY_3)
	_check(bar._buttons[2].disabled and item.get_charges_left() == charges_before, "enemy phase disables healing without spending")
	_demo.reset_demo()

func _test_item_use_description_viewport() -> void:
	_demo.reset_demo()
	var battle := _demo.session as BattleTacticalSession
	# Одинаковый каталог всех владельцев: подсказка обязана прочитать параметры,
	# а настоящий input — применить их, без отдельного числа в UI.
	for owner in battle.state.get_owners():
		for item: ItemInstance in owner._items.values():
			if item.get_definition_id() == &"tactical_healing_flask":
				item.get_definition().use_heal_amount = 7.0
	var actor := battle.selected_unit()
	actor.vitals.apply_damage(20.0)
	_demo._refresh()
	var button := _demo._action_bar._buttons[2]
	_check(button.tooltip_text.contains("+7 HP") and button.text.contains("1 основное") and button.text.contains("2/2"), "typed action drives healing tooltip, price and charges")
	await _key(KEY_3)
	_check(actor.vitals.get_hp() == 19.0 and actor.action_resources.get_main_left() == 0 and battle.healing_item().get_charges_left() == 1, "typed action UI applies the displayed heal and cost")
	await _capture("battle-24-item-use-description")
	_demo.reset_demo()
	await _key(KEY_4)
	_check(_demo.summoning_mode and not _demo.attack_mode, "adjacent target still enters summon mode")
	await _key(KEY_ESCAPE)
	_check(not _demo.summoning_mode and battle.summoning_item().get_charges_left() == 2, "target cancellation spends nothing")
	await _key(KEY_4)
	_demo.select_character(battle.units[2].id)
	_check(not _demo.summoning_mode, "switching actor clears item target mode")
	_demo.reset_demo()

func _test_action_return_to_movement() -> void:
	_demo.reset_demo()
	var battle := _demo.session as BattleTacticalSession
	var actor := battle.units[0]
	await _click_cell(actor.cell)
	_check(battle.selected_id == actor.id and not _demo.attack_mode and _demo._move_button.button_pressed, "first ally click selects movement immediately")
	await _click_cell(Vector2i(1, 2))
	_check(actor.cell == Vector2i(1, 2) and actor.move_points_left < 5.0, "first selection moves without M")
	var before := ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict()
	var counters := battle.context.simulation_counters()
	for invalid_cell: Vector2i in [Vector2i(1, 3), battle.units[2].cell, battle.units[5].cell]:
		await _key(KEY_A)
		await _click_cell(invalid_cell)
		_check(not _demo.attack_mode and not _demo.board_view.attack_mode and _demo._forecast == null and _demo._move_button.button_pressed, "invalid empty/friendly/distant target returns movement: %s" % invalid_cell)
		_check(_demo._status.text.contains("недопустимая цель") and _demo._log.text.contains("недопустимая цель"), "invalid target has visible explanation")
		_check(ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == before and battle.context.simulation_counters() == counters, "invalid target spends nothing and does not move on the same click")
	await _click_cell(Vector2i(1, 3))
	_check(actor.cell == Vector2i(1, 3), "next click after rejected attack moves without M")
	_demo.reset_demo()
	actor = battle.units[4]
	await _click_cell(actor.cell)
	await _key(KEY_A)
	await _click_cell(battle.units[5].cell)
	_check(battle.last_receipt.status == ActionReceipt.APPLIED and actor.action_resources.get_main_left() == 0 and not _demo.attack_mode and _demo._forecast == null, "successful attack spends main and returns movement")
	var reachable := battle.reachable_cells()
	var destination := actor.cell
	for cell: Vector2i in reachable:
		if cell != actor.cell and battle.board.occupant_at(cell) == null:
			destination = cell
			break
	_check(destination != actor.cell, "reachable destination exists after attack")
	await _click_cell(destination)
	_check(actor.cell == destination and actor.move_points_left < 5.0 and actor.action_resources.get_main_left() == 0 and actor.action_resources.get_bonus_left() == 1, "attack return preserves resources and permits remaining movement")
	await _key(KEY_A)
	await _click_control(_demo._roster.get_child(0) as Button)
	_check(battle.selected_id == battle.units[0].id and not _demo.attack_mode, "roster ally selection also returns movement")
	_demo.reset_demo()
	actor = battle.selected_unit()
	await _key(KEY_4)
	before = ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict()
	await _click_cell(actor.cell)
	_check(not _demo.summoning_mode and _demo._status.text.contains("недопустимая цель") and ItemSimulationSnapshot.capture(battle.state, []).snapshot.to_dict() == before, "rejected summon returns movement without spending or reselecting")
	await _click_cell(Vector2i(1, 2))
	_check(actor.cell == Vector2i(1, 2), "next click after rejected summon moves")
	_demo.reset_demo()

func _test_flow() -> void:
	var battle := BattleTacticalSession.new()
	_check(battle.living_ids(Faction.Type.PLAYER).size() == 3 and battle.living_ids(Faction.Type.ENEMY).size() == 3, "3 vs 3")
	_check(battle.round_number == 1 and battle.phase == BattleTacticalSession.Phase.PLAYER_TURN, "player starts round 1")
	_check(not battle.select_unit(battle.units[1].id), "cannot select enemy")
	_check(battle.move_to(Vector2i(1, 2)).status == ActionReceipt.APPLIED, "partial movement")
	var move_left := battle.units[0].move_points_left
	var snapshot := battle.board.to_snapshot_dict()
	var revision := battle.context.get_revision()
	_check(battle.select_unit(battle.units[2].id) and battle.select_unit(battle.units[0].id), "free ally switching")
	_check(battle.board.to_snapshot_dict() == snapshot and battle.context.get_revision() == revision and battle.units[0].move_points_left == move_left, "switch preserves all resources and state")
	_check(battle.attack_unit(battle.units[2].id).reason == &"battle/friendly_target", "friendly target refused")
	battle.select_unit(battle.units[4].id)
	var actor := battle.units[4]
	var target := battle.units[5]
	var attack := battle.attack_unit(target.id)
	_check(attack.status == ActionReceipt.APPLIED and not target.is_alive(), "real chasm death")
	_check(actor.action_resources.get_main_left() == 0 and actor.move_points_left == 5.0 and actor.action_resources.get_bonus_left() == 1, "attack costs only one main")
	_check(battle.phase == BattleTacticalSession.Phase.PLAYER_TURN, "one dead enemy does not end battle")
	var stale := MoveCommand.new(actor.id, [actor.cell, Vector2i(6, 6)], battle.context.get_revision())
	_check(battle.end_player_turn(), "end player turn")
	_check(stale.validate(battle.context) == &"move/stale_revision", "turn boundary invalidates old command")
	_check(actor.action_resources.get_main_left() == 0 and battle.units[0].move_points_left == move_left, "outgoing team not refilled")
	_check(target.action_resources.get_main_left() == 1 and not target.is_alive(), "dead enemy not revived/refilled")
	_check(not battle.end_player_turn() and not battle.select_unit(actor.id), "no double end or selection during enemy turn")
	_check(battle.attack_unit(battle.units[1].id).reason == &"battle/input_locked" and battle.move_to(Vector2i(6, 6)).reason == &"battle/input_locked", "player APIs locked")
	_drain_enemy(battle)
	_check(battle.phase == BattleTacticalSession.Phase.PLAYER_TURN and battle.round_number == 2, "enemy turn finite; next round")
	for unit in battle.units:
		if unit.is_alive() and unit.faction == Faction.Type.PLAYER:
			_check(unit.action_resources.get_main_left() == 1 and unit.move_points_left == 5.0, "incoming living player refilled exactly")
	# Fault и busy не должны маскироваться пополнением ресурсов.
	battle.context._busy = true
	_check(not battle.end_player_turn(), "busy transition refused")
	battle.context._busy = false
	battle.context._faulted = true
	_check(not battle.end_player_turn() and battle.move_to(Vector2i.ZERO).status == ActionReceipt.REJECTED, "fault blocks input")
	battle.reset()
	_check(battle.context.get_revision() == 0 and not battle.context.is_faulted(), "reset clears fault with new context")
	# Preflight всей команды должен отказать без восстановления первого юнита.
	battle.units[0].action_resources.try_spend_main(1)
	battle.units[2].action_resources = null
	var refill := BattleTurnRefill.new(battle.living_ids(Faction.Type.PLAYER), battle.context.get_revision(), Faction.Type.PLAYER)
	_check(battle._submit(refill).status == ActionReceipt.REJECTED and battle.units[0].action_resources.get_main_left() == 0, "invalid team refill atomic preflight")
	battle.close()

func _test_ai() -> void:
	var battle := BattleTacticalSession.new()
	var ai := BattleDemoBT.new()
	var snapshot := battle.board.to_snapshot_dict()
	var revision := battle.context.get_revision()
	var one := ai.decide(battle, battle.units[3])
	var two := ai.decide(battle, battle.units[3])
	_check(one.kind == BattleAIIntent.Kind.ATTACK and one.target_id == battle.units[2].id, "AI chooses legal hostile attack")
	_check(one.kind == two.kind and one.target_id == two.target_id and one.path == two.path, "AI deterministic")
	_check(battle.board.to_snapshot_dict() == snapshot and battle.context.get_revision() == revision, "AI decision pure")
	# Удалённая цель требует нескольких ходов: AI должен взять доступный prefix.
	for unit in battle.units: battle.board.remove_unit(unit)
	var actor := battle.units[1]
	var target := battle.units[0]
	actor.cell = Vector2i(0, 0)
	target.cell = Vector2i(7, 0)
	battle.board.add_unit(actor)
	battle.board.add_unit(target)
	var approach := ai.decide(battle, actor)
	_check(approach.kind == BattleAIIntent.Kind.MOVE and approach.path.size() == 6, "AI approaches beyond one turn range")
	_check(MoveCommand.new(actor.id, approach.path, revision).validate(battle.context) == &"", "AI approach validates against real command")
	var legacy := AIAction.make_move(Vector2i(1, 0))
	var converted := BattleAIIntent.from_utility(actor, legacy, [actor.cell, Vector2i(1, 0)])
	_check(converted.kind == BattleAIIntent.Kind.MOVE and converted.actor_id == actor.id, "Utility adapter next move intent")
	_check(BattleAIIntent.from_utility(actor, legacy).kind == BattleAIIntent.Kind.WAIT, "Utility adapter rejects missing route")
	actor.action_resources.try_spend_main(1)
	_check(ai.decide(battle, actor).kind == BattleAIIntent.Kind.WAIT, "AI without main waits")
	battle.close()

func _drain_enemy(battle: BattleTacticalSession) -> void:
	for _step in 20:
		if battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: return
		var receipt := battle.step_enemy()
		if receipt != null: _check(receipt.status == ActionReceipt.APPLIED, "enemy command applies")
	_check(false, "enemy turn exceeded bound")

func _play(battle: BattleTacticalSession, active_player: bool) -> BattleTacticalSession.Phase:
	var ai := BattleDemoBT.new()
	var probe := DrainProbe.new()
	probe.battle = battle
	battle.context._sink = probe
	for _round in 30:
		if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if active_player:
			for id in battle.living_ids(Faction.Type.PLAYER):
				if not battle.select_unit(id): break
				for _action in 2:
					var actor := battle.board.get_unit_by_id(id)
					var intent := ai.decide(battle, actor)
					if intent.kind == BattleAIIntent.Kind.WAIT: break
					var receipt: ActionReceipt
					if intent.kind == BattleAIIntent.Kind.ATTACK: receipt = battle.attack_unit(intent.target_id)
					elif intent.kind == BattleAIIntent.Kind.SUMMON: receipt = battle.use_summoning_item(intent.cell)
					else: receipt = battle.move_to(intent.path.back())
					_check(receipt.status == ActionReceipt.APPLIED, "player command applies in full battle")
					if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		if battle.phase != BattleTacticalSession.Phase.PLAYER_TURN: break
		battle.end_player_turn()
		_drain_enemy(battle)
	print("FULL BATTLE active=%s rounds=%d phase=%s" % [active_player, battle.round_number, battle.phase_text()])
	var revision := battle.context.get_revision()
	var snapshot := battle.board.to_snapshot_dict()
	_check(not battle.end_player_turn() and battle.move_to(Vector2i.ZERO).status == ActionReceipt.REJECTED, "terminal input refused")
	_check(battle.context.get_revision() == revision and battle.board.to_snapshot_dict() == snapshot, "terminal state stable")
	_check(probe.saw_last_death and not probe.prematurely_terminal, "outcome only after complete queue drain")
	probe.battle = null
	battle.context._sink = ActionEventSink.new()
	return battle.phase

func _click_cell(cell: Vector2i, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var view := _demo.board_view
	var position := view.global_position + view.cell_center(cell)
	if _demo.session.board.occupant_at(cell) != null:
		position.y -= 25.0 * view.grid_config.tile_size.x / 128.0
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		_viewport.push_input(event, true)
	await process_frame

func _click_control(control: Control) -> void:
	var position := control.global_position + control.size * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		_viewport.push_input(event, true)
	await process_frame

func _test_enemy_inspection() -> void:
	var battle := _demo.session as BattleTacticalSession
	var enemy := battle.units[1]
	var selected := battle.selected_id
	# Исчерпанный остаток прошлого хода не должен скрывать движение после будущего refill.
	enemy.move_points_left = 0.0
	var before := battle.board.to_snapshot_dict()
	var revision := battle.context.get_revision()
	await _click_cell(enemy.cell)
	_check(_demo.inspected_id == enemy.id and _demo.board_view.inspected_id == enemy.id, "enemy mouse click inspects")
	_check(battle.selected_id == selected and battle.board.to_snapshot_dict() == before and battle.context.get_revision() == revision, "inspection never selects enemy or mutates battle")
	_check(enemy.move_points_left == 0.0 and enemy.action_resources.get_main_left() == 1, "inspection does not refill enemy")
	var finder := GridPathfinder.new()
	finder.configure(battle.board.get_bounds(), battle.board.make_spatial_data_provider(enemy), 1, &"spatial_move_v1")
	var expected := finder.get_reachable_cells(enemy.cell, 5.0)
	_check(_demo.board_view.inspection_cells == expected and expected.size() > 1, "inspection uses full next-turn budget with real provider")
	_check(not expected.has(Vector2i(4, 5)) and not expected.has(Vector2i(6, 2)) and not expected.has(battle.units[0].cell), "enemy range excludes wall void and occupied opponent")
	_check(_demo._status.text.contains("Осмотр") or _demo._stats.text.contains("Осмотр"), "inspection visibly distinguished from player selection")
	_check(_demo._status.text.contains("5.0 ОД"), "inspection labels budget rather than cell count")
	_demo.board_view.hover_cell = Vector2i(3, 2)
	_demo.board_view.refresh()
	_check(_demo.board_view._path.is_empty(), "inspection suppresses player path")
	var highlighted: Dictionary = {}
	for visual in _demo.board_view._entity_visuals:
		if visual.role != BattleDemoIsoVisual.Role.UNIT and visual.enemy_range:
			highlighted[visual.grid_anchor] = true
			_check(visual.get_parent() == _demo.board_view._entities and not visual.reachable, "enemy marker stays on Y-sorted tile with no allied dots")
	_check(highlighted.size() == expected.size(), "every reachable tile visibly highlighted")
	await _capture("battle-06-enemy-range")
	await _click_cell(enemy.cell)
	_check(_demo.inspected_id == UnitId.NONE, "same enemy click toggles inspection off")
	(_demo._roster.get_child(1) as Button).pressed.emit()
	_check(_demo.inspected_id == enemy.id and battle.selected_id == selected, "enemy roster inspects without selection")
	await _key(KEY_ESCAPE)
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "Escape clears inspection")
	_demo.inspect_enemy(enemy.id)
	await _key(KEY_M)
	_check(_demo.inspected_id == UnitId.NONE, "M clears inspection")
	_demo.inspect_enemy(enemy.id)
	await _click_cell(enemy.cell, MOUSE_BUTTON_RIGHT)
	_check(_demo.inspected_id == UnitId.NONE, "right click clears inspection")
	_demo.inspect_enemy(enemy.id)
	await _click_cell(Vector2i(1, 2))
	_check(_demo.inspected_id == UnitId.NONE and battle.units[0].cell == Vector2i(0, 2) and battle.context.get_revision() == revision, "empty click only dismisses inspection")
	await _click_cell(Vector2i(1, 2))
	_check(battle.units[0].cell == Vector2i(1, 2), "next empty click executes normal player move")
	_demo.inspect_enemy(enemy.id)
	_demo.select_character(battle.units[2].id)
	_check(_demo.inspected_id == UnitId.NONE and battle.selected_id == battle.units[2].id, "ally selection clears enemy inspection")
	_demo.inspect_enemy(enemy.id)
	await _key(KEY_A)
	_check(_demo.inspected_id == UnitId.NONE and _demo.attack_mode, "attack mode clears inspection")
	(_demo._roster.get_child(1) as Button).pressed.emit()
	_check(_demo.inspected_id == enemy.id and not _demo.attack_mode, "roster inspection leaves attack mode")
	_demo.set_attack_mode(false)
	_demo.inspect_enemy(enemy.id)
	_demo.end_turn()
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "end turn clears inspection")
	_demo.inspect_enemy(enemy.id)
	_check(_demo.inspected_id == UnitId.NONE, "inspection cannot restore stale player-turn range during AI")
	_demo.reset_demo()

func _test_attack_forecast_viewport() -> void:
	var battle := _demo.session as BattleTacticalSession
	var actor := battle.units[4]
	var target := battle.units[5]
	var before := battle.board.to_snapshot_dict()
	var revision := battle.context.get_revision()
	_demo.select_character(actor.id)
	await _key(KEY_A)
	await process_frame
	await process_frame
	await _mouse_motion(_demo.board_view.cell_center(target.cell) - Vector2(0, 25.0 * _demo.board_view.grid_config.tile_size.x / 128.0))
	_check(_demo.attack_mode and _demo.board_view.hover_cell == target.cell, "viewport hover enters attack target")
	_check(_demo._forecast != null and _demo._forecast.status == &"APPLIED", "hover builds applied forecast")
	_check(_demo._forecast_panel.text.contains("HP") and _demo._forecast_panel.text.contains("Последствия"), "forecast panel shows HP and receipt events")
	_check(_demo._forecast_panel.text.contains(target.debug_name) and _demo._forecast_panel.text.contains("погиб"), "forecast shows lethal void outcome")
	_check(_demo._stats.text.begins_with(target.debug_name) and battle.selected_id == actor.id, "hover inspects target while keeping actor")
	var target_visual: BattleDemoIsoVisual
	for visual in _demo.board_view._entity_visuals:
		if visual.unit == target: target_visual = visual
	_check(target_visual != null and target_visual.forecast_entry.get("after", {}).get("hp", -1.0) == 0.0, "target HP bar receives lethal final HP")
	_check(battle.board.to_snapshot_dict() == before and battle.context.get_revision() == revision and actor.action_resources.get_main_left() == 1, "forecast hover does not mutate live state")
	await _capture("battle-07-forecast")
	var kept := _demo._forecast
	await _mouse_motion(Vector2(_demo.board_view.size.x + 5, _demo._forecast_panel.global_position.y + 40 - _demo.board_view.global_position.y))
	_check(_demo._forecast == kept, "crossing panel gap retains forecast")
	await _mouse_motion(_demo._forecast_panel.global_position + Vector2(60, 40) - _demo.board_view.global_position)
	_check(_demo._forecast == kept, "moving to details retains forecast for scrolling")
	await _wheel_down(_demo._forecast_panel.global_position + Vector2(60, 40))
	_check(_demo._forecast == kept and _demo._forecast_panel.get_v_scroll_bar().value > 0, "mouse wheel reads remaining forecast events")
	await _capture("battle-10-forecast-details")
	await _mouse_motion(Vector2(-12, -12))
	_check(_demo._forecast == null and _demo._forecast_panel.text.contains("Наведите"), "viewport exit clears forecast")
	_check(_demo._stats.text.begins_with(actor.debug_name), "mouse exit restores selected inspection")
	await _mouse_motion(_demo.board_view.cell_center(target.cell))
	_check(_demo._forecast != null, "hover returns after exit")
	_demo.select_character(battle.units[0].id)
	_check(_demo._forecast == null and not _demo.attack_mode, "selection clears forecast")
	_demo.end_turn()
	_check(_demo._forecast == null, "phase change clears forecast")
	_demo.reset_demo()
	_check(_demo._forecast == null and _demo.board_view.forecast == null, "reset clears forecast overlay")
	await process_frame
	await process_frame
	# Боковая панель остаётся в окне; длинный осмотр и цепь прокручиваются внутри неё.
	_check(_demo._instructions.get_global_rect().end.y <= _viewport.size.y and _demo.board_view.size.y >= 520, "panels fit viewport with usable board")
	_demo.inspect_enemy(battle.units[1].id)
	_demo.toggle_scenario()
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "mode switch clears inspection")
	await _click_cell(_demo.session.units[1].cell)
	_check(_demo.session.selected_id == _demo.session.units[1].id, "sandbox still selects enemy for manual play")
	_check(not (_demo._roster.get_child(1) as Button).disabled, "sandbox enemy roster still enabled")
	_demo.toggle_scenario()
	_demo.inspect_enemy(_demo.session.units[1].id)
	_demo.reset_demo()
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "reset clears inspection")
	_demo.inspect_enemy(-1)
	_demo.inspect_enemy(_demo.session.units[0].id)
	_check(_demo.inspected_id == UnitId.NONE, "invalid or friendly inspection refused")
	# Последующий receipt обязан снять осмотр погибшего, даже если смерть пришла извне UI.
	battle = _demo.session as BattleTacticalSession
	_demo.inspect_enemy(battle.units[5].id)
	battle.select_unit(battle.units[4].id)
	_demo._show_receipt(battle.attack_unit(battle.units[5].id))
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "death receipt clears inspected enemy")
	_demo.reset_demo()
	_demo.inspect_enemy(battle.units[1].id)
	battle.context._faulted = true
	_demo._refresh()
	_check(_demo.inspected_id == UnitId.NONE and _demo.board_view.inspection_cells.is_empty(), "fault clears inspection")
	_demo.reset_demo()
	_demo.inspect_enemy((_demo.session as BattleTacticalSession).units[1].id)
	_check(_demo._stats.text.contains("Лечение +2.0") and _demo._stats.text.contains("пока предмет активен") and not _demo._stats.text.contains("Амулет"), "inspection reads effect amount duration with hidden source")
	await _capture("battle-08-inspection")
	var inspection_scroll := _demo._stats.get_parent() as ScrollContainer
	await _mouse_motion(inspection_scroll.global_position + Vector2(50, 60) - _demo.board_view.global_position)
	await _wheel_down(inspection_scroll.global_position + Vector2(50, 60))
	_check(inspection_scroll.scroll_vertical > 0, "inspection details scroll through viewport input")
	await _capture("battle-11-inspection-effects")
	_demo.reset_demo()
	battle = _demo.session as BattleTacticalSession
	# Та же атака меняет HP союзника за целью: bar обязан получить его отдельный итог.
	battle.board.set_terrain(Vector2i(4, 5), TerrainType.Type.FLOOR)
	battle.board.move_unit(battle.units[0], Vector2i(4, 5))
	_demo.select_character(battle.units[2].id)
	await _key(KEY_A)
	await process_frame
	await _mouse_motion(_demo.board_view.cell_center(battle.units[3].cell))
	var collateral := false
	for visual in _demo.board_view._entity_visuals:
		if visual.unit == battle.units[0] and not visual.forecast_entry.is_empty():
			collateral = visual.forecast_entry["after"]["hp"] < visual.forecast_entry["before"]["hp"]
	_check(collateral and _demo._forecast_panel.text.contains("сталкивается"), "collateral ally HP bar and collision detail")
	await _capture("battle-09-collateral")
	await _mouse_motion(_demo.board_view.cell_center(battle.units[2].cell))
	_check(_demo._forecast != null and _demo._forecast.status == ActionReceipt.REJECTED and _demo._forecast.units.is_empty(), "friendly/self hover explains refusal without HP overlay")
	_demo.reset_demo()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
	await process_frame

func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _demo.board_view.global_position + position
	event.global_position = event.position
	# Координаты в пространстве viewport: headless display не задаёт масштаб окна.
	_viewport.push_input(event, true)
	await process_frame
	await process_frame

func _wheel_down(position: Vector2) -> void:
	for _step in 6:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		_viewport.push_input(event, true)
		var release := event.duplicate() as InputEventMouseButton
		release.pressed = false
		_viewport.push_input(release, true)
	await process_frame
	await process_frame

func _capture(label: String) -> void:
	if _captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := _viewport.get_texture().get_image()
	_check(picture != null and picture.save_png(_captures.path_join(label + ".png")) == OK, "capture " + label)

func _test_summoning_item_viewport() -> void:
	_demo.reset_demo()
	_demo.set_process(false)
	var battle := _demo.session as BattleTacticalSession
	var actor := battle.selected_unit()
	var bar := _demo._action_bar
	_check(bar._buttons[3].get_meta("action_id") == &"summoning_item" and not bar._buttons[3].disabled and bar._buttons[3].text.contains("2/2"), "slot4 separate seal with charges")
	await _key(KEY_4)
	_check(_demo.summoning_mode and not _demo.attack_mode and _demo.board_view._reachable.has(Vector2i(0, 1)) and not _demo.board_view._reachable.has(Vector2i(1, 2)), "key4 enters valid summon cells")
	await _click_cell(Vector2i(1, 2))
	_check(not _demo.summoning_mode and battle.units.size() == 6 and battle.summoning_item().get_charges_left() == 2 and _demo._status.text.contains("недопустимая цель"), "invalid clicked cell returns movement and preserves charge")
	await _capture("battle-18-summon-targeting")
	await _key(KEY_4)
	await _key(KEY_ESCAPE)
	_check(not _demo.summoning_mode, "escape cancels summon targeting")
	await _click_control(bar._buttons[3])
	_check(_demo.summoning_mode, "GUI seal enters targeting")
	await _click_cell(Vector2i(0, 1))
	var helper := battle.state.active_summon(actor.id)
	_check(helper != null and battle.units.size() == 7 and battle.summoning_item().get_charges_left() == 1 and not _demo.summoning_mode and _demo._forecast == null, "clicked cell summons full participant and clears preview")
	if helper == null:
		_demo.reset_demo()
		_demo.set_process(true)
		return
	_check(_demo._log.text.contains("использует печать") and _demo._log.text.contains("призывает"), "summon journal uses correct item")
	var seen := false
	for visual in _demo.board_view._entity_visuals:
		if visual.role == BattleDemoIsoVisual.Role.UNIT and visual.grid_anchor == helper.cell:
			seen = visual.get_parent() == _demo.board_view._entities
	_check(seen, "helper figure belongs to common ENTITIES Y-sort")
	await _capture("battle-19-summon-pending")
	await _click_cell(helper.cell)
	_check(battle.selected_id == helper.id and helper.action_resources.get_main_left() == 0 and _demo._stats.text.contains("следующего хода"), "field selects pending helper without refill")
	_check(bar._buttons[2].disabled and bar._buttons[3].disabled and bar._buttons[1].disabled, "helper has no flask/seal and cannot guard pending")
	# Настоящая прокрутка открывает нового участника в растущем списке.
	var scroll := _demo._roster.get_parent() as ScrollContainer
	var pos := scroll.global_position + scroll.size * 0.5
	for _i in 8:
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_WHEEL_DOWN
			event.pressed = pressed
			event.position = pos
			event.global_position = pos
			_viewport.push_input(event, true)
		await process_frame
	_check(scroll.scroll_vertical > 0, "real roster scrolling reaches dynamic participants")
	var helper_button := _demo._roster.get_child(6) as Button
	_check(helper_button.text.contains("ЖДЁТ ХОДА"), "roster shows pending deadline")
	await _click_control(helper_button)
	_check(battle.selected_id == helper.id and helper.action_resources.get_main_left() == 0, "scrolled roster click selects helper without refill")
	_demo.select_character(actor.id)
	actor.try_refill_turn_resources()
	_demo._refresh()
	await _key(KEY_4)
	_check(not _demo.summoning_mode and _demo._status.text.contains("живой помощник") and battle.summoning_item().get_charges_left() == 1, "key4 explains active-helper refusal")
	await _key(KEY_ENTER)
	_check(not _demo.summoning_mode and bar._buttons[3].disabled, "enemy phase locks summon UI")
	for _step in 40:
		if battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		var receipt := battle.step_enemy()
		if receipt != null: _demo._show_receipt(receipt)
	_demo._refresh()
	_demo.select_character(helper.id)
	_check(not battle.state.is_summon_pending(helper.id) and helper.action_resources.get_main_left() == 1 and not bar._buttons[1].disabled, "next own turn helper ready in UI")
	await _capture("battle-20-summon-ready")
	await _click_cell(Vector2i(0, 0))
	_check(helper.cell == Vector2i(0, 0) and helper.move_points_left == 3.0, "ready helper moves by real input")
	await _key(KEY_R)
	_check(battle.units.size() == 6 and battle.state.get_summons().is_empty() and bar._buttons[3].text.contains("2/2"), "UI reset removes helper and restores seal")
	_demo.set_process(true)
