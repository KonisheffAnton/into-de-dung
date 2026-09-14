extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _demo: BattleDemo
var _captures: String = ""

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
	root.add_child(_demo)
	await process_frame
	await process_frame
	var battle := _demo.session as BattleTacticalSession
	_check(battle != null and _demo.tactical_mode, "default tactical scene")
	_check(_demo._phase_label.text.contains("Ваш ход") and not _demo._end_turn_button.disabled, "turn visible and enabled")
	_check(not (_demo._roster.get_child(1) as Button).disabled and not (_demo._roster.get_child(2) as Button).disabled, "enemy roster inspectable; allies selectable")
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
		root.push_input(event, true)
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
	var picture := root.get_texture().get_image()
	_check(picture != null and picture.save_png(_captures.path_join(label + ".png")) == OK, "capture " + label)
