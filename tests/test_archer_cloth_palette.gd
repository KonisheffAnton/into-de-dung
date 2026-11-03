extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const CURRENT_BATTLE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")
const ArcherClothRenderProbe = preload("res://tests/fixtures/archer_cloth_render_probe.gd")
const ARCHER_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/archer_idle_v1/idle_frames.tres")

var passed: int = 0
var failed: int = 0
var captures: String = ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ARCHER CLOTH PALETTE: " + label)


func _run() -> void:
	# Здесь проверяется только legacy-палитра Арчера; новая skin-модель тестируется отдельно.
	CharacterSkinCatalog._loaded[&"silver_ranger"] = null
	var visual := UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
	root.add_child(visual)
	await process_frame
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 32.0
	config.origin_offset = Vector2(320.0, 48.0)
	check(visual.apply_view(_values(&"archer", Faction.Type.PLAYER), config), "allied Archer fixture applies")
	visual.set_process(false)
	var still := visual.get_node("ArtRoot/PlayerArcherSprite") as Sprite2D
	var enemy := visual.get_node("ArtRoot/EnemyArcherSprite") as Sprite2D
	var idle := visual.get_node("ArtRoot/ArcherIdleSprite") as Sprite2D
	var ids := [still.material.get_instance_id(), enemy.material.get_instance_id(), idle.material.get_instance_id()]
	check(ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2],
		"each Archer still and idle layer owns a separate material")
	var enemy_visual := UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
	root.add_child(enemy_visual)
	check(enemy_visual.apply_view(_values(&"archer", Faction.Type.ENEMY), config), "separate enemy Archer applies")
	enemy_visual.set_cloth_palette(3)
	var enemy_instance_still := enemy_visual.get_node("ArtRoot/EnemyArcherSprite") as Sprite2D
	check(enemy_instance_still.material.get_instance_id() != enemy.material.get_instance_id()
		and not bool((enemy_instance_still.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
		"enemy instance material is isolated and remains unrecolored under allied palette")
	enemy_visual.queue_free()
	check(ArcherClothPalette.mask_slot(still.texture) == 0, "still texture maps to slot zero")
	check(ArcherClothPalette.mask_slot(AtlasTexture.new()) == -1
		and ArcherClothPalette.mask_slot(ImageTexture.new()) == -1,
		"unsupported AtlasTexture and pathless texture never receive a mask slot")
	visual.set_cloth_palette(3)
	check(_mask_matches(still) and _mask_matches(idle), "allied still and idle use their matching cloth masks")
	check(bool((enemy.material as ShaderMaterial).get_shader_parameter("cloth_enabled")),
		"hidden enemy-side layer inside the allied Archer keeps its class material palette")
	check((idle.material as ShaderMaterial).get_shader_parameter("brighter_palette_strength") == 1.0,
		"palette preserves authored brighter strength")
	var elapsed := visual.idle_clock.get_elapsed()
	var frame_index := visual.idle_clock.get_frame_index()
	var current_idle_texture := idle.texture
	visual.set_cloth_palette(4)
	check(idle.texture == current_idle_texture and visual.idle_clock.get_elapsed() == elapsed
		and visual.idle_clock.get_frame_index() == frame_index,
		"changing palette preserves current idle frame and phase")
	visual.set_cloth_palette(3)
	for frame: int in ARCHER_IDLE.get_frame_count(&"idle"):
		var texture := ARCHER_IDLE.get_frame_texture(&"idle", frame)
		check(ArcherClothPalette.mask_slot(texture) == frame, "idle frame maps to mask slot " + str(frame))
		visual._apply_clip_frame(ARCHER_IDLE, &"idle", (float(frame) * 13.0 + 6.5) / 60.0)
		check(idle.texture == texture and _mask_matches(idle), "sampled frame " + str(frame + 1) + " matches its mask")
	check(visual.idle_clock.get_elapsed() == elapsed and visual.idle_clock.get_frame_index() == frame_index,
		"palette and frame-mask sync preserve the idle clock")
	visual.archer_idle_frames = null
	visual.sync_scene_art()
	check(still.visible and not idle.visible, "missing animation falls back to still while selected palette applies")
	check(_mask_matches(still), "still fallback retains slot-zero mask")
	visual.archer_idle_frames = ARCHER_IDLE
	visual.sync_scene_art()
	var warrior := _values(&"warrior", Faction.Type.PLAYER)
	check(visual.apply_view(warrior, config) and not _cloth_enabled_for_archer(visual),
		"switching to another class disables all obsolete Archer layers")
	check(visual.apply_view(_values(&"archer", Faction.Type.ENEMY), config) and not _cloth_enabled_for_archer(visual),
		"faction switch to enemy disables Archer recoloring")
	check(visual.apply_view(_values(&"archer", Faction.Type.PLAYER), config) and _mask_matches(idle),
		"returning to allied Archer reapplies selected cloth palette")
	var original := visual.get_node("ArtRoot/PlayerArcherSprite") as Sprite2D
	var original_material := original.material as ShaderMaterial
	visual.set_cloth_palette(0)
	check(not _cloth_enabled_for_archer(visual) and original_material.get_shader_parameter("cloth_enabled") == false,
		"choice zero disables recoloring exactly")
	var old_texture := original.texture
	original.texture = GradientTexture2D.new()
	visual.set_cloth_palette(3)
	check(not bool(original_material.get_shader_parameter("cloth_enabled")), "unknown texture path disables mask safely")
	original.texture = old_texture
	visual.set_cloth_palette(3)
	check(_mask_matches(original), "restored known texture restores mask")
	visual.queue_free()
	await process_frame
	await _check_shared_selector()
	if DisplayServer.get_name() != "headless":
		var render_result: Dictionary = await ArcherClothRenderProbe.run(self, captures)
		passed += int(render_result.get("passed", 0))
		failed += int(render_result.get("failed", 0))
	print("ARCHER CLOTH PALETTE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _check_shared_selector() -> void:
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
	var archer: BattleDefenderIdleVisual
	for item: BattleManagedUnitVisual in demo.board_view._unit_visuals.values():
		if item.unit.alive and item.unit.faction == Faction.Type.PLAYER and item.visual_class_id == &"archer":
			archer = item as BattleDefenderIdleVisual
			break
	check(archer != null, "seeded HeroHub battle contains allied Archer")
	var selector := demo._cloth_palette as OptionButton
	check(selector != null and selector.get_item_count() == 7 and selector.selected == 0,
		"Archer uses the established seven-choice shared HUD selector")
	if archer != null and selector != null:
		var before := _snapshot(session)
		selector.select(4)
		selector.item_selected.emit(4)
		var idle := archer.get_node("ArtRoot/ArcherIdleSprite") as Sprite2D
		check(archer.cloth_palette == 4 and _mask_matches(idle), "shared HUD choice applies to allied Archer")
		check(_snapshot(session) == before, "HUD palette choice preserves battle state, RNG and counters")
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			await process_frame
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(captures.path_join("archer-cloth-battle.png")) == OK,
				"capture selected Archer palette in the real HeroHub battle")
		selector.select(0)
		selector.item_selected.emit(0)
		check(not _cloth_enabled_for_archer(archer), "shared HUD reset restores original Archer colors")
	demo.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame


func _values(class_id: StringName, faction: Faction.Type) -> Dictionary:
	var statuses: Array[Dictionary] = []
	return {"cell": Vector2i(2, 3), "half_steps": 0,
		"unit": {"id": 73, "faction": int(faction), "name": "Лучник", "alive": true,
			"hp": 12.0, "hp_max": 18.0, "balance": 2.0, "balance_max": 4.0},
		"visual_class_id": class_id, "selected": false, "inspected": false, "hovered": false,
		"acting": false, "show_rear": false, "summon_pending": false, "forecast_entry": {},
		"armor_values": {"current": 0.0, "maximum": 0.0}, "shield_view": {},
		"raised_shield_view": {"active": false}, "reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0}, "status_entries": statuses}


func _mask_matches(sprite: Sprite2D) -> bool:
	var slot := ArcherClothPalette.mask_slot(sprite.texture)
	var material := sprite.material as ShaderMaterial
	return slot >= 0 and material != null and bool(material.get_shader_parameter("cloth_enabled")) \
		and material.get_shader_parameter("cloth_mask_origin") == ArcherClothPalette.mask_origin(slot) \
		and material.get_shader_parameter("cloth_masks") == ArcherClothPalette.MASKS


func _cloth_enabled_for_archer(visual: BattleDefenderIdleVisual) -> bool:
	for path: String in ["ArtRoot/PlayerArcherSprite", "ArtRoot/EnemyArcherSprite", "ArtRoot/ArcherIdleSprite"]:
		var material := (visual.get_node(path) as Sprite2D).material as ShaderMaterial
		if bool(material.get_shader_parameter("cloth_enabled")): return true
	return false


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(), "counters": session.context.simulation_counters(),
		"revision": session.context.get_revision(), "phase": session.phase}
