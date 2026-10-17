extends SceneTree

const BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")

var output: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_capture")


func _capture() -> void:
	if output.is_empty():
		quit(1)
		return
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var session := HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	var view := SubViewport.new()
	view.size = Vector2i(1600, 1200)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var demo := BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	view.add_child(demo)
	# Неподвижный технический снимок настоящего поля, без исполнения хода ИИ.
	demo.set_process(false)
	await process_frame
	await process_frame
	var before := _snapshot(session)
	demo.board_view.zoom_camera(0.9, demo.board_view.size * 0.5)
	demo.board_view.pan_camera(Vector2(0, -50))
	demo._cloth_palette.select(2)
	demo._cloth_palette.item_selected.emit(2)
	await process_frame
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image().save_png(output)
	var unchanged := before == _snapshot(session)
	demo.queue_free()
	await process_frame
	view.queue_free()
	await process_frame
	print("BATTLEFIELD CAPTURE: saved=%s state_unchanged=%s" % [result == OK, unchanged])
	quit(0 if result == OK and unchanged else 1)


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}
