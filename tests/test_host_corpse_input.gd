extends "res://tests/test_battle_magic_freshness_ui.gd"

var capture_dir: String = ""

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL HOST CORPSE INPUT: " + label)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): capture_dir = argument.trim_prefix("--captures=")
	call_deferred("run")

func _party_session() -> BattleCoreReactionsSession:
	var profile := HeroHubState.create(73519)
	profile.enable_mage_deck()
	var mage_id := 0
	var second_id := 0
	for id: int in profile.heroes:
		var hero: HeroProgression = profile.heroes[id]
		if hero.class_id == &"mage": mage_id = id
		elif second_id == 0: second_id = id
	if mage_id <= 0 or second_id <= 0: return null
	profile.party.clear()
	profile.party.assign([mage_id, second_id])
	if not profile.select_mage_host(mage_id): return null
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
	if value.phase != BattleTacticalSession.Phase.PLAYER_TURN: value.close(); return null
	# Forecasting raise/return requires their full costs while preserving valid active-team clock fields.
	value.state.abilities.serials.assign([8, 8])
	value.state.abilities.ended.assign([7, 8])
	value.state.abilities.maximum = 9
	var mage_unit_id := 0
	for unit_id: int in value.actor_loadouts:
		if value.actor_loadouts[unit_id].get("class_id") == &"mage": mage_unit_id = int(unit_id); break
	if mage_unit_id <= 0 or not value.select_unit(mage_unit_id): value.close(); return null
	value.state.abilities.mana = 9
	return value

func _install_hand_type(type_id: String) -> Dictionary:
	var deck := session.state.deck
	if deck == null or deck.hand_ids.is_empty(): return {}
	var slot := 0
	var id: int = deck.hand_ids[slot]
	for index: int in deck.cards.size():
		if int(deck.cards[index].id) == id:
			var card: Dictionary = deck.cards[index].duplicate(true)
			card["type_id"] = type_id
			deck.cards[index] = card
			break
	demo._refresh_mage()
	return {"slot":slot,"id":id,"definition":MageCardCatalog.get_card(type_id)}

func _select_and_hover(type_id: String, cell: Vector2i) -> Dictionary:
	var selected := _install_hand_type(type_id)
	if selected.is_empty(): return {}
	demo._choose_card_slot(int(selected.slot))
	_request_hover(cell)
	return selected

func _set_remains(kind: String) -> void:
	for index: int in session.state.environment.corpses.size():
		var body: Dictionary = session.state.environment.corpses[index].duplicate(true)
		if int(body.get("source_unit_id", 0)) != session.state.card_effects.host_unit_id: continue
		body["remains"] = kind
		body["fresh_turns_left"] = 0 if kind == "bones" else 1
		body["fresh_round_pending"] = false
		session.state.environment.corpses[index] = body
		return

func _focus_host_anchor() -> void:
	var board := demo.board_view
	if board == null or not is_instance_valid(board._host_anchor_visual) or not board._host_anchor_visual.visible: return
	var anchor_screen := board.world_to_view(board._host_anchor_visual.position)
	var center := board.size * 0.5
	board.zoom_camera(1.8, anchor_screen)
	board.pan_camera(center - anchor_screen)

func _save_capture(name: String, focus_anchor: bool = false) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	if focus_anchor: _focus_host_anchor()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(demo.get_viewport().get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK,
		"optional rendered capture " + name)

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): capture_dir = argument.trim_prefix("--captures=")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	session = _party_session()
	check(session != null, "real expedition has mage host and surviving party member")
	if session == null:
		viewport.queue_free(); quit(1); return
	if not await _open_demo():
		check(false, "HeroHubBattleView takes the real corpse-target fixture")
		await _close_demo(); viewport.queue_free(); quit(1); return
	var host_id: int = session.state.card_effects.host_unit_id
	var host := session.board.get_unit_by_id(host_id)
	var ally_id := 0
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.PLAYER and unit.is_alive() and unit.id != host_id: ally_id = unit.id; break
	var ally := session.board.get_unit_by_id(ally_id)
	check(host != null and ally != null, "fixture resolves distinct host and ally")
	if host == null or ally == null: await _close_demo(); viewport.queue_free(); quit(1); return
	var host_cell: Vector2i = host.cell
	var alive_card := _install_hand_type("card.light_step")
	demo._choose_card_slot(int(alive_card.slot))
	_request_hover(host_cell)
	check(await _wait_magic_result() and demo._action_forecast_target_id == host_id,
		"living-host hover preview targets its current bound unit")
	var alive_request_current := demo._action_forecast_request_current()
	var death := session._queue.submit(DeathCommand.new(host_id, DamageSource.new(&"test", 0, host_cell)), session.context)
	check(death.status == ActionReceipt.APPLIED and not demo._action_forecast_request_current(),
		"host death revision invalidates the pending living-target request")
	check(alive_request_current, "living-target request began current before death")
	check(session.select_unit(ally_id), "surviving ally can take over input after host death")
	var ally_old_cell: Vector2i = ally.cell
	check(session.board.move_unit(ally, host_cell), "live ally can occupy the empty remains cell")
	demo._refresh()
	var corpse := HostBinding.corpse(session.state, host_id)
	check(not corpse.is_empty() and corpse.cell == host_cell, "dead bound host has an authoritative body at the target cell")
	var light := _select_and_hover("card.light_step", host_cell)
	check(not light.is_empty() and demo._card_target_id(light.definition, host_cell) == host_id,
		"host-only card resolves bound dead host ahead of the live cell occupant")
	check(await _wait_magic_result() and demo._elemental_forecast != null
		and demo._elemental_forecast.status == ActionReceipt.APPLIED and demo._action_forecast_target_id == host_id
		and demo._action_forecast_cell == host_cell,
		"corpse-target card hover publishes the host ID and exact cell")
	await _save_capture("host-corpse-field", true)
	await _save_capture("host-card-target", true)
	demo.set_process(true)
	var clicked := _click_board_cell(host_cell)
	check(clicked == host_cell, "real board input click resolves to the corpse cell under the ally")
	check(await _settle_live_action(), "corpse-cell click returns execution ownership")
	check(session.last_receipt != null and session.last_receipt.status == ActionReceipt.APPLIED,
		"host-only card click executes through normal mage command")
	demo.set_process(false)
	var fire_imbue := _select_and_hover("card.fire_imbue", host_cell)
	check(not fire_imbue.is_empty() and demo._card_target_id(fire_imbue.definition, host_cell) == ally_id,
		"fire imbue prefers a living occupant at the carrier remains cell")
	check(await _wait_magic_result() and demo._elemental_forecast != null
		and demo._elemental_forecast.status == ActionReceipt.APPLIED and demo._action_forecast_target_id == ally_id,
		"fire imbue hover forecast uses the visible living ally")
	check(session.board.move_unit(ally, ally_old_cell), "ally leaves the corpse cell for fallback check")
	_set_remains("bones")
	demo._refresh()
	check(HostBinding.anchor(session.state).get("kind", "") == "bones", "aged host body publishes the bones anchor")
	var fire_fallback := _select_and_hover("card.fire_imbue", host_cell)
	check(not fire_fallback.is_empty() and demo._card_target_id(fire_fallback.definition, host_cell) == host_id,
		"fire imbue falls back to dead host bones only on the now-empty remains cell")
	check(await _wait_magic_result() and demo._elemental_forecast != null
		and demo._elemental_forecast.status == ActionReceipt.APPLIED and demo._action_forecast_target_id == host_id,
		"dead-host fallback hover forecast retains the bound unit ID")
	await _save_capture("host-bones-field", true)
	var shield := _select_and_hover("card.shield", host_cell)
	check(not shield.is_empty() and demo._card_target_id(shield.definition, host_cell) == host_id,
		"shield fallback also targets the dead carrier on an empty remains cell")
	check(await _wait_magic_result() and demo._elemental_forecast != null
		and demo._elemental_forecast.status == ActionReceipt.APPLIED and demo._action_forecast_target_id == host_id,
		"shield fallback preview uses the same resolved target")
	for cell_card: String in ["card.raise", "card.return_to_life"]:
		if cell_card == "card.return_to_life":
			_set_remains("fresh")
			demo._refresh()
		var selected := _select_and_hover(cell_card, host_cell)
		check(not selected.is_empty() and demo._card_target_id(selected.definition, host_cell) == UnitId.NONE,
			"%s is routed by corpse cell, not unit target" % cell_card)
		check(await _wait_magic_result() and demo._elemental_forecast != null
			and demo._elemental_forecast.status == ActionReceipt.APPLIED and demo._action_forecast_cell == host_cell
			and demo._action_forecast_target_id == UnitId.NONE,
			"%s hover forecast preserves selected remains cell" % cell_card)
	var current_cell_request := demo._action_forecast_request_current()
	session.state.card_effects.host_unit_id = ally_id
	check(current_cell_request and not demo._action_forecast_request_current(),
		"raised-host ID change invalidates the outstanding cell-card freshness witness")
	session.state.card_effects.host_unit_id = host_id
	# Удаление тела меняет якорь на духа: тело уже нельзя выбрать как host_unit.
	for index: int in range(session.state.environment.corpses.size() - 1, -1, -1):
		if int(session.state.environment.corpses[index].get("source_unit_id", 0)) == host_id:
			session.state.environment.corpses.remove_at(index)
	demo._refresh()
	var spirit_anchor := HostBinding.anchor(session.state)
	check(spirit_anchor.get("kind", "") == "spirit", "consuming the body leaves a spirit anchor")
	var light_definition: MageCardDefinition = MageCardCatalog.get_card("card.light_step")
	check(demo._card_target_id(light_definition, host_cell) == UnitId.NONE,
		"spirit anchor is not a body target for host-only cards")
	demo._clear_forecast()
	check(demo._elemental_forecast == null and not demo._action_forecast_pending,
		"spirit capture has no stale card calculation")
	await _save_capture("host-spirit-field", true)
	await _close_demo()
	viewport.queue_free()
	await process_frame
	print("HOST CORPSE INPUT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
