extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const TILE_SCENE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL TAMED TROGLODYTE VISUAL: " + label)

func _visual(id: int, faction: Faction.Type, kind: StringName = &"tamed_troglodyte") -> BattleCharacterSkinVisual:
	var visual := UNIT_SCENE.instantiate() as BattleCharacterSkinVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.show_ground_shadow = true
	viewport.add_child(visual)
	var statuses: Array[Dictionary] = []
	var values := {
		"cell": Vector2i(1, 1), "half_steps": 0,
		"unit": {"id": id, "faction": int(faction), "name": "Прирученный троглодит", "alive": true,
			"hp": 24.0, "hp_max": 24.0, "balance": 0.0, "balance_max": 4.0},
		"visual_class_id": kind, "visual_skin_id": CharacterSkinCatalog.resolve_id(kind),
		"selected": false, "inspected": false, "hovered": false, "acting": false,
		"forecast_entry": {}, "show_rear": false, "summon_pending": false,
		"armor_values": {}, "shield_view": {}, "raised_shield_view": {},
		"reaction_view": {}, "action_resources_view": {}, "status_entries": statuses
	}
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(128, 64)
	check(visual.apply_view(values, config), "real visual accepts the enemy skin")
	visual.set_process(false)
	return visual

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 340)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	check(CharacterSkinCatalog.ids(&"tamed_troglodyte") == [&"tamed_troglodyte"], "catalog registers a separate enemy identity")
	check(CharacterSkinCatalog.normalized({}).size() == 5 and not CharacterSkinCatalog.normalized({}).has(&"tamed_troglodyte"),
		"enemy identity stays outside the five hero cosmetics")
	var definition := CharacterSkinCatalog.definition(&"tamed_troglodyte", &"tamed_troglodyte")
	check(definition != null, "approved skin resource resolves")
	if definition == null:
		print("TAMED TROGLODYTE VISUAL RESULTS: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(definition.display_name == "Прирученный троглодит" and definition.class_id == &"tamed_troglodyte",
		"enemy has its own display name and class id")
	check(definition.animations.get_frame_count(&"idle") == 33
		and definition.animations.get_frame_count(&"idle_secondary") == 33
		and definition.animations.get_frame_count(&"buff") == 33
		and definition.animations.get_frame_count(&"death") == 33,
		"all authored clips contain 33 frames")
	check(definition.ambient_buff_interval == 0.0, "buff remains an active ability only")
	var enemy := _visual(81721, Faction.Type.ENEMY)
	var sprite := enemy.class_still_sprite()
	var unit_view := enemy.unit
	var view_before := {"id": unit_view.id, "faction": unit_view.faction, "alive": unit_view.alive,
		"hp": unit_view.hp, "balance": unit_view.balance}
	check(enemy.skin_definition == definition and sprite != null, "real visual selects the resource")
	if sprite != null:
		check(enemy.get_authored_facing_x() == -1 and sprite.scale == Vector2(0.5, 0.5),
			"enemy keeps the authored left facing without an unnecessary mirror")
	check(enemy.get_unit_pick_rect() == Rect2(-37, -40, 74, 50), "lowered stocky silhouette keeps its claws inside the pick area")
	var warrior := _visual(81722, Faction.Type.PLAYER, &"fighter")
	var player_troglodyte := _visual(81723, Faction.Type.PLAYER)
	var player_sprite := player_troglodyte.class_still_sprite()
	check(player_troglodyte.get_authored_facing_x() == 1 and player_sprite != null
		and player_sprite.scale == Vector2(-0.5, 0.5), "player faction mirrors the authored left facing")
	var warrior_skin := CharacterSkinCatalog.definition(&"fighter", &"red_bastion")
	check(warrior_skin != null and definition.still.get_image().get_used_rect().size.y
		< warrior_skin.still.get_image().get_used_rect().size.y * 0.7,
		"native body height is about two thirds of the fighter")
	check(warrior.get_unit_art_scale() == enemy.get_unit_art_scale(), "troglodyte retains the shared scene art scale")
	_check_ground_contacts(enemy)
	_check_ground_contacts(player_troglodyte)
	var rest_shadow := enemy._ground_shadow.transform
	enemy.sync_scene_art()
	check(enemy._ground_shadow.transform == rest_shadow, "repeated sync does not accumulate shadow scaling")
	enemy.action_offset = Vector2(7, -4)
	enemy.sync_scene_art()
	check(enemy._ground_shadow.transform == rest_shadow, "body action does not drag the contact shadow")
	enemy.action_offset = Vector2.ZERO
	enemy.sync_scene_art()
	enemy.grid_config.tile_size.y = 96
	enemy.half_steps = 1
	enemy.sync_scene_art()
	_check_ground_contacts(enemy)
	enemy.grid_config.tile_size.y = 64
	enemy.half_steps = 0
	enemy.sync_scene_art()
	var clock := enemy.skin_clock
	check(clock._normal_cycles >= 3 and clock._normal_cycles <= 6, "secondary idle waits three to six main cycles")
	clock.secondary = true
	clock.elapsed = 0.0
	enemy._draw_skin_idle()
	check(sprite.texture == definition.animations.get_frame_texture(&"idle_secondary", 0), "rare idle selects its own first atlas frame")
	clock.secondary = false
	clock.elapsed = 0.0
	var idle_phase := clock.elapsed
	enemy._draw_skin_idle()
	check(sprite.texture == definition.animations.get_frame_texture(&"idle", 0) and clock.elapsed == idle_phase,
		"main idle draws without changing its local clock")
	var buff_elapsed := definition.clip_duration(&"buff") * 0.5
	enemy.sample_buff(buff_elapsed)
	check(sprite.texture == definition.animations.get_frame_texture(&"buff", 16), "active buff samples the selected roar clip")
	enemy._skin_ambient_elapsed = 0.25
	enemy.sample_buff(0.0)
	check(enemy._skin_ambient_elapsed < 0.0, "an active ability cancels any ambient presentation state")
	enemy.sample_death(1.0)
	check(sprite.texture == definition.animations.get_frame_texture(&"death", 32), "death route holds the authored final frame")
	enemy.reset_view_pose()
	check(not enemy._skin_dying and enemy._skin_buff_elapsed < 0.0, "pose reset clears death and ability routes")
	check(unit_view.id == view_before["id"] and unit_view.faction == view_before["faction"]
		and unit_view.alive == view_before["alive"] and unit_view.hp == view_before["hp"]
		and unit_view.balance == view_before["balance"], "visual routes leave the runtime unit view unchanged")
	if DisplayServer.get_name() != "headless":
		warrior.position = Vector2(180, 270); enemy.position = Vector2(450, 270); player_troglodyte.position = Vector2(720, 270)
		for visual: BattleCharacterSkinVisual in [warrior, enemy, player_troglodyte]:
			_add_tile(visual.position, visual.grid_config)
			visual.scale = Vector2(2, 2)
			visual.set_process(false)
		player_troglodyte.sample_buff(buff_elapsed)
		var labels := ["Воин", "Троглодит · ожидание", "Троглодит · рёв Р2"]
		var label_nodes: Array[Label] = []
		for i: int in labels.size():
			var label := Label.new(); label.text = labels[i]; label.position = Vector2(90 + i * 270, 294)
			viewport.add_child(label)
			label_nodes.append(label)
		await process_frame
		await RenderingServer.frame_post_draw
		var captures := "user://troglodyte-captures"
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
		DirAccess.make_dir_recursive_absolute(captures)
		check(viewport.get_texture().get_image().save_png(captures.path_join("troglodyte-warrior-runtime.png")) == OK, "GPU comparison at equal integer display enlargement")
		# На той же земле отдельно проверяем возврат рёва и лежащий финал выбранной С2.
		enemy.sample_death(1.0)
		player_troglodyte.clear_buff()
		label_nodes[1].text = "Троглодит · смерть С2"
		label_nodes[2].text = "Троглодит · ожидание"
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png(captures.path_join("troglodyte-c2-grounded.png")) == OK, "C2 final corpse keeps the same ground support")
	enemy.retire_view()
	warrior.retire_view()
	player_troglodyte.retire_view()
	viewport.queue_free()
	await process_frame
	print("TAMED TROGLODYTE VISUAL RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _add_tile(at: Vector2, config: IsoGridConfig) -> void:
	var tile := TILE_SCENE.instantiate() as BattleTerrainVisual
	viewport.add_child(tile)
	viewport.move_child(tile, 0)
	tile.apply_view({"cell": Vector2i.ZERO, "role": BattleDemoIsoVisual.Role.FLOOR,
		"half_steps": 0, "is_void": false, "reachable": false, "enemy_range": false, "burning": false}, config)
	tile.position = at
	tile.scale = Vector2(2, 2)

func _check_ground_contacts(visual: BattleCharacterSkinVisual) -> void:
	var shadow := visual._ground_shadow
	var sprite := visual.class_still_sprite()
	check(shadow.visible and shadow.position == visual.get_visual_offset(), "shadow stays on the actual cell support")
	# Три разнесённые опоры исходной позы: передние когти и дальняя лапа.
	for contact: Vector2 in [Vector2(66, 188), Vector2(125, 200), Vector2(189, 185)]:
		var local_contact := shadow.to_local(sprite.to_global(contact))
		check(local_contact.length() <= visual.ground_shadow_radius, "authored paw contacts fit the contact shadow for both facings")
	var front := visual.to_local(sprite.to_global(Vector2(125, 200)))
	check(front.y > visual.get_visual_offset().y + 5.0 and front.y < visual.get_visual_offset().y + 9.0,
		"nearest paw sits on the front half of the tile rather than its rear edge")
