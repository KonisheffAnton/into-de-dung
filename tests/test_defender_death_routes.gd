extends "res://tests/test_presentation_environment.gd"

const DEFENDER_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const ENEMY_WARRIOR_DEATH: SpriteFrames = preload("res://assets/art_presets/trials/enemy_warrior_death_v1/death_frames.tres")

var visual_class: StringName = &"warrior"
var death_seconds: float = 1.98
var clip_property: StringName = &"death_frames"
var sprite_path: String = "ArtRoot/DefenderIdleSprite"
var sprite_scale: float = 1.0
var suite: String = "DEFENDER DEATH ROUTES"
var production_enemy_art_for_packet: bool = false


func _initialize() -> void:
	if "--rogue" in OS.get_cmdline_user_args():
		visual_class = &"rogue"
		death_seconds = 3.60
		clip_property = &"rogue_death_frames"
		sprite_path = "ArtRoot/RogueIdleSprite"
		sprite_scale = 1.0
		suite = "ROGUE DEATH ROUTES"
	super._initialize()


func start_packet(data: Dictionary, s: BattleCoreReactionsSession, label: String) -> Dictionary:
	for unit: UnitState in s.units: s.unit_visual_classes[unit.id] = visual_class
	board.session = s
	board.refresh()
	for unit: UnitState in s.units:
		if unit.faction != Faction.Type.ENEMY or visual_class != &"warrior": continue
		var visual := board._presentation_visual(unit.id) as BattleDefenderIdleVisual
		if visual == null: continue
		visual.enemy_warrior_art_enabled = production_enemy_art_for_packet
		var enemy_still := visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		if production_enemy_art_for_packet:
			enemy_still.texture = visual.enemy_warrior_idle_frames.get_frame_texture(&"idle", 0)
		else:
			var player_still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
			enemy_still.texture = player_still.texture
		visual.sync_scene_art()
	return super.start_packet(data, s, label)


func seek_pose(id: int, kinds: Array[StringName]) -> Dictionary:
	var pose := super.seek_pose(id, kinds)
	var visual := board._presentation_visual(id) as BattleDefenderIdleVisual
	if pose.get("kind") == &"fall" and visual != null:
		check(not visual._death_active, "fall never starts the ground death clip")
		if visual._uses_enemy_warrior_art():
			check(visual._active_death_frames() == ENEMY_WARRIOR_DEATH,
				"enemy fall retains selected death resource without playing it")
	return pose


func _check_enemy_generic_death_fallback(visual: BattleDefenderIdleVisual, id: int, label: String) -> void:
	check(visual._active_death_frames() == null and not visual.can_play_death()
		and is_equal_approx(board._death_seconds(id), 0.20),
		label + " selects generic death duration")
	board._field_presentation.sample_death(0.5, board, id)
	check(not visual._death_active and visual.get_node("ArtRoot").rotation > 0.0
		and visual.modulate.a < 1.0,
		label + " samples generic death pose")
	visual.reset_view_pose()


func route(kind: String) -> void:
	var s := BattleCoreReactionsSession.new() if kind == "mage" else field_fixture()
	if kind == "mage":
		s._enemy_index = s._enemy_ids.size()
		s.step_enemy()
		for unit: UnitState in s.units:
			for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	var victim := s.units[5] if kind == "collision_enemy" else (s.units[2] if kind.begins_with("collision") else s.units[1])
	victim.vitals.set_hp(1.0)
	if kind == "collision_single": victim.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
	if not kind.begins_with("collision"):
		s.units[0].stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	if kind == "ranged":
		check(s.board.move_unit(s.units[5], Vector2i(5, 1)), "ranged fixture clears destination")
		check(s.board.move_unit(victim, Vector2i(4, 3)), "ranged target three cells away")
		s.units[0].stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 4.0)
	var data: Dictionary
	if kind == "mage":
		victim.armor.natural["fire"] = 0
		var before := ActionPresentationState.capture(s.state)
		s._queue.capture_presentation = true
		var receipt := s.cast_mage_spell(&"mage.fire", victim.id)
		check(receipt.status == ActionReceipt.APPLIED, "real lethal mage receipt: " + String(receipt.reason))
		data = {"before": before, "frames": receipt.get_presentation_frames(), "events": receipt.get_events(), "after": ActionPresentationState.capture(s.state)}
	else:
		data = packet_attack(s, "Defender " + kind)
	check(data.events.any(func(e: Dictionary) -> bool: return e.kind == &"died" and int(e.target_unit_id) == victim.id), kind + " has confirmed death")
	if kind == "collision_enemy":
		check(data.events.any(func(event: Dictionary) -> bool:
			return event.kind == &"died" and int(event.target_unit_id) == victim.id \
				and event.get("source", {}).get("kind") == &"collision"),
			"enemy collision death is carried by the collision receipt")
	var saved := start_packet(data, s, kind)
	var pose := seek_pose(victim.id, [&"death"])
	if kind == "collision_single":
		var frame_events: Array = player._frames[player._index].events
		check(frame_events.any(func(e: Dictionary) -> bool: return e.kind == &"collision")
			and frame_events.any(func(e: Dictionary) -> bool: return e.kind == &"died" and int(e.target_unit_id) == victim.id and e.get("source", {}).get("kind") == &"collision"), "single pair owns collision and death in same receipt frame")
		check(player._chain == null, "single lethal collision takes ordinary frame path")
		check(player._tween.get_total_elapsed_time() < BattleDemoBoard.OBSTACLE_APPROACH_SECONDS + 0.06, "single collision death begins at contact")
		check(float(pose.progress) < 0.03, "single collision samples opening death pose at contact")
	check(not pose.is_empty(), kind + " reaches death through actual player Tween")
	var visual := board._presentation_visual(victim.id) as BattleDefenderIdleVisual
	check(visual != null and visual._death_active, kind + " selects authored death")
	if visual != null and visual._death_active:
		advance(0.5)
		check(player.active and visual.unit.alive and visual.death_progress > 0.48 / death_seconds and visual.death_progress < 0.7 / death_seconds,
			kind + " holds before and follows the selected death clock")
		check(not board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id), kind + " corpse waits for clip")
		var sprite := visual.get_node(sprite_path) as Sprite2D
		var art := visual.get_node("ArtRoot") as Node2D
		check(is_zero_approx(art.rotation) and is_equal_approx(art.scale.x, art.scale.y) and visual.modulate.a == 1.0, kind + " no synthetic rotation squash fade")
		if visual_class == &"rogue":
			var actual_progress := visual.death_progress
			check(is_equal_approx(board._death_seconds(victim.id), 3.60), kind + " selected death duration")
			for frame_index: int in 17:
				board._field_presentation.sample_death((float(frame_index) * 0.15 + 0.075) / 3.60, board, victim.id)
				check(sprite.texture == visual.rogue_death_frames.get_frame_texture(&"death", frame_index)
					and sprite.visible and not visual.class_still_sprite().visible,
					kind + " new rogue death ordered frame " + str(frame_index))
				check(sprite.position == Vector2(64 if victim.faction == Faction.Type.ENEMY else -64, -83)
					and is_equal_approx(sprite.self_modulate.a, 1.0) and visual.unit.alive
					and not board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id),
					kind + " fixed anchor, opaque clip and delayed corpse " + str(frame_index))
			board._field_presentation.sample_death(actual_progress, board, victim.id)
			check(is_equal_approx(sprite.self_modulate.a, 1.0), kind + " keeps rogue opaque during fall and hold")
			var elapsed := visual.death_progress * death_seconds
			var midpoint_target: float = 2.55 + 0.25 + 0.40
			if elapsed < midpoint_target: advance(midpoint_target - elapsed)
			elapsed = visual.death_progress * death_seconds
			var expected_alpha := 1.0 - clampf((elapsed - 2.55 - 0.25) / 0.80, 0.0, 1.0)
			check(player.active and visual._death_active and is_equal_approx(sprite.self_modulate.a, expected_alpha)
				and sprite.self_modulate.a > 0.35 and sprite.self_modulate.a < 0.65,
				kind + " follows the expected rogue fade alpha through the real Tween near midpoint")
		check(sprite.scale.x == (-sprite_scale if victim.faction == Faction.Type.ENEMY else sprite_scale), kind + " faction mirror")
		var texture := sprite.texture
		var fade_alpha := sprite.self_modulate.a
		board.size += Vector2(17, 11)
		board.zoom_camera(0.95, board.size * 0.5)
		check(sprite.texture == texture and visual._death_active
			and (visual_class != &"rogue" or is_equal_approx(sprite.self_modulate.a, fade_alpha)), kind + " resize preserves frame and fade")
		await capture(("rogue-" if visual_class == &"rogue" else "defender-") + kind)
		if visual_class == &"rogue":
			var elapsed := visual.death_progress * death_seconds
			var end_target: float = death_seconds - 0.01
			if elapsed < end_target: advance(end_target - elapsed)
			elapsed = visual.death_progress * death_seconds
			var expected_alpha := 1.0 - clampf((elapsed - 2.55 - 0.25) / 0.80, 0.0, 1.0)
			check(player.active and sprite.self_modulate.a < 0.02 and is_equal_approx(sprite.self_modulate.a, expected_alpha),
				kind + " reaches near-transparent at the end of rogue fade")
	finish()
	assert_playback_unchanged(s, saved, data, kind)
	check(board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id), kind + " publishes real corpse")
	# Повторный показ готового пакета проверяет управление часами без нового исполнения.
	start_packet(data, s, kind + " cancel")
	seek_pose(victim.id, [&"death"])
	player.cancel()
	check(board._field_presentation.poses.is_empty(), kind + " cancel clears poses")
	if visual_class == &"rogue":
		check(is_equal_approx(((board._presentation_visual(victim.id) as BattleDefenderIdleVisual).get_node(sprite_path) as Sprite2D).self_modulate.a, 1.0),
			kind + " cancel restores authored rogue sprite alpha")
	for node: Node in board._entities.get_children():
		if node is BattleDefenderIdleVisual: check(not node._death_active, kind + " cancel clears clip")
	start_packet(data, s, kind + " speed")
	seek_pose(victim.id, [&"death"])
	player.set_speed(3.0)
	advance(death_seconds / 3.0 + 0.04)
	check(not (board._presentation_visual(victim.id) as BattleDefenderIdleVisual)._death_active, kind + " x3 finishes victim at the selected duration")
	finish()
	player.cancel()
	start_packet(data, s, kind + " skip")
	seek_pose(victim.id, [&"death"])
	var stale := player._tween
	player.skip()
	stale.custom_step(2.0)
	check(not player.active and board._field_presentation.poses.is_empty()
		and not (board._presentation_visual(victim.id) as BattleDefenderIdleVisual)._death_active, kind + " skip clears clip and stale Tween")
	if visual_class == &"rogue":
		check(is_equal_approx(((board._presentation_visual(victim.id) as BattleDefenderIdleVisual).get_node(sprite_path) as Sprite2D).self_modulate.a, 1.0),
			kind + " skip restores authored rogue sprite alpha")
	if visual_class == &"warrior" and victim.faction == Faction.Type.ENEMY and kind in ["melee", "ranged", "mage", "collision", "collision_single", "collision_enemy"]:
		production_enemy_art_for_packet = true
		var enemy_saved := start_packet(data, s, kind + " enemy death2")
		var enemy_pose := seek_pose(victim.id, [&"death"])
		var enemy_visual := board._presentation_visual(victim.id) as BattleDefenderIdleVisual
		if enemy_visual != null:
			var enemy_still := enemy_visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
			var death_sprite := enemy_visual.get_node("ArtRoot/EnemyWarriorIdleSprite") as Sprite2D
			var art_root := enemy_visual.get_node("ArtRoot") as Node2D
			var unit_root_position := enemy_visual.position
			var art_root_transform := art_root.transform
			var label_anchor := (enemy_visual.get_node("ArtRoot/LabelAnchor") as Node2D).transform
			var effect_anchor := (enemy_visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform
			var pick_rect := enemy_visual.get_unit_pick_rect()
			var bars_offset := enemy_visual.get_unit_bars_offset()
			check(not enemy_pose.is_empty() and enemy_visual._uses_enemy_warrior_art()
				and enemy_visual._active_death_frames() == ENEMY_WARRIOR_DEATH and enemy_visual.can_play_death()
				and is_equal_approx(board._death_seconds(victim.id), 2.55)
				and death_sprite.scale == Vector2(-1, 1)
				and death_sprite.position.is_equal_approx(Vector2(71, -83)),
				kind + " enemy selects dedicated death at mirrored anchor for 2.55 seconds")
			advance(0.10)
			check(enemy_visual._death_active and enemy_visual.death_progress > 0.0
				and death_sprite.texture == ENEMY_WARRIOR_DEATH.get_frame_texture(&"death", 0)
				and death_sprite.visible and not enemy_still.visible
				and is_zero_approx(art_root.rotation) and is_equal_approx(art_root.scale.x, art_root.scale.y)
				and enemy_visual.modulate.a == 1.0 and enemy_visual.unit.alive
				and not board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id),
				kind + " enemy death samples the first selected frame without synthetic pose")
			var tween_progress := enemy_visual.death_progress
			var elapsed := 0.0
			check(not ENEMY_WARRIOR_DEATH.get_animation_loop(&"death")
				and ENEMY_WARRIOR_DEATH.get_animation_speed(&"death") == 60.0,
				kind + " enemy death is non-looping at 60 fps")
			for frame_index: int in 17:
				check(ENEMY_WARRIOR_DEATH.get_frame_duration(&"death", frame_index) == 9.0,
					kind + " enemy death frame %02d has authored 150 ms duration" % (frame_index + 1))
				var frame_duration := ENEMY_WARRIOR_DEATH.get_frame_duration(&"death", frame_index) / ENEMY_WARRIOR_DEATH.get_animation_speed(&"death")
				board._field_presentation.sample_death((elapsed + frame_duration * 0.5) / 2.55, board, victim.id)
				check(death_sprite.texture == ENEMY_WARRIOR_DEATH.get_frame_texture(&"death", frame_index),
					kind + " enemy selects ordered death frame %02d" % (frame_index + 1))
				elapsed += frame_duration
			check(is_equal_approx(elapsed, 2.55), kind + " enemy selected death totals 2.55 seconds")
			board._field_presentation.sample_death(tween_progress, board, victim.id)
			# Отдача удара меняет action_offset независимо от кадров смерти; её движение не запрещаем.
			check(enemy_visual.position.is_equal_approx(unit_root_position)
				and art_root.transform.x.is_equal_approx(art_root_transform.x)
				and art_root.transform.y.is_equal_approx(art_root_transform.y)
				and art_root.position.is_equal_approx(enemy_visual.get_visual_offset() + enemy_visual.action_offset),
				kind + " death keeps root and scale while preserving the existing recoil offset")
			var resize_progress := enemy_visual.death_progress
			var resize_texture := death_sprite.texture
			var resize_transform := art_root.transform
			var resize_tile_width := board.grid_config.tile_size.x
			board.size += Vector2(17, 11)
			board.zoom_camera(0.95, board.size * 0.5)
			var resize_ratio := board.grid_config.tile_size.x / resize_tile_width
			check(enemy_visual._death_active and is_equal_approx(enemy_visual.death_progress, resize_progress)
				and death_sprite.texture == resize_texture
				and art_root.transform.x.is_equal_approx(resize_transform.x * resize_ratio)
				and art_root.transform.y.is_equal_approx(resize_transform.y * resize_ratio)
				and art_root.position.is_equal_approx(enemy_visual.get_visual_offset() + enemy_visual.action_offset)
				and death_sprite.position.is_equal_approx(Vector2(71, -83))
				and death_sprite.scale == Vector2(-1, 1)
				and (enemy_visual.get_node("ArtRoot/LabelAnchor") as Node2D).transform.is_equal_approx(label_anchor)
				and (enemy_visual.get_node("ArtRoot/EffectAnchor") as Node2D).transform.is_equal_approx(effect_anchor)
				and enemy_visual.get_unit_pick_rect() == pick_rect
				and enemy_visual.get_unit_bars_offset() == bars_offset,
				kind + " resize restores the same death frame and preserves root, HUD and anchor transforms")
			# Единственные часы клипа принадлежат общему Tween; состояние боя остаётся before до его завершения.
			var remaining_until_2_54 := maxf(0.0, 2.54 - tween_progress * 2.55)
			advance(remaining_until_2_54)
			check(player.active and enemy_visual.unit.alive
				and enemy_visual.death_progress < 1.0
				and not board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id),
				kind + " enemy holds before state and withholds corpse through 2.54 seconds")
			finish()
			check(not enemy_visual.unit.alive
				and board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id)
				and not published.is_empty() and published.back() == data.after,
				kind + " enemy publishes after and body only when the death Tween completes")
			assert_playback_unchanged(s, enemy_saved, data, kind + " enemy death2")
			start_packet(data, s, kind + " enemy death2 x3")
			seek_pose(victim.id, [&"death"])
			player.set_speed(3.0)
			advance(2.55 / 3.0 + 0.04)
			check(not (board._presentation_visual(victim.id) as BattleDefenderIdleVisual)._death_active,
				kind + " enemy x3 speed completes the selected death duration")
			# Тело относится к последующей публикации receipt; общий пакет может содержать ещё кадры.
			finish()
			check(board._view_corpses.any(func(c: Dictionary) -> bool: return c.source_unit_id == victim.id)
				and published.back() == data.after, kind + " enemy x3 publishes final body at packet completion")
			player.cancel()
			var playback_snapshot := snapshot(s)
			var playback_rng := s.context.get_rng().to_dict().duplicate(true)
			var playback_counters := s.context.simulation_counters()
			start_packet(data, s, kind + " enemy death2 cancel")
			seek_pose(victim.id, [&"death"])
			player.cancel()
			var canceled_visual := board._presentation_visual(victim.id) as BattleDefenderIdleVisual
			check(not player.active and board._field_presentation.poses.is_empty()
				and canceled_visual != null and not canceled_visual._death_active
				and snapshot(s) == playback_snapshot and s.context.get_rng().to_dict() == playback_rng
				and s.context.simulation_counters() == playback_counters,
				kind + " enemy cancel clears death and preserves state/RNG")
			start_packet(data, s, kind + " enemy death2 skip")
			seek_pose(victim.id, [&"death"])
			var enemy_stale_tween := player._tween
			player.skip()
			enemy_stale_tween.custom_step(2.6)
			check(not player.active and board._field_presentation.poses.is_empty()
				and not (board._presentation_visual(victim.id) as BattleDefenderIdleVisual)._death_active
				and snapshot(s) == playback_snapshot and s.context.get_rng().to_dict() == playback_rng
				and s.context.simulation_counters() == playback_counters,
				kind + " enemy skip clears death and stale Tween without state/RNG changes")
			start_packet(data, s, kind + " enemy death2 retire")
			seek_pose(victim.id, [&"death"])
			var retiring_visual := board._presentation_visual(victim.id) as BattleDefenderIdleVisual
			retiring_visual.retire_view()
			check(not retiring_visual._death_active and retiring_visual.unit == null,
				kind + " enemy retire clears death ownership")
		else:
			check(false, kind + " enemy death2 visual exists")
		production_enemy_art_for_packet = false
	board.session = null
	s.close()
	await process_frame


func fallbacks() -> void:
	var s := field_fixture()
	board.session = s
	s.unit_visual_classes[s.units[1].id] = visual_class
	board.refresh()
	var visual := board._presentation_visual(s.units[1].id) as BattleDefenderIdleVisual
	if visual_class == &"warrior" and visual._uses_enemy_warrior_art():
		visual.enemy_warrior_art_enabled = false
		var enemy_still := visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
		var player_still := visual.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
		enemy_still.texture = player_still.texture
		visual.sync_scene_art()
	var frames: SpriteFrames = visual.get(clip_property)
	visual.set(clip_property, null)
	check(is_equal_approx(board._death_seconds(visual.unit.id), 0.20), "missing clip keeps generic duration")
	board._field_presentation.sample_death(0.5, board, visual.unit.id)
	check(not visual._death_active and visual.get_node("ArtRoot").rotation > 0.0 and visual.modulate.a < 1.0, "missing clip keeps generic death pose")
	visual.reset_view_pose()
	visual.set(clip_property, frames)
	visual.visual_class_id = &"mage"
	check(not visual.can_play_death(), "other visual class keeps its own death")
	visual.visual_class_id = visual_class
	visual.sample_death(0.5)
	visual.retire_view()
	check(not visual._death_active and visual.unit == null, "retire clears authored death ownership")
	if visual_class == &"warrior":
		var enemy_unit: UnitState
		for candidate: UnitState in s.units:
			if candidate.faction == Faction.Type.ENEMY:
				enemy_unit = candidate
				break
		if enemy_unit != null:
			s.unit_visual_classes[enemy_unit.id] = &"warrior"
			board.refresh()
			var enemy_visual := board._presentation_visual(enemy_unit.id) as BattleDefenderIdleVisual
			if enemy_visual != null:
				enemy_visual.enemy_warrior_art_enabled = true
				var enemy_still := enemy_visual.get_node("ArtRoot/EnemyWarriorSprite") as Sprite2D
				enemy_still.texture = enemy_visual.enemy_warrior_idle_frames.get_frame_texture(&"idle", 0)
				enemy_visual.sync_scene_art()
				check(enemy_visual._uses_enemy_warrior_art() and enemy_visual._active_death_frames() == ENEMY_WARRIOR_DEATH
					and enemy_visual.can_play_death() and is_equal_approx(board._death_seconds(enemy_unit.id), 2.55),
					"enemy PixelLab idle selects its dedicated 2.55-second death")
				board._field_presentation.sample_death(0.5, board, enemy_unit.id)
				check(enemy_visual._death_active and is_zero_approx(enemy_visual.get_node("ArtRoot").rotation)
					and enemy_visual.modulate.a == 1.0,
					"enemy death uses authored frames without synthetic pose")
				enemy_visual.reset_view_pose()
				var enemy_frames := enemy_visual.enemy_warrior_death_frames
				enemy_visual.enemy_warrior_death_frames = null
				_check_enemy_generic_death_fallback(enemy_visual, enemy_unit.id, "missing enemy death resource")
				var invalid := SpriteFrames.new()
				invalid.add_animation(&"death")
				for frame: int in 16: invalid.add_frame(&"death", enemy_frames.get_frame_texture(&"death", frame))
				invalid.set_animation_speed(&"death", 60.0)
				enemy_visual.enemy_warrior_death_frames = invalid
				_check_enemy_generic_death_fallback(enemy_visual, enemy_unit.id, "short enemy death resource")
				invalid = SpriteFrames.new()
				invalid.add_animation(&"death")
				for frame: int in 17: invalid.add_frame(&"death", enemy_frames.get_frame_texture(&"death", frame))
				invalid.set_animation_speed(&"death", 0.0)
				enemy_visual.enemy_warrior_death_frames = invalid
				_check_enemy_generic_death_fallback(enemy_visual, enemy_unit.id, "zero-speed enemy death resource")
				invalid.set_animation_speed(&"death", 60.0)
				invalid.set_frame(&"death", 8, null)
				enemy_visual.enemy_warrior_death_frames = invalid
				_check_enemy_generic_death_fallback(enemy_visual, enemy_unit.id, "enemy death resource with missing texture")
				enemy_visual.enemy_warrior_death_frames = enemy_frames
			else:
				check(false, "enemy visual exists for generic death coverage")
	board.session = null
	s.close()
	await process_frame


func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	board = BattleDemoBoard.new()
	board.size = viewport.size
	board.unit_visual_scene = DEFENDER_SCENE
	viewport.add_child(board)
	player = BattlePresentationPlayer.new()
	root.add_child(player)
	player.frame_started.connect(func(frame: Dictionary) -> void: started.append(frame))
	player.frame_finished.connect(func(state: Dictionary) -> void: published.append(state))
	await process_frame
	for kind: String in ["melee", "ranged", "mage", "collision", "collision_single"]: await route(kind)
	await out_of_bounds_chain()
	await void_chain_same_frame()
	await occupied_collapse()
	production_enemy_art_for_packet = true
	await out_of_bounds_chain()
	await void_chain_same_frame()
	await occupied_collapse()
	production_enemy_art_for_packet = false
	await route("collision_enemy")
	await fallbacks()
	player.queue_free()
	board.session = null
	viewport.queue_free()
	await process_frame
	print("%s RESULTS: %d passed, %d failed" % [suite, passed, failed])
	quit(0 if failed == 0 else 1)
