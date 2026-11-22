extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const CLASS_IDS: Array[StringName] = [&"warrior", &"fighter", &"shieldbearer", &"mage", &"rogue", &"archer"]
const ZOOMS: Array[float] = [1.0, 0.5, 0.75, 1.13, 1.25]

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
	if not captures.is_empty():
		await _check_crisp_number_pixels()
		await _check_balance_sections()
		await _check_armor_visibility_lifecycle()
	_check_action_pose_invariants()
	await _check_death_hides_bars()
	viewport.queue_free()
	await process_frame
	print("UNIT VITAL BARS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _vital_cases() -> Array[Dictionary]:
	return [
		{"hp": 100.0, "hp_max": 100.0, "armor": 100.0, "armor_max": 100.0, "balance": 0.0, "balance_max": 5.0, "case": "full"},
		{"hp": 50.5, "hp_max": 100.0, "armor": 50.5, "armor_max": 100.0, "balance": 3.0, "balance_max": 7.0, "case": "half"},
		{"hp": 0.1, "hp_max": 100.0, "armor": 0.1, "armor_max": 100.0, "balance": 4.0, "balance_max": 5.0, "case": "near-zero"},
		{"hp": 0.0, "hp_max": 100.0, "armor": 0.0, "armor_max": 100.0, "balance": 7.0, "balance_max": 7.0, "case": "empty"},
		{"hp": 123456789012.5, "hp_max": 123456789012.5, "armor": 105.0, "armor_max": 120.0, "balance": 0.0, "balance_max": 120.0, "case": "long-number"},
		{"hp": 35.25, "hp_max": 60.0, "armor": 2.25, "armor_max": 50.0, "balance": 0.0, "balance_max": 0.0, "case": "immune"},
		{"hp": 0.75, "hp_max": 1.5, "armor": 0.5, "armor_max": 0.5, "balance": 1.0, "balance_max": 5.0, "case": "fractional-max"},
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
		"long-number": case_label = "Длинное число"
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
		var hp_text_point := _bar_screen_anchor(visual) + Vector2(0.0, 19.5)
		var armor_text_point := _bar_screen_anchor(visual) + Vector2(0.0, 6.5)
		check(_has_centered_dark_ink(image, hp_text_point, zoom),
			"HP amount ink stays centered and legible at zoom %.2f for %s %s" % [zoom, visual.visual_class_id, row.case])
		if String(row.case) == "long-number":
			check(visual.unit.hp == 123456789012.5 and BattleEventText.amount_text(visual.unit.hp) == "123456789012.5",
				"long HP keeps its exact published amount for the displayed text")
			check(_has_dark_ink_outside_standard_track(image, _bar_screen_anchor(visual) + Vector2(0.0, 19.5)),
				"long HP glyphs remain visible beyond the original 48-pixel track width")
		check(_has_centered_dark_ink(image, armor_text_point, zoom),
			"armor amount ink stays centered and legible at zoom %.2f for %s %s" % [zoom, visual.visual_class_id, row.case])
		if String(row.case) == "full":
			var hp_frame := _bar_screen_anchor(visual) + Vector2(-23.5, 19.5)
			var armor_frame := _bar_screen_anchor(visual) + Vector2(-23.5, 6.5)
			check(_has_color_near(image, hp_frame, Color.BLACK, zoom)
				and _has_color_near(image, armor_frame, Color.BLACK, zoom),
				"inset black frames remain visible around HP and armor at zoom %.2f" % zoom)
		if String(row.case) in ["full", "empty", "fractional-max"]:
			check(_bar_edge_rows_are_palette_only(image, _bar_screen_anchor(visual), 14,
				[Color("a2bf7b"), Color("bad592"), Color("89a365"), Color("777d70")]),
				"HP top and bottom interior rows contain only track colors at zoom %.2f for %s" % [zoom, row.case])
			check(_bar_edge_rows_are_palette_only(image, _bar_screen_anchor(visual), 1,
				[Color("c0cacb"), Color("dce4e2"), Color("a4b1b4"), Color("747d80")]),
				"armor top and bottom interior rows contain only track colors at zoom %.2f for %s" % [zoom, row.case])
		if String(row.case) == "half":
			var hp_fill := _bar_screen_anchor(visual) + Vector2(-21.0, 19.5)
			var armor_fill := _bar_screen_anchor(visual) + Vector2(-21.0, 6.5)
			check(_has_color_near(image, hp_fill, Color("a2bf7b"), zoom),
				"half HP remains green at zoom %.2f" % zoom)
			check(_has_color_near(image, armor_fill, Color("c0cacb"), zoom),
				"half armor remains metallic gray at zoom %.2f" % zoom)
			var forecast_fill := _bar_screen_anchor(visual) + Vector2(-16.0, 19.5)
			check(_has_color_near(image, forecast_fill, Color("f29b9b"), zoom),
				"damage forecast segment remains distinct at zoom %.2f" % zoom)
		if String(row.case) == "empty":
			var hp_track := _bar_screen_anchor(visual) + Vector2(-18.0, 19.5)
			var armor_track := _bar_screen_anchor(visual) + Vector2(-18.0, 6.5)
			check(_has_color_near(image, hp_track, Color("777d70"), zoom),
				"zero HP keeps a neutral track visible at zoom %.2f" % zoom)
			check(_has_color_near(image, armor_track, Color("747d80"), zoom),
				"zero armor keeps a neutral metallic track visible at zoom %.2f" % zoom)
		if String(row.case) == "near-zero":
			var reserve_pixel := _bar_screen_anchor(visual) + Vector2(-22.5, 29.0)
			check(_has_color_near(image, reserve_pixel, Color("a58b60"), zoom),
				"positive tiny balance reserve remains visible at zoom %.2f" % zoom)
		if String(row.case) == "full":
			var balance_start := _bar_screen_anchor(visual) + Vector2(-20.0, 29.0)
			var balance_end := _bar_screen_anchor(visual) + Vector2(20.0, 29.0)
			var balance_upper := _bar_screen_anchor(visual) + Vector2(0.0, 27.0)
			var balance_lower := _bar_screen_anchor(visual) + Vector2(0.0, 30.0)
			check(_has_color_near(image, balance_start, Color("a58b60"), zoom)
				and _has_color_near(image, balance_end, Color("a58b60"), zoom),
				"full reserve spans the framed balance bar at zoom %.2f" % zoom)
			check(_has_color_near(image, balance_upper, Color("cdb888"), zoom)
				and _has_color_near(image, balance_lower, Color("a58b60"), zoom),
				"balance fill stays visibly thicker than a one-pixel line at zoom %.2f" % zoom)
			var partial_end := _bar_screen_anchor(visuals[1]) + Vector2(10.0, 29.0)
			check(_has_color_near(image, partial_end, Color("45494b"), zoom),
				"half reserve leaves its far half empty at zoom %.2f" % zoom)
		if String(row.case) == "empty":
			var empty_reserve := _bar_screen_anchor(visual) + Vector2(-22.0, 29.0)
			check(_has_color_near(image, empty_reserve, Color("45494b"), zoom),
				"depleted balance shows an empty neutral track at zoom %.2f" % zoom)
		if String(row.case) == "immune":
			var immune_pixel := _bar_screen_anchor(visual) + Vector2(0.0, 29.0)
			check(_has_color_near(image, immune_pixel, Color("a58b60"), zoom),
				"zero maximum balance shows full immunity reserve at zoom %.2f" % zoom)
		if String(row.case) == "fractional-max":
			var fractional_armor := _bar_screen_anchor(visual) + Vector2(20.0, 6.5)
			check(_has_color_near(image, fractional_armor, Color("c0cacb"), zoom),
				"subunit armor maximum preserves a fully filled fractional value at zoom %.2f" % zoom)
			var partial_balance := _bar_screen_anchor(visual) + Vector2(0.0, 29.0)
			check(_has_color_near(image, partial_balance, Color("a58b60"), zoom),
				"four whole balance points remain filled beside fractional HP/armor at zoom %.2f" % zoom)
		if is_equal_approx(zoom, 1.0) and row_index < 6:
			var enemy_index := row_index + 7
			var enemy_visual := visuals[enemy_index]
			var player_color_point := _bar_screen_anchor(visual) + Vector2(-18.0, 19.5)
			var enemy_color_point := _bar_screen_anchor(enemy_visual) + Vector2(-18.0, 19.5)
			if String(row.case) == "half":
				check(_sampled_colors_match(image, player_color_point, enemy_color_point),
					"ally and enemy receive the same HP fill color for %s" % visual.visual_class_id)
	check(BattleBalanceDisplay.ratio(99.9, 100.0) > 0.0 and BattleBalanceDisplay.ratio(0.0, 0.0) == 1.0,
		"balance sample semantics retain positive reserve and maximum-zero immunity")


func _check_balance_sections() -> void:
	var visual := visuals[0]
	var old_balance := visual.unit.balance
	var old_maximum := visual.unit.balance_max
	var fixed_edges: Dictionary = {
		5: [-23, -14, -5, 5, 14, 23],
		7: [-23, -16, -10, -3, 3, 10, 16, 23],
	}
	# Ожидаемые целые экранные границы заданы отдельно от алгоритма рисования.
	for zoom: float in ZOOMS:
		stage.scale = Vector2.ONE * zoom
		for maximum: int in [5, 7]:
			var edges: Array = fixed_edges[maximum]
			for remaining_points: int in range(maximum + 1):
				visual.unit.balance = float(maximum - remaining_points)
				visual.unit.balance_max = float(maximum)
				visual.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var anchor := Vector2i(_bar_screen_anchor(visual))
				var separators: Array[int] = []
				for point: int in range(1, maximum):
					var edge := int(edges[point])
					if image.get_pixelv(anchor + Vector2i(edge, 28)).is_equal_approx(Color.BLACK) \
						and image.get_pixelv(anchor + Vector2i(edge, 29)).is_equal_approx(Color.BLACK): separators.append(edge)
				check(separators == edges.slice(1, maximum),
					"%d whole-point separators land on approved integer boundaries at zoom %.2f" % [maximum, zoom])
				for section: int in maximum:
					var sample_x := floori((float(edges[section]) + float(edges[section + 1]) - 1.0) * 0.5)
					var pixel := image.get_pixelv(anchor + Vector2i(sample_x, 29))
					var filled := section < remaining_points
					check(pixel.is_equal_approx(Color("a58b60")) if filled else pixel.is_equal_approx(Color("45494b")),
						"%d/%d point section %d is fully %s at zoom %.2f" % [remaining_points, maximum, section + 1, "filled" if filled else "empty", zoom])
					if filled:
						check(not pixel.is_equal_approx(Color("45494b")), "filled section has a negative empty-track control")
					else:
						check(not pixel.is_equal_approx(Color("a58b60")), "empty section has a negative filled-track control")
				if maximum == 5 and remaining_points == 5 and is_equal_approx(zoom, 1.0):
					await _capture(image, "unit-vitals-five-sections")
		# Неполные DTO значения округляются вниз до целых очков перед разметкой.
		visual.unit.balance = 3.75
		visual.unit.balance_max = 7.8
		visual.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var fractional_image := viewport.get_texture().get_image()
		var fractional_anchor := Vector2i(_bar_screen_anchor(visual))
		check(BattleBalanceDisplay.remaining(3.75, 7.8) == 4.0
			and BattleBalanceDisplay.ratio(3.75, 7.8) == 4.0 / 7.0
			and BattleBalanceDisplay.value_text(3.75, 7.8) == "4/7",
			"synthetic fractional balance DTO floors to four of seven whole points")
		check(fractional_image.get_pixelv(fractional_anchor + Vector2i(0, 29)).is_equal_approx(Color("a58b60"))
			and fractional_image.get_pixelv(fractional_anchor + Vector2i(6, 29)).is_equal_approx(Color("45494b")),
			"fractional DTO paints four whole sections and a fully empty fifth section")
		for maximum: float in [120.0, 1e30]:
			visual.unit.balance = 0.0
			visual.unit.balance_max = maximum
			visual.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var dense_image := viewport.get_texture().get_image()
			var dense_anchor := Vector2i(_bar_screen_anchor(visual))
			var dense_separators := 0
			for x: int in range(-23, 23):
				if dense_image.get_pixelv(dense_anchor + Vector2i(x, 28)).is_equal_approx(Color.BLACK) \
					and dense_image.get_pixelv(dense_anchor + Vector2i(x, 29)).is_equal_approx(Color.BLACK): dense_separators += 1
			check(dense_separators == 0 and dense_image.get_pixelv(dense_anchor + Vector2i(0, 29)).is_equal_approx(Color("a58b60")),
				"dense %s point maximum keeps a solid full reserve without dividers" % String.num(maximum, 0))
		visual.unit.balance = 0.0
		visual.unit.balance_max = 0.0
		visual.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var immune_image := viewport.get_texture().get_image()
		check(immune_image.get_pixelv(Vector2i(_bar_screen_anchor(visual)) + Vector2i(0, 29)).is_equal_approx(Color("a58b60")),
			"zero maximum keeps full immunity fill without segmented divisions")
	visual.unit.balance = old_balance
	visual.unit.balance_max = old_maximum
	visual.queue_redraw()


func _check_armor_visibility_lifecycle() -> void:
	stage.scale = Vector2.ONE
	check(BattleUnitVitalsPainter.armor_amount_text(0.00001) == "<0.1"
		and BattleUnitVitalsPainter.armor_amount_text(0.099) == "<0.1",
		"positive armor below display precision is not labeled zero")
	check(BattleUnitVitalsPainter.armor_amount_text(0.0) == "0"
		and BattleUnitVitalsPainter.armor_amount_text(0.1) == "0.1",
		"zero and the first displayable tenth retain their normal armor amounts")
	# Повторная публикация проверяет живую фигуру: временная броня появляется и исчезает без пересоздания HUD.
	for faction_row: int in 2:
		var visual := visuals[faction_row * 7]
		var faction := Faction.Type.PLAYER if faction_row == 0 else Faction.Type.ENEMY
		var values := _view_values(_vital_cases()[0], &"warrior", faction, 8100 + faction_row * 7,
			Vector2i(faction_row * 3, faction_row * 3))
		var original_armor: Dictionary = values.armor_values.duplicate(true)
		values.armor_values = {}
		check(visual.apply_view(values, config), "no-armor publication updates the existing figure")
		await process_frame
		await RenderingServer.frame_post_draw
		var without_armor := viewport.get_texture().get_image()
		var anchor := _bar_screen_anchor(visual)
		var cases: Array[Dictionary] = [
			{"label": "zero native capacity", "armor": {"maximum": 0.0, "current": 0.0, "extra": 0.0}, "visible": false},
			{"label": "magical grant", "armor": {"maximum": 0.0, "current": 7.5, "extra": 7.5}, "visible": true},
			{"label": "positive fractional grant", "armor": {"maximum": 0.0, "current": 0.00001, "extra": 0.00001}, "visible": true},
			{"label": "spent magical grant", "armor": {"maximum": 0.0, "current": 0.0, "extra": 0.0}, "visible": false},
			{"label": "grant restored again", "armor": {"maximum": 0.0, "current": 3.0, "extra": 3.0}, "visible": true},
			{"label": "depleted equipped armor", "armor": {"maximum": 100.0, "current": 0.0, "extra": 0.0}, "visible": true},
			{"label": "armor absent again", "armor": {}, "visible": false},
		]
		for sample: Dictionary in cases:
			values.armor_values = sample.armor
			# Прогноз нуля не скрывает ещё имеющуюся броню; прогноз получения не создаёт её заранее.
			values.forecast_entry = {"after": {"armor_current": 0.0 if sample.visible else 12.0}}
			check(visual.apply_view(values, config), "%s republishes armor values" % sample.label)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			if sample.visible:
				var color := Color("747d80") if float(sample.armor.current) == 0.0 else Color("c0cacb")
				check(_has_color_near(image, anchor + Vector2(-18.0, 6.5), color, 1.0, 0.01),
					"%s shows the appropriate armor track for faction %d" % [sample.label, faction_row])
				check(_has_centered_dark_ink(image, anchor + Vector2(0.0, 6.5), 1.0),
					"%s shows its armor amount for faction %d" % [sample.label, faction_row])
			else:
				check(_regions_equal(without_armor, anchor, image, anchor, Rect2i(-24, 0, 48, 13)),
					"%s leaves no armor frame, amount or forecast for faction %d" % [sample.label, faction_row])
			for region: Rect2i in [Rect2i(-24, 14, 48, 11), Rect2i(-24, 27, 48, 4)]:
				check(_regions_equal(without_armor, anchor, image, anchor, region),
					"%s preserves HP and balance for faction %d" % [sample.label, faction_row])
			if faction_row == 0 and String(sample.label) in ["zero native capacity", "magical grant", "spent magical grant"]:
				await _capture(image, "unit-vitals-" + String(sample.label).replace(" ", "-"))
		values.armor_values = original_armor
		values.forecast_entry = {}
		visual.apply_view(values, config)


func _bar_origin(visual: BattleDemoIsoVisual) -> Vector2:
	return visual.get_visual_offset() + visual.get_unit_bars_offset() * (config.tile_size.x / 128.0)


func _bar_screen_anchor(visual: BattleDemoIsoVisual) -> Vector2:
	return (visual.get_viewport_transform() * visual.get_global_transform() * _bar_origin(visual)).round()


func _check_crisp_number_pixels() -> void:
	# Равенство областей подтверждает, что экранные полосы не масштабируются вместе с картой.
	var reference_image: Image
	var reference_anchors: Dictionary = {}
	for zoom: float in ZOOMS:
		stage.scale = Vector2.ONE * zoom
		stage.position = Vector2(0.37, 0.61)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image.is_empty():
			check(false, "fractional-pan crispness render returns an image at scale %.2f" % zoom)
			continue
		if is_equal_approx(zoom, 1.0):
			reference_image = image.duplicate()
		for faction_row: int in 2:
			for case_index: int in [0, 3, 6]:
				var visual := visuals[faction_row * 7 + case_index]
				var row: Dictionary = _vital_cases()[case_index]
				var anchor := _bar_screen_anchor(visual)
				var reference_key := faction_row * 7 + case_index
				if is_equal_approx(zoom, 1.0):
					reference_anchors[reference_key] = anchor
				else:
					var reference_anchor: Vector2 = reference_anchors[reference_key]
					for region: Rect2i in [Rect2i(-24, 1, 48, 11), Rect2i(-24, 14, 48, 11), Rect2i(-24, 27, 48, 4)]:
						check(_regions_equal(reference_image, reference_anchor, image, anchor, region),
							"fixed RGBA bar region matches zoom 1.0 at %.2f for %s row %d" % [zoom, row.case, faction_row])
				check(_has_antialiased_black_ink(image, anchor + Vector2(0, 19.5)),
					"PlayBold HP text has black ink and blended antialias edges at zoom %.2f" % zoom)
		if is_equal_approx(zoom, 1.13): await _capture(image, "unit-vitals-fixed-fractional-pan")


func _regions_equal(first: Image, first_anchor: Vector2, second: Image, second_anchor: Vector2, region: Rect2i) -> bool:
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var first_point := Vector2i(roundi(first_anchor.x) + x, roundi(first_anchor.y) + y)
			var second_point := Vector2i(roundi(second_anchor.x) + x, roundi(second_anchor.y) + y)
			if first_point.x < 0 or first_point.y < 0 or second_point.x < 0 or second_point.y < 0: return false
			if first_point.x >= first.get_width() or first_point.y >= first.get_height() or second_point.x >= second.get_width() or second_point.y >= second.get_height(): return false
			if first.get_pixelv(first_point) != second.get_pixelv(second_point): return false
	return true


func _bar_edge_rows_are_palette_only(image: Image, anchor: Vector2, bar_top: int, palette: Array[Color]) -> bool:
	# Ряды у внутренней рамки должны оставаться заливкой/пустым треком, без цифр.
	for y_offset: int in [bar_top + 1, bar_top + 9]:
		for x_offset: int in range(-22, 22):
			var point := Vector2i(roundi(anchor.x) + x_offset, roundi(anchor.y) + y_offset)
			if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height(): return false
			var pixel := image.get_pixelv(point)
			var found := false
			for color: Color in palette:
				if pixel.is_equal_approx(color):
					found = true
					break
			if not found: return false
	return true


func _has_antialiased_black_ink(image: Image, center: Vector2) -> bool:
	var saw_black := false
	var saw_edge := false
	var hp_palette: Array[Color] = [Color("a2bf7b"), Color("bad592"), Color("89a365"), Color("777d70")]
	for y: int in range(roundi(center.y) - 3, roundi(center.y) + 4):
		for x: int in range(roundi(center.x) - 20, roundi(center.x) + 21):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel := image.get_pixel(x, y)
			if pixel.r < 0.04 and pixel.g < 0.04 and pixel.b < 0.04: saw_black = true
			else:
				for base: Color in hp_palette:
					if pixel.is_equal_approx(base): continue
					for coverage: float in [0.2, 0.35, 0.5, 0.65, 0.8]:
						var blended := base * (1.0 - coverage)
						if absf(pixel.r - blended.r) < 0.025 and absf(pixel.g - blended.g) < 0.025 and absf(pixel.b - blended.b) < 0.025:
							saw_edge = true
							break
					if saw_edge: break
	return saw_black and saw_edge


func _has_dark_ink_outside_standard_track(image: Image, center: Vector2) -> bool:
	# Ищем чернила за исходным краем, но внутри расширенного трека и вдали от его обводки.
	for y: int in range(roundi(center.y) - 3, roundi(center.y) + 4):
		for side: int in [-1, 1]:
			for offset: int in range(25, 29):
				var x := roundi(center.x) + side * offset
				if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
				var pixel := image.get_pixel(x, y)
				if pixel.r < 0.12 and pixel.g < 0.12 and pixel.b < 0.12: return true
	return false


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
	var point := _bar_screen_anchor(visual) + Vector2(0.0, 19.0)
	check(not _has_color_near(image, point, Color("a2bf7b"), 1.0),
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
