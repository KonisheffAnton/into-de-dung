extends SceneTree

const CURRENT_BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const RogueClothRenderProbe = preload("res://tests/fixtures/rogue_cloth_render_probe.gd")
const ROGUE_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/idle_frames.tres")
const ROGUE_BUFF: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/buff_frames.tres")
const ROGUE_DEATH: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/death_frames.tres")

var passed: int = 0
var failed: int = 0
var captures: String = ""


func _initialize() -> void:
	# Старые маски проверяются на fallback-модели; новый облик сохраняет исходный RGB.
	CharacterSkinCatalog._loaded[&"short_cape"] = null
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ROGUE CLOTH PALETTE: " + label)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var profile := HeroHubState.create(9404)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var session := HeroHubBattleFactory.create(profile).session as BattleCoreReactionsSession
	var demo := CURRENT_BATTLE.instantiate() as HeroHubBattleView
	demo.expedition_battle = true
	demo.supplied_session = session
	viewport.add_child(demo)
	demo.set_process(false)
	await process_frame
	await process_frame
	var rogue := _find_rogue(demo, Faction.Type.PLAYER)
	var enemy := _find_rogue(demo, Faction.Type.ENEMY)
	check(rogue != null, "real HeroHub battle includes an allied Rogue")
	if enemy == null:
		enemy = UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
		viewport.add_child(enemy)
		var config := IsoGridConfig.new()
		config.tile_size = Vector2(128.0, 96.0)
		config.height_step = 32.0
		config.origin_offset = Vector2(320.0, 48.0)
		enemy.apply_view(_view_values(&"rogue", 87, Faction.Type.ENEMY), config)
		# Дополнительный враг проверяет изоляцию материалов, но не принадлежит полю похода.
		enemy.hide()
	check(enemy != null, "enemy Rogue fixture is available for material isolation")
	if rogue != null:
		_check_selector_and_resources(demo, rogue, enemy)
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			await process_frame
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(captures.path_join("rogue-cloth-battle.png")) == OK,
				"capture selected Rogue palette in the real HeroHub battle")
		_check_animation_slots(rogue)
		_check_runtime_switches(demo, rogue, session)
		_check_detached_setter(demo, rogue, session)
	if DisplayServer.get_name() != "headless":
		var result: Dictionary = await RogueClothRenderProbe.run(self, captures)
		passed += int(result.get("passed", 0))
		failed += int(result.get("failed", 0))
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("ROGUE CLOTH PALETTE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find_rogue(demo: HeroHubBattleView, faction: Faction.Type) -> BattleDefenderIdleVisual:
	for item: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		if item.unit.alive and item.unit.faction == faction and item.visual_class_id == &"rogue":
			return item as BattleDefenderIdleVisual
	return null


func _check_selector_and_resources(demo: HeroHubBattleView, rogue: BattleDefenderIdleVisual,
		enemy: BattleDefenderIdleVisual) -> void:
	var selector := demo._cloth_palette
	check(selector != null and selector.get_item_count() == 7 and selector.selected == 0
		and selector.get_signal_connection_list(&"item_selected").size() == 1,
		"existing selector retains seven default choices and one signal")
	if selector == null or enemy == null: return
	for index: int in DefenderClothPalette.count():
		check(selector.get_item_text(index) == "Одежда: " + DefenderClothPalette.label(index),
			"shared label remains " + str(index))
	var paths: Array[String] = ["ArtRoot/PlayerRogueSprite", "ArtRoot/EnemyRogueSprite", "ArtRoot/RogueIdleSprite"]
	var material_ids: Array[int] = []
	for path: String in paths:
		var sprite := rogue.get_node(path) as Sprite2D
		check(sprite.material is ShaderMaterial, "rogue sprite owns shader material " + path)
		material_ids.append(sprite.material.get_instance_id())
	check(material_ids.size() == 3 and material_ids[0] != material_ids[1]
		and material_ids[0] != material_ids[2] and material_ids[1] != material_ids[2],
		"each rogue sprite gets its own duplicated material")
	var enemy_still := enemy.get_node("ArtRoot/EnemyRogueSprite") as Sprite2D
	check((rogue.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D).material != enemy_still.material,
		"PackedScene material is isolated between unit instances")
	selector.select(3)
	selector.item_selected.emit(3)
	var still := rogue.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var slot := RogueClothPalette.mask_slot(still.texture)
	check(demo.board_view.defender_cloth_palette == 3 and rogue.cloth_palette == 3
		and slot == -1 and _original_palette(still), "selection is stored but new rogue retains original colors")
	var idle := rogue.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	check(_original_palette(idle), "unselected idle has no old clothing mask")
	check(not _any_cloth_enabled(enemy), "enemy rogue remains original under allied selection")


func _check_animation_slots(visual: BattleDefenderIdleVisual) -> void:
	# Архивные маски сохраняют таблицу; новая геометрия не заимствует их координаты.
	var expected_slot := 1
	for animation: StringName in [&"idle", &"buff", &"death"]:
		var frames := ROGUE_IDLE if animation == &"idle" else (ROGUE_BUFF if animation == &"buff" else ROGUE_DEATH)
		for frame: int in frames.get_frame_count(animation):
			check(RogueClothPalette.mask_slot(frames.get_frame_texture(animation, frame)) == expected_slot,
				"legacy rogue atlas retains slot " + str(expected_slot))
			expected_slot += 1
	check(expected_slot == 32, "all 31 legacy animation slots retained")
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	for frame: int in 17:
		visual.sample_death((float(frame) * 0.15 + 0.075) / 3.60)
		check(idle.texture == visual.rogue_death_frames.get_frame_texture(&"death", frame)
			and RogueClothPalette.mask_slot(idle.texture) == -1 and _original_palette(idle),
			"new death frame is shown without old mask " + str(frame))
	visual.reset_view_pose()


func _check_runtime_switches(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual,
		session: BattleCoreReactionsSession) -> void:
	var baseline := _snapshot(session)
	var still := visual.get_node("ArtRoot/PlayerRogueSprite") as Sprite2D
	var idle := visual.get_node("ArtRoot/RogueIdleSprite") as Sprite2D
	visual.set_process(false)
	visual.sample_buff(0.35)
	var buff_texture := idle.texture
	var buff_elapsed := visual._buff_elapsed
	demo.board_view.set_defender_cloth_palette(4)
	check(idle.texture == buff_texture and visual._buff_elapsed == buff_elapsed and _original_palette(idle),
		"selection during generic guard preserves texture and elapsed time")
	visual.clear_buff()
	visual.sample_death(0.8)
	visual.sync_scene_art()
	var death_texture := idle.texture
	var death_alpha := idle.self_modulate.a
	var progress := visual.death_progress
	demo.board_view.set_defender_cloth_palette(5)
	check(idle.texture == death_texture and visual.death_progress == progress
		and idle.self_modulate.a == death_alpha and _original_palette(idle),
		"selection at death progress 0.8 preserves frame, progress, and fade alpha")
	visual.death_progress = 0.0
	visual.reset_view_pose()
	var size := demo.board_view.size
	demo.board_view.refresh()
	demo.board_view.size = size + Vector2(11.0, 7.0)
	demo.board_view._rescale_layout()
	check(demo.board_view.defender_cloth_palette == 5 and _original_palette(still),
		"reset, resize, and republish preserve allied rogue selection")
	demo.board_view.size = size
	demo.board_view._rescale_layout()
	var old_texture := still.texture
	still.texture = GradientTexture2D.new()
	visual.set_cloth_palette(5)
	check(not bool((still.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
		"unknown rogue texture safely disables mask")
	still.texture = old_texture
	visual.set_cloth_palette(5)
	check(_original_palette(still), "new rogue still keeps original colors after unknown texture")
	var mage_values := _view_values(&"mage", 41)
	check(visual.apply_view(mage_values, visual.grid_config) and not idle.visible
		and not _any_cloth_enabled_for_rogue(visual), "class switch hides and disables obsolete rogue artwork")
	var warrior_values := _view_values(&"warrior", 41)
	check(visual.apply_view(warrior_values, visual.grid_config) and not _any_cloth_enabled_for_rogue(visual)
		and _defender_mask_matches(visual.get_node("ArtRoot/DefenderIdleSprite") as Sprite2D),
		"warrior class receives its own mask and leaves every Rogue layer disabled")
	var rogue_values := _view_values(&"rogue", 41)
	check(visual.apply_view(rogue_values, visual.grid_config) and not idle.visible and still.visible and _original_palette(still),
		"return to rogue keeps selected colors and static model")
	var enemy_values := _view_values(&"rogue", 41, Faction.Type.ENEMY)
	check(visual.apply_view(enemy_values, visual.grid_config) and not _any_cloth_enabled_for_rogue(visual),
		"faction change disables every Rogue clothing mask")
	check(visual.apply_view(rogue_values, visual.grid_config) and _original_palette(still),
		"allied faction retains original new Rogue colors")
	visual.role = BattleDemoIsoVisual.Role.FLOOR
	visual.sync_scene_art()
	check(not _any_cloth_enabled_for_rogue(visual), "non-unit role disables every Rogue clothing mask")
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.sync_scene_art()
	check(_snapshot(session) == baseline, "selection, playback, and class switches preserve battle state and RNG")


func _check_detached_setter(demo: HeroHubBattleView, visual: BattleDefenderIdleVisual,
		session: BattleCoreReactionsSession) -> void:
	var baseline := _snapshot(session)
	demo.board_view.session = null
	demo.board_view.execution_pending = true
	demo.board_view.set_defender_cloth_palette(6)
	check(demo.board_view.defender_cloth_palette == 6 and visual.cloth_palette == 6,
		"setter remains safe after session detaches")
	check(_snapshot(session) == baseline, "detached setter leaves core state, RNG, and counters unchanged")
	demo.board_view.execution_pending = false
	demo.board_view.session = session


func _view_values(class_id: StringName, unit_id: int, faction: Faction.Type = Faction.Type.PLAYER) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {"cell": Vector2i(2, 3), "half_steps": 0,
		"unit": {"id": unit_id, "faction": int(faction), "name": "Разбойник", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": class_id, "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false,
		"forecast_entry": {}, "armor_values": {"current": 0.0, "maximum": 0.0}, "shield_view": {},
		"raised_shield_view": {"active": false}, "reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}


func _original_palette(sprite: Sprite2D) -> bool:
	var material := sprite.material as ShaderMaterial
	return material != null and not bool(material.get_shader_parameter("cloth_enabled")) \
		and is_zero_approx(float(material.get_shader_parameter("brighter_palette_strength")))


func _defender_mask_matches(sprite: Sprite2D) -> bool:
	var slot := DefenderClothPalette.mask_slot(sprite.texture)
	var material := sprite.material as ShaderMaterial
	return slot >= 0 and material != null and bool(material.get_shader_parameter("cloth_enabled")) \
		and material.get_shader_parameter("cloth_mask_origin") == DefenderClothPalette.mask_origin(slot)


func _any_cloth_enabled(visual: BattleDefenderIdleVisual) -> bool:
	return _any_cloth_enabled_for_rogue(visual)


func _any_cloth_enabled_for_rogue(visual: BattleDefenderIdleVisual) -> bool:
	for path: String in ["ArtRoot/PlayerRogueSprite", "ArtRoot/EnemyRogueSprite", "ArtRoot/RogueIdleSprite"]:
		var sprite := visual.get_node(path) as Sprite2D
		if bool((sprite.material as ShaderMaterial).get_shader_parameter("cloth_enabled")): return true
	return false
