extends SceneTree

const Visual = preload("res://scripts/demo/battle_demo_iso_visual.gd")
const WARM := Color("f1e4c8")
const COOL := Color("b6cfce")
const OVERFLOW := Color("e0ddcb")
const OLD_PANEL := Color("101d27")

var passed: int = 0
var failed: int = 0
var captures: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL STATUS COUNTER LAYOUT: " + label)

func color_pixel_count(image: Image, expected: Color, rect: Rect2i, tolerance: float = 0.01) -> int:
	var count := 0
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			if absf(pixel.r - expected.r) <= tolerance and absf(pixel.g - expected.g) <= tolerance and absf(pixel.b - expected.b) <= tolerance:
				count += 1
	return count

func new_color_pixel_count(image: Image, reference: Image, expected: Color, rect: Rect2i) -> int:
	var count := 0
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel := image.get_pixel(x, y)
			var prior := reference.get_pixel(x, y)
			var coverage := tint_coverage(pixel, prior, expected)
			if pixel.a >= 0.5 and coverage >= 0.08:
				count += 1
	return count

func new_colored_bounds(image: Image, reference: Image, expected: Color, rect: Rect2i) -> Rect2i:
	var result := Rect2i()
	var initialized := false
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel := image.get_pixel(x, y)
			var prior := reference.get_pixel(x, y)
			if pixel.a < 0.5 or tint_coverage(pixel, prior, expected) < 0.08: continue
			if not initialized:
				result = Rect2i(x, y, 1, 1)
				initialized = true
			else:
				var right := maxi(result.end.x, x + 1)
				var bottom := maxi(result.end.y, y + 1)
				result.position.x = mini(result.position.x, x)
				result.position.y = mini(result.position.y, y)
				result.size = Vector2i(right - result.position.x, bottom - result.position.y)
	return result

func tint_coverage(actual: Color, reference: Color, tint: Color) -> float:
	# Сглаженные края глифа смешивают светлый цвет с рисунком или тёмной обводкой.
	var actual_channels: Array[float] = [actual.r, actual.g, actual.b]
	var reference_channels: Array[float] = [reference.r, reference.g, reference.b]
	var tint_channels: Array[float] = [tint.r, tint.g, tint.b]
	var channel_index := 0
	var largest_delta := 0.0
	for index: int in 3:
		var delta := absf(tint_channels[index] - reference_channels[index])
		if delta > largest_delta:
			channel_index = index
			largest_delta = delta
	if largest_delta < 0.12: return -1.0
	var coverage := (actual_channels[channel_index] - reference_channels[channel_index]) \
		/ (tint_channels[channel_index] - reference_channels[channel_index])
	if coverage < 0.05 or coverage > 1.08: return -1.0
	var estimate := reference.lerp(tint, clampf(coverage, 0.0, 1.0))
	if absf(actual.r - estimate.r) > 0.14 or absf(actual.g - estimate.g) > 0.14 \
		or absf(actual.b - estimate.b) > 0.14:
		return -1.0
	return coverage

func count_color_outside(image: Image, expected: Color, protected_rect: Rect2i) -> int:
	var count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if protected_rect.has_point(Vector2i(x, y)):
				continue
			var pixel := image.get_pixel(x, y)
			if pixel.a >= 0.5 and absf(pixel.r - expected.r) < 0.035 and absf(pixel.g - expected.g) < 0.035 and absf(pixel.b - expected.b) < 0.035:
				count += 1
	return count

func draw_probe(entries: Array[Dictionary], scale: float, offset: Vector2, hovered: bool = false, selected: bool = false, inspected: bool = false) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Node2D.new()
	canvas.position = Vector2(128, 64) + offset
	canvas.scale = Vector2.ONE * scale
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var visual := Visual.new()
	visual.status_entries = entries
	visual.hovered = hovered
	visual.selected = selected
	visual.inspected = inspected
	var draw_callback := visual._draw_status_icons.bind(canvas)
	canvas.draw.connect(draw_callback)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	canvas.draw.disconnect(draw_callback)
	visual.free()
	viewport.queue_free()
	await process_frame
	return image

func draw_panel_probe(scale: float, offset: Vector2) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Node2D.new()
	canvas.position = Vector2(128, 64) + offset
	canvas.scale = Vector2.ONE * scale
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var draw_callback := func() -> void:
		canvas.draw_style_box(Visual.STATUS_HOVER_PANEL, Rect2(-14, -27, 28, 24))
	canvas.draw.connect(draw_callback)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	canvas.draw.disconnect(draw_callback)
	viewport.queue_free()
	await process_frame
	return image

func draw_hover_sequence(entries: Array[Dictionary], scale: float, offset: Vector2) -> Array[Image]:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Node2D.new()
	canvas.position = Vector2(128, 64) + offset
	canvas.scale = Vector2.ONE * scale
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var visual := Visual.new()
	visual.status_entries = entries
	var draw_callback := visual._draw_status_icons.bind(canvas)
	canvas.draw.connect(draw_callback)
	var images: Array[Image] = []
	for state: bool in [false, true, false]:
		visual.hovered = state
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
	canvas.draw.disconnect(draw_callback)
	visual.free()
	viewport.queue_free()
	await process_frame
	return images

func save_capture(image: Image, label: String) -> void:
	if captures.is_empty():
		return
	check(image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func pixel_region(scale: float, offset: Vector2, local_rect: Rect2) -> Rect2i:
	var origin := Vector2(128, 64) + offset
	var top_left := origin + local_rect.position * scale
	var bottom_right := origin + local_rect.end * scale
	return Rect2i(Vector2i(floori(top_left.x), floori(top_left.y)), Vector2i(ceili(bottom_right.x) - floori(top_left.x), ceili(bottom_right.y) - floori(top_left.y)))

func changed_bounds(image: Image, reference: Image, rect: Rect2i) -> Rect2i:
	var result := Rect2i()
	var initialized := false
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).is_equal_approx(reference.get_pixel(x, y)): continue
			if not initialized:
				result = Rect2i(x, y, 1, 1)
				initialized = true
			else:
				var right := maxi(result.end.x, x + 1)
				var bottom := maxi(result.end.y, y + 1)
				result.position.x = mini(result.position.x, x)
				result.position.y = mini(result.position.y, y)
				result.size = Vector2i(right - result.position.x, bottom - result.position.y)
	return result

func has_antialiased_counter_edge(image: Image, reference: Image, rect: Rect2i, tint: Color) -> bool:
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var actual := image.get_pixel(x, y)
			var prior := reference.get_pixel(x, y)
			if actual.is_equal_approx(prior): continue
			var coverage := tint_coverage(actual, prior, tint)
			if coverage >= 0.08 and coverage <= 0.95: return true
	return false

func opaque_pixel_count(image: Image, rect: Rect2i) -> int:
	var count := 0
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a > 0.5:
				count += 1
	return count

func painted_inside_bounds(image: Image, scale: float, offset: Vector2, bounds: Rect2) -> bool:
	var origin := Vector2(128, 64) + offset
	var allowed := bounds.grow(1.0)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a < 0.05: continue
			var local := (Vector2(x, y) + Vector2(0.5, 0.5) - origin) / scale
			if not allowed.has_point(local): return false
	return true

func counter_regions(scale: float, offset: Vector2) -> Dictionary:
	# Первая иконка стоит у левого края горизонтального ряда над полосами.
	return {
		"icon": pixel_region(scale, offset, Rect2(-10, -25, 20, 20)),
		"stack": pixel_region(scale, offset, Rect2(-10, -25, 10, 9)),
		"duration": pixel_region(scale, offset, Rect2(2, -15, 8, 10)),
	}

func status(id: String, stacks: int, remaining: int) -> Dictionary:
	return {"id": id, "stacks": stacks, "remaining": remaining}

func run() -> void:
	var simple := [status("bleeding", 2, 3)] as Array[Dictionary]
	var icon_only := [status("bleeding", 0, 0)] as Array[Dictionary]
	var wet := [status("wet", 0, 2)] as Array[Dictionary]
	var large := [status("poison", 123, 123)] as Array[Dictionary]
	var crowded: Array[Dictionary] = [status("bleeding", 2, 3), status("burning", 4, 5), status("wet", 0, 2), status("poison", 99, 123), status("acid", 1, 1), status("extra_a", 0, 0), status("extra_b", 0, 0), status("extra_c", 0, 0), status("bleeding", 77, 77), {"id": "stunned", "stacks": 4, "remaining": 4, "embodied": true}]
	var structural := Visual.new()
	structural.status_entries = crowded
	var visible := structural.visible_status_entries()
	check(visible.size() == 3 and structural.status_overflow_count() == 5, "three icons and +5 overflow follow deduplication and embodied filtering")
	var box := structural.status_hud_bounds()
	check(box == Rect2(-41, -27, 82, 24), "overflow panel stays 82 by 24 above the armor bar")
	structural.hovered = true
	check(structural.status_hud_bounds() == box, "hover backing never shifts status layout bounds")
	var widths: Array[float] = [28.0, 46.0, 60.0]
	var steps: Array[float] = [20.0, 18.0, 16.0]
	check(Visual.STATUS_ICON_SIZE == 18.0 and Visual.STATUS_SLOT_SIZE == 20.0,
		"status drawing is 18px while its established layout slot remains 20px")
	for count: int in range(1, 4):
		var unique: Array[Dictionary] = []
		for index: int in count:
			unique.append(status("layout-%d" % index, 0, 1))
		structural.status_entries = unique
		var current_bounds := structural.status_hud_bounds()
		check(current_bounds.position == Vector2(-widths[count - 1] * 0.5, -27.0)
			and current_bounds.size == Vector2(widths[count - 1], 24.0), "panel width for %d icons preserves centered row and fixed vertical anchor" % count)
		check(structural._status_icon_step(count) == steps[count - 1], "%d icons keep the original bounded slot overlap" % count)
	structural.status_entries = crowded.slice(0, 4)
	check(structural.status_hud_bounds() == Rect2(-41, -27, 82, 24) and structural.status_overflow_count() == 1, "overflow extends the three-icon row to its 82-pixel maximum")
	structural.status_entries = []
	check(structural.status_hud_bounds() == Rect2(), "empty row has neither hover bounds nor an empty panel")
	structural.status_entries = wet
	check(structural.visible_status_entries()[0].stacks == 0 and structural.visible_status_entries()[0].remaining == 2, "wet duration is retained without a stack badge")
	structural.free()
	var source_icon := BattleConditionIcons.character_texture(&"bleeding")
	var source_image := source_icon.get_image() if source_icon != null else Image.new()
	var partial_alpha := false
	if not source_image.is_empty():
		for y: int in source_image.get_height():
			for x: int in source_image.get_width():
				var alpha := source_image.get_pixel(x, y).a
				if alpha > 0.0 and alpha < 1.0:
					partial_alpha = true
					break
			if partial_alpha: break
	check(source_icon != null and source_icon.get_width() == 96 and source_icon.get_height() == 96 and partial_alpha,
		"character status symbol uses the 96px transparent vector source with antialiased alpha")
	var panel_image := Visual.STATUS_HOVER_PANEL.texture.get_image()
	var panel_source := Image.new()
	var panel_error := panel_source.load_png_from_buffer(FileAccess.get_file_as_bytes(Visual.STATUS_HOVER_PANEL.texture.resource_path))
	check(panel_error == OK and panel_image.get_width() > 0 and panel_image.get_height() > 0, "horizontal panel source loads for the status row")
	if panel_error == OK:
		panel_image.convert(Image.FORMAT_RGBA8)
		panel_source.convert(Image.FORMAT_RGBA8)
		check(panel_image.get_data() == panel_source.get_data(), "panel import preserves source RGBA and transparent pixels")
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
	if DisplayServer.get_name() == "headless":
		print("STATUS COUNTER LAYOUT RESULTS: %d passed, %d failed, pixel checks skipped (headless)" % [passed, failed])
		quit(1 if failed > 0 else 0)
		return
	var at_one := await draw_probe(simple, 1.0, Vector2(0.35, 0.65))
	var at_three_quarters := await draw_probe(simple, 0.75, Vector2(0.35, 0.65))
	var hovered_one := await draw_probe(simple, 1.0, Vector2(0.35, 0.65), true)
	var hovered_three_quarters := await draw_probe(simple, 0.75, Vector2(0.35, 0.65), true)
	var selected_only := await draw_probe(simple, 1.0, Vector2(0.35, 0.65), false, true, false)
	var inspected_only := await draw_probe(simple, 1.0, Vector2(0.35, 0.65), false, false, true)
	var hover_transitions := await draw_hover_sequence(simple, 1.0, Vector2(0.35, 0.65))
	var reference := await draw_probe(icon_only, 1.0, Vector2(0.35, 0.65), true)
	var empty_panel := await draw_panel_probe(1.0, Vector2(0.35, 0.65))
	var reference_three_quarters := await draw_probe(icon_only, 0.75, Vector2(0.35, 0.65), true)
	save_capture(at_one, "status-counter-idle-100")
	save_capture(at_three_quarters, "status-counter-idle-075")
	save_capture(hovered_one, "status-counter-hover-on-100")
	save_capture(hovered_three_quarters, "status-counter-hover-on-075")
	save_capture(hover_transitions[0], "status-counter-hover-off")
	save_capture(hover_transitions[2], "status-counter-hover-restored-off")
	var regions_one := counter_regions(1.0, Vector2(0.35, 0.65))
	var regions_three_quarters := counter_regions(0.75, Vector2(0.35, 0.65))
	var icon: Rect2i = regions_one["icon"]
	var hover_panel_probe := pixel_region(1.0, Vector2(0.35, 0.65), Rect2(-14, -27, 28, 24))
	var hover_panel_probe_075 := pixel_region(0.75, Vector2(0.35, 0.65), Rect2(-14, -27, 28, 24))
	check(opaque_pixel_count(hover_transitions[0], hover_panel_probe) == 0 and opaque_pixel_count(hover_transitions[1], hover_panel_probe) > 0 and opaque_pixel_count(hover_transitions[2], hover_panel_probe) == 0, "hover panel appears on hover and clears when hover leaves")
	check(opaque_pixel_count(at_one, hover_panel_probe) == 0 and opaque_pixel_count(hovered_one, hover_panel_probe) > 0, "idle icon row gains backing only while hovered at 100 percent")
	check(opaque_pixel_count(at_three_quarters, hover_panel_probe_075) == 0 and opaque_pixel_count(hovered_three_quarters, hover_panel_probe_075) > 0, "hover backing remains visible at 75 percent zoom")
	check(opaque_pixel_count(at_one, Rect2i(0, 0, at_one.get_width(), at_one.get_height())) == 0 and opaque_pixel_count(hovered_one, Rect2i(0, 0, hovered_one.get_width(), hovered_one.get_height())) > 0, "idle hides the full status row and hover restores icons and counters")
	check(opaque_pixel_count(selected_only, hover_panel_probe) == 0 and opaque_pixel_count(inspected_only, hover_panel_probe) == 0, "selection and inspection alone do not show hover backing")
	check(opaque_pixel_count(selected_only, Rect2i(0, 0, selected_only.get_width(), selected_only.get_height())) == 0 and opaque_pixel_count(inspected_only, Rect2i(0, 0, inspected_only.get_width(), inspected_only.get_height())) == 0, "selection and inspection alone hide status icons and counters")
	check(opaque_pixel_count(hover_transitions[0], Rect2i(0, 0, hover_transitions[0].get_width(), hover_transitions[0].get_height())) == 0 and opaque_pixel_count(hover_transitions[2], Rect2i(0, 0, hover_transitions[2].get_width(), hover_transitions[2].get_height())) == 0, "status icons, counters, and backing disappear immediately when hover ends")
	var empty_hover := await draw_probe([], 1.0, Vector2.ZERO, true)
	check(opaque_pixel_count(empty_hover, Rect2i(0, 0, empty_hover.get_width(), empty_hover.get_height())) == 0, "hover does not draw a panel for an empty status row")
	var upper_left: Rect2i = regions_one["stack"]
	var lower_right: Rect2i = regions_one["duration"]
	var warm_one := new_color_pixel_count(hovered_one, reference, WARM, upper_left)
	var cool_one := new_color_pixel_count(hovered_one, reference, COOL, lower_right)
	check(warm_one > 0, "stack glyph appears in upper-left icon region")
	check(cool_one > 0, "duration glyph appears in lower-right icon region")
	var icon_ink := changed_bounds(reference, empty_panel,
		pixel_region(1.0, Vector2(0.35, 0.65), Rect2(-10, -25, 20, 20)))
	check(icon_ink.size != Vector2i.ZERO and icon_ink.size.x <= 18 and icon_ink.size.y <= 18,
		"icon-only render confirms the 18px drawing fits the unchanged 20px slot")
	var fallback_image := await draw_probe([status("extra_a", 0, 0)] as Array[Dictionary], 1.0, Vector2(0.35, 0.65), true)
	var fallback_ink := changed_bounds(fallback_image, empty_panel,
		pixel_region(1.0, Vector2(0.35, 0.65), Rect2(-10, -25, 20, 20)))
	check(fallback_ink.size != Vector2i.ZERO and fallback_ink.size.x <= 8 and fallback_ink.size.y <= 8,
		"fallback diamond also scales to 90 percent inside the original slot")
	var counter_font := Visual._status_counter_font.base_font as FontFile
	var original_play_data := FileAccess.get_file_as_bytes("res://assets/ui/combat_fonts/combat_letters.ttf")
	check(counter_font != null and not original_play_data.is_empty() and counter_font.data == original_play_data
		and counter_font.antialiasing == TextServer.FONT_ANTIALIASING_GRAY
		and counter_font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED,
		"status counters use the real Play Bold subset with grayscale AA and no subpixel placement")
	check(has_antialiased_counter_edge(hovered_one, reference, upper_left, WARM),
		"status counter render diff contains a grayscale blended Play glyph edge")
	var remaining_icon_pixels := 0
	for y: int in range(icon.position.y, icon.end.y):
		for x: int in range(icon.position.x, icon.end.x):
			var pixel := hovered_one.get_pixel(x, y)
			if pixel.a >= 0.5 and pixel == reference.get_pixel(x, y):
				remaining_icon_pixels += 1
	check(remaining_icon_pixels > 20, "original icon foreground remains visible beneath the counters")
	var glyph_one := new_colored_bounds(hovered_one, reference, WARM, upper_left)
	var glyph_three_quarters := new_colored_bounds(hovered_three_quarters, reference_three_quarters, WARM, regions_three_quarters["stack"])
	check(glyph_one.size.y >= 6 and glyph_three_quarters.size.y >= 4
		and glyph_three_quarters.size.y <= glyph_one.size.y,
		"coverage-aware screen-space glyphs remain legible as they scale from 100 to 75 percent")
	check(new_color_pixel_count(hovered_three_quarters, reference_three_quarters, COOL, regions_three_quarters["duration"]) > 0, "duration remains visible inside the icon at 75 percent")
	var outside_icon := icon.grow(1)
	check(count_color_outside(hovered_one, WARM, outside_icon) == 0 and count_color_outside(hovered_one, COOL, outside_icon) == 0, "counter tints stay within the icon with one-pixel outline tolerance")
	var outside_icon_three_quarters: Rect2i = regions_three_quarters["icon"].grow(1)
	check(count_color_outside(hovered_three_quarters, WARM, outside_icon_three_quarters) == 0 and count_color_outside(hovered_three_quarters, COOL, outside_icon_three_quarters) == 0, "scaled counter tints stay within the icon with one-pixel tolerance")
	check(count_color_outside(hovered_one, OLD_PANEL, outside_icon) == 0, "old dark counter backplate color is absent outside icon pixels")
	var bounds_visual := Visual.new()
	bounds_visual.status_entries = simple
	var expected_bounds := bounds_visual.status_hud_bounds()
	bounds_visual.free()
	var painted := Rect2i()
	var has_painted := false
	for y: int in range(hovered_one.get_height()):
		for x: int in range(hovered_one.get_width()):
			if hovered_one.get_pixel(x, y).a < 0.05: continue
			if not has_painted:
				painted = Rect2i(x, y, 1, 1)
				has_painted = true
			else:
				var right := maxi(painted.end.x, x + 1)
				var bottom := maxi(painted.end.y, y + 1)
				painted.position.x = mini(painted.position.x, x)
				painted.position.y = mini(painted.position.y, y)
				painted.size = Vector2i(right - painted.position.x, bottom - painted.position.y)
	var bounds_contain_paint := false
	if has_painted:
		var local_top_left := Vector2(painted.position) - (Vector2(128, 64) + Vector2(0.35, 0.65))
		var local_bottom_right := Vector2(painted.end) - (Vector2(128, 64) + Vector2(0.35, 0.65))
		bounds_contain_paint = expected_bounds.grow(1.0).has_point(local_top_left) and expected_bounds.grow(1.0).has_point(local_bottom_right)
	check(bounds_contain_paint, "painted pixels fit status bounds with one-pixel tolerance")
	var simple_bounds := Rect2(-14, -27, 28, 24)
	check(painted_inside_bounds(hovered_one, 1.0, Vector2(0.35, 0.65), simple_bounds)
		and painted_inside_bounds(hovered_three_quarters, 0.75, Vector2(0.35, 0.65), simple_bounds),
		"horizontal panel, counters, and symbol paint remain within bounds at 100 and 75 percent")
	var wet_image := await draw_probe(wet, 1.0, Vector2.ZERO, true)
	var wet_reference := await draw_probe([status("wet", 0, 0)] as Array[Dictionary], 1.0, Vector2.ZERO, true)
	save_capture(wet_image, "status-counter-wet")
	var wet_regions := counter_regions(1.0, Vector2.ZERO)
	var wet_stack_region: Rect2i = wet_regions["stack"]
	check(new_color_pixel_count(wet_image, wet_reference, WARM, wet_stack_region) == 0, "zero stacks draw no stack badge")
	var wet_duration_region: Rect2i = wet_regions["duration"]
	check(new_color_pixel_count(wet_image, wet_reference, COOL, wet_duration_region) > 0, "zero-stack status still draws duration")
	var large_image := await draw_probe(large, 1.0, Vector2.ZERO, true)
	var large_reference := await draw_probe([status("poison", 0, 0)] as Array[Dictionary], 1.0, Vector2.ZERO, true)
	save_capture(large_image, "status-counter-99plus")
	var large_regions := counter_regions(1.0, Vector2.ZERO)
	var large_stack_region: Rect2i = large_regions["stack"]
	var large_duration_region: Rect2i = large_regions["duration"]
	check(new_color_pixel_count(large_image, large_reference, WARM, large_stack_region) > 0 and new_color_pixel_count(large_image, large_reference, COOL, large_duration_region) > 0, "99+ stack and remaining labels render")
	var crowded_image := await draw_probe(crowded, 1.0, Vector2.ZERO)
	var crowded_hover_image := await draw_probe(crowded, 1.0, Vector2.ZERO, true)
	save_capture(crowded_image, "status-counter-overflow")
	save_capture(crowded_hover_image, "status-counter-overflow-hover")
	var overflow_region := pixel_region(1.0, Vector2.ZERO, Rect2(17, -23, 20, 14))
	check(color_pixel_count(crowded_hover_image, OVERFLOW, overflow_region) > 0, "overflow +5 remains visible inside the compact row while hovered")
	var overflow_panel_probe := pixel_region(1.0, Vector2.ZERO, Rect2(-41, -27, 82, 24))
	check(opaque_pixel_count(crowded_image, overflow_panel_probe) == 0 and opaque_pixel_count(crowded_hover_image, overflow_panel_probe) > 0, "overflow status row also receives backing only while hovered")
	check(color_pixel_count(crowded_hover_image, WARM, overflow_region) == 0 and color_pixel_count(crowded_hover_image, COOL, overflow_region) == 0, "overflow label keeps its distinct light tint")
	var flat_entries: Array[Dictionary] = [status("bleeding", 2, 3), status("burning", 0, 0), status("poison", 0, 0), status("acid", 0, 0), status("wet", 0, 0)]
	var first_alone := await draw_probe(simple, 1.0, Vector2(-27, 0), true)
	var dense := await draw_probe(flat_entries, 1.0, Vector2.ZERO, true)
	var first_slot := pixel_region(1.0, Vector2.ZERO, Rect2(-37, -25, 20, 20))
	check(color_pixel_count(dense, WARM, first_slot) == color_pixel_count(first_alone, WARM, first_slot) and color_pixel_count(dense, COOL, first_slot) == color_pixel_count(first_alone, COOL, first_slot), "later overlapping icons cannot paint over the first icon counters")
	for count: int in range(1, 4):
		var subset: Array[Dictionary] = []
		for index: int in count: subset.append(flat_entries[index])
		var count_image := await draw_probe(subset, 1.0, Vector2.ZERO, true)
		var count_image_075 := await draw_probe(subset, 0.75, Vector2(0.35, 0.65), true)
		save_capture(count_image, "status-density-%d-100" % count)
		save_capture(count_image_075, "status-density-%d-075" % count)
		var left_cap := Rect2(-widths[count - 1] * 0.5, -27, 2, 24)
		var right_cap := Rect2(widths[count - 1] * 0.5 - 2, -27, 2, 24)
		check(opaque_pixel_count(count_image, pixel_region(1.0, Vector2.ZERO, left_cap)) > 0
			and opaque_pixel_count(count_image, pixel_region(1.0, Vector2.ZERO, right_cap)) > 0
			and opaque_pixel_count(count_image_075, pixel_region(0.75, Vector2(0.35, 0.65), left_cap)) > 0
			and opaque_pixel_count(count_image_075, pixel_region(0.75, Vector2(0.35, 0.65), right_cap)) > 0,
			"horizontal panel end caps remain visible with %d effects at 100/75 percent" % count)
	print("STATUS COUNTER LAYOUT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
