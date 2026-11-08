extends SceneTree

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport


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
		printerr("FAIL BATTLE CONDITION ICONS: " + label)


func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	return {
		"state": ItemSimulationSnapshot.capture(session.state, []).snapshot.to_dict(),
		"rng": session.context.get_rng().to_dict(),
		"counters": session.context.simulation_counters(),
	}


func _run() -> void:
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
	_test_catalogue()
	_test_cell_projection()
	await _test_battle_ui()
	await _capture_contact_sheet()
	print("BATTLE CONDITION ICONS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_catalogue() -> void:
	check(BattleConditionIcons.IDS.size() == 24, "catalogue contains the selected 24 IDs")
	for icon_id: StringName in BattleConditionIcons.IDS:
		for pixels: int in [16, 32]:
			var icon: Texture2D = BattleConditionIcons.texture(icon_id, pixels, false)
			check(icon != null, "%s %dpx texture loads" % [String(icon_id), pixels])
			if icon == null:
				continue
			check(icon.get_size() == Vector2(pixels, pixels), "%s texture is native %dpx" % [String(icon_id), pixels])
			var image := icon.get_image()
			var source := Image.new()
			var decode_error := source.load_png_from_buffer(FileAccess.get_file_as_bytes(icon.resource_path))
			if decode_error != OK:
				check(false, "source PNG decodes for exact import comparison")
				continue
			image.convert(Image.FORMAT_RGBA8)
			source.convert(Image.FORMAT_RGBA8)
			check(image.get_data() == source.get_data(), "%s %dpx import preserves exact source RGBA" % [String(icon_id), pixels])
			var clear_border := true
			for offset: int in pixels:
				if image.get_pixel(offset, 0).a != 0.0 or image.get_pixel(offset, pixels - 1).a != 0.0:
					clear_border = false
				if image.get_pixel(0, offset).a != 0.0 or image.get_pixel(pixels - 1, offset).a != 0.0:
					clear_border = false
			check(clear_border, "%s %dpx texture has transparent outer rows and columns" % [String(icon_id), pixels])
			var framed := BattleConditionIcons.texture(icon_id, pixels)
			check(framed != null and framed.get_size() == icon.get_size(), "%s framed icon keeps native dimensions" % String(icon_id))
			var framed_image := framed.get_image()
			var panel := (load("res://assets/art_presets/approved/status_icons_framed_v1/frame-%d.png" % pixels) as Texture2D).get_image()
			framed_image.convert(Image.FORMAT_RGBA8)
			panel.convert(Image.FORMAT_RGBA8)
			panel.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
			check(framed_image.get_data() == panel.get_data(), "%s framed image is exactly unchanged A over the wooden panel" % String(icon_id))
			check(framed_image.get_pixel(pixels >> 1, pixels >> 1).a == 1.0, "wooden center is opaque")
	check(BattleConditionIcons.texture(&"../bleeding") == null, "path-like unknown ID cannot load a texture")
	check(BattleConditionIcons.texture(&"bleeding/../../project.godot") == null, "traversal ID cannot load a texture")
	check(BattleConditionIcons.bbcode(&"unknown").is_empty(), "unknown ID creates no BBCode")
	check(BattleConditionIcons.bbcode(&"bleeding", 1).begins_with("[img=16x16]"), "BBCode display size clamps to 16px")
	check(BattleConditionIcons.bbcode(&"bleeding", 99).begins_with("[img=32x32]"), "BBCode display size clamps to 32px")
	var inline := BattleConditionIcons.inline_icons([&"bleeding", &"poison", &"bleeding", &"unknown"])
	check(inline.count("[img=") == 2 and inline.find("bleeding") < inline.find("poison"), "inline icons deduplicate valid IDs and preserve order")
	check(not inline.begins_with(" ") and not inline.ends_with(" "), "inline icon run has no outer spacing")
	check(BattleConditionPresentation.reaction_icon({"mode": CombatPerksState.Mode.OPPORTUNIST}) == &"opportunist", "opportunist mode maps to its icon")
	check(BattleConditionPresentation.reaction_icon({"mode": CombatPerksState.Mode.COUNTERATTACK}) == &"counterattack", "counterattack mode maps to its icon")
	check(BattleConditionPresentation.reaction_icon({"mode": CombatPerksState.Mode.COVER}) == &"cover", "cover mode maps to its icon")
	check(BattleConditionPresentation.reaction_icon({"mode": 0}).is_empty(), "inactive mode has no reaction icon")


func _cell_ids(entries: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in entries:
		ids.append(StringName(entry.get("id", &"")))
	return ids


func _test_cell_projection() -> void:
	var board := BattleDemoBoard.new()
	board._view_width = 8
	board._view_height = 8
	board._view_terrain.resize(64)
	board._view_terrain.fill(TerrainType.Type.FLOOR)
	board._view_fires = [{"cell": Vector2i(0, 0), "effect": "burning"}]
	var hazards := BattleHazards.empty()
	hazards.acid = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	check(BattleHazards.add_trap(hazards, Vector2i(4, 0), "wall", Vector2i.RIGHT), "valid first wall trap on shared cell")
	check(BattleHazards.add_trap(hazards, Vector2i(4, 0)), "valid floor trap coexists with wall trap")
	check(BattleHazards.add_trap(hazards, Vector2i(4, 0), "wall", Vector2i.LEFT), "valid second wall direction on shared cell")
	check(BattleHazards.add_trap(hazards, Vector2i(5, 0)), "valid unarmed floor trap")
	hazards.traps[1].armed_team = int(Faction.Type.PLAYER)
	check(BattleHazards.valid(hazards), "mixed trap fixture follows real core schema")
	board._view_hazards = hazards.duplicate(true)
	board._view_corpses = [{"cell": Vector2i(4, 0)}, {"cell": Vector2i(4, 0)}]
	board._view_collapse = [Vector2i(0, 0)]
	board._view_terrain[1] = TerrainType.Type.DEEP_ACID
	board._view_terrain[2] = TerrainType.Type.VOID
	board._view_terrain[3] = TerrainType.Type.HAZARD
	board.session = null
	check(_cell_ids(board.displayed_cell_conditions(Vector2i(0, 0))) == [&"fire_on_tile", &"collapse_warning"], "floor fire and collapse map to their cell icons")
	check(board.displayed_cell_conditions(Vector2i(1, 0)).size() == 1 and _cell_ids(board.displayed_cell_conditions(Vector2i(1, 0))) == [&"deep_acid"], "deep acid never becomes the acid-pool icon")
	check(_cell_ids(board.displayed_cell_conditions(Vector2i(2, 0))) == [&"void"], "void never becomes the acid-pool icon")
	check(_cell_ids(board.displayed_cell_conditions(Vector2i(3, 0))) == [&"hazard"], "generic hazard never becomes the acid-pool icon")
	var occupied := board.displayed_cell_conditions(Vector2i(4, 0))
	check(_cell_ids(occupied) == [&"acid_pool", &"corpse", &"wall_trap", &"floor_trap", &"wall_trap"], "all mixed trap kinds and directions coexist with acid and corpse")
	check(String(occupied[1].title) == "Труп ×2", "multiple corpse markers are represented by one counted entry")
	check(String(occupied[2].title).contains("→") and String(occupied[4].title).contains("←"), "both wall trap directions remain visible")
	check(String(occupied[2].title).contains("при толчке в грань") and not String(occupied[2].title).contains("взведена"), "wall trap never mislabels its absent timer as unarmed")
	check(String(occupied[3].title).contains(" · взведена"), "floor trap still shows its armed team timer")
	check(board._view_hazards == hazards, "inspection never mutates published trap state")
	var floor_trap := board.displayed_cell_conditions(Vector2i(5, 0))
	check(_cell_ids(floor_trap) == [&"floor_trap"] and String(floor_trap[0].title).contains("не взведена"), "floor trap shows its unarmed state")
	check(board.displayed_cell_conditions(Vector2i(-1, 0)).is_empty() and board.displayed_cell_conditions(Vector2i(8, 8)).is_empty(), "out-of-bounds cell conditions are empty")
	check(board.displayed_cell_summary(Vector2i(-1, 0)).contains("Наведите"), "out-of-bounds summary uses the neutral inspection prompt")
	board.free()


func _test_battle_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var profile := HeroHubState.create(9404, 4)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var demo := (load("res://scenes/demo/battle/hero_hub_battle.tscn") as PackedScene).instantiate() as HeroHubBattleView
	var route := HeroHubScreen.new()
	check(route._configure_first_room_art(demo, profile), "production first-room art is configured")
	route.free()
	demo.supplied_session = HeroHubBattleFactory.create(profile).session
	viewport.add_child(demo)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	demo.set_process(false)
	demo.end_turn()
	demo._confirm_selected_mulligan()
	var session := demo.session as BattleCoreReactionsSession
	if session.phase == BattleTacticalSession.Phase.ENEMY_TURN:
		session._enemy_index = session._enemy_ids.size()
		session.step_enemy()
	demo._refresh()
	for index: int in 5:
		await process_frame
	var board := demo.board_view
	var card := demo._character_card
	var target: UnitState = session.selected_unit()
	var neighbors: Array[UnitState] = []
	for unit: UnitState in session.units:
		if unit.id != target.id and unit.is_alive():
			neighbors.append(unit)
			if neighbors.size() == 2:
				break
	check(neighbors.size() == 2, "battle fixture exposes two neighboring units")
	var live_before := _snapshot(session)
	var frame := ActionPresentationState.capture(session.state)
	var shown: Dictionary = frame.units[target.id]
	shown.bleeding = {"stacks": 2, "ticks_left": 3}
	shown.elemental = {"poison_stacks": 2, "poison_ticks": 3, "acid_ticks": 2}
	shown.control = {"stunned_turns": 1, "entangled_turns": 1}
	shown.pending = true
	shown.raised_shield = {"active": true}
	shown.reaction_view = {"mode": CombatPerksState.Mode.OPPORTUNIST, "ready": true}
	var neighbor_row: Dictionary = frame.units[neighbors[0].id]
	neighbor_row.bleeding = {"stacks": 1, "ticks_left": 1}
	var second_neighbor: Dictionary = frame.units[neighbors[1].id]
	second_neighbor.elemental = {"burning_stacks": 1, "burning_ticks": 2}
	var card_row := {
		"id": target.id, "name": "Иконный тест", "faction": int(Faction.Type.PLAYER), "alive": false,
		"hp": 18.0, "hp_max": 20.0, "balance": 4.0, "balance_max": 12.0,
		"armor": {"current": 4.0, "maximum": 8.0, "extra": 0.0}, "main": 1, "bonus": 1, "move": 3.0,
		"shield": {"hp": 2.0, "hits_left": 1}, "raised_shield": {"active": true}, "pending": true, "guard": true,
		"control": {"stunned_turns": 1, "entangled_turns": 1},
		"elemental": {"frozen_turns": 1, "burning_stacks": 2, "burning_ticks": 2,
			"poison_stacks": 3, "poison_ticks": 2, "acid_ticks": 2, "wet_turns": 1},
		"bleeding": {"stacks": 2, "ticks_left": 3},
		"reaction_view": {"mode": CombatPerksState.Mode.COUNTERATTACK, "ready": true},
	}
	var card_data := BattleCharacterCardData.frame(card_row, {"class_label": "Тест", "portrait": null})
	var bbcode: String = card_data.status_bbcode
	for icon_id: StringName in [&"stunned", &"frozen", &"entangled", &"bleeding", &"burning", &"poison", &"acid", &"wet", &"shield"]:
		check(bbcode.contains("/32/%s.png" % String(icon_id)), "card status facts include %s icon" % String(icon_id))
	for icon_id: StringName in [&"pending", &"raised_shield", &"counterattack", &"corpse"]:
		check(bbcode.contains("/32/%s.png" % String(icon_id)), "card auxiliary facts include %s icon" % String(icon_id))
	check(String(card_data.status_text).contains("Кровотечение") and String(card_data.status_text).contains("стаки: 2") and String(card_data.status_text).contains("Яд"), "card retains plain status facts beside icons")
	var published_before: Dictionary = frame.duplicate(true)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1440, 900)]:
		viewport.size = dimensions
		for index: int in 4:
			await process_frame
		var board_rect := board.get_global_rect()
		var hand_rect := demo._mage_row.get_global_rect()
		var desired_zoom: float = 0.75 if dimensions == Vector2i(1280, 720) else 1.0
		var focus := board._world_cell_center(target.cell)
		for neighbor: UnitState in neighbors:
			focus += board._world_cell_center(neighbor.cell)
		focus /= float(neighbors.size() + 1)
		var focus_screen := Vector2(dimensions) * Vector2(0.44, 0.46)
		var focus_local := focus_screen - board.global_position
		board.zoom_camera(desired_zoom, focus_local)
		board.pan_camera(focus_local - board.world_to_view(focus))
		var camera_zoom := board.camera_view.zoom
		var camera_offset := board.camera_view.offset
		board.show_presentation_state(frame)
		demo._displayed_unit_hovered(target.id)
		board.session = null
		var visible := board._presentation_visual(target.id)
		check(visible.visible_status_entries().size() == 3 and visible.visible_status_entries()[0].id == "bleeding" and visible.visible_status_entries()[1].id == "poison" and visible.visible_status_entries()[2].id == "acid", "presentation-only bleeding, poison, and acid render below the figure")
		check(visible.status_entries.size() == 5 and visible.visible_status_entries().size() <= 5, "two embodied control facts remain in details without duplicating the three world icons")
		check(board._presentation_visual(neighbors[0].id).visible_status_entries().size() == 1 and board._presentation_visual(neighbors[1].id).visible_status_entries().size() == 1, "neighbor units carry one synthetic status each")
		check(_snapshot(session) == live_before, "synthetic status and tile publications leave state, RNG, and counters unchanged")
		var target_id: int = target.id
		demo._open_character_card(target_id)
		var screenshot_row: Dictionary = shown.duplicate(true)
		screenshot_row.id = target.id
		screenshot_row.name = target.debug_name
		screenshot_row.faction = int(target.faction)
		screenshot_row.alive = true
		screenshot_row.control = {}
		screenshot_row.shield = {}
		var screenshot_data := BattleCharacterCardData.frame(screenshot_row, demo._character_card_identity)
		var live_data := BattleCharacterCardData.live(target, session.state, session.actor_loadouts.get(target.id, {}), demo._inspection_options(target))
		screenshot_data.attributes_text = live_data.attributes_text
		screenshot_data.details_text = live_data.details_text
		card.show_data(screenshot_data)
		for index: int in 4:
			await process_frame
		check(card.visible and card.name_label.text == target.debug_name and card.portrait_rect.texture != null, "right card keeps the selected fighter name and portrait with synthetic presentation facts")
		check(String(screenshot_data.status_bbcode).contains("/32/bleeding.png") and String(screenshot_data.status_bbcode).contains("/32/poison.png") and String(screenshot_data.status_bbcode).contains("/32/acid.png") and String(screenshot_data.status_bbcode).contains("/32/opportunist.png"), "H1 screenshot frame shows its three synthetic conditions and reaction")
		check(not card.get_global_rect().intersects(demo._mage_row.get_global_rect()), "status card does not intersect hand at %dx%d" % [dimensions.x, dimensions.y])
		check(board.get_global_rect() == board_rect and board.camera_view.zoom == camera_zoom and board.camera_view.offset == camera_offset and demo._mage_row.get_global_rect() == hand_rect, "status/tile/card changes preserve board, camera, and hand geometry")
		check(frame == published_before, "board and card consumers leave the published DTO unchanged")
		# Шапка с портретом остаётся на месте; прокрутка показывает сам предмет этой пробы.
		card.scroll_container.scroll_vertical += floori(card.status_label.global_position.y - card.scroll_container.global_position.y - 28.0)
		for index: int in 3: await process_frame
		await _capture("h1-presentation-only-status-card-%dx%d" % [dimensions.x, dimensions.y])
		demo._close_character_card()
		board.session = session
		for index: int in 4:
			await process_frame
		var tile_cell := target.cell
		var tile_frame := frame.duplicate(true)
		var hazards: Dictionary = tile_frame.get("hazards", {}).duplicate(true)
		var acid_cells: Array = hazards.get("acid", []).duplicate()
		acid_cells.append(tile_cell)
		hazards["acid"] = acid_cells
		tile_frame["hazards"] = hazards
		var corpses: Array = tile_frame.get("corpses", []).duplicate(true)
		corpses.append({"cell": tile_cell, "faction": int(Faction.Type.ENEMY)})
		tile_frame["corpses"] = corpses
		board.show_presentation_state(tile_frame)
		board.hover_cell = tile_cell
		demo._displayed_unit_hovered(UnitId.NONE)
		check(demo._compact_inspection.get_parsed_text().contains("Кислота") and demo._compact_inspection.get_parsed_text().contains("Труп"), "compact tile inspection displays published acid and corpse facts")
		check(demo._compact_inspection.text.contains("[img=32x32]") and not demo._compact_inspection.text.contains("\n"), "wide cell motifs use readable 32px in one fixed-height row")
		check(board.get_global_rect() == board_rect and board.camera_view.zoom == camera_zoom and board.camera_view.offset == camera_offset and demo._mage_row.get_global_rect() == hand_rect, "combined tile states keep exact board, camera, and hand geometry")
		await _capture("h1-presentation-only-tile-icons-%dx%d" % [dimensions.x, dimensions.y])
	check(_snapshot(session) == live_before, "detached inspection and card rendering leave the real battle untouched")
	demo.queue_free()
	viewport.queue_free()
	await process_frame


func _capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "battle capture %s" % label)


func _capture_contact_sheet() -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	var sheet := SubViewport.new()
	sheet.size = Vector2i(960, 900)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var panel := VBoxContainer.new()
	panel.position = Vector2(16.0, 12.0)
	panel.size = Vector2(928.0, 876.0)
	panel.add_theme_constant_override("separation", 1)
	sheet.add_child(panel)
	var background := ColorRect.new()
	background.color = Color("171b20")
	background.position = Vector2.ZERO
	background.size = Vector2(sheet.size)
	background.z_index = -1
	sheet.add_child(background)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Каталог значков состояний · выбранный набор A"
	title.custom_minimum_size.x = 430.0
	title.add_theme_color_override("font_color", Color("e0ddcb"))
	heading.add_child(title)
	for heading_text: String in ["16 px · нативный", "32 px · нативный"]:
		var size_label := Label.new()
		size_label.text = heading_text
		size_label.custom_minimum_size.x = 128.0
		size_label.add_theme_color_override("font_color", Color("e0ddcb"))
		heading.add_child(size_label)
	panel.add_child(heading)
	var russian_names: Dictionary[StringName, String] = {
		&"bleeding": "Кровотечение", &"burning": "Горение", &"poison": "Яд", &"acid": "В кислоте",
		&"stunned": "Оглушён", &"entangled": "Путы", &"frozen": "Заморожен", &"wet": "Мокрый",
		&"shield": "Щит", &"raised_shield": "Поднятый щит", &"opportunist": "Оппортунист",
		&"counterattack": "Контратака", &"cover": "Прикрытие", &"pending": "Ожидает хода",
		&"fire_on_tile": "Огонь на клетке", &"acid_pool": "Кислотная плёнка", &"spikes": "Кальтропы",
		&"corpse": "Труп", &"collapse_warning": "Угроза обрушения", &"floor_trap": "Напольная ловушка",
		&"wall_trap": "Настенная ловушка", &"deep_acid": "Глубокая кислота", &"void": "Провал",
		&"hazard": "Опасная поверхность",
	}
	for icon_id: StringName in BattleConditionIcons.IDS:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 35.0
		var label := Label.new()
		label.text = "%s · %s" % [russian_names.get(icon_id, String(icon_id)), String(icon_id)]
		label.custom_minimum_size = Vector2(430.0, 34.0)
		label.clip_text = true
		label.add_theme_color_override("font_color", Color("e0ddcb"))
		row.add_child(label)
		for pixels: int in [16, 32]:
			var icon := TextureRect.new()
			icon.texture = BattleConditionIcons.texture(icon_id, pixels)
			icon.custom_minimum_size = Vector2(128.0, 34.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(icon)
		panel.add_child(row)
	for index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	check(sheet.get_texture().get_image().save_png(captures.path_join("status-icon-catalogue-16-32.png")) == OK, "24-icon 16/32px catalogue capture")
	sheet.queue_free()
	await process_frame
