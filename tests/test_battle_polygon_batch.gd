extends SceneTree

const DUNGEON_TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
const BATCH_SCRIPT: Script = preload("res://scripts/demo/battle_polygon_batch.gd")
const SIMPLE_POLYGON_COUNT: int = 64
const CHANNEL_TOLERANCE: float = 1.0 / 255.0 + 0.000001

var passed: int = 0
var failed: int = 0
var max_channel_delta: float = 0.0
var batch_metrics: Dictionary = {}
var viewport: SubViewport
var content: Node2D
var dungeon: BattleTerrainVisual
var polygons: Array[Polygon2D] = []
var simple_polygons: Array[Polygon2D] = []
var texture: Texture2D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE POLYGON BATCH: " + label)

func _run() -> void:
	var original_root_children := root.get_child_count()
	_build_scene()
	var authored_before := _authoring_signature()
	var native_image := await _capture_if_renderable()
	var native_draw_calls := _draw_calls()
	check(dungeon != null and not dungeon.batch_simple_polygons, "dungeon comparison tile starts on native Polygon2D path")
	check(polygons.size() >= SIMPLE_POLYGON_COUNT + 5, "fixture contains the batch group and unsupported fallback cases")
	check(_batch_connections(false), "native setup has no batch callback connections")
	if not native_image.is_empty(): check(native_image.get_size() == Vector2i(1024, 768), "native oracle image captured")
	_enable_batch()
	var batch_image := await _capture_if_renderable()
	var batch_draw_calls := _draw_calls()
	check(_authoring_signature() == authored_before, "enabling the batch preserves node IDs and authored geometry/properties")
	check(_batch_connections(true), "eligible polygons receive one batch callback without helper nodes")
	if not native_image.is_empty() and not batch_image.is_empty():
		var first_diff := _compare_images(native_image, batch_image)
		max_channel_delta = maxf(max_channel_delta, first_diff.max_delta)
		check(first_diff.equal, "batch image matches native oracle within 1/255 per channel")
	else:
		print("BATTLE POLYGON BATCH RENDER CHECKS SKIPPED: headless/no render target")
	var gpu := DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if gpu:
		check(batch_draw_calls < native_draw_calls, "Compatibility batches the 64 shared-texture quads into fewer 2D draw calls")
		batch_metrics = {"native_draw_calls": native_draw_calls, "batch_draw_calls": batch_draw_calls}
	else:
		batch_metrics = {"draw_calls_skipped": true, "display_server": DisplayServer.get_name(),
			"renderer": RenderingServer.get_current_rendering_method()}
		print("BATTLE POLYGON BATCH DRAW-CALL CHECK SKIPPED: requires Compatibility GPU rendering")
	await _mutate_and_compare_native()
	await _disable_and_check_native()
	viewport.queue_free()
	await process_frame
	await process_frame
	check(root.get_child_count() == original_root_children, "freeing batch owner removes its viewport without helper nodes")
	var released := true
	for polygon: Polygon2D in polygons: released = released and not is_instance_valid(polygon)
	check(released, "owner teardown releases polygon nodes and their bound callbacks")
	print("BATTLE POLYGON BATCH METRICS: %s" % JSON.stringify(batch_metrics))
	print("BATTLE POLYGON BATCH MAX CHANNEL DELTA: %.6f" % max_channel_delta)
	print("BATTLE POLYGON BATCH RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _build_scene() -> void:
	viewport = SubViewport.new()
	viewport.name = "BatchOracleViewport"
	viewport.size = Vector2i(1024, 768)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	content = Node2D.new()
	content.name = "AuthoredPolygonOwner"
	content.position = Vector2(6, 4)
	content.rotation = 0.01
	content.scale = Vector2(1.05, 1.0)
	content.modulate = Color(1.0, 0.96, 0.9, 1.0)
	viewport.add_child(content)
	dungeon = DUNGEON_TILE.instantiate() as BattleTerrainVisual
	dungeon.batch_simple_polygons = false
	dungeon.grid_config = IsoGridConfig.new()
	dungeon.position = Vector2(128, 150)
	content.add_child(dungeon)
	for candidate: Node in dungeon.find_children("*", "Polygon2D", true, false):
		polygons.append(candidate as Polygon2D)
	texture = _make_texture()
	for index: int in SIMPLE_POLYGON_COUNT:
		var polygon := _make_simple_polygon(index)
		content.add_child(polygon)
		polygons.append(polygon)
		simple_polygons.append(polygon)
	_add_fallback_polygons()

func _make_simple_polygon(index: int) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = "SharedTextureQuad%02d" % index
	polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(22, 0), Vector2(22, 22), Vector2(0, 22)])
	polygon.uv = PackedVector2Array([Vector2.ZERO, Vector2(24, 0), Vector2(24, 24), Vector2(0, 24)])
	polygon.texture = texture
	polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	polygon.color = Color(0.88, 0.94, 1.0, 1.0)
	polygon.position = Vector2(500 + (index % 8) * 30, 30 + floori(float(index) / 8.0) * 30)
	polygon.z_index = index % 3
	if index == 0:
		polygon.offset = Vector2(3, 2)
		polygon.modulate = Color(0.9, 1.0, 0.72, 0.93)
	return polygon

func _add_fallback_polygons() -> void:
	var antialiased := _make_simple_polygon(101)
	antialiased.name = "FallbackAA"
	antialiased.antialiased = true
	antialiased.position = Vector2(760, 300)
	content.add_child(antialiased)
	polygons.append(antialiased)
	var uv_transform := _make_simple_polygon(102)
	uv_transform.name = "FallbackUVTransform"
	uv_transform.texture_scale = Vector2(2, 1)
	uv_transform.position = Vector2(800, 300)
	content.add_child(uv_transform)
	polygons.append(uv_transform)
	var triangle := Polygon2D.new()
	triangle.name = "FallbackTriangle"
	triangle.texture = texture
	triangle.polygon = PackedVector2Array([Vector2.ZERO, Vector2(28, 0), Vector2(14, 24)])
	triangle.uv = PackedVector2Array([Vector2.ZERO, Vector2(24, 0), Vector2(12, 20)])
	triangle.position = Vector2(840, 300)
	content.add_child(triangle)
	polygons.append(triangle)
	var scripted := _make_simple_polygon(103)
	scripted.name = "FallbackScripted"
	var script := GDScript.new()
	script.source_code = "extends Polygon2D\n"
	check(script.reload() == OK, "fallback probe GDScript parses")
	scripted.set_script(script)
	scripted.position = Vector2(880, 300)
	content.add_child(scripted)
	polygons.append(scripted)
	var callback := _make_simple_polygon(104)
	callback.name = "FallbackForeignDrawCallback"
	callback.position = Vector2(920, 300)
	callback.draw.connect(_foreign_draw.bind(callback))
	content.add_child(callback)
	polygons.append(callback)

func _foreign_draw(surface: Polygon2D) -> void:
	surface.draw_circle(Vector2(11, 11), 5.0, Color(1.0, 0.1, 0.9, 1.0))

func _make_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y: int in 8:
		for x: int in 8:
			image.set_pixel(x, y, Color(1.0, 0.6, 0.1, 1.0) if (x + y) % 2 == 0 else Color(0.1, 0.35, 0.9, 1.0))
	return ImageTexture.create_from_image(image)

func _enable_batch() -> void:
	dungeon.batch_simple_polygons = true
	for polygon: Polygon2D in polygons:
		if polygon.get_parent() != dungeon: BATCH_SCRIPT.configure(polygon, true)

func _disable_batch() -> void:
	dungeon.batch_simple_polygons = false
	for polygon: Polygon2D in polygons:
		if polygon.get_parent() != dungeon: BATCH_SCRIPT.configure(polygon, false)

func _batch_connections(enabled: bool) -> bool:
	for polygon: Polygon2D in polygons:
		var found := false
		for connection: Dictionary in polygon.draw.get_connections():
			var callback: Callable = connection.callable
			var bound: Array = callback.get_bound_arguments()
			if callback.get_method() == "_draw" and bound.size() == 1 and bound[0] == polygon:
				found = true
		if enabled and not found: return false
		if not enabled and found: return false
	return true

func _authoring_signature() -> Dictionary:
	var signature: Dictionary = {"tile": dungeon.get_instance_id(), "owner_child_count": content.get_child_count(),
		"owner_transform": content.transform, "owner_modulate": content.modulate, "polygons": []}
	for polygon: Polygon2D in polygons:
		(signature.polygons as Array).append({"id": polygon.get_instance_id(), "points": polygon.polygon.duplicate(),
			"uv": polygon.uv.duplicate(), "colors": polygon.vertex_colors.duplicate(), "color": polygon.color,
			"texture": polygon.texture.get_instance_id() if polygon.texture != null else 0,
			"offset": polygon.offset, "texture_rotation": polygon.texture_rotation, "texture_offset": polygon.texture_offset,
			"texture_scale": polygon.texture_scale, "position": polygon.position, "rotation": polygon.rotation,
			"scale": polygon.scale, "modulate": polygon.modulate, "z": polygon.z_index, "antialiased": polygon.antialiased,
			"script": polygon.get_script()})
	return signature

func _capture_if_renderable() -> Image:
	if DisplayServer.get_name() == "headless": return Image.new()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	return image.duplicate() if image != null else Image.new()

func _draw_calls() -> int:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility": return -1
	return viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)

func _compare_images(expected: Image, actual: Image) -> Dictionary:
	if expected.get_size() != actual.get_size(): return {"equal": false, "max_delta": 1.0}
	var largest := 0.0
	for y: int in expected.get_height():
		for x: int in expected.get_width():
			var a := expected.get_pixel(x, y)
			var b := actual.get_pixel(x, y)
			largest = maxf(largest, absf(a.r - b.r))
			largest = maxf(largest, absf(a.g - b.g))
			largest = maxf(largest, absf(a.b - b.b))
			largest = maxf(largest, absf(a.a - b.a))
	return {"equal": largest <= CHANNEL_TOLERANCE, "max_delta": largest}

func _mutate_and_compare_native() -> void:
	var candidate := simple_polygons[0]
	candidate.polygon = PackedVector2Array([Vector2.ZERO, Vector2(28, 1), Vector2(26, 26), Vector2(-1, 24)])
	candidate.color = Color(0.25, 0.9, 0.45, 0.8)
	candidate.vertex_colors = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE, Color.WHITE])
	candidate.uv = PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40)])
	candidate.queue_redraw()
	var enabled_image := await _capture_if_renderable()
	_disable_batch()
	var native_after_mutation := await _capture_if_renderable()
	check(_batch_connections(false), "disabling disconnects batch callbacks and restores Polygon2D native drawing")
	check(_authoring_signature().polygons.size() == polygons.size(), "mutation retains authored polygon node count")
	if not enabled_image.is_empty() and not native_after_mutation.is_empty():
		var diff := _compare_images(native_after_mutation, enabled_image)
		max_channel_delta = maxf(max_channel_delta, diff.max_delta)
		check(diff.equal, "mutated geometry/color/UV batch still matches its fresh native oracle")

func _disable_and_check_native() -> void:
	var native_image := await _capture_if_renderable()
	_enable_batch()
	var reenabled_image := await _capture_if_renderable()
	if not native_image.is_empty() and not reenabled_image.is_empty():
		var diff := _compare_images(native_image, reenabled_image)
		max_channel_delta = maxf(max_channel_delta, diff.max_delta)
		check(diff.equal, "re-enabled batch remains pixel-equivalent after native restoration")
	_disable_batch()
