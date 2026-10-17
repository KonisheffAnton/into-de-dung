extends SceneTree

const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var output: String = ""
var approved: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--approved="): approved = argument.trim_prefix("--approved=")
	call_deferred("_run")

func _capture(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute(approved)
	# Читаем authored still до _ready: без idle, HUD, теней и clocks.
	var unit := UNIT.instantiate()
	var source := unit.get_node("ArtRoot/PlayerWarriorSprite") as Sprite2D
	var material := source.material.duplicate() as ShaderMaterial
	assert(is_equal_approx(float(material.get_shader_parameter("brighter_palette_strength")), 1.0))
	var view := SubViewport.new()
	view.size = Vector2i(352, 320)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = source.texture
	sprite.scale = source.scale * 4.0
	sprite.position = Vector2(22, 16)
	sprite.material = material
	view.add_child(sprite)
	material.set_shader_parameter("brighter_palette_strength", 0.0)
	var before := await _capture(view)
	material.set_shader_parameter("brighter_palette_strength", 1.0)
	var after := await _capture(view)
	var alpha_changed: int = 0
	var rgb_changed: int = 0
	for y: int in after.get_height():
		for x: int in after.get_width():
			var old := before.get_pixel(x, y)
			var next := after.get_pixel(x, y)
			if old.a != next.a: alpha_changed += 1
			if old.a > 0.0 and old != next: rgb_changed += 1
	assert(alpha_changed == 0 and rgb_changed > 0)
	assert(after.save_png(approved.path_join("defender-reference.png")) == OK)
	var comparison := Image.create(704, 320, false, Image.FORMAT_RGBA8)
	comparison.fill(Color("596047"))
	comparison.blend_rect(before, Rect2i(0, 0, 352, 320), Vector2i.ZERO)
	comparison.blend_rect(after, Rect2i(0, 0, 352, 320), Vector2i(352, 0))
	assert(comparison.save_png(output.path_join("comparison.png")) == OK)
	var report := {"status": "PASS", "alpha_changed": alpha_changed, "visible_rgb_changed": rgb_changed,
		"source_scene": "scenes/demo/visuals/art_trial_unit.tscn", "source_node": "ArtRoot/PlayerWarriorSprite",
		"strength": 1.0, "view_scale": 4.0, "size": [352, 320],
		"scope": "Current character color/style reference requested by U; source gameplay PNGs unchanged."}
	var file := FileAccess.open(output.path_join("render-validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	unit.free()
	view.queue_free()
	await process_frame
	print("DEFENDER REFERENCE: PASS, alpha changed=%d, RGB changed=%d" % [alpha_changed, rgb_changed])
	quit()
