extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL MAGE ARCHER SKINS: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for route: String in ["archer/ordinary", "archer/entangle", "mage/ordinary", "mage/burning", "mage/wet", "mage/freeze", "archer/lethal", "mage/lethal", "mage/burning_lethal"]:
		await _test_route(route)
	viewport.queue_free()
	await process_frame
	print("MAGE ARCHER SKINS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return {"state": capture.snapshot.to_dict(), "rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(), "admission": SummonAdmission.values(session.context)}

func _fixture(class_id: StringName) -> Dictionary:
	var profile := HeroHubState.create(91203, 4)
	profile.party.assign([4, 2, 5])
	if not profile.start_battle(): return {}
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty(): return {}
	var session := bundle.session as BattleCoreReactionsSession
	if not session.start_battle(): session.close(); return {}
	var steps := 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		session.step_enemy(); steps += 1
	if not session.can_player_act(): session.close(); return {}
	var actor := session.board.get_unit_by_id(int(bundle.hero_units[4 if class_id == &"mage" else 2]))
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[-1])
	# После хода ИИ соседняя клетка может быть занята: расставляем фикстуру через доску.
	for index: int in session.units.size():
		var unit: UnitState = session.units[index]
		var staging_cell := Vector2i(index, 7)
		session.board.set_terrain(staging_cell, TerrainType.Type.FLOOR)
		check(session.board.move_unit(unit, staging_cell), "fixture stages unit through BattleBoard")
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		if unit != actor: unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 0.0)
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(4, 3)]:
		session.board.set_terrain(cell, TerrainType.Type.FLOOR)
		session.board.set_height_steps(cell, 0)
	check(session.board.move_unit(actor, Vector2i(3, 3)) and session.board.move_unit(target, Vector2i(4, 3)),
		"fixture positions actor and target through BattleBoard")
	actor.try_refill_turn_resources()
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 500.0)
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1000.0)
	target.vitals.set_hp(500.0)
	target.vitals.set_balance(0.0)
	target.armor.natural.physical = 0
	target.armor.natural.fire = 0
	target.guard_stance = false
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	check(session.select_unit(actor.id), "factory actor selected with genuine class loadout")
	var board := BattleDemoBoard.new()
	board.unit_visual_scene = UNIT_SCENE
	board.size = viewport.size
	board.session = session
	viewport.add_child(board)
	board.refresh()
	return {"session": session, "actor": actor, "target": target, "board": board}

func _test_route(route: String) -> void:
	var parts := route.split("/")
	var class_id := StringName(parts[0])
	var fixture := _fixture(class_id)
	check(not fixture.is_empty(), route + " starts factory fixture")
	if fixture.is_empty(): return
	var session: BattleCoreReactionsSession = fixture.session
	var actor: UnitState = fixture.actor
	var target: UnitState = fixture.target
	var board: BattleDemoBoard = fixture.board
	var visual := board._presentation_visual(actor.id) as BattleCharacterSkinVisual
	check(visual != null and visual.skin_definition != null and visual.skin_definition.id == (&"star_hood" if class_id == &"mage" else &"silver_ranger"), route + " uses selected default skin")
	if visual == null or visual.skin_definition == null:
		board.free(); session.close(); return
	var command: Command
	var lethal := parts[1] in ["lethal", "burning_lethal"]
	if lethal:
		target.vitals.set_hp(1.0)
		session.unit_visual_classes[target.id] = &""
		board.refresh()
	var attack := parts[1] in ["ordinary", "entangle", "lethal"]
	if attack:
		var attack_id: StringName = &"entangling_strike" if parts[1] == "entangle" else session.actor_loadouts[actor.id].attack_id
		command = AttackCommand.new(actor.id, target.id, actor.cell, target.cell, attack_id, session.context.get_revision())
	else:
		command = ElementalCastCommand.new(actor.id, target.id, &"burning" if parts[1] == "burning_lethal" else StringName(parts[1]), session.context.get_revision())
	var before := ActionPresentationState.capture(session.state)
	var original := _snapshot(session)
	var ids := UnitId.get_counter()
	var preview := ForecastSimulation.run(session.context, session._queue, command)
	check(_snapshot(session) == original and UnitId.get_counter() == ids, route + " preview preserves source and IDs")
	session._queue.capture_presentation = true
	var receipt := session._queue.submit(command, session.context)
	check(receipt.status == ActionReceipt.APPLIED and receipt.status == preview.status
		and receipt.get_events() == preview.events and receipt.get_steps() == preview.steps, route + " real events/steps match preview")
	check(_snapshot(session) == {"state": preview.snapshot_after, "rng": preview.rng_after,
		"counters": preview.counters_after, "admission": preview.admission_after}, route + " full preview/live parity")
	var frames := receipt.get_presentation_frames()
	var after := ActionPresentationState.capture(session.state)
	var committed := _snapshot(session)
	if lethal: check(not target.is_alive(), route + " genuine lethal receipt kills generic target")
	if frames.is_empty():
		check(false, route + " has presentation frames")
		board.free(); session.close(); return
	board.execution_pending = true
	board.session = null # Проигрывание обязано обойтись отделёнными значениями.
	if not attack:
		var frame: Dictionary = frames[0]
		check(not board._matching_skin_cast(frame.events, frame.step).is_empty(), route + " matched applied cast")
		for key: String in ["status", "command_seq", "kind"]:
			var bad: Dictionary = frame.step.duplicate(true)
			bad[key] = {"status": &"SKIPPED", "command_seq": int(frame.step.command_seq) + 1, "kind": &"mage_cast"}[key]
			check(board._matching_skin_cast(frame.events, bad).is_empty(), route + " rejects mismatched " + key)
	for mode: String in ["complete", "skip", "cancel", "speed3"]:
		var player := BattlePresentationPlayer.new()
		viewport.add_child(player)
		player.set_speed(3.0 if mode == "speed3" else 1.0)
		player.play(board, before, frames, after)
		if player._tween != null: player._tween.pause()
		check(board._defender_buff_visual == visual and visual._skin_buff_elapsed == 0.0, route + " selected ability starts: " + mode)
		if player._tween != null: player._tween.custom_step(0.60 / player.speed)
		var phase := visual._skin_buff_elapsed
		var texture := visual.class_still_sprite().texture
		check(phase > 0.0 and texture is AtlasTexture and (texture as AtlasTexture).atlas.resource_path.ends_with("/buff.png"), route + " samples chosen ability atlas: " + mode)
		board.size += Vector2(7, 3)
		board._rescale_layout()
		check(board._presentation_visual(actor.id) == visual and visual.class_still_sprite().texture == texture
			and is_equal_approx(visual._skin_buff_elapsed, phase) and visual.get_authored_facing_x() == 1,
			route + " resize preserves clip/owner/target facing: " + mode)
		check(visual.action_offset == Vector2.ZERO, route + " ability feet remain planted: " + mode)
		if attack:
			check(board._ghosts.get_child_count() == 1 and not (board._ghosts.get_child(0) as CanvasItem).visible,
				route + " projectile waits for the release pose: " + mode)
		if mode == "skip": player.skip()
		elif mode == "cancel": player.cancel()
		else:
			var saw_flight := false
			var saw_tail := false
			var saw_last := false
			var checked_contact := false
			var checked_short_death := false
			for tick: int in 170:
				if not player.active: break
				if player._tween != null and player._tween.is_valid():
					player._tween.pause()
					player._tween.custom_step(0.035 / player.speed)
				if board._defender_buff_visual == visual:
					saw_tail = saw_tail or visual._skin_buff_elapsed > 1.9
					saw_last = saw_last or visual.class_still_sprite().texture == visual.skin_definition.animations.get_frame_texture(&"buff", 32)
				for node: Node in board._ghosts.get_children():
					if node is BattlePresentationProjectile and (node as CanvasItem).visible: saw_flight = true
				if attack and visual._skin_buff_elapsed > 1.9 and not checked_contact:
					checked_contact = true
					check(board._numbers.get_child_count() > 0 and player._published != after,
						route + " contact feedback precedes after while recovery clip continues")
				if lethal and attack and visual._skin_buff_elapsed > 2.1 and not checked_short_death:
					checked_short_death = true
					var victim := board._presentation_visual(target.id)
					check(victim != null and is_equal_approx(victim.death_progress, 1.0) and victim.unit.alive
						and not board._view_corpses.any(func(row: Dictionary) -> bool: return int(row.get("source_unit_id", 0)) == target.id),
						route + " short death completes on time while corpse waits for shooter recovery")
				await process_frame
			check(not player.active and saw_tail and saw_last, route + " complete clip reaches held frame32: " + mode)
			if attack: check(saw_flight and checked_contact, route + " release/flight/contact route exercised: " + mode)
			if lethal and attack: check(checked_short_death, route + " short-death timing exercised: " + mode)
			if lethal:
				check(board._view_corpses.any(func(row: Dictionary) -> bool: return int(row.get("source_unit_id", 0)) == target.id),
					route + " confirmed corpse is published after the ability and death")
		check(board._defender_buff_visual == null and visual._skin_buff_elapsed < 0.0 and visual.presentation_facing_x == 0
			and visual.class_still_sprite().visible, route + " cleanup restores team pose: " + mode)
		check(_snapshot(session) == committed, route + " playback leaves state/RNG/counters untouched: " + mode)
		player.free()
	board.free()
	session.close()
	await process_frame
