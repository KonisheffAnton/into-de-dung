extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const CLASS_IDS: Array[StringName] = [&"warrior", &"fighter", &"shieldbearer", &"mage", &"rogue", &"archer"]
const ZOOMS: Array[float] = [0.75, 1.0, 1.25]

var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport
var stage: Node2D
var config: IsoGridConfig
var visuals: Array[BattleCharacterSkinVisual] = []


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
		printerr("FAIL UNIT VITAL BARS: " + label)


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node2D.new()
	stage.position = Vector2(0.35, 0.65)
	viewport.add_child(stage)
	config = IsoGridConfig.new()
	config.tile_size = Vector2(128.0, 96.0)
	config.height_step = 32.0
	config.origin_offset = Vector2(260.25, 190.5)
	var rows: Array[Dictionary] = _vital_cases()
	for faction_row: int in 2:
		for index: int in rows.size():
			var visual := UNIT_SCENE.instantiate() as BattleCharacterSkinVisual
			check(visual != null, "production trial unit creates class %d for faction row %d" % [index, faction_row])
			if visual == null:
				continue
			visual.role = BattleDemoIsoVisual.Role.UNIT
			stage.add_child(visual)
			visuals.append(visual)
	await process_frame
	for faction_row: int in 2:
		for index: int in rows.size():
			var visual_index := faction_row * rows.size() + index
			var visual := visuals[visual_index]
			var class_id: StringName = CLASS_IDS[index] if index < CLASS_IDS.size() else &"mage"
			var faction := Faction.Type.PLAYER if faction_row == 0 else Faction.Type.ENEMY
			var values := _view_values(rows[index], class_id, faction, visual_index + 8100,
				Vector2i(index + faction_row * 3, -index + faction_row * 3))
			check(visual.apply_view(values, config), "published view applies for %s %s" % [class_id, "ally" if faction_row == 0 else "enemy"])
			visual.set_process(false)
			check(visual._view_initialized and visual.unit != null and visual.unit.hp == float(rows[index].hp),
				"art trial receives copied vital snapshot for %s" % class_id)
			if visual_index == 0:
				var saved_hp := visual.unit.hp
				var saved_armor := float(visual.armor_values["current"])
				values.unit.hp = -99.0
				values.armor_values.current = -99.0
				check(visual.unit.hp == saved_hp and float(visual.armor_values["current"]) == saved_armor,
					"applying a vital view copies caller data instead of aliasing later mutations")
			check(visual.class_still_sprite() != null and _has_visible_sprite(visual.get_node("ArtRoot")),
				"production character art remains visible behind bars for %s %s" % [class_id, "ally" if faction_row == 0 else "enemy"])
			_add_gallery_label(visual, rows[index], class_id, faction)
			if index == 0:
				check(visual.visible_status_entries().size() == 1 and visual.status_hud_bounds().size.y > 0.0,
					"status icon remains attached above the bar region")
	# Проверяются все шесть используемых id классов и отдельное субединичное значение брони.
	for zoom_index: int in ZOOMS.size():
		await _check_zoom(zoom_index)
	_check_action_pose_invariants()
	await _check_death_hides_bars()
	viewport.queue_free()
	await process_frame
	print("UNIT VITAL BARS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _vital_cases() -> Array[Dictionary]:
	return [
		{"hp": 100.0, "hp_max": 100.0, "armor": 100.0, "armor_max": 100.0, "balance": 0.0, "balance_max": 100.0, "case": "full"},
		{"hp": 50.5, "hp_max": 100.0, "armor": 50.5, "armor_max": 100.0, "balance": 50.0, "balance_max": 100.0, "case": "half"},
		{"hp": 0.1, "hp_max": 100.0, "armor": 0.1, "armor_max": 100.0, "balance": 99.9, "balance_max": 100.0, "case": "near-zero"},
		{"hp": 0.0, "hp_max": 100.0, "armor": 0.0, "armor_max": 100.0, "balance": 100.0, "balance_max": 100.0, "case": "empty"},
		{"hp": 123.0, "hp_max": 123.0, "armor": 105.0, "armor_max": 120.0, "balance": 0.0, "balance_max": 120.0, "case": "three-digit"},
		{"hp": 35.25, "hp_max": 60.0, "armor": 2.25, "armor_max": 50.0, "balance": 0.0, "balance_max": 0.0, "case": "immune"},
		{"hp": 0.75, "hp_max": 1.5, "armor": 0.5, "armor_max": 0.5, "balance": 4.5, "balance_max": 10.0, "case": "fractional-max"},
	]


func _view_values(row: Dictionary, class_id: StringName, faction: Faction.Type, unit_id: int, cell: Vector2i) -> Dictionary:
	var statuses: Array[Dictionary] = []
	if String(row.case) == "full":
		statuses.append({"id": "bleeding", "title": "Кровотечение", "stacks": 2, "remaining": 3, "duration_unit": "тиков в начале своего хода", "embodied": false})
	var forecast: Dictionary = {}
	if String(row.case) == "half":
		forecast = {"after": {"hp": 10.0, "alive": true, "armor_current": 10.0}}
	return {
		"cell": cell, "half_steps": 0,
		"unit": {"id": unit_id, "faction": int(faction), "name": "Проба %d" % unit_id,
			"alive": true, "hp": float(row.hp), "hp_max": float(row.hp_max),
			"balance": float(row.balance), "balance_max": float(row.balance_max)},
		"visual_class_id": class_id, "visual_skin_id": &"",
		"selected": false, "inspected": false, "hovered": false, "acting": false,
		"show_rear": false, "summon_pending": false, "forecast_entry": forecast,
		"armor_values": {"current": float(row.armor), "maximum": float(row.armor_max), "extra": 0.0},
		"shield_view": {}, "raised_shield_view": {"active": false},
		"reaction_view": {"mode": 0, "ready": false, "charge": 0},
		"action_resources_view": {"main": 1, "bonus": 0, "move": 3.0},
		"status_entries": statuses,
	}


func _add_gallery_label(visual: BattleDemoIsoVisual, row: Dictionary, class_id: StringName, faction: Faction.Type) -> void:
	var faction_label := "Союзники" if faction == Faction.Type.PLAYER else "Противники"
	var class_label := "Воин" if class_id == &"warrior" else ("Боец" if class_id == &"fighter" else ("Страж" if class_id == &"shieldbearer" else ("Маг" if class_id == &"mage" else ("Плут" if class_id == &"rogue" else "Лучник"))))
	var case_label := "Полный"
	match String(row.case):
		"half": case_label = "Половина"
		"near-zero": case_label = "Почти ноль"
		"empty": case_label = "Ноль"
		"three-digit": case_label = "Три цифры"
		"immune": case_label = "Иммунитет"
		"fractional-max": case_label = "Дробный максимум"
	var label := Label.new()
	label.position = visual.position + Vector2(-62.0, 66.0)
	label.size = Vector2(124.0, 30.0)
	label.text = "%s · %s\n%s\n%s" % [faction_label, class_label, case_label, String(class_id)]
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("f2f4ed"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	stage.add_child(label)


func _check_zoom(zoom_index: int) -> void:
	var zoom: float = ZOOMS[zoom_index]
	var status_bounds := visuals[0].status_hud_bounds()
	stage.scale = Vector2.ONE * zoom
	stage.position = Vector2(0.35, 0.65)
	for visual: BattleCharacterSkinVisual in visuals:
		visual.queue_redraw()
	await process_frame
	check(visuals[0].status_hud_bounds() == status_bounds and status_bounds.end.y < 1.0,
		"zoom leaves the status row fixed above the armor strip")
	if captures.is_empty(): return
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(not image.is_empty() and _has_rendered_color(image), "GPU produces a nonempty vital gallery at zoom %.2f" % zoom)
	if image.is_empty() or not _has_rendered_color(image): return
	await _capture(image, "unit-vitals-zoom-%s" % String.num(zoom, 2).replace(".", "-"))
	for row_index: int in range(visuals.size()):
		var visual := visuals[row_index]
		var case_index := row_index % 7
		var row := _vital_cases()[case_index]
		var origin := _bar_origin(visual)
		var hp_text_point := _screen_point(visual, origin + Vector2(0.0, 20.5))
		var armor_text_point := _screen_point(visual, origin + Vector2(0.0, 6.5))
		check(_has_centered_dark_ink(image, hp_text_point, zoom),
			"HP amount ink stays centered and legible at zoom %.2f for %s %s" % [zoom, visual.visual_class_id, row.case])
		check(_has_centered_dark_ink(image, armor_text_point, zoom),
			"armor amount ink stays centered and legible at zoom %.2f for %s %s" % [zoom, visual.visual_class_id, row.case])
		if String(row.case) == "full":
			var hp_frame := _screen_point(visual, origin + Vector2(-23.5, 20.5))
			var armor_frame := _screen_point(visual, origin + Vector2(-23.5, 6.5))
			check(_has_color_near(image, hp_frame, Color.BLACK, zoom)
				and _has_color_near(image, armor_frame, Color.BLACK, zoom),
				"inset black frames remain visible around HP and armor at zoom %.2f" % zoom)
		if String(row.case) == "half":
			var hp_fill := _screen_point(visual, origin + Vector2(-21.0, 20.5))
			var armor_fill := _screen_point(visual, origin + Vector2(-21.0, 6.5))
			check(_has_color_near(image, hp_fill, Color("73bd68"), zoom),
				"half HP remains green at zoom %.2f" % zoom)
			check(_has_color_near(image, armor_fill, Color("bbc5ce"), zoom),
				"half armor remains metallic gray at zoom %.2f" % zoom)
			var forecast_fill := _screen_point(visual, origin + Vector2(-16.0, 20.5))
			check(_has_color_near(image, forecast_fill, Color("f29b9b"), zoom),
				"damage forecast segment remains distinct at zoom %.2f" % zoom)
		if String(row.case) == "empty":
			var hp_track := _screen_point(visual, origin + Vector2(-18.0, 20.5))
			var armor_track := _screen_point(visual, origin + Vector2(-18.0, 6.5))
			check(_has_color_near(image, hp_track, Color("7c857c"), zoom),
				"zero HP keeps a neutral track visible at zoom %.2f" % zoom)
			check(_has_color_near(image, armor_track, Color("7e8993"), zoom),
				"zero armor keeps a neutral metallic track visible at zoom %.2f" % zoom)
		if String(row.case) == "near-zero":
			var reserve_pixel := _screen_point(visual, origin + Vector2(-22.5, 29.0))
			check(_has_color_near(image, reserve_pixel, Color("d1a05c"), zoom),
				"positive tiny balance reserve remains visible at zoom %.2f" % zoom)
		if String(row.case) == "full":
			var balance_middle := 27.0 + 2.0 * maxf(1.0, 1.0 / zoom)
			var balance_start := _screen_point(visual, origin + Vector2(-20.0, balance_middle))
			var balance_end := _screen_point(visual, origin + Vector2(20.0, balance_middle))
			var balance_upper := _screen_point(visual, origin + Vector2(0.0, balance_middle - 0.5 / zoom))
			var balance_lower := _screen_point(visual, origin + Vector2(0.0, balance_middle + 0.5 / zoom))
			check(_has_color_near(image, balance_start, Color("d1a05c"), zoom)
				and _has_color_near(image, balance_end, Color("d1a05c"), zoom),
				"full reserve spans the framed balance bar at zoom %.2f" % zoom)
			check(_has_color_near(image, balance_upper, Color("f3d39f"), zoom)
				and _has_color_near(image, balance_lower, Color("d1a05c"), zoom),
				"balance fill stays visibly thicker than a one-pixel line at zoom %.2f" % zoom)
			var partial_end := _screen_point(visuals[1], _bar_origin(visuals[1]) + Vector2(10.0, 29.0))
			check(_has_color_near(image, partial_end, Color("45494b"), zoom),
				"half reserve leaves its far half empty at zoom %.2f" % zoom)
		if String(row.case) == "empty":
			var empty_reserve := _screen_point(visual, origin + Vector2(-22.0, 29.0))
			check(_has_color_near(image, empty_reserve, Color("45494b"), zoom),
				"depleted balance shows an empty neutral track at zoom %.2f" % zoom)
		if String(row.case) == "immune":
			var immune_pixel := _screen_point(visual, origin + Vector2(0.0, 29.0))
			check(_has_color_near(image, immune_pixel, Color("d1a05c"), zoom),
				"zero maximum balance shows full immunity reserve at zoom %.2f" % zoom)
		if String(row.case) == "fractional-max":
			var fractional_armor := _screen_point(visual, origin + Vector2(20.0, 6.5))
			check(_has_color_near(image, fractional_armor, Color("bbc5ce"), zoom),
				"subunit armor maximum preserves a fully filled fractional value at zoom %.2f" % zoom)
			var partial_balance := _screen_point(visual, origin + Vector2(0.0, 29.0))
			check(_has_color_near(image, partial_balance, Color("d1a05c"), zoom),
				"fractional balance reserve remains amber at zoom %.2f" % zoom)
		if zoom_index == 1 and row_index < 6:
			var enemy_index := row_index + 7
			var enemy_visual := visuals[enemy_index]
			var player_color_point := _screen_point(visual, origin + Vector2(-18.0, 20.5))
			var enemy_color_point := _screen_point(enemy_visual, _bar_origin(enemy_visual) + Vector2(-18.0, 20.5))
			if String(row.case) == "half":
				check(_sampled_colors_match(image, player_color_point, enemy_color_point),
					"ally and enemy receive the same HP fill color for %s" % visual.visual_class_id)
	check(BattleBalanceDisplay.ratio(99.9, 100.0) > 0.0 and BattleBalanceDisplay.ratio(0.0, 0.0) == 1.0,
		"balance sample semantics retain positive reserve and maximum-zero immunity")


func _bar_origin(visual: BattleDemoIsoVisual) -> Vector2:
	return visual.get_visual_offset() + visual.get_unit_bars_offset() * (config.tile_size.x / 128.0)


func _screen_point(visual: BattleDemoIsoVisual, local_point: Vector2) -> Vector2:
	return visual.get_global_transform_with_canvas() * local_point


func _has_visible_sprite(node: Node) -> bool:
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.visible and sprite.texture != null: return true
	if node is AnimatedSprite2D:
		var animated := node as AnimatedSprite2D
		if animated.visible and animated.sprite_frames != null: return true
	for child: Node in node.get_children():
		if _has_visible_sprite(child): return true
	return false


func _has_color_near(image: Image, point: Vector2, expected: Color, zoom: float, tolerance: float = 0.13) -> bool:
	var center := Vector2i(roundi(point.x), roundi(point.y))
	var radius := maxi(1, ceili(zoom))
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var actual := image.get_pixel(x, y)
			if absf(actual.r - expected.r) < tolerance and absf(actual.g - expected.g) < tolerance and absf(actual.b - expected.b) < tolerance:
				return true
	return false


func _has_centered_dark_ink(image: Image, point: Vector2, zoom: float) -> bool:
	var center := Vector2i(roundi(point.x), roundi(point.y))
	var x_radius := maxi(1, ceili(10.0 * zoom))
	var y_radius := maxi(1, ceili(2.0 * zoom))
	var ink_pixels: int = 0
	for y: int in range(center.y - y_radius, center.y + y_radius + 1):
		for x: int in range(center.x - x_radius, center.x + x_radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.12 or pixel.g > 0.12 or pixel.b > 0.12: continue
			var ink_luminance := _relative_luminance(pixel)
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if dx == 0 and dy == 0: continue
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= image.get_width() or ny >= image.get_height(): continue
					var surround_luminance := _relative_luminance(image.get_pixel(nx, ny))
					var contrast := (maxf(surround_luminance, ink_luminance) + 0.05) / (minf(surround_luminance, ink_luminance) + 0.05)
					if contrast >= 4.5:
						ink_pixels += 1
						break
				if ink_pixels >= 2: break
	return ink_pixels >= 2


func _relative_luminance(color: Color) -> float:
	var red := color.r / 12.92 if color.r <= 0.04045 else pow((color.r + 0.055) / 1.055, 2.4)
	var green := color.g / 12.92 if color.g <= 0.04045 else pow((color.g + 0.055) / 1.055, 2.4)
	var blue := color.b / 12.92 if color.b <= 0.04045 else pow((color.b + 0.055) / 1.055, 2.4)
	return 0.2126 * red + 0.7152 * green + 0.0722 * blue


func _sampled_colors_match(image: Image, first: Vector2, second: Vector2) -> bool:
	var a := image.get_pixel(roundi(first.x), roundi(first.y))
	var b := image.get_pixel(roundi(second.x), roundi(second.y))
	return absf(a.r - b.r) < 0.05 and absf(a.g - b.g) < 0.05 and absf(a.b - b.b) < 0.05


func _check_action_pose_invariants() -> void:
	var visual := visuals[0]
	var root_position := visual.position
	var anchor := visual.grid_anchor
	var pick_rect := visual.get_unit_pick_rect()
	var art := visual.get_node("ArtRoot") as Node2D
	var art_position := art.position
	var bars_before := _bar_origin(visual)
	visual.action_offset = Vector2(7.0, -3.0)
	visual.queue_redraw()
	check(visual.position == root_position and visual.grid_anchor == anchor and visual.get_unit_pick_rect() == pick_rect,
		"action pose leaves the board root, cell, and picking geometry unchanged")
	check(art.position != art_position and _bar_origin(visual) == bars_before,
		"action pose moves character art without moving its vitals from the published foot")
	visual.action_offset = Vector2.ZERO


func _check_death_hides_bars() -> void:
	var visual := visuals[0]
	var row := _vital_cases()[0]
	var values := _view_values(row, visual.visual_class_id, Faction.Type.PLAYER, visual.unit.id, visual.grid_anchor)
	values.unit.alive = false
	values.unit.hp = 0.0
	check(visual.apply_view(values, config) and not visual._status_hud.visible,
		"dead published view hides the status HUD and vital bar carrier")
	if captures.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image.is_empty(): return
	if not _has_rendered_color(image): return
	var point := _screen_point(visual, _bar_origin(visual) + Vector2(0.0, 20.0))
	check(not _has_color_near(image, point, Color("73bd68"), 1.0),
		"death does not leave a living green HP fill on the stage")
	await _capture(image, "unit-vitals-death")


func _capture(image: Image, name: String) -> void:
	if captures.is_empty(): return
	DirAccess.make_dir_recursive_absolute(captures)
	check(image.save_png(captures.path_join(name + ".png")) == OK, "PNG " + name)


func _has_rendered_color(image: Image) -> bool:
	for y: int in range(0, image.get_height(), 13):
		for x: int in range(0, image.get_width(), 13):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.5 and pixel.r + pixel.g + pixel.b > 0.3:
				return true
	return false
