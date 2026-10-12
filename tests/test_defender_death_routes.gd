extends "res://tests/test_presentation_environment.gd"

const DEFENDER_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")

var visual_class: StringName = &"warrior"
var death_seconds: float = 1.98
var clip_property: StringName = &"death_frames"
var sprite_path: String = "ArtRoot/DefenderIdleSprite"
var sprite_scale: float = 1.0
var suite: String = "DEFENDER DEATH ROUTES"


func _initialize() -> void:
	if "--rogue" in OS.get_cmdline_user_args():
		visual_class = &"rogue"
		death_seconds = 1.70
		clip_property = &"rogue_death_frames"
		sprite_path = "ArtRoot/RogueIdleSprite"
		sprite_scale = 0.25
		suite = "ROGUE DEATH ROUTES"
	super._initialize()


func start_packet(data: Dictionary, s: BattleCoreReactionsSession, label: String) -> Dictionary:
	for unit: UnitState in s.units: s.unit_visual_classes[unit.id] = visual_class
	board.session = s
	board.refresh()
	return super.start_packet(data, s, label)


func seek_pose(id: int, kinds: Array[StringName]) -> Dictionary:
	var pose := super.seek_pose(id, kinds)
	var visual := board._presentation_visual(id) as BattleDefenderIdleVisual
	if pose.get("kind") == &"fall" and visual != null:
		check(not visual._death_active, "fall never starts the ground death clip")
	return pose


func route(kind: String) -> void:
	var s := BattleCoreReactionsSession.new() if kind == "mage" else field_fixture()
	if kind == "mage":
		s._enemy_index = s._enemy_ids.size()
		s.step_enemy()
		for unit: UnitState in s.units:
			for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0
	var victim := s.units[2] if kind.begins_with("collision") else s.units[1]
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
			check(is_equal_approx(sprite.self_modulate.a, 1.0), kind + " keeps rogue opaque during fall and hold")
			var elapsed := visual.death_progress * death_seconds
			var midpoint_target: float = 0.65 + 0.25 + 0.40
			if elapsed < midpoint_target: advance(midpoint_target - elapsed)
			elapsed = visual.death_progress * death_seconds
			var expected_alpha := 1.0 - clampf((elapsed - 0.65 - 0.25) / 0.80, 0.0, 1.0)
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
			var expected_alpha := 1.0 - clampf((elapsed - 0.65 - 0.25) / 0.80, 0.0, 1.0)
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
	board.session = null
	s.close()
	await process_frame


func fallbacks() -> void:
	var s := field_fixture()
	board.session = s
	s.unit_visual_classes[s.units[1].id] = visual_class
	board.refresh()
	var visual := board._presentation_visual(s.units[1].id) as BattleDefenderIdleVisual
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
	await fallbacks()
	player.queue_free()
	board.session = null
	viewport.queue_free()
	await process_frame
	print("%s RESULTS: %d passed, %d failed" % [suite, passed, failed])
	quit(0 if failed == 0 else 1)
