extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const DEATH_FRAMES: SpriteFrames = preload("res://assets/art_presets/trials/defender_death_v1/death_frames.tres")
const PlayerTurnFixture = preload("res://tests/fixtures/player_turn_fixture.gd")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport
var captures: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL DEFENDER DEATH: " + label)


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision()}


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_test_resource()
	await _test_real_receipt_clip()
	viewport.queue_free()
	await process_frame
	print("DEFENDER DEATH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_resource() -> void:
	check(DEATH_FRAMES.has_animation(&"death") and not DEATH_FRAMES.get_animation_loop(&"death"),
		"resource is a finite death animation")
	check(DEATH_FRAMES.get_animation_speed(&"death") == 50.0 and DEATH_FRAMES.get_frame_count(&"death") == 33,
		"death contains 33 ordered frames at 50 fps")
	for index: int in 33:
		check(DEATH_FRAMES.get_frame_duration(&"death", index) == 3.0,
			"frame %02d has exact 60ms duration" % (index + 1))
	check(is_equal_approx(33.0 * 3.0 / 50.0, 1.98), "gameplay death clip totals 1.98 seconds")


func _test_real_receipt_clip() -> void:
	var session := PlayerTurnFixture.create()
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in 6:
		var unit: UnitState = session.units[index]
		session.board.move_unit(unit, Vector2i(index, 0))
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 256.0)
		unit.vitals.set_hp(256.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 10.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 8.0)
		unit.armor.natural["physical"] = 0
	var actor: UnitState = session.units[0]
	var target: UnitState = session.units[1]
	session.board.move_unit(actor, Vector2i(2, 3))
	session.board.move_unit(target, Vector2i(3, 3))
	target.vitals.set_hp(1.0)
	for item: ItemInstance in session.state.get_owner(target.id)._items.values():
		item.armor_remaining = 0
	session.unit_visual_classes[target.id] = &"warrior"
	var before := ActionPresentationState.capture(session.state)
	session._queue.capture_presentation = true
	var command := AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"demo_strike", session.context.get_revision())
	var receipt := session._queue.submit(command, session.context)
	session._queue.capture_presentation = false
	var after := ActionPresentationState.capture(session.state)
	var committed := _snapshot(session)
	var frames := receipt.get_presentation_frames()
	var death_frame_index: int = -1
	for frame_index: int in frames.size():
		var frame: Dictionary = frames[frame_index]
		if frame.events.any(func(event: Dictionary) -> bool:
			return event.get("kind") == &"died" and int(event.get("target_unit_id", -1)) == target.id):
			death_frame_index = frame_index
	check(receipt.status == ActionReceipt.APPLIED and death_frame_index >= 0,
		"applied production receipt contains a separate lethal result frame")
	if receipt.status != ActionReceipt.APPLIED or frames.is_empty():
		session.close()
		return
	check(death_frame_index >= 0, "receipt contains the target death event")
	var board := BattleDemoBoard.new()
	board.size = viewport.size
	board.session = session
	board.unit_visual_scene = UNIT_SCENE
	viewport.add_child(board)
	board.refresh()
	board.show_presentation_state(before)
	var visual := board._presentation_visual(target.id) as BattleDefenderIdleVisual
	# Этот fixture явно оставляет старый Defender клип для отдельного legacy покрытия.
	if visual != null and target.faction == Faction.Type.ENEMY:
		visual.enemy_warrior_art_enabled = false
		var legacy_still := visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var ally_still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
		legacy_still.texture = ally_still.texture
		visual.sync_scene_art()
	check(visual != null and visual.death_frames == DEATH_FRAMES and visual.can_play_death(),
		"legacy fixture explicitly retains the packaged Defender death clip")
	if visual != null:
		var sprite := visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D
		var still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
		var art := visual.get_node("ArtRoot") as Node2D
		var player := BattlePresentationPlayer.new()
		viewport.add_child(player)
		player.play(board, before, frames, after)
		player._tween.pause()
		check(player.active, "real receipt starts the shared Tween playback")
		var frame_guard: int = 0
		while player.active and player._index < death_frame_index and frame_guard < 8:
			player._tween.custom_step(0.5)
			if player.active:
				player._tween.pause()
			frame_guard += 1
		check(player.active and player._index == death_frame_index,
			"Tween advances through preceding receipt frames to the lethal result")
		if player.active and player._index == death_frame_index:
			player._tween.custom_step(0.18)
			if player.active:
				player._tween.pause()
		var tween_death_pose: Dictionary = board._field_presentation.poses.get(target.id, {})
		check(tween_death_pose.get("kind") == &"death"
			and float(tween_death_pose.get("progress", -1.0)) >= 0.0,
			"lethal result frame samples death through its shared Tween")
		# Независимо от числа receipt-кадров проверяем каждый source-кадр на его
		# игровой временной середине; полное Tween completion проверяется ниже.
		var elapsed: float = 0.0
		for index: int in 33:
			var duration := DEATH_FRAMES.get_frame_duration(&"death", index) / DEATH_FRAMES.get_animation_speed(&"death")
			board._field_presentation.sample_death((elapsed + duration * 0.5) / 1.98, board, target.id)
			check(sprite.texture == DEATH_FRAMES.get_frame_texture(&"death", index),
				"sample selects authored death frame %02d" % (index + 1))
			check(sprite.visible and not still.visible and art.scale.y == art.scale.x,
				"death keeps the art upright and replaces the still")
			if index == 8 and not captures.is_empty():
				DirAccess.make_dir_recursive_absolute(captures)
				await process_frame
				await RenderingServer.frame_post_draw
				check(viewport.get_texture().get_image().save_png(captures.path_join("defender-death-mid.png")) == OK,
					"captures death pose on shared progress")
			elapsed += duration
		check(is_equal_approx(elapsed, 1.98) and sprite.texture == DEATH_FRAMES.get_frame_texture(&"death", 32),
			"direct field sampling reaches final authored frame at 1.98 seconds")
		board.size += Vector2(19, 11)
		board._rescale_layout()
		board._field_presentation.restore(board)
		check(sprite.texture == DEATH_FRAMES.get_frame_texture(&"death", 32),
			"resize restores the sampled final death phase")
		check(_snapshot(session) == committed, "death playback leaves committed state, RNG, counters and revision unchanged")
		for index: int in 8:
			if player.active:
				player._tween.custom_step(0.5)
				if player.active:
					player._tween.pause()
		check(not player.active, "real receipt Tween completes and publishes the after state")
		player._tween.custom_step(1.0)
		check(not visual._death_active, "completed Tween cannot revive death")
		board.show_presentation_state(after)
		check(not visual.unit.alive and not visual._death_active and not sprite.visible,
			"committed corpse replaces the transient clip after publication")
		player.queue_free()
	board.queue_free()
	session.close()
	await process_frame
