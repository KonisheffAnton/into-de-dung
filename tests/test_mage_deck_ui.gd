extends SceneTree

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var host: HeroHubScreen
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1; printerr("FAIL MAGE DECK UI: " + label)

func _run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/demo/main_menu.tscn", "production menu route")
	var path := "user://mage-deck-ui-%d.save" % Time.get_ticks_usec()
	viewport = SubViewport.new(); viewport.size = Vector2i(1280,850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport); viewport.notify_mouse_entered()
	await _open(path)
	check(host.run != null and not host.run.mage_deck.is_empty() and host.run.phase == "hub", "fresh deck profile")
	if host.run == null: quit(1); return
	var original: Array = host.run.mage_deck.base_types.duplicate()
	await _press("deck_edit")
	await _press("deck_less_card_wet")
	await _press("deck_more_card_burning")
	check(host.deck_editing and host.deck_draft != original and host.run.mage_deck.base_types == original, "base edit remains draft")
	var deck_header := host.find_child("HubTitle",true,false) as Label
	check(deck_header != null and deck_header.text.contains("10/10"), "base count stays in fixed header")
	await _capture("deck-base-draft")
	await _press("deck_cancel")
	check(not host.deck_editing and host.run.mage_deck.base_types == original, "cancel keeps saved base")
	await _press("deck_edit")
	await _press("deck_less_card_wet")
	await _press("deck_more_card_burning")
	await _press("deck_save")
	check(not host.deck_editing and host.run.mage_deck.base_types.count("card.burning") == 1 and HeroHubStore.read_run(path).run.to_dict() == host.run.to_dict(), "save publishes exact base")
	await _press("start_expedition")
	check(host.run.expedition != null and host.run.expedition.is_deck(), "production expedition")
	if host.run.expedition == null: _finish(); return
	var node_id: int = host.run.expedition.available_nodes()[0]
	var map: ExpeditionMapView = null
	for candidate: Node in host.find_children("*", "", true, false):
		if candidate is ExpeditionMapView: map = candidate as ExpeditionMapView; break
	check(map != null, "map route visible")
	var before_checkpoint := host.run.to_dict()
	host.save_path = path + "/cannot-write"
	await _press("room_%d" % node_id)
	check(host._pending_save != null and host.run.to_dict() == before_checkpoint and host.battle_view == null, "failed checkpoint write blocks battle")
	var pending_checkpoint: Dictionary = host._pending_save.to_dict() if host._pending_save != null else {}
	host._expedition_action("choose",{"node":node_id})
	check(host._pending_save != null and host._pending_save.to_dict() == pending_checkpoint, "pending checkpoint blocks second choice")
	host.save_path = path
	await _press("retry_save")
	check(host.run.to_dict() == pending_checkpoint and HeroHubStore.read_run(path).run.to_dict() == pending_checkpoint, "retry publishes exact checkpoint")
	await process_frame; await process_frame
	check(host.battle_view != null and host.run.expedition.phase == "battle", "saved checkpoint opens battle")
	if host.battle_view == null: _finish(); return
	var demo := host.battle_view
	var session := host._battle_bundle.session as BattleCoreReactionsSession
	check(demo.size.x <= viewport.size.x and demo.size.y <= viewport.size.y and demo._instructions.get_global_rect().end.y <= float(viewport.size.y), "deck UI fits 1280x850")
	check(demo._mage_label.get_global_rect().end.x <= float(viewport.size.x) and demo._mage_label.text.contains("Мана") and demo._mage_label.text.contains("добор") and demo._mage_label.text.contains("сыграно") and demo._mage_label.text.contains("замена:"), "deck counters fit visible header")
	check(session.is_deploying() and session.state.deck.hand_ids.size() == 5 and not session.state.deck.mulligan_done, "setup five card hand")
	demo.end_turn()
	check(session.is_deploying() and session.mage_deployment_confirmed and not session.state.deck.mulligan_done, "deployment must precede mulligan")
	await _capture("deck-mulligan")
	await _click(demo._card_buttons[0].global_position + demo._card_buttons[0].size * 0.5)
	check(demo._mulligan_ids.size() == 1, "real card button chooses one copy")
	await _click(demo._card_confirm_button.global_position + demo._card_confirm_button.size * 0.5)
	check(session.state.deck.mulligan_done and not session.is_deploying() and session.state.deck.hand_ids.size() == 5, "confirm starts with five cards")
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size(); session.step_enemy()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN, "player card window")
	session.state.abilities.mana = 0
	demo._refresh()
	var costly_id: int = session.state.deck.hand_ids[0]
	check(not demo._card_buttons[0].disabled, "unaffordable card remains selectable for free replace")
	await _click(demo._card_buttons[0].global_position + demo._card_buttons[0].size * 0.5)
	check(demo._card_selected_id == costly_id, "selected expensive copy")
	await _click(demo._card_replace_button.global_position + demo._card_replace_button.size * 0.5)
	check(session.state.abilities.mana == 0 and not session.state.deck.hand_ids.has(costly_id) and session.state.deck.replaced_serial == session.state.abilities.serials[0], "replace spends no mana and changes hand")
	# Во время показа HUD обязан брать зону и ману из кадра, а не из финальной сессии.
	var frame := ActionPresentationState.capture(session.state)
	demo._render_presentation_hud(frame)
	check(demo._mage_label.text.contains("0/2") and demo._mage_label.text.contains("добор %d" % session.state.deck.draw_ids.size()) and demo._card_buttons[0].disabled, "frame HUD shows mana, zones, disabled hand")
	demo._refresh()
	session.state.abilities.mana = 2
	var unit_slot := -1
	for slot: int in session.state.deck.hand_ids.size():
		var card := session.state.deck.card(session.state.deck.hand_ids[slot])
		var definition := MageCardCatalog.get_card(card.type_id)
		if definition != null and definition.target_policy not in ["valid_cell", "corpse_cell"]: unit_slot = slot; break
	check(unit_slot >= 0, "unit target available after replace")
	if unit_slot >= 0:
		demo._refresh()
		await _click(demo._card_buttons[unit_slot].global_position + demo._card_buttons[unit_slot].size * 0.5)
		var actor := session.board.get_unit_by_id(session.living_ids(Faction.Type.PLAYER)[0])
		var origin: Vector2i = actor.cell
		var empty := Vector2i(-1,-1)
		for zoom: float in [1.0,0.75]:
			if zoom < 1.0:
				demo.board_view.zoom_camera(zoom,demo.board_view.size * 0.5)
				await process_frame
			var rect := demo.board_view.get_global_rect()
			for y: int in session.board.height:
				for x: int in session.board.width:
					var candidate := Vector2i(x,y)
					var point := demo.board_view.global_position + demo.board_view.cell_center(candidate)
					if session.board.is_terrain_walkable(candidate) and not session.board.is_occupied(candidate) and rect.grow(-12).has_point(point) and Rect2(Vector2.ZERO,Vector2(viewport.size)).has_point(point) and demo.board_view.cell_at(point - demo.board_view.global_position) == candidate:
						empty = candidate; break
				if empty.x >= 0: break
			if empty.x >= 0: break
		check(empty.x >= 0, "empty board target")
		if empty.x >= 0: await _click(demo.board_view.global_position + demo.board_view.cell_center(empty))
		check(demo._card_selected_id == 0 and actor.cell == origin and not demo.attack_mode, "rejected target returns movement without moving")
	await _click(demo._end_turn_button.global_position + demo._end_turn_button.size * 0.5)
	check(session.state.deck.hand_ids.size() == 6, "end turn draws visible sixth card")
	await _capture("deck-six-card-hand")
	var saved := host.run.to_dict()
	viewport.remove_child(host); host.queue_free(); await process_frame
	await _open(path)
	check(host.run != null and host.run.to_dict() == saved and host.battle_view != null, "checkpoint reload exact profile")
	if host.battle_view != null:
		var restored := host._battle_bundle.session as BattleCoreReactionsSession
		check(restored.is_deploying() and restored.state.deck.hand_ids.size() == 5 and not restored.state.deck.mulligan_done, "reload starts independent battle hand")
	await _rewards_camp_and_return(path)
	await _final_reward_variants(path)
	_finish()

func _open(path: String) -> void:
	host = (load("res://scenes/demo/hero_hub.tscn") as PackedScene).instantiate() as HeroHubScreen
	host.save_path = path; host.expedition_mode = true; host.mage_deck_mode = true
	viewport.add_child(host)
	await process_frame; await process_frame

func _outcome_for(profile: HeroHubState) -> Dictionary:
	var hp: Dictionary = {}; var gear: Dictionary = {}
	for id: int in profile.party: hp[id] = float((profile.heroes[id] as HeroProgression).max_hp())
	for item: Dictionary in profile.expedition.checkpoint.legacy_inputs.items: gear[item.id] = item.remaining
	return {"ruleset_id":ExpeditionRulesRegistry.DECK,"run_id":profile.run_serial,
		"node_id":profile.expedition.current_node().id,"serial":profile.expedition.battle_serial,
		"victory":true,"hp":hp,"gear":gear}

func _fixture_battle_outcome() -> void:
	check(host.run.expedition.phase == "battle", "fixture entered battle")
	if host.run.expedition.phase != "battle": return
	var result := ExpeditionTransitions.apply(host.run,"outcome",_outcome_for(host.run))
	check(result.is_ok(), "battle outcome fixture " + result.reason)
	if result.is_ok(): host._commit(result.profile)
	await process_frame; await process_frame

func _rewards_camp_and_return(path: String) -> void:
	await _fixture_battle_outcome()
	check(host.run.expedition.phase == "reward" and host.run.battle_report.open, "reward waits for decision")
	await _capture("deck-reward")
	var cards_before: int = host.run.expedition.cards.size()
	await _press("reward_0")
	check(host.run.expedition.cards.size() == cards_before + 1 and host.run.battle_report.reward_state == "chosen", "reward choice adds found copy")
	check(HeroHubStore.read_run(path).run.to_dict() == host.run.to_dict(), "chosen reward persisted")
	await _press("continue_battle_report")
	var rewards_seen: int = 1
	for unused: int in 20:
		if host.run.expedition == null or host.run.expedition.phase == "camp_departure": break
		match host.run.expedition.phase:
			"route": await _press("room_%d" % host.run.expedition.available_nodes()[0])
			"battle": await _fixture_battle_outcome()
			"reward":
				if rewards_seen == 1:
					await _press("reward_skip")
					check(host.run.battle_report.reward_state == "skipped", "second reward explicit skip")
				else: await _press("reward_skip")
				rewards_seen += 1
				await _press("continue_battle_report")
			"service": await _press("service_heal")
	check(rewards_seen >= 2 and host.run.expedition.phase == "camp_departure", "route reaches camp after choose and skip")
	if host.run.expedition.phase != "camp_departure": return
	await _capture("deck-camp")
	var found_id: int = 0
	for card: Dictionary in host.run.expedition.cards:
		if card.origin == "found": found_id = card.id; break
	check(found_id > 0 and host.run.expedition.active_ids.has(found_id), "found card active at camp")
	if found_id <= 0: return
	var active_before: Array = host.run.expedition.active_ids.duplicate()
	await _press("camp_deck_edit")
	await _press("camp_card_%d" % found_id)
	check(host.deck_editing and not host.deck_draft.has(found_id) and host.run.expedition.active_ids == active_before, "camp edit remains draft")
	await _press("camp_deck_cancel")
	check(not host.deck_editing and host.run.expedition.active_ids == active_before, "camp cancel keeps found active")
	await _press("camp_deck_edit")
	await _press("camp_card_%d" % found_id)
	await _press("camp_deck_save")
	check(not host.run.expedition.active_ids.has(found_id) and host.run.expedition.cards.any(func(card: Dictionary) -> bool: return card.id == found_id), "found copy saved as passive")
	check(HeroHubStore.read_run(path).run.to_dict() == host.run.to_dict(), "camp composition persisted")
	await _capture("deck-camp-passive")
	await _press("camp_leave")
	check(host.run.phase == "hub" and host.run.battle_report.open and host.run.battle_report.return_reason == "early", "early return opens report")
	check(host.run.battle_report.returned_cards.any(func(card: Dictionary) -> bool: return card.id == found_id and not card.was_active), "early report includes passive found copy")
	await _capture("deck-return-report")
	var report := host.run.to_dict()
	viewport.remove_child(host); host.queue_free(); await process_frame
	await _open(path)
	check(host.run != null and host.run.to_dict() == report and host.run.battle_report.open, "reload keeps open return report")
	await _press("continue_battle_report")
	check(not host.run.battle_report.open and HeroHubStore.read_run(path).run.to_dict() == host.run.to_dict(), "Continue closes report once")

func _final_pending_fixture(seed: int) -> HeroHubState:
	var profile := HeroHubState.create(seed)
	profile.enable_mage_deck()
	var start := ExpeditionTransitions.apply(profile,"start")
	if not start.is_ok(): return null
	profile = start.profile
	for unused: int in 40:
		if profile.expedition == null: return null
		if profile.expedition.phase == "reward" and profile.expedition.current_node().kind == "final": return profile
		var result: ExpeditionTransitionResult = null
		match profile.expedition.phase:
			"route": result = ExpeditionTransitions.apply(profile,"choose",{"node":profile.expedition.available_nodes()[0]})
			"battle": result = ExpeditionTransitions.apply(profile,"outcome",_outcome_for(profile))
			"reward":
				result = ExpeditionTransitions.apply(profile,"reward",{"index":0})
				if result.is_ok() and result.profile.battle_report.open: result.profile.dismiss_battle_report()
			"service": result = ExpeditionTransitions.apply(profile,"service",{"kind":"heal"})
			"camp_departure": result = ExpeditionTransitions.apply(profile,"continue")
			_: return null
		if result == null or not result.is_ok(): return null
		profile = result.profile
	return null

func _final_reward_variants(path: String) -> void:
	var pending := _final_pending_fixture(5410)
	check(pending != null and pending.expedition.current_node().kind == "final" and pending.battle_report.open, "final pending reward fixture")
	if pending == null: return
	for choice: int in [0,-1]:
		host._commit(HeroHubState.from_dict(pending.to_dict()))
		await process_frame; await process_frame
		check(host.run.expedition.phase == "reward", "final UI pending before decision")
		await _capture("deck-final-pending-%s" % ("choose" if choice == 0 else "skip"))
		await _press("reward_0" if choice == 0 else "reward_skip")
		check(host.run.phase == "hub" and host.run.battle_report.open and host.run.battle_report.return_reason == "completed", "final choice opens completed report")
		check(host.run.battle_report.reward_state == ("chosen" if choice == 0 else "skipped"), "final choice/skip recorded")
		check(HeroHubStore.read_run(path).run.to_dict() == host.run.to_dict(), "final decision persisted")
		await _capture("deck-final-report-%s" % ("choose" if choice == 0 else "skip"))
		await _press("continue_battle_report")

func _press(name: String) -> void:
	await process_frame; await process_frame
	var button := host.find_child(name, true, false) as Button
	check(button != null and not button.disabled, "button " + name)
	if button == null or button.disabled: return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame; await process_frame
	await _click(button.global_position + button.size * 0.5)

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position
	viewport.push_input(motion,true); await process_frame
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.global_position = position
	event.pressed = true; viewport.push_input(event,true); await process_frame
	event.pressed = false; viewport.push_input(event,true)
	await process_frame
	if host.battle_view != null: await preload("res://tests/fixtures/battle_execution_wait.gd").settle(self,host.battle_view)

func _capture(label: String) -> void:
	if captures.is_empty(): return
	var directory := captures if captures.is_absolute_path() else ProjectSettings.globalize_path("res://" + captures)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		check(false, "PNG directory " + label)
		return
	await process_frame; await process_frame
	var image := viewport.get_texture().get_image()
	check(image != null and image.save_png(directory.path_join(label + ".png")) == OK, "PNG " + label)

func _finish() -> void:
	if host != null: host.queue_free()
	viewport.queue_free()
	print("MAGE DECK UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
