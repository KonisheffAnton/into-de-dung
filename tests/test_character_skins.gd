extends SceneTree

const BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const SKINS: Array[Dictionary] = [
	{"id": &"watch_shield", "class": &"shieldbearer"},
	{"id": &"grey_bastion", "class": &"shieldbearer"},
	{"id": &"red_bastion", "class": &"fighter"},
]

var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CHARACTER SKINS: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _test_skins_and_clock()
	await _test_shield_command()
	await _test_fighter_attack_routes()
	await _test_lethal_skin_deaths()
	if DisplayServer.get_name() != "headless": await _test_rendered_skins()
	viewport.queue_free()
	await process_frame
	print("CHARACTER SKINS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _capture_path() -> String:
	var directory := "user://character-skins-captures"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): directory = argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	return directory

func _test_rendered_skins() -> void:
	viewport.size = Vector2i(960, 650)
	viewport.transparent_bg = true
	var visual_cells: Array[Dictionary] = []
	for row: int in SKINS.size():
		var entry: Dictionary = SKINS[row]
		for column: int in 4:
			var faction := Faction.Type.ENEMY if column == 1 else Faction.Type.PLAYER
			var visual := _make_visual(700 + row * 4 + column, entry.class, faction, entry.id)
			var anchor := Vector2(120 + column * 240, 150 + row * 200)
			visual.position = anchor
			# Проверяем зеркальные пиксели тела отдельно от незеркальных букв/HP.
			visual.self_modulate.a = 0.0
			if column == 2: visual.sample_buff(1.12)
			if column == 3: visual.sample_death(1.0)
			visual.set_process(false)
			visual_cells.append({"visual": visual, "anchor": anchor, "label": "%s %d" % [entry.id, column]})
			var label := Label.new()
			label.text = "%s · %s" % [entry.id, ["idle PLAYER", "idle ENEMY", "ability 2", "death 3"][column]]
			label.position = anchor + Vector2(-110, 35)
			viewport.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	check(not pixels.is_empty(), "GPU provides skin contact pixels")
	if not pixels.is_empty():
		for cell: Dictionary in visual_cells:
			var count := 0
			var center: Vector2i = Vector2i(cell.anchor)
			for y: int in range(center.y - 100, center.y + 30):
				for x: int in range(center.x - 90, center.x + 90):
					if pixels.get_pixel(x, y).a > 0.2: count += 1
			check(count > 100, "GPU renders visible selected frame: " + String(cell.label))
		for row: int in SKINS.size():
			var compared := 0
			var differences := 0
			for y: int in range(150 + row * 200 - 100, 150 + row * 200):
				for x: int in range(-90, 90):
					var left := pixels.get_pixel(120 + x, y)
					var right := pixels.get_pixel(360 - x - 1, y)
					if left.a < 0.2 and right.a < 0.2: continue
					compared += 1
					# Преобразование shader RGB в8bit допускает один уровень округления; alpha совпадает строго.
					if absf(left.r - right.r) > 1.01 / 255.0 or absf(left.g - right.g) > 1.01 / 255.0 or absf(left.b - right.b) > 1.01 / 255.0 or left.a != right.a: differences += 1
			check(compared > 100 and differences == 0, "GPU opposite teams mirror all body pixels (RGB1/255, exact alpha): %s (%d/%d)" % [SKINS[row].id, differences, compared])
		check(pixels.save_png(_capture_path().path_join("selected-skins-gpu.png")) == OK, "save rendered skin contact")

func _visual_values(unit_id: int, class_id: StringName, faction: Faction.Type, skin_id: StringName) -> Dictionary:
	var status_entries: Array[Dictionary] = []
	return {
		"cell": Vector2i(1, 1), "half_steps": 0,
		"unit": {"id": unit_id, "faction": int(faction), "name": "Skin test", "alive": true,
			"hp": 100.0, "hp_max": 100.0, "balance": 0.0, "balance_max": 100.0},
		"visual_class_id": class_id, "visual_skin_id": skin_id,
		"selected": false, "inspected": false, "hovered": false, "acting": false,
		"forecast_entry": {}, "show_rear": false, "summon_pending": false,
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {},
		"reaction_view": {}, "action_resources_view": {}, "status_entries": status_entries,
	}

func _make_visual(unit_id: int, class_id: StringName, faction: Faction.Type, skin_id: StringName,
		parent: Node = null) -> BattleCharacterSkinVisual:
	var visual := UNIT_SCENE.instantiate() as BattleCharacterSkinVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.show_ground_shadow = false
	var host: Node = viewport if parent == null else parent
	host.add_child(visual)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	check(visual.apply_view(_visual_values(unit_id, class_id, faction, skin_id), config),
		"initial apply_view installs %s for %s" % [skin_id, faction])
	return visual

func _frame_at(frames: SpriteFrames, animation: StringName, elapsed: float) -> Texture2D:
	var remaining := elapsed * frames.get_animation_speed(animation)
	for index: int in frames.get_frame_count(animation):
		var duration := frames.get_frame_duration(animation, index)
		if remaining < duration or index == frames.get_frame_count(animation) - 1:
			return frames.get_frame_texture(animation, index)
		remaining -= duration
	return null

func _test_skins_and_clock() -> void:
	var visuals: Array[BattleCharacterSkinVisual] = []
	var by_skin_and_side: Dictionary = {}
	var next_id := 10
	for skin_entry: Dictionary in SKINS:
		var skin_id: StringName = skin_entry.id
		var class_id: StringName = skin_entry.class
		var definition := CharacterSkinCatalog.definition(class_id, skin_id)
		check(definition != null and definition.id == skin_id and definition.class_id == class_id,
			"catalog resolves %s to its class resource" % skin_id)
		if definition == null: continue
		check(definition.still != null and definition.animations != null and definition.anchor == Vector2(128, 200)
			and is_equal_approx(definition.texture_scale, 0.5), "%s has approved still, SpriteFrames, anchor and scale" % skin_id)
		for animation: StringName in [&"idle", &"buff", &"death"]:
			check(definition.clip_valid(animation) and definition.animations.get_frame_count(animation) == 33,
				"%s %s clip has 33 valid atlas frames" % [skin_id, animation])
			check(definition.animations.get_animation_loop(animation) == (animation == &"idle"),
				"%s %s loop flag matches its role" % [skin_id, animation])
		for animation: StringName in [&"buff", &"death"]:
			var atlas_frame := definition.animations.get_frame_texture(animation, 0) as AtlasTexture
			check(atlas_frame != null and atlas_frame.atlas.resource_path.ends_with("/%s/%s.png" % [skin_id, animation]),
				"%s %s resolves the selected PixelLab sheet" % [skin_id, animation])
		check(is_equal_approx(definition.clip_duration(&"idle"), 2.97), "%s idle duration is retained" % skin_id)
		check(is_equal_approx(definition.clip_duration(&"buff"), 2.31), "%s selected ability duration is retained" % skin_id)
		check(is_equal_approx(definition.clip_duration(&"death"), 3.74), "%s death3 keeps its 1500ms final hold" % skin_id)
		if skin_id == &"watch_shield":
			check(definition.clip_valid(&"idle_secondary") and definition.animations.get_animation_loop(&"idle_secondary"),
				"model 02 alone exposes its repeating secondary idle")
		else:
			check(not definition.animations.has_animation(&"idle_secondary"), "%s has no unselected secondary idle" % skin_id)
		for faction: Faction.Type in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
			var visual := _make_visual(next_id, class_id, faction, skin_id)
			next_id += 1
			visuals.append(visual)
			by_skin_and_side["%s:%d" % [skin_id, int(faction)]] = visual
			var sprite := visual.class_still_sprite()
			var team_facing := 1 if faction == Faction.Type.PLAYER else -1
			var mirrored := team_facing != definition.source_facing_x
			var expected_scale_x := -0.5 if mirrored else 0.5
			var expected_anchor_x := 64.0 if mirrored else -64.0
			check(sprite != null and sprite.texture == definition.animations.get_frame_texture(&"idle", 0) and sprite.visible,
				"%s %s side draws selected primary idle" % [skin_id, faction])
			check(sprite != null and is_equal_approx(sprite.scale.x, expected_scale_x)
				and is_equal_approx(sprite.scale.y, 0.5)
				and sprite.position.is_equal_approx(Vector2(expected_anchor_x, -100.0)),
				"%s %s keeps uniform scale and mirrored anchor" % [skin_id, faction])
			if sprite != null:
				var material := sprite.material as ShaderMaterial
				check(material != null and is_equal_approx(float(material.get_shader_parameter(&"shieldbearer_palette_strength")), definition.shieldbearer_palette_strength),
					"%s %s uses only its approved shieldbearer RGB palette strength" % [skin_id, faction])
				check(sprite.get_meta(&"source_facing_x", 0) == definition.source_facing_x,
					"%s %s keeps authored direction metadata" % [skin_id, faction])
			if faction == Faction.Type.PLAYER:
				visual._draw_skin_idle()
				check(not visual.skin_clock.secondary and sprite.texture == definition.animations.get_frame_texture(&"idle", 0),
					"%s starts with its primary idle clip" % skin_id)
			var buff_mid := definition.animations.get_frame_duration(&"buff", 16) * 0.5 / definition.animations.get_animation_speed(&"buff")
			visual.sample_buff(buff_mid)
			check(sprite.texture == _frame_at(definition.animations, &"buff", buff_mid),
				"%s %s ability2 selects its source atlas frame" % [skin_id, faction])
			var buff_texture := sprite.texture
			var buff_transform := sprite.transform
			visual.sync_scene_art()
			visual.sync_scene_art()
			check(sprite.texture == buff_texture and sprite.transform.is_equal_approx(buff_transform),
				"%s %s keeps buff frame and facing on repeated sync" % [skin_id, faction])
			visual.sample_death(1.0)
			check(sprite.texture == definition.animations.get_frame_texture(&"death", 32),
				"%s %s death3 selects its held final atlas pose" % [skin_id, faction])
			var death_texture := sprite.texture
			var death_transform := sprite.transform
			visual.sync_scene_art()
			visual.sync_scene_art()
			check(sprite.texture == death_texture and sprite.transform.is_equal_approx(death_transform),
				"%s %s keeps death frame and facing on repeated sync" % [skin_id, faction])
			visual.reset_view_pose()
			visual.sync_scene_art()
			var base_transform := sprite.transform
			for attack_facing: int in [-1, 1]:
				visual.presentation_facing_x = attack_facing
				var should_attack_flip := attack_facing != team_facing
				var expected_attack_sign := signf(base_transform.x.x) * (-1.0 if should_attack_flip else 1.0)
				var attack_transform := sprite.transform
				check(is_equal_approx(signf(attack_transform.x.x), expected_attack_sign)
					and is_equal_approx(visual.get_attack_mirror_x(), -1.0 if should_attack_flip else 1.0),
					"%s %s temporary facing %d is relative to team orientation" % [skin_id, faction, attack_facing])
				visual.sync_scene_art()
				visual.sync_scene_art()
				check(sprite.transform.is_equal_approx(attack_transform),
					"%s %s repeated sync preserves temporary attack facing" % [skin_id, faction])
			visual.presentation_facing_x = 0
			check(sprite.transform.is_equal_approx(base_transform)
				and is_equal_approx(signf(sprite.transform.x.x), signf(base_transform.x.x)),
				"%s %s reset restores its team facing and anchor" % [skin_id, faction])
	for skin_entry: Dictionary in SKINS:
		var skin_id: StringName = skin_entry.id
		var class_id: StringName = skin_entry.class
		var visual := by_skin_and_side["%s:%d" % [skin_id, int(Faction.Type.PLAYER)]] as BattleCharacterSkinVisual
		var sprite := visual.class_still_sprite()
		visual.skin_clock.advance(0.41)
		var saved_phase := visual.skin_clock.elapsed
		var owner_before := visual._skin_owner
		var definition_before := visual.skin_definition
		var enemy_values := _visual_values(owner_before, class_id, Faction.Type.ENEMY, skin_id)
		var config := IsoGridConfig.new(); config.tile_size = Vector2(128.0, 96.0)
		visual.apply_view(enemy_values, config)
		var enemy_mirrored := -1 != definition_before.source_facing_x
		check(visual._skin_owner == owner_before and visual.skin_definition == definition_before
			and is_equal_approx(visual.skin_clock.elapsed, saved_phase),
			"%s same-ID side swap preserves owner, resource and idle phase" % skin_id)
		check(is_equal_approx(sprite.scale.x, -0.5 if enemy_mirrored else 0.5)
			and sprite.position.is_equal_approx(Vector2(64.0 if enemy_mirrored else -64.0, -100.0)),
			"%s PLAYER-to-ENEMY swap updates team facing" % skin_id)
		var player_values := _visual_values(owner_before, class_id, Faction.Type.PLAYER, skin_id)
		visual.apply_view(player_values, config)
		var player_mirrored := 1 != definition_before.source_facing_x
		check(is_equal_approx(visual.skin_clock.elapsed, saved_phase)
			and is_equal_approx(sprite.scale.x, -0.5 if player_mirrored else 0.5)
			and sprite.position.is_equal_approx(Vector2(64.0 if player_mirrored else -64.0, -100.0)),
			"%s ENEMY-to-PLAYER swap restores team facing without resetting idle" % skin_id)
	var player_17 := by_skin_and_side["grey_bastion:%d" % int(Faction.Type.PLAYER)] as BattleCharacterSkinVisual
	var enemy_17 := by_skin_and_side["grey_bastion:%d" % int(Faction.Type.ENEMY)] as BattleCharacterSkinVisual
	if player_17 != null and enemy_17 != null and player_17.class_still_sprite() != null and enemy_17.class_still_sprite() != null:
		var player_17_material := player_17.class_still_sprite().material as ShaderMaterial
		var enemy_17_material := enemy_17.class_still_sprite().material as ShaderMaterial
		check(player_17_material != null and enemy_17_material != null and player_17_material != enemy_17_material
			and is_equal_approx(float(player_17_material.get_shader_parameter(&"shieldbearer_palette_strength")), 1.0)
			and is_equal_approx(float(enemy_17_material.get_shader_parameter(&"shieldbearer_palette_strength")), 1.0),
			"model 17 has independent palette materials on both battle sides")
	else:
		check(false, "model 17 exposes both side sprites for independent materials")

	var idle_visual := by_skin_and_side["watch_shield:%d" % int(Faction.Type.PLAYER)] as BattleCharacterSkinVisual
	if idle_visual == null:
		check(false, "model 02 exposes its player visual for clock tests")
		for visual: BattleCharacterSkinVisual in visuals:
			if is_instance_valid(visual): visual.queue_free()
		return
	var skin := idle_visual.skin_definition
	var idle_seconds := skin.clip_duration(&"idle")
	# Смена стороны выше намеренно продвинула часы; этот сценарий начинает новый полный цикл.
	idle_visual.skin_clock.configure(10, idle_seconds, skin.clip_duration(&"idle_secondary"))
	check(idle_visual.skin_clock._normal_cycles in range(3, 7), "secondary idle gap starts between three and six full cycles")
	idle_visual.skin_clock.advance(idle_seconds * idle_visual.skin_clock._normal_cycles + 0.002)
	check(idle_visual.skin_clock.secondary and idle_visual.skin_clock.elapsed < 0.01,
		"model 02 runs the secondary once after complete primary cycles")
	idle_visual._draw_skin_idle()
	check(idle_visual.class_still_sprite().texture == _frame_at(skin.animations, &"idle_secondary", idle_visual.skin_clock.elapsed),
		"model 02 secondary idle samples its own atlas clip")
	var secondary_seconds := skin.clip_duration(&"idle_secondary")
	idle_visual.skin_clock.advance(secondary_seconds + 0.002)
	check(not idle_visual.skin_clock.secondary and idle_visual.skin_clock.elapsed < 0.01
		and idle_visual.skin_clock._normal_cycles in range(3, 7), "secondary returns to primary and schedules another gap")
	var different_gaps: Dictionary = {}
	seed(71391)
	var expected_global_random := randi()
	seed(71391)
	for visual_seed: int in range(1, 13):
		var clock := CharacterIdleClock.new()
		clock.configure(visual_seed, idle_seconds, secondary_seconds)
		clock.advance(idle_seconds * float(clock._normal_cycles) + secondary_seconds * 0.3)
		different_gaps[clock._normal_cycles] = true
	check(different_gaps.size() > 1, "visual-only seeds produce varied gaps")
	check(randi() == expected_global_random, "private idle clocks leave the global RNG untouched")

	# Часы idle принадлежат рисунку; обычный refresh и resize их не перезапускают.
	idle_visual.skin_clock.advance(0.37)
	var values := _visual_values(10, &"shieldbearer", Faction.Type.PLAYER, &"watch_shield")
	var same_config := IsoGridConfig.new(); same_config.tile_size = Vector2(128.0, 96.0)
	var phase := idle_visual.skin_clock.elapsed
	idle_visual.apply_view(values, same_config)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "same-unit board refresh preserves idle phase")
	var resized := IsoGridConfig.new(); resized.tile_size = Vector2(160.0, 120.0)
	idle_visual.apply_view(values, resized)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "board resize preserves idle phase")
	var sprite := idle_visual.class_still_sprite()
	var visible_idle_texture: Texture2D = sprite.texture
	idle_visual.ambient_animation_paused = true
	idle_visual._process(0.4)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase) and sprite.texture == skin.still,
		"action pause stops local idle clock and restores static art")
	idle_visual.ambient_animation_paused = false
	idle_visual.frozen = true
	idle_visual._process(0.4)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "frozen state pauses idle clock")
	idle_visual.frozen = false
	idle_visual.stunned = true
	idle_visual._process(0.4)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "stunned state pauses idle clock")
	idle_visual.stunned = false
	idle_visual.summon_pending = true
	idle_visual._process(0.4)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "pending summon pauses idle clock")
	idle_visual.summon_pending = false
	idle_visual.action_offset = Vector2(3.0, 0.0)
	idle_visual._process(0.4)
	check(is_equal_approx(idle_visual.skin_clock.elapsed, phase), "action pose pauses idle clock")
	idle_visual.action_offset = Vector2.ZERO
	idle_visual.sync_scene_art()
	check(visible_idle_texture != null and idle_visual.skin_clock.elapsed == phase,
		"idle resumes from the saved phase after the action")

	# Вторичный клип, buff и death выбирают реальные AtlasTexture кадры по SpriteFrames timing.
	var clip_frames := skin.animations
	for index: int in [0, 16, 32]:
		var elapsed := 0.0
		for frame: int in index: elapsed += clip_frames.get_frame_duration(&"buff", frame) / clip_frames.get_animation_speed(&"buff")
		elapsed += clip_frames.get_frame_duration(&"buff", index) * 0.5 / clip_frames.get_animation_speed(&"buff")
		idle_visual.sample_buff(elapsed)
		check(sprite.texture == _frame_at(clip_frames, &"buff", elapsed), "buff samples source atlas frame %02d" % index)
	for progress: float in [0.0, 0.5, 1.0]:
		idle_visual.sample_death(progress)
		check(idle_visual._skin_dying and sprite.texture == _frame_at(clip_frames, &"death", skin.clip_duration(&"death") * progress),
			"death3 samples authored atlas pose at %s" % progress)
	idle_visual.reset_view_pose()
	idle_visual.sync_scene_art()
	check(not idle_visual._skin_dying and idle_visual._skin_buff_elapsed < 0.0, "reset clears death and ability presentation state")

	var original_frames := skin.animations
	skin.animations = SpriteFrames.new()
	idle_visual.frozen = true
	idle_visual.sample_buff(0.4)
	check(not idle_visual.can_play_buff() and sprite.texture == skin.still,
		"invalid selected clip falls back to visible still rather than stale buff")
	skin.animations = original_frames
	idle_visual.frozen = false
	idle_visual.reset_view_pose()

	# Публикация другого владельца, класса или скина создаёт новую фазу с нулевой позой.
	idle_visual.skin_clock.advance(0.61)
	values = _visual_values(99, &"shieldbearer", Faction.Type.PLAYER, &"watch_shield")
	idle_visual.apply_view(values, resized)
	check(idle_visual._skin_owner == 99 and is_zero_approx(idle_visual.skin_clock.elapsed), "unit ownership change resets idle phase")
	values = _visual_values(99, &"fighter", Faction.Type.PLAYER, &"red_bastion")
	idle_visual.skin_clock.advance(0.23)
	idle_visual.apply_view(values, resized)
	check(idle_visual.skin_definition.id == &"red_bastion" and is_zero_approx(idle_visual.skin_clock.elapsed), "class/skin change resets the clip clock")
	values = _visual_values(99, &"shieldbearer", Faction.Type.PLAYER, &"grey_bastion")
	idle_visual.apply_view(values, resized)
	check(idle_visual.skin_definition.id == &"grey_bastion" and not idle_visual.skin_clock.secondary
		and is_zero_approx(idle_visual.skin_clock.elapsed), "skin change resets its idle schedule")
	idle_visual.retire_view()
	check(idle_visual._skin_owner == UnitId.NONE and idle_visual._skin_buff_elapsed < 0.0
		and not idle_visual._skin_dying and idle_visual.class_still_sprite() == null,
		"retire clears the old skin owner and action poses")
	for visual: BattleCharacterSkinVisual in visuals:
		if is_instance_valid(visual): visual.queue_free()
	await process_frame

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var capture := ItemSimulationSnapshot.capture(session.state, [])
	return {"state": capture.snapshot.to_dict() if capture.snapshot != null else {},
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}

func _make_battle(seed: int) -> Dictionary:
	var profile := HeroHubState.create(seed, 3)
	if profile == null: return {}
	profile.party.assign([5, 1, 2])
	if not profile.start_battle(): return {}
	var bundle := HeroHubBattleFactory.create(profile)
	if bundle.is_empty(): return {}
	var session := bundle.session as BattleCoreReactionsSession
	if not session.start_battle(): session.close(); return {}
	var steps := 0
	while session.phase == BattleTacticalSession.Phase.ENEMY_TURN and steps < 30:
		session.step_enemy(); steps += 1
	if not session.can_player_act(): session.close(); return {}
	var fighter_id: int = int(bundle.hero_units[5])
	var shield_id: int = int(bundle.hero_units[1])
	var fighter := session.board.get_unit_by_id(fighter_id)
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	for unit: UnitState in session.units:
		if unit == fighter or unit == target: continue
		unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 0.0)
	check(session.board.move_unit(target, fighter.cell + Vector2i.RIGHT), "test target is placed adjacent through BattleBoard")
	fighter.stats.set_base_value(StatTypes.StatType.POWER, 11.0)
	fighter.stats.set_base_value(StatTypes.StatType.MASTERY, 10.0)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 500.0)
	target.vitals.set_hp(500.0)
	target.vitals.set_balance(0.0)
	target.guard_stance = false
	target.armor.natural.physical = 0
	for item: ItemInstance in session.state.get_owner(target.id)._items.values(): item.armor_remaining = 0
	check(session.select_unit(fighter_id), "fighter selected for art-route command")
	var demo := BATTLE_SCENE.instantiate() as HeroHubBattleView
	demo.supplied_session = session
	demo.character_skins = {&"shieldbearer": &"grey_bastion", &"fighter": &"red_bastion"}
	viewport.add_child(demo)
	await process_frame
	demo.set_process(false)
	demo.board_view.unit_visual_scene = UNIT_SCENE
	demo.board_view.refresh()
	return {"profile": profile, "bundle": bundle, "session": session, "demo": demo,
		"board": demo.board_view as BattleDemoBoard, "fighter_id": fighter_id, "shield_id": shield_id,
		"target_id": target.id, "ordinary_attack_id": StringName(session.actor_loadouts[fighter_id].attack_id)}

func _close_battle(fixture: Dictionary) -> void:
	if fixture.is_empty(): return
	var demo := fixture.demo as HeroHubBattleView
	var session := fixture.session as BattleCoreReactionsSession
	if demo != null: demo.queue_free()
	if session != null: session.close()
	await process_frame

func _drain_paused_player(presentation: BattlePresentationPlayer, max_steps: int = 180) -> void:
	for _step: int in max_steps:
		if not presentation.active: break
		if presentation._tween != null and presentation._tween.is_valid():
			presentation._tween.pause()
			presentation._tween.custom_step(0.05)
		await process_frame
	check(not presentation.active, "bounded paused-Tween playback completes naturally")

func _captured_action(session: BattleCoreReactionsSession, action: StringName, target_id: int = 0) -> ActionReceipt:
	session.begin_presentation_capture()
	var receipt: ActionReceipt
	match action:
		&"raise_shields": receipt = session.raise_shields()
		&"attack": receipt = session.attack_unit(target_id)
		&"kick": receipt = session.click_attack(target_id)
	session.take_presentation_capture()
	return receipt

func _find_event_frame(frames: Array, kind: StringName, actor_id: int, attack_id: StringName = &"") -> Dictionary:
	for frame: Dictionary in frames:
		for event: Dictionary in frame.events:
			if event.get("kind") != kind or int(event.get("actor_unit_id", UnitId.NONE)) != actor_id: continue
			if attack_id != &"" and StringName(event.get("attack_definition_id", &"")) != attack_id: continue
			return frame
	return {}

func _test_shield_command() -> void:
	var fixture := await _make_battle(83021)
	check(not fixture.is_empty(), "real battle fixture starts for shield command")
	if fixture.is_empty(): return
	var session := fixture.session as BattleCoreReactionsSession
	var board := fixture.board as BattleDemoBoard
	var shield_id: int = fixture.shield_id
	var visual := board._presentation_visual(shield_id) as BattleCharacterSkinVisual
	check(session.select_unit(shield_id), "shieldbearer selected for Raise Shields")
	board.refresh()
	check(board._presentation_visual(shield_id) == visual, "same-side board refresh retains the live skin visual")
	var refresh_phase := visual.skin_clock.elapsed
	board.size += Vector2(19.0, 13.0)
	board._rescale_layout()
	check(board._presentation_visual(shield_id) == visual and is_equal_approx(visual.skin_clock.elapsed, refresh_phase),
		"board resize retains visual identity and idle phase")
	check(visual != null and visual.skin_definition.id == &"grey_bastion" and visual.can_play_buff(),
		"board public skin values select model 17 for the Shieldbearer")
	var before := ActionPresentationState.capture(session.state)
	var receipt := _captured_action(session, &"raise_shields")
	var frames := receipt.get_presentation_frames()
	check(receipt.status == ActionReceipt.APPLIED and not frames.is_empty(), "Raise Shields produces a real applied receipt frame")
	if frames.is_empty(): await _close_battle(fixture); return
	var frame: Dictionary = frames[0]
	check(frame.step.get("kind") == &"raise_shields" and board._matching_defender_buff(frame.events, frame.step) == visual,
		"only the matching applied raised_shields command selects buff 2")
	var skipped: Dictionary = frame.step.duplicate(true); skipped.status = &"SKIPPED"
	check(board._matching_defender_buff(frame.events, skipped) == null, "skipped shield command cannot start its selected clip")
	var wrong_sequence: Dictionary = frame.step.duplicate(true); wrong_sequence.command_seq = int(frame.step.command_seq) + 1
	check(board._matching_defender_buff(frame.events, wrong_sequence) == null, "unrelated shield command sequence cannot start its clip")
	var committed := _snapshot(session)
	var after := ActionPresentationState.capture(session.state)
	var player := BattlePresentationPlayer.new(); fixture.demo.add_child(player)
	player.play(board, before, frames, after); player._tween.pause()
	check(player.active and board._defender_buff_visual == visual and visual._skin_buff_elapsed == 0.0
		and visual.class_still_sprite().texture == visual.skin_definition.animations.get_frame_texture(&"buff", 0),
		"production presentation starts the selected shield ability clip")
	check(_snapshot(session) == committed, "shield presentation leaves snapshot, battle RNG and counters unchanged")
	player.skip()
	check(not player.active and board._defender_buff_visual == null and visual._skin_buff_elapsed < 0.0,
		"skip clears the shield clip and restores its base pose")
	player.play(board, before, frames, after); player._tween.pause(); player.cancel()
	check(board._defender_buff_visual == null and visual._skin_buff_elapsed < 0.0,
		"cancel clears the shield clip without a stale callback")
	player.play(board, before, frames, after); player._tween.pause()
	var shield_committed := _snapshot(session)
	await _drain_paused_player(player)
	check(not player.active and board._defender_buff_visual == null and visual._skin_buff_elapsed < 0.0
		and _snapshot(session) == shield_committed,
		"normal shield ability completion releases buff clip without changing the committed battle")
	player.queue_free()
	check(_snapshot(session) == committed, "skip/cancel do not mutate committed battle state or RNG")
	await _close_battle(fixture)

func _test_fighter_attack_routes() -> void:
	for attack_kind: StringName in [&"cleave", &"ordinary", &"kick"]:
		var fixture := await _make_battle(83100 + attack_kind.hash())
		check(not fixture.is_empty(), "%s battle fixture starts" % attack_kind)
		if fixture.is_empty(): continue
		var session := fixture.session as BattleCoreReactionsSession
		var board := fixture.board as BattleDemoBoard
		var actor_id: int = fixture.fighter_id
		var visual := board._presentation_visual(actor_id) as BattleCharacterSkinVisual
		check(visual != null and visual.skin_definition.id == &"red_bastion", "%s uses fighter skin ability source" % attack_kind)
		var before := ActionPresentationState.capture(session.state)
		match attack_kind:
			&"cleave": session.warrior_selected = WarriorKit.CLEAVE
			&"kick": session.warrior_selected = WarriorKit.KICK
			_: session.warrior_selected = &""
		var receipt := _captured_action(session, &"attack" if attack_kind != &"kick" else &"kick", int(fixture.target_id))
		check(receipt.status == ActionReceipt.APPLIED, "%s attack remains mechanically applied" % attack_kind)
		var frames := receipt.get_presentation_frames()
		var after := ActionPresentationState.capture(session.state)
		var expected_attack: StringName = WarriorKit.CLEAVE if attack_kind == &"cleave" else (WarriorKit.KICK if attack_kind == &"kick" else StringName(fixture.ordinary_attack_id))
		var attack_frame := _find_event_frame(frames, &"attacked", actor_id, expected_attack)
		check(not attack_frame.is_empty(), "%s contact frame retains its attack definition" % attack_kind)
		if attack_kind == &"cleave":
			var event_kinds: Array[StringName] = []
			for event: Dictionary in receipt.get_events(): event_kinds.append(StringName(event.get("kind", &"")))
			check(event_kinds.has(&"damaged") and event_kinds.has(&"bleeding_changed"),
				"Cleave keeps its confirmed contact damage and bleed events")
		var committed := _snapshot(session)
		var complete_buff := attack_kind == &"cleave"
		var playback: BattlePresentationPlayer
		if not attack_frame.is_empty():
			var tween := board.animate_presentation_frame(attack_frame.events, attack_frame.step)
			if tween != null: tween.pause()
			var should_play := attack_kind == &"cleave"
			check((board._defender_buff_visual == visual) == should_play,
				"only Cleave event selects fighter buff 2; ordinary attack and kick keep their own pose")
			if should_play:
				check(visual._skin_buff_elapsed == 0.0
					and visual.class_still_sprite().texture == visual.skin_definition.animations.get_frame_texture(&"buff", 0),
					"Cleave selects the chosen ability AtlasTexture on contact")
			if tween != null: tween.kill()
		if complete_buff and not frames.is_empty():
			playback = BattlePresentationPlayer.new()
			fixture.demo.add_child(playback)
			playback.play(board, before, frames, after)
			playback._tween.pause()
			await _drain_paused_player(playback)
			check(board._defender_buff_visual == null and visual._skin_buff_elapsed < 0.0
				and _snapshot(session) == committed,
				"Cleave ability2 completes naturally after contact without changing battle state")
		board._clear_defender_buff()
		board.clear_strike_poses()
		check(_snapshot(session) == committed, "%s presentation changes no committed state, RNG or counters" % attack_kind)
		if playback != null:
			playback.queue_free()
		await _close_battle(fixture)

func _test_lethal_skin_deaths() -> void:
	var routes: Array[Dictionary] = [
		{"skin": &"watch_shield", "class": &"shieldbearer"},
		{"skin": &"grey_bastion", "class": &"shieldbearer"},
		{"skin": &"red_bastion", "class": &"fighter"},
	]
	for route: Dictionary in routes:
		var skin_id: StringName = route.skin
		var class_id: StringName = route.class
		var fixture := await _make_battle(84000 + String(skin_id).hash())
		check(not fixture.is_empty(), "%s lethal battle fixture starts" % skin_id)
		if fixture.is_empty(): continue
		var session := fixture.session as BattleCoreReactionsSession
		var board := fixture.board as BattleDemoBoard
		var target_id: int = fixture.target_id
		var target := session.board.get_unit_by_id(target_id)
		var original_loadout: Dictionary = session.actor_loadouts.get(target_id, {}).duplicate(true)
		# В этом тесте меняется только визуальная маршрутизация цели. Её фракция,
		# характеристики и механический loadout остаются созданными factory.
		session.unit_visual_classes[target_id] = class_id
		board.character_skins[class_id] = skin_id
		board.refresh()
		var visual := board._presentation_visual(target_id) as BattleCharacterSkinVisual
		check(visual != null and visual.skin_definition != null and visual.skin_definition.id == skin_id,
			"%s renderer route selects the intended target skin" % skin_id)
		if visual == null or visual.skin_definition == null:
			await _close_battle(fixture)
			continue
		target.vitals.set_hp(1.0)
		target.vitals.set_balance(0.0)
		target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 1000.0)
		target.armor.natural.physical = 0
		for item: ItemInstance in session.state.get_owner(target_id)._items.values(): item.armor_remaining = 0
		var attacker := session.board.get_unit_by_id(int(fixture.fighter_id))
		attacker.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		attacker.stats.set_base_value(StatTypes.StatType.POWER, 30.0)
		attacker.stats.set_base_value(StatTypes.StatType.MASTERY, 30.0)
		session.warrior_selected = &""
		check(session.actor_loadouts.get(target_id, {}) == original_loadout,
			"%s visual-only route does not alter target combat loadout" % skin_id)
		var before := ActionPresentationState.capture(session.state)
		var receipt := _captured_action(session, &"attack", target_id)
		var frames: Array[Dictionary] = receipt.get_presentation_frames()
		var after := ActionPresentationState.capture(session.state)
		check(receipt.status == ActionReceipt.APPLIED
			and receipt.get_events().any(func(event: Dictionary) -> bool:
				return event.get("kind", &"") == &"died" and int(event.get("target_unit_id", 0)) == target_id),
			"%s target death comes from a real lethal attack receipt" % skin_id)
		check(not frames.is_empty() and not target.is_alive(), "%s lethal packet contains confirmed after state" % skin_id)
		if frames.is_empty():
			await _close_battle(fixture)
			continue
		check(is_equal_approx(board._death_seconds(target_id), 3.74) and visual.can_play_death(),
			"%s routes death3 with its selected 3.74-second duration" % skin_id)
		var committed := _snapshot(session)
		var playback := BattlePresentationPlayer.new()
		fixture.demo.add_child(playback)
		var published: Array[Dictionary] = []
		playback.frame_finished.connect(func(state: Dictionary) -> void: published.append(state))
		playback.play(board, before, frames, after)
		if playback._tween != null: playback._tween.pause()
		check(playback.active and playback._published == before,
			"%s shows the receipt before state while the death clip is pending" % skin_id)
		var approach_steps := 0
		while playback.active and not visual._skin_dying and approach_steps < 60:
			if playback._tween != null and playback._tween.is_valid():
				playback._tween.pause()
				playback._tween.custom_step(0.05)
			await process_frame
			approach_steps += 1
		check(visual._skin_dying and visual.unit != null and visual.unit.alive
			and not board._view_corpses.any(func(corpse: Dictionary) -> bool: return int(corpse.get("source_unit_id", 0)) == target_id),
			"%s holds living before-state until the selected death finishes" % skin_id)
		if visual._skin_dying:
			for _sample: int in 8:
				if playback._tween == null or not playback._tween.is_valid(): break
				playback._tween.pause()
				playback._tween.custom_step(0.10)
				await process_frame
			var death_elapsed := visual.death_progress * visual.death_duration()
			check(visual._skin_dying and visual.class_still_sprite().texture
				== _frame_at(visual.skin_definition.animations, &"death", death_elapsed)
				and visual.class_still_sprite().visible,
				"%s playback samples selected death3 atlas frame while visible" % skin_id)
			check(playback.active and visual.unit.alive
				and not board._view_corpses.any(func(corpse: Dictionary) -> bool: return int(corpse.get("source_unit_id", 0)) == target_id),
				"%s does not publish death before the death3 hold completes" % skin_id)
		var final_hold_steps := 0
		while playback.active and visual._skin_dying and visual.death_progress * visual.death_duration() < 3.65 and final_hold_steps < 100:
			if playback._tween != null and playback._tween.is_valid():
				playback._tween.pause()
				playback._tween.custom_step(0.05)
			await process_frame
			final_hold_steps += 1
		check(visual._skin_dying and visual.class_still_sprite().texture
			== visual.skin_definition.animations.get_frame_texture(&"death", 32)
			and playback.active and visual.unit.alive,
			"%s reaches and holds death3 final frame before publishing the corpse" % skin_id)
		await _drain_paused_player(playback, 220)
		var no_live_view_unit := not board._view_units.any(func(row: Dictionary) -> bool:
			return int(row.unit.id) == target_id and bool(row.unit.alive))
		check(no_live_view_unit and board._view_corpses.any(func(corpse: Dictionary) -> bool:
			return int(corpse.get("source_unit_id", 0)) == target_id)
			and not published.is_empty() and published.back() == after,
			"%s publishes the real death and after state only at normal completion" % skin_id)
		check(_snapshot(session) == committed, "%s death playback leaves battle snapshot/RNG unchanged" % skin_id)
		if is_instance_valid(visual):
			visual.reset_view_pose()
			visual.sync_scene_art()
			check(not visual._skin_dying and visual._skin_buff_elapsed < 0.0,
				"%s retained visual clears death pose on reset" % skin_id)
		else:
			check(board._presentation_visual(target_id) == null,
				"%s normal death completion retires its visual without a stale node" % skin_id)
		playback.queue_free()
		await _close_battle(fixture)
