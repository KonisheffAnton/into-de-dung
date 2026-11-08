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

func colored_bounds(image: Image, expected: Color, rect: Rect2i) -> Rect2i:
	var result := Rect2i()
	var initialized := false
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5 or absf(pixel.r - expected.r) > 0.01 or absf(pixel.g - expected.g) > 0.01 or absf(pixel.b - expected.b) > 0.01:
				continue
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

func draw_probe(entries: Array[Dictionary], scale: float, offset: Vector2) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Node2D.new()
	canvas.position = Vector2(128, 64) + offset
	canvas.scale = Vector2.ONE * scale
	viewport.add_child(canvas)
	var visual := Visual.new()
	visual.status_entries = entries
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

func save_capture(image: Image, label: String) -> void:
	if captures.is_empty():
		return
	check(image.save_png(captures.path_join(label + ".png")) == OK, "PNG " + label)

func pixel_region(scale: float, offset: Vector2, local_rect: Rect2) -> Rect2i:
	var origin := Vector2(128, 64) + offset
	var top_left := origin + local_rect.position * scale
	var bottom_right := origin + local_rect.end * scale
	return Rect2i(Vector2i(floori(top_left.x), floori(top_left.y)), Vector2i(ceili(bottom_right.x) - floori(top_left.x), ceili(bottom_right.y) - floori(top_left.y)))

func counter_regions(scale: float, offset: Vector2) -> Dictionary:
	var center := Vector2(128, 64) + offset
	var slot_left := center.x - 8.0 * scale - 2.0
	var slot_width := 16.0 * scale + 4.0
	var stack_baseline := center.y - 27.0 * scale
	var duration_baseline := center.y - 1.0 * scale
	var icon_top := center.y - 25.0 * scale
	var icon_bottom := center.y - 9.0 * scale
	var stack_top := floori(stack_baseline - 13.0)
	var stack_bottom := floori(icon_top - 0.5)
	var duration_top := ceili(icon_bottom + 0.5)
	var duration_bottom := ceili(duration_baseline + 1.0)
	return {
		"icon": pixel_region(scale, offset, Rect2(-8, -25, 16, 16)),
		"stack": Rect2i(floori(slot_left), stack_top, ceili(slot_width), maxi(0, stack_bottom - stack_top)),
		"duration": Rect2i(floori(slot_left), duration_top, ceili(slot_width), maxi(0, duration_bottom - duration_top)),
	}

func status(id: String, stacks: int, remaining: int) -> Dictionary:
	return {"id": id, "stacks": stacks, "remaining": remaining}

func run() -> void:
	var simple := [status("bleeding", 2, 3)] as Array[Dictionary]
	var wet := [status("wet", 0, 2)] as Array[Dictionary]
	var large := [status("poison", 123, 123)] as Array[Dictionary]
	var crowded: Array[Dictionary] = [status("bleeding", 2, 3), status("burning", 4, 5), status("wet", 0, 2), status("poison", 99, 123), status("acid", 1, 1), status("extra_a", 0, 0), status("extra_b", 0, 0), status("extra_c", 0, 0)]
	var structural := Visual.new()
	structural.status_entries = crowded
	var visible := structural.visible_status_entries()
	check(visible.size() == 5 and structural.status_overflow_count() == 3, "five icons retain +3 overflow")
	var box := structural.status_hud_bounds()
	check(box.position.y == -36.0 and box.size.y == 36.0, "bounds reserve both counter rows")
	structural.status_entries = wet
	check(structural.visible_status_entries()[0].stacks == 0 and structural.visible_status_entries()[0].remaining == 2, "wet duration is retained without a stack badge")
	structural.free()
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
	if OS.has_feature("headless"):
		print("STATUS COUNTER LAYOUT RESULTS: %d passed, %d failed, pixel checks skipped (headless)" % [passed, failed])
		quit(1 if failed > 0 else 0)
		return
	var at_one := await draw_probe(simple, 1.0, Vector2(0.35, 0.65))
	var at_three_quarters := await draw_probe(simple, 0.75, Vector2(0.35, 0.65))
	save_capture(at_one, "status-counter-simple-100")
	save_capture(at_three_quarters, "status-counter-simple-075")
	var regions_one := counter_regions(1.0, Vector2(0.35, 0.65))
	var regions_three_quarters := counter_regions(0.75, Vector2(0.35, 0.65))
	var icon: Rect2i = regions_one["icon"]
	var above: Rect2i = regions_one["stack"]
	var below: Rect2i = regions_one["duration"]
	var warm_one := color_pixel_count(at_one, WARM, above)
	var cool_one := color_pixel_count(at_one, COOL, below)
	check(warm_one > 0, "stack glyph has foreground pixels above icon")
	check(cool_one > 0, "duration glyph has foreground pixels below icon")
	check(color_pixel_count(at_one, WARM, icon, 0.025) == 0 and color_pixel_count(at_one, COOL, icon, 0.025) == 0, "flat counter glyph fills do not cover icon pixels")
	var glyph_one := colored_bounds(at_one, WARM, above)
	var glyph_three_quarters := colored_bounds(at_three_quarters, WARM, regions_three_quarters["stack"])
	check(glyph_one.size != Vector2i.ZERO and abs(glyph_one.size.y - glyph_three_quarters.size.y) <= 2, "screen-space glyph height remains legible at both scales")
	var black_panels := count_color_outside(at_one, OLD_PANEL, icon)
	check(black_panels == 0, "old dark counter backplate color is absent outside icon pixels")
	var bounds_visual := Visual.new()
	bounds_visual.status_entries = simple
	var expected_bounds := bounds_visual.status_hud_bounds()
	bounds_visual.free()
	var painted := Rect2i()
	var has_painted := false
	for y: int in range(at_one.get_height()):
		for x: int in range(at_one.get_width()):
			if at_one.get_pixel(x, y).a < 0.05: continue
			if not has_painted:
				painted = Rect2i(x, y, 1, 1)
				has_painted = true
			else:
				var right := maxi(painted.end.x, x + 1)
				var bottom := maxi(painted.end.y, y + 1)
				painted.position.x = mini(painted.position.x, x)
				painted.position.y = mini(painted.position.y, y)
				painted.size = Vector2i(right - painted.position.x, bottom - painted.position.y)
	if has_painted:
		var local_top_left := Vector2(painted.position) - (Vector2(128, 64) + Vector2(0.35, 0.65))
		var local_bottom_right := Vector2(painted.end) - (Vector2(128, 64) + Vector2(0.35, 0.65))
		check(expected_bounds.grow(1.0).has_point(local_top_left) and expected_bounds.grow(1.0).has_point(local_bottom_right), "painted pixels fit status bounds with one-pixel tolerance")
	var wet_image := await draw_probe(wet, 1.0, Vector2.ZERO)
	save_capture(wet_image, "status-counter-wet")
	var wet_regions := counter_regions(1.0, Vector2.ZERO)
	check(color_pixel_count(wet_image, WARM, wet_regions["stack"]) == 0, "zero stacks draw no stack badge")
	var wet_duration_region: Rect2i = wet_regions["duration"]
	check(color_pixel_count(wet_image, COOL, wet_duration_region) > 0, "zero-stack status still draws duration")
	var large_image := await draw_probe(large, 1.0, Vector2.ZERO)
	save_capture(large_image, "status-counter-99plus")
	var large_regions := counter_regions(1.0, Vector2.ZERO)
	var large_stack_region: Rect2i = large_regions["stack"]
	var large_duration_region: Rect2i = large_regions["duration"]
	check(color_pixel_count(large_image, WARM, large_stack_region) > 0 and color_pixel_count(large_image, COOL, large_duration_region) > 0, "99+ stack and remaining labels render")
	var crowded_image := await draw_probe(crowded, 1.0, Vector2.ZERO)
	save_capture(crowded_image, "status-counter-overflow")
	var overflow_slot_width := 26.0
	var overflow_total_width := float(Visual.STATUS_ICON_LIMIT) * Visual.STATUS_ICON_SIZE + float(Visual.STATUS_ICON_LIMIT) * Visual.STATUS_ICON_GAP + overflow_slot_width
	var overflow_start := 128.0 + overflow_total_width * 0.5 - overflow_slot_width
	var overflow_baseline := 64.0 - 14.0
	var overflow_region := Rect2i(floori(overflow_start + 1.0), floori(overflow_baseline - 12.0), 24, 14)
	check(color_pixel_count(crowded_image, OVERFLOW, overflow_region) > 0, "overflow +3 remains visible beyond five icon slots")
	check(color_pixel_count(crowded_image, WARM, overflow_region) == 0 and color_pixel_count(crowded_image, COOL, overflow_region) == 0, "overflow label keeps its distinct light tint")
	print("STATUS COUNTER LAYOUT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
