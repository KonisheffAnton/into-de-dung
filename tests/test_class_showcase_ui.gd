extends SceneTree

const MENU_SCENE: PackedScene = preload("res://scenes/demo/main_menu.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/demo/battle/hero_hub_battle.tscn")

var passed: int = 0
var failed: int = 0
var viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CLASS SHOWCASE UI: " + label)

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var menu := MENU_SCENE.instantiate() as Control
	viewport.add_child(menu)
	await _settle(3)
	var owned_save := String(menu.get("save_path"))
	var continue_button := menu.get_node_or_null("CenterContainer/VBoxContainer/continue_game") as Button
	check(continue_button != null, "protected main menu exposes continue_game")
	if continue_button == null:
		menu.queue_free()
		await _settle(2)
		quit(1)
		return
	continue_button.pressed.emit()
	await _settle(6)
	var hub := menu.get_node_or_null("ExpeditionHub") as HeroHubScreen
	check(hub != null and hub.run != null, "real continue_game signal opens the campaign hub")
	if hub == null or hub.run == null:
		menu.queue_free()
		await _settle(2)
		quit(1)
		return
	check(hub.run.hero_catalog_version == 4, "main menu creates catalog4 profile")
	var party_classes: Dictionary = {}
	for hero_id: int in hub.run.party:
		var hero: HeroProgression = hub.run.heroes[hero_id]
		party_classes[hero.class_id] = int(party_classes.get(hero.class_id, 0)) + 1
	check(hub.run.party.size() == 3 and party_classes.size() == 3
		and party_classes.has(&"rogue") and party_classes.has(&"mage") and party_classes.has(&"fighter"),
		"new catalog defaults to Rogue, Mage and Fighter party")
	# Выбор носителя должен пройти через модальный UI и сохранить назначение до старта.
	hub._start_battle()
	await _settle(2)
	var host_dialog: HostPossessionDialog = hub._dashboard._host_dialog
	check(host_dialog.is_visible_in_tree(), "missing host opens the real possession dialog before expedition start")
	check(hub.battle_view == null and hub.run.expedition == null, "host selection is required before any expedition starts")
	var selected_host: int = hub.run.party[1] if hub.run.party.size() > 1 else hub.run.party[0]
	var host_button := host_dialog.get_node_or_null("Dialog/Content/Heroes/Hero%d" % selected_host) as Button
	check(host_button != null, "host dialog exposes the selected party member")
	if host_button != null: host_button.pressed.emit()
	(host_dialog.get_node("Dialog/Content/Actions/Confirm") as Button).pressed.emit()
	await _settle(3)
	check(int(hub.run.mage_deck.host_hero_id) == selected_host, "confirming the host dialog persists the chosen hero")
	# Проходим настоящий старт похода; на первом маршруте все варианты — боевые комнаты.
	hub._start_battle()
	await _settle(6)
	if hub.battle_view == null and hub.run.expedition != null and hub.run.expedition.phase == "route":
		var route_nodes := hub.run.expedition.available_nodes()
		var selected_node: int = route_nodes[0] if not route_nodes.is_empty() else 0
		var room_button := hub.find_child("room_%d" % selected_node, true, false) as Button
		check(room_button != null, "real first-room button is available after starting expedition")
		if room_button != null: room_button.pressed.emit()
		await _settle(8)
	check(hub.battle_view != null, "actual expedition transition opens the first tactical field")
	if hub.battle_view != null:
		var battle_result := _check_live_roster(hub.battle_view, hub.run)
		if not battle_result.is_empty():
			var board: BattleDemoBoard = battle_result.board
			var session: BattleCoreReactionsSession = battle_result.session
			var before_camera := _combat_values(session)
			if DisplayServer.get_name() != "headless":
				board.zoom_camera(1.0, board.size * 0.5)
				var mean_cell := Vector2.ZERO
				for unit: UnitState in session.units: mean_cell += Vector2(unit.cell)
				mean_cell /= float(maxi(1, session.units.size()))
				var mean_center := board.cell_center(Vector2i(roundi(mean_cell.x), roundi(mean_cell.y)))
				board.pan_camera(board.size * 0.5 - mean_center)
				await RenderingServer.frame_post_draw
				for visible_unit: UnitState in session.units:
					if visible_unit.archetype_id != TroglodyteKit.ID: continue
					var visual := board._presentation_visual(visible_unit.id)
					var screen_position := visual.get_global_transform_with_canvas().origin
					check(Rect2(70, 190, 1140, 480).has_point(screen_position), "new troglodyte appears inside the opening viewport away from HUD")
				var captures := _capture_directory()
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
				var image := viewport.get_texture().get_image()
				check(not image.is_empty() and image.save_png(captures.path_join("class-roster-facing.png")) == OK,
					"GPU screenshot captures all classes at 100% centered on mean actor cell")
				check(is_equal_approx(board.camera_view.zoom, 1.0),
					"showcase screenshot uses 100% board zoom")
			check(_combat_values(session) == before_camera, "camera and roster display do not change HP or battle state")
	menu.queue_free()
	await _settle(3)
	check(not FileAccess.file_exists(owned_save), "temporary main-menu save is cleaned up with the menu")
	await _test_single_party_mage_enemy()
	viewport.queue_free()
	await process_frame
	print("CLASS SHOWCASE UI RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_live_roster(view: HeroHubBattleView, profile: HeroHubState) -> Dictionary:
	var session := view.supplied_session
	var board := view.board_view
	check(session != null and board != null, "first tactical field owns its factory session and board")
	if session == null or board == null: return {}
	check(session.units.size() == 7 and session.actor_loadouts.size() == 7,
		"three class heroes, two missing classes and the named hobgoblin share one field")
	var counts: Dictionary = {}
	var enemy_count := 0
	var enemy_without_loadout := 0
	var hobgoblin_count := 0
	var expected_skins: Dictionary[StringName, StringName] = {
		&"shieldbearer": &"watch_shield", &"fighter": &"red_bastion",
		&"rogue": &"short_cape", &"mage": &"star_hood", &"archer": &"silver_ranger",
		&"sick_hobgoblin": &"sick_hobgoblin", &"tamed_troglodyte": &"tamed_troglodyte",
	}
	for unit: UnitState in session.units:
		var loadout: Dictionary = session.actor_loadouts.get(unit.id, {})
		var class_id: StringName = StringName(loadout.get("class_id", &""))
		check(class_id != &"", "every showcase actor has a class loadout")
		counts[class_id] = int(counts.get(class_id, 0)) + 1
		var visual := board._presentation_visual(unit.id)
		check(visual != null and visual.visual_class_id == class_id,
			"actor class identity reaches its board visual: " + String(class_id))
		var expected_skin := StringName(expected_skins.get(class_id, &""))
		var skin_visual := visual as BattleCharacterSkinVisual
		check(skin_visual != null and skin_visual.skin_definition != null
			and skin_visual.skin_definition.id == expected_skin,
			"five-class production roster uses its registered skin: " + String(class_id))
		if class_id == &"sick_hobgoblin":
			check(loadout.get("attack_id", &"") == MageDeckRules.hero_attack_id(unit.id)
				and session.unit_visual_classes.get(unit.id) == &"sick_hobgoblin",
				"named hobgoblin keeps its ordinary personal strike and visual class")
		if unit.faction != Faction.Type.ENEMY: continue
		enemy_count += 1
		if class_id == &"sick_hobgoblin": hobgoblin_count += 1
		if loadout.is_empty(): enemy_without_loadout += 1
		if visual == null: continue
		var presets := visual.get_node_or_null("ArtRoot/EnemyPresets")
		var presets_hidden := presets != null
		if presets != null:
			for node: Node in presets.get_children():
				if node is CanvasItem and (node as CanvasItem).visible: presets_hidden = false
		check(presets_hidden, "named class actor does not borrow an EnemyPreset: " + String(class_id))
	var expected: Array[StringName] = HeroCatalog.class_ids(4)
	var exactly_one_of_each := counts.size() == expected.size() + 2
	for class_id: StringName in expected:
		if int(counts.get(class_id, 0)) != 1: exactly_one_of_each = false
	check(enemy_count == 4 and enemy_without_loadout == 0, "two absent classes and two monsters carry their own enemy loadouts")
	check(hobgoblin_count == 1 and int(counts.get(&"sick_hobgoblin", 0)) == 1,
		"one named hobgoblin appears independently of the five hero classes")
	check(exactly_one_of_each, "all five hero class identities and two monsters appear exactly once")
	check(view.expedition_battle and profile.phase == "expedition" and profile.expedition.phase == "battle",
		"showcase is the selected expedition battle, without starting a new campaign mode")
	# У исходников разные направления; покой фигуры определяется её командой.
	for unit: UnitState in session.units:
		if unit.faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: continue
		var visual := board._presentation_visual(unit.id) as BattleCharacterSkinVisual
		if visual == null or visual.skin_definition == null: continue
		check(visual.get_authored_facing_x() == (1 if unit.faction == Faction.Type.PLAYER else -1),
			"skin source art faces its team side: " + String(visual.skin_definition.id))
	return {"session": session, "board": board}

func _test_single_party_mage_enemy() -> void:
	var profile := HeroHubState.create(9914, 4)
	profile.party.assign([5])
	check((profile.heroes[5] as HeroProgression).class_id == &"fighter", "single-party factory profile keeps Fighter as its only ally")
	check(profile.start_battle(), "single-party catalog4 factory fixture starts")
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "single-party factory adds four absent classes and the named hobgoblin")
	if bundle.is_empty(): return
	var session: BattleCoreReactionsSession = bundle.session
	var view := BATTLE_SCENE.instantiate() as HeroHubBattleView
	view.supplied_session = session
	view.character_skins = {}
	viewport.add_child(view)
	await _settle(6)
	var board := view.board_view
	var mage: UnitState = null
	for unit: UnitState in session.units:
		if unit.faction == Faction.Type.ENEMY and session.actor_loadouts.get(unit.id, {}).get("class_id", &"") == &"mage": mage = unit
	check(session.units.size() == 7 and session.actor_loadouts.size() == 7 and mage != null,
		"single Fighter party yields four absent hero classes and the named enemy")
	if mage != null and board != null:
		var visual := board._presentation_visual(mage.id)
		var body := visual.get_node_or_null("ArtRoot/BodySprite") as Sprite2D if visual != null else null
		var skin_visual := visual as BattleCharacterSkinVisual
		var selected: Sprite2D = skin_visual.class_still_sprite() if skin_visual != null else null
		var presets := visual.get_node_or_null("ArtRoot/EnemyPresets") if visual != null else null
		check(skin_visual != null and visual.visual_class_id == &"mage"
			and skin_visual.skin_definition != null and skin_visual.skin_definition.id == &"star_hood"
			and selected != null and selected.visible and body != null and not body.visible
			and visual._selected_body_node() == selected,
			"Mage uses star_hood while hiding legacy BodySprite")
		var all_presets_hidden := presets != null
		if presets != null:
			for node: Node in presets.get_children():
				if node is CanvasItem and (node as CanvasItem).visible: all_presets_hidden = false
		check(all_presets_hidden, "Mage fallback never selects a random EnemyPreset")
		if visual != null:
			var enemy_body_facing := signf(selected.transform.x.x) if selected != null else 0.0
			check(enemy_body_facing < 0.0, "Mage skin faces left on the enemy team")
			visual.presentation_facing_x = 1
			var attack_body_facing := signf(selected.transform.x.x) if selected != null else 0.0
			var attack_pose := Transform2D.IDENTITY
			if selected != null: attack_pose = selected.transform
			check(attack_body_facing > 0.0, "Mage skin temporarily faces right toward its target")
			visual.sync_scene_art()
			visual.sync_scene_art()
			check(selected != null and selected.transform.is_equal_approx(attack_pose)
				and visual.visual_class_id == &"mage",
				"Mage temporary facing survives repeated art sync")
			visual.presentation_facing_x = 0
			check(selected != null and signf(selected.transform.x.x) < 0.0,
				"Mage facing reset restores enemy-left orientation")
			# Проверяем повторное использование узла после анонимного NPC: класс Mage
			# должен выключить случайный preset и сохранить нейтральный силуэт.
			visual.visual_class_id = &""
			visual.sync_scene_art()
			var no_class_has_no_skin_sprite := selected == null or not selected.visible
			visual.visual_class_id = &"mage"
			visual.sync_scene_art()
			check(no_class_has_no_skin_sprite and selected != null and selected.visible
				and body != null and not body.visible and visual.visual_class_id == &"mage"
				and visual._selected_body_node() == selected,
				"reused NPC visual restores star_hood without exposing Mage fallback or random preset")
	view._join_execution()
	viewport.remove_child(view)
	view.queue_free()
	session.close()
	await process_frame

func _combat_values(session: BattleCoreReactionsSession) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for unit: UnitState in session.units:
		values.append({"id": unit.id, "faction": int(unit.faction), "hp": unit.vitals.get_hp(), "alive": unit.is_alive(), "cell": unit.cell})
	return values

func _capture_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): return argument.trim_prefix("--captures=")
	return "user://class-roster-facing-captures"

func _settle(frames: int) -> void:
	for _frame: int in frames: await process_frame
