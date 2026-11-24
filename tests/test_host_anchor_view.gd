extends "res://tests/test_mage_deck_battle.gd"

var viewport: SubViewport
var view: BattleDemoBoard

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	view = BattleDemoBoard.new()
	view.size = Vector2(960, 700)
	viewport.add_child(view)
	await process_frame
	var session := fixture()
	var host_id := session.living_ids(Faction.Type.PLAYER)[0]
	var host := session.board.get_unit_by_id(host_id)
	session.state.card_effects.host_unit_id = host_id
	var living := ActionPresentationState.capture(session.state)
	check(living.host_anchor.kind == "living" and living.host_anchor.unit_id == host_id, "live capture publishes host anchor values")
	living.host_anchor.cell = Vector2i(7, 7)
	check(ActionPresentationState.capture(session.state).host_anchor.cell == host.cell, "anchor frame does not alias live position")
	var live_frame := ActionPresentationState.capture(session.state)
	view.show_presentation_state(live_frame)
	var units_before := view._view_units.size()
	var occupant_before := session.board.occupant_at(host.cell)
	view.host_glow = {"color":"blue", "form":"flame", "flicker":"still"}
	var dead := session._queue.submit(DeathCommand.new(host_id, DamageSource.new(&"test", 0, host.cell)), session.context)
	check(dead.status == ActionReceipt.APPLIED, "host death uses ordinary command path")
	var corpse_frame := ActionPresentationState.capture(session.state)
	check(corpse_frame.host_anchor.kind in ["fresh", "bones"] and corpse_frame.host_anchor.cell == host.cell, "death frame anchors to host remains")
	view.show_presentation_state(corpse_frame)
	check(view._host_anchor_visual.visible and view._host_anchor_visual._kind in ["fresh", "bones"], "remains display a small separate flame marker")
	check(view._view_units.size() == units_before and session.board.occupant_at(host.cell) == null and occupant_before == host, "marker adds no unit or occupancy")
	var corpse_area_count: int = corpse_frame.action_areas.size()
	view.show_presentation_state(corpse_frame)
	check(view.action_areas.size() == corpse_area_count, "anchor contributes no action areas")
	# После расходования останков сохраняется авторитетная позиция смерти над void-клеткой без пола.
	session.state.environment.corpses.clear()
	session.board.set_terrain(host.cell, TerrainType.Type.VOID)
	session.state.card_effects.host_death_cell = host.cell
	session.state.card_effects.host_death_height = 4
	var spirit_frame := ActionPresentationState.capture(session.state)
	check(spirit_frame.host_anchor.kind == "spirit" and spirit_frame.host_anchor.height == 4, "consumed remains leave stored floating spirit anchor")
	view.show_presentation_state(spirit_frame)
	var expected := IsoGridUtils.grid_to_screen(host.cell, view.grid_config, 0) - Vector2(0, 2.0 * view.grid_config.height_step)
	check(view._host_anchor_visual.visible and view._host_anchor_visual.position.is_equal_approx(expected), "spirit uses detached stored half-step height over void pit")
	check(view._view_units.size() == units_before and session.board.occupant_at(host.cell) == null, "spirit remains nonoccupying")
	var raised_id := session.living_ids(Faction.Type.PLAYER)[1]
	session.state.card_effects.host_unit_id = raised_id
	var raised_frame := ActionPresentationState.capture(session.state)
	check(raised_frame.host_anchor.unit_id == raised_id and raised_frame.host_anchor.kind == "living", "capture follows host id after raise transfer")
	view.show_presentation_state(raised_frame)
	check(not view._host_anchor_visual.visible and view.host_unit_id == raised_id, "living carrier returns glow to its body and follows new ID")
	check(ActionPresentationState.capture_host_anchor(session.state).unit_id == raised_id, "live refresh tracks the current binding")
	var party := session.living_ids(Faction.Type.PLAYER)
	for id: int in party:
		if id != raised_id:
			session._queue.submit(DeathCommand.new(id, DamageSource.new(&"test", 0, session.board.get_unit_by_id(id).cell)), session.context)
	session._queue.submit(DeathCommand.new(raised_id, DamageSource.new(&"test", 0, session.board.get_unit_by_id(raised_id).cell)), session.context)
	var wiped := ActionPresentationState.capture_host_anchor(session.state)
	check(HostBinding.party_dead(session.state) and wiped.is_empty(), "permanent party wipe suppresses anchor")
	view.show_presentation_state({"width":0,"height":0,"host_anchor":{}})
	check(not view._host_anchor_visual.visible, "empty presentation hides anchor")
	session.close()
	view.queue_free()
	viewport.queue_free()
	await process_frame
	print("HOST ANCHOR VIEW RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
