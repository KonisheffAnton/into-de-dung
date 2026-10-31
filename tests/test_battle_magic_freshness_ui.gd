extends SceneTree

const HERO_BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const FORECAST_WAIT = preload("res://tests/fixtures/action_forecast_wait.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var demo: CountingHeroHubBattleView
var session: BattleCoreReactionsSession

class CountingHeroHubBattleView extends HeroHubBattleView:
	var card_cache_calls: int = 0
	var elemental_cache_calls: int = 0
	var mage_refresh_calls: int = 0

	func _refresh_mage() -> void:
		mage_refresh_calls += 1
		super._refresh_mage()

	func _mage_card_cache(target: UnitState, cell: Vector2i) -> Dictionary:
		card_cache_calls += 1
		return super._mage_card_cache(target, cell)

	func _elemental_cast_cache(actor: UnitState, target: UnitState, effect: StringName,
			cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
		elemental_cache_calls += 1
		return super._elemental_cast_cache(actor, target, effect, cell)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE MAGIC FRESHNESS UI: " + label)

func _new_session() -> BattleCoreReactionsSession:
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	var mage_id: int = 0
	for id: int in profile.heroes:
		var hero: HeroProgression = profile.heroes[id]
		if hero.class_id == &"mage": mage_id = id; break
	if mage_id <= 0: return null
	# Один настоящий маг делает источник способностей и его loadout явными.
	profile.party.clear()
	profile.party.append(mage_id)
	var started := ExpeditionTransitions.apply(profile, "start", {})
	if not started.is_ok(): return null
	var bundle := HeroHubBattleFactory.create(started.profile)
	if bundle.is_empty(): return null
	var value: BattleCoreReactionsSession = bundle.session
	if value.state.deck == null or value.state.abilities == null: value.close(); return null
	if not value.confirm_mage_deployment() or value.confirm_mage_mulligan([]).status != ActionReceipt.APPLIED \
			or not value.start_battle(): value.close(); return null
	if value.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		value._enemy_index = value._enemy_ids.size()
		value.step_enemy()
	if value.phase != BattleTacticalSession.Phase.PLAYER_TURN:
		value.close(); return null
	var mage_unit_id: int = 0
	for unit_id: int in value.actor_loadouts:
		if value.actor_loadouts[unit_id].get("class_id") == &"mage": mage_unit_id = int(unit_id); break
	if mage_unit_id <= 0 or not value.select_unit(mage_unit_id): value.close(); return null
	value.state.abilities.mana = value.state.abilities.maximum
	return value

func _open_demo() -> bool:
	var raw := HERO_BATTLE_SCENE.instantiate()
	raw.set_script(CountingHeroHubBattleView)
	demo = raw as CountingHeroHubBattleView
	demo.supplied_session = session
	demo.presentation_enabled = false
	viewport.add_child(demo)
	await process_frame
	await process_frame
	demo.set_process(false)
	return demo.session == session and demo._battle != null and demo._battle.can_player_act()

func _close_demo() -> void:
	if is_instance_valid(demo):
		demo.queue_free()
		await process_frame
	demo = null
	session = null

func _first_enemy() -> UnitState:
	for unit: UnitState in session.units:
		if unit.is_alive() and unit.faction == Faction.Type.ENEMY: return unit
	return null

func _fire_card_slot() -> int:
	var fire_id: int = 0
	for card: Dictionary in session.state.deck.cards:
		if card.type_id == "card.fire": fire_id = int(card.id); break
	if fire_id <= 0: return -1
	if not session.state.deck.hand_ids.has(fire_id):
		var slot := 0
		var draw_index: int = session.state.deck.draw_ids.find(fire_id)
		if draw_index < 0 or session.state.deck.hand_ids.is_empty(): return -1
		var displaced: int = session.state.deck.hand_ids[slot]
		session.state.deck.hand_ids[slot] = fire_id
		session.state.deck.draw_ids[draw_index] = displaced
	return session.state.deck.hand_ids.find(fire_id)

func _card_index(card_id: int) -> int:
	for index: int in session.state.deck.cards.size():
		if int(session.state.deck.cards[index].id) == card_id: return index
	return -1

func _request_hover(cell: Vector2i) -> void:
	demo.board_view.hover_cell = cell
	demo._hover(cell)

func _click_board_cell(cell: Vector2i) -> Vector2i:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = demo.board_view.cell_center(cell)
	event.global_position = demo.board_view.global_position + event.position
	event.pressed = true
	var picked := demo.board_view.cell_at(event.position)
	demo.board_view._gui_input(event)
	return picked

func _arrange_elemental_target() -> UnitState:
	var actor := session.selected_unit()
	if actor == null: return null
	for enemy: UnitState in session.units:
		if enemy.faction != Faction.Type.ENEMY or not enemy.is_alive(): continue
		for y: int in session.board.height:
			for x: int in session.board.width:
				var origin := Vector2i(x, y)
				if session.board.is_occupied(origin) or not session.board.is_terrain_walkable(origin) or session.board.is_lethal(origin): continue
				if AttackReachCheck.inspect_spatial_cells(session.board, origin, actor.faction, enemy.cell, ElementalCastCommand.RANGE) != &"": continue
				if session.board.move_unit(actor, origin):
					demo._refresh()
					return enemy
	return null

func _target_replacement_invalidates(target: UnitState) -> bool:
	var old_cell: Vector2i = target.cell
	var replacement: UnitState
	for unit: UnitState in session.units:
		if unit.faction == target.faction and unit.id != target.id and unit.is_alive(): replacement = unit; break
	if replacement == null: return false
	var replacement_cell: Vector2i = replacement.cell
	var spare := _find_spare_cell(replacement_cell, old_cell)
	if spare.x < 0 or not session.board.move_unit(target, spare): return false
	if not session.board.move_unit(replacement, old_cell):
		session.board.move_unit(target, old_cell)
		return false
	var invalidated := not demo._action_forecast_request_current()
	var restored_replacement := session.board.move_unit(replacement, replacement_cell)
	var restored_target := session.board.move_unit(target, old_cell)
	return invalidated and restored_replacement and restored_target and demo._action_forecast_request_current()

func _wait_owner_after_preparation() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while demo.session == null and demo._forecast_preparation_worker.is_started() and Time.get_ticks_msec() < deadline:
		demo._poll_forecast_preparation()
		if demo.session == null: await process_frame
	return demo.session == session and not demo._forecast_preparation_worker.is_started()

func _wait_magic_result() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if demo.session == null:
			demo._poll_forecast_preparation()
		else:
			demo._process_action_forecast()
			if demo._elemental_forecast != null and not demo._action_forecast_pending \
					and not demo._action_forecast_worker.is_started(): return true
		await process_frame
	return false

func _test_process_reuses_mage_display(label: String) -> void:
	var witness := demo._action_forecast_freshness
	demo.mage_refresh_calls = 0
	demo.set_process(true)
	for _frame: int in 4: await process_frame
	demo.set_process(false)
	var ready_calls: int = demo.mage_refresh_calls
	check(witness != null and demo._mage_display_freshness == witness and ready_calls > 0,
		"%s: real process refresh stamps the displayed mage state against the ready witness" % label)
	demo.set_process(true)
	for _frame: int in 4: await process_frame
	demo.set_process(false)
	check(demo.mage_refresh_calls == ready_calls and demo._mage_display_freshness == witness,
		"%s: subsequent process frames reuse the exact ready mage display" % label)

func _settle_live_action() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while demo.is_execution_pending() and Time.get_ticks_msec() < deadline: await process_frame
	return not demo.is_execution_pending() and demo.session == session

func _prepare_elemental_case() -> bool:
	session = _new_session()
	if session == null: return false
	if not await _open_demo(): return false
	var target := _first_enemy()
	if target == null: return false
	(session as BattleCoreReactionsSession).elemental_selected = &"wet"
	target = _arrange_elemental_target()
	if target == null: return false
	_request_hover(target.cell)
	check(_target_replacement_invalidates(target),
		"same-cell enemy replacement before preparation invalidates the elemental request")
	_request_hover(target.cell)
	return true

func _find_spare_cell(exclude_a: Vector2i, exclude_b: Vector2i) -> Vector2i:
	for y: int in session.board.height:
		for x: int in session.board.width:
			var cell := Vector2i(x, y)
			if cell == exclude_a or cell == exclude_b or session.board.is_occupied(cell) \
					or not session.board.is_terrain_walkable(cell) or session.board.is_lethal(cell): continue
			return cell
	return Vector2i(-1, -1)

func _test_elemental_freshness() -> void:
	check(await _prepare_elemental_case(), "production expedition creates a player-turn mage UI fixture")
	if session == null or demo == null: return
	check(demo._action_forecast_pending and demo._action_freshness_expected,
		"HeroHubBattleView requests an exact freshness witness for an elemental forecast")
	check(await _wait_magic_result(), "elemental preparation and detached forecast finish")
	var first := demo._elemental_forecast
	var first_witness := demo._action_forecast_freshness
	check(first != null and first.status == ActionReceipt.APPLIED and first_witness != null,
		"real elemental wet forecast is APPLIED and carries a non-null freshness witness")
	var cache_calls: int = demo.elemental_cache_calls
	for _read: int in 3: demo._process_action_forecast()
	check(demo._elemental_forecast == first and demo._action_forecast_freshness == first_witness
		and demo.elemental_cache_calls == cache_calls,
		"stationary ready elemental forecast is reused without full snapshot-cache capture")
	await _test_process_reuses_mage_display("elemental")

	var mana_label_before: String = demo._mage_label.text
	var raw_mana_before: int = session.state.abilities.mana
	var raw_mana_revision: int = session.context.get_revision()
	session.state.abilities.mana = raw_mana_before - 1 if raw_mana_before > 0 else 1
	demo._refresh_mage()
	var changed_mana_label: String = demo._mage_label.text
	check(session.context.get_revision() == raw_mana_revision and changed_mana_label != mana_label_before,
		"explicit mage refresh displays a same-revision raw mana change")
	session.state.abilities.mana = raw_mana_before
	demo.set_process(true)
	await process_frame
	await process_frame
	demo.set_process(false)
	check(demo._mage_label.text == mana_label_before and demo._mage_display_freshness == first_witness,
		"next process refresh restores the witness-world mana label after the raw value is reverted")

	var mana_before: int = session.state.abilities.mana
	var revision_before: int = session.context.get_revision()
	session.state.abilities.mana = mana_before - 1
	check(session.context.get_revision() == revision_before and not first_witness.matches(session),
		"same-revision live mana mutation invalidates the exact witness")
	demo._process(0.0)
	check(demo._mage_label.text != mana_label_before and demo._elemental_forecast == null
		and demo._mage_display_freshness == null,
		"full process guard refreshes raw mana UI and drops the stale preview before releasing session ownership")
	check(await _wait_magic_result(), "mana change requests and publishes a fresh elemental forecast")
	check(demo._elemental_forecast != first and demo._action_forecast_freshness != first_witness
		and demo._elemental_forecast.snapshot_before.abilities.mana == mana_before - 1
		and demo.elemental_cache_calls == cache_calls,
		"mana reprepare uses a new witness and does not fall back to whole-snapshot cache")

	# Изменение после возврата владельца, но до публикации detached симуляции, должно отбросить её результат.
	var target := session.board.get_unit_by_id(demo._action_forecast_target_id)
	var action_cell: Vector2i = demo._action_forecast_cell
	session.state.abilities.mana -= 1
	demo._process_action_forecast()
	check(demo.session == null and demo._forecast_preparation_worker.is_started(),
		"next same-revision change starts a new preparation lease")
	check(await _wait_owner_after_preparation(), "preparation restores owner before detached publication window")
	check(demo._action_forecast_freshness != null and demo._action_forecast_worker.is_started(),
		"prepared action is detached while its input witness is available")
	session.state.abilities.mana = 0 if session.state.abilities.mana > 0 else 1
	var deadline := Time.get_ticks_msec() + 15000
	while demo._action_forecast_worker._thread != null and demo._action_forecast_worker._thread.is_alive() \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	demo._process_action_forecast()
	check(not demo._action_forecast_worker.is_started() and demo._elemental_forecast == null,
		"live mutation after prepare but before publication rejects the detached result")
	check(target != null and session.board.get_unit_by_id(target.id) == target and action_cell == target.cell,
		"detached-publication test preserves the original target and cell")
	_request_hover(action_cell)
	check(await _wait_magic_result(), "forecast can be requested again after stale publication is rejected")
	var ready_mana: int = session.state.abilities.mana
	var target_id: int = target.id
	var final_preview: ForecastSimulation = demo._elemental_forecast
	var expected_after: Dictionary = final_preview.snapshot_after.duplicate(true) if final_preview != null else {}
	demo.set_process(true)
	var clicked_cell := _click_board_cell(action_cell)
	check(clicked_cell == action_cell, "board click coordinate resolves to the displayed target cell")
	check(await _settle_live_action(), "ordinary elemental click command returns session ownership")
	var receipt: ActionReceipt = session.last_receipt
	var actor := session.selected_unit()
	var live_capture := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	var elemental_event_found := false
	if receipt != null:
		for event: Dictionary in receipt.get_events():
			if event.get("kind") == &"elemental_cast" and int(event.get("target_unit_id", 0)) == target_id \
					and event.get("effect") == &"wet": elemental_event_found = true
	var success: bool = (receipt != null and receipt.status == ActionReceipt.APPLIED
		and session.state.abilities.mana == ready_mana and target_id > 0
		and target.elemental.wet_turns > 0 and elemental_event_found and live_capture.snapshot != null
		and live_capture.snapshot.to_dict() == expected_after)
	check(success, "fresh elemental click outcome status=%s reason=%s events=%s actor=%s target=%s effect=%s clicked=%s/%s main=%s mana=%s/%s modes=%s" % [
		"null" if receipt == null else String(receipt.status), "" if receipt == null else String(receipt.reason),
		[] if receipt == null else receipt.get_events(), "null" if actor == null else str([actor.id, actor.cell]),
		"null" if target == null else str([target.id, target.cell, target.elemental.burning_ticks]),
		String(session.elemental_selected), clicked_cell, action_cell,
		-1 if actor == null else actor.action_resources.get_main_left(), session.state.abilities.mana, ready_mana,
		[demo._card_selected_id, demo.attack_mode, demo.summoning_mode, demo.raising_mode]])
	await _close_demo()

func _test_card_freshness() -> void:
	session = _new_session()
	check(session != null, "production expedition fixture includes a live mage deck")
	if session == null: return
	if not await _open_demo(): check(false, "HeroHubBattleView owns the card fixture after setup"); return
	var slot := _fire_card_slot()
	check(slot >= 0, "production fire card is present in the current hand")
	if slot < 0: await _close_demo(); return
	demo._choose_card_slot(slot)
	var card_id: int = session.state.deck.hand_ids[slot]
	var card_index := _card_index(card_id)
	var original_type: String = String(session.state.deck.card(card_id).type_id)
	var target := _first_enemy()
	check(target != null and original_type == "card.fire", "fire card has a live enemy target")
	if target == null: await _close_demo(); return
	_request_hover(target.cell)
	check(demo._action_forecast_kind == &"mage_card" and demo._action_forecast_freshness == null,
		"card selection begins a freshness-tracked request before worker completion")
	check(_target_replacement_invalidates(target),
		"same-cell enemy replacement before preparation invalidates the card request")
	_request_hover(target.cell)
	# Изменение допустимого каталожного типа до начала prepare не должно прикрепить новый witness к старому эффекту.
	var card_record: Dictionary = session.state.deck.cards[card_index]
	card_record["type_id"] = "card.heal"
	session.state.deck.cards[card_index] = card_record
	check(not demo._action_forecast_request_current(), "pre-prepare nested card type change invalidates the captured request")
	card_record["type_id"] = original_type
	session.state.deck.cards[card_index] = card_record
	check(demo._action_forecast_request_current(), "restoring the original card type restores request validity")
	check(await _wait_magic_result(), "fire card preparation and detached forecast finish")
	var first := demo._elemental_forecast
	var first_witness := demo._action_forecast_freshness
	check(first != null and first.status == ActionReceipt.APPLIED and first_witness != null,
		"real card.fire forecast is APPLIED and carries a non-null freshness witness")
	var cache_calls: int = demo.card_cache_calls
	for _read: int in 3: demo._process_action_forecast()
	check(demo._elemental_forecast == first and demo._action_forecast_freshness == first_witness
		and demo.card_cache_calls == cache_calls,
		"stationary ready card forecast is reused without full snapshot-cache capture")
	await _test_process_reuses_mage_display("card")

	var card_button_text: String = demo._card_buttons[slot].text
	var card_label_before: String = demo._mage_label.text
	var card_revision: int = session.context.get_revision()
	card_record = session.state.deck.cards[card_index]
	card_record["type_id"] = "card.heal" if original_type == "card.fire" else "card.fire"
	session.state.deck.cards[card_index] = card_record
	demo._refresh_mage()
	var changed_button_text: String = demo._card_buttons[slot].text
	check(session.context.get_revision() == card_revision and not first_witness.matches(session)
		and changed_button_text != card_button_text,
		"explicit mage refresh displays and invalidates a same-revision nested card type change")
	card_record = session.state.deck.cards[card_index]
	card_record["type_id"] = original_type
	session.state.deck.cards[card_index] = card_record
	demo._refresh_mage()
	check(demo._card_buttons[slot].text == card_button_text and demo._mage_label.text == card_label_before,
		"explicit refresh restores the original card display after its raw type is reverted")
	demo.set_process(true)
	await process_frame
	await process_frame
	demo.set_process(false)
	check(demo._mage_display_freshness == first_witness,
		"process restamps the restored card display before testing a later raw mutation")

	var revision_before: int = session.context.get_revision()
	var original_origin: String = String(session.state.deck.card(card_id).origin)
	card_record = session.state.deck.cards[card_index]
	card_record["origin"] = "found" if original_origin == "base" else "base"
	session.state.deck.cards[card_index] = card_record
	check(session.context.get_revision() == revision_before and not first_witness.matches(session),
		"same-revision nested card metadata mutation invalidates the exact witness")
	demo._process(0.0)
	check(demo._elemental_forecast == null and demo._mage_display_freshness == null,
		"full process guard drops the stale card preview before releasing session ownership")
	check(await _wait_magic_result(), "nested card change requests and publishes a fresh forecast")
	check(demo._elemental_forecast != first and demo._action_forecast_freshness != first_witness
		and demo.card_cache_calls == cache_calls,
		"card reprepare uses the fresh witness without old snapshot-cache fallback")
	var mana_before: int = session.state.abilities.mana
	var final_preview: ForecastSimulation = demo._elemental_forecast
	var expected_after: Dictionary = final_preview.snapshot_after.duplicate(true) if final_preview != null else {}
	demo.set_process(true)
	var clicked_cell := _click_board_cell(target.cell)
	check(clicked_cell == target.cell, "card click coordinate resolves to the displayed target cell")
	check(await _settle_live_action(), "ordinary card click command returns session ownership")
	var live_capture := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.APPLIED
		and session.state.abilities.mana < mana_before and session.state.deck.spent_ids.has(card_id)
		and live_capture.snapshot != null and live_capture.snapshot.to_dict() == expected_after,
		"fresh card forecast still submits the normal APPLIED play-card command")
	await _close_demo()

func _test_unsupported_witness_fallback() -> void:
	session = _new_session()
	check(session != null, "fallback test has the same production expedition session graph")
	if session == null: return
	if not await _open_demo(): check(false, "HeroHubBattleView owns the fallback fixture"); return
	var target := _arrange_elemental_target()
	check(target != null, "fallback target is a real enemy within elemental range")
	if target == null: await _close_demo(); return
	session.set_meta(&"unsupported_freshness_rid", RID())
	(session as BattleCoreReactionsSession).elemental_selected = &"wet"
	_request_hover(target.cell)
	check(demo._action_freshness_expected, "supported production session first requests the freshness path")
	check(await _wait_magic_result(), "RID metadata safely falls back through the owned preparation lifecycle")
	check(demo._elemental_forecast != null and demo._elemental_forecast.status == ActionReceipt.APPLIED
		and demo._action_forecast_freshness == null and not demo._action_freshness_expected
		and demo.elemental_cache_calls > 0,
		"unsupported witness uses legacy elemental snapshot cache for an APPLIED result")
	var cache_calls: int = demo.elemental_cache_calls
	var original_mana: int = session.state.abilities.mana
	var changed_mana: int = original_mana - 1 if original_mana > 0 else 1
	var revision: int = session.context.get_revision()
	session.state.abilities.mana = changed_mana
	check(revision == session.context.get_revision(), "fallback mutation leaves context revision unchanged")
	demo._process_action_forecast()
	check(await _wait_magic_result(), "legacy cache detects direct mana mutation and refreshes the forecast")
	check(demo._elemental_forecast != null and demo._elemental_forecast.snapshot_before.abilities.mana == changed_mana
		and demo._action_forecast_freshness == null and not demo._action_freshness_expected
		and demo.elemental_cache_calls > cache_calls,
		"same-revision mana mutation invalidates and reprepares through full snapshot-cache fallback")
	session.remove_meta(&"unsupported_freshness_rid")
	await _close_demo()

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _test_elemental_freshness()
	await _test_card_freshness()
	await _test_unsupported_witness_fallback()
	viewport.queue_free()
	await process_frame
	print("BATTLE MAGIC FRESHNESS UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
