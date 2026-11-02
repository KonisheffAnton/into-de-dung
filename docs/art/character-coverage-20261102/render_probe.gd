extends SceneTree

const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const NATIVE = preload("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")
var output: String = ""
var baseline: String = ""
var old_native: Shader
var old_generic: Shader

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): output = arg.trim_prefix("--captures=")
		if arg.begins_with("--baseline="): baseline = arg.trim_prefix("--baseline=")
	call_deferred("_run")

func _old_shader(name: String) -> Shader:
	var shader := Shader.new()
	var code := FileAccess.get_file_as_string(baseline.path_join(name))
	code = code.replace('#include "', '#include "res://assets/art_presets/trials/pixel_zoom_v1/')
	shader.code = code
	return shader

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	old_native = _old_shader("native_sprite.gdshader")
	old_generic = _old_shader("character_palette.gdshader")
	var view := SubViewport.new()
	view.size = Vector2i(960, 1960)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background := ColorRect.new()
	background.color = Color("171f2e")
	background.size = Vector2(view.size)
	view.add_child(background)
	var columns: Array[Node2D] = []
	for col: int in 3:
		var column := Node2D.new()
		column.position.x = 160 + col * 320
		view.add_child(column)
		columns.append(column)
		_label(view, ["До · игровой масштаб", "После · игровой масштаб", "После · камера 200%"][col], Vector2(col * 320 + 20, 12))
	var unit := UNIT.instantiate()
	var row := 0
	for skin_id: StringName in [&"watch_shield", &"grey_bastion", &"red_bastion", &"short_cape"]:
		var definition := CharacterSkinCatalog.definition(&"rogue" if skin_id == &"short_cape" else (&"fighter" if skin_id == &"red_bastion" else &"shieldbearer"), skin_id)
		var sprite := Sprite2D.new()
		sprite.texture = definition.animations.get_frame_texture(&"idle", 0)
		sprite.centered = false
		sprite.position = -definition.anchor * definition.texture_scale
		sprite.scale = Vector2.ONE * definition.texture_scale
		var material := ShaderMaterial.new()
		material.shader = NATIVE
		var region := (sprite.texture as AtlasTexture).region
		material.set_shader_parameter("source_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
		material.set_shader_parameter("native_size", Vector2(128, 128))
		material.set_shader_parameter("shieldbearer_palette_strength", definition.shieldbearer_palette_strength)
		sprite.material = material
		_add_row(view, columns, sprite, 0.72 if skin_id == &"short_cape" else 0.8, String(skin_id), row)
		sprite.free()
		row += 1
	for path: String in ["PlayerArcherSprite", "PlayerWarriorSprite", "PlayerShieldbearerSprite", "PlayerFighterSprite", "EnemyPresets/Bearded", "EnemyPresets/Helmet", "EnemyPresets/Redhair", "BodySprite"]:
		_add_row(view, columns, unit.get_node("ArtRoot/" + path) as Sprite2D, 0.6400003306666667 if path == "PlayerArcherSprite" else 0.8, path, row)
		row += 1
	unit.free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var saved := view.get_texture().get_image().save_png(output.path_join("models-before-after.png")) == OK
	# Это короткая проверка стоимости общей выборки, не FPS всей игры.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	columns[2].visible = false
	var timings: Dictionary = {}
	for index: int in [0, 1, 1, 0]:
		columns[0].visible = index == 0
		columns[1].visible = index == 1
		for warm: int in 8: await process_frame
		var samples: Array[float] = []
		for sample: int in 30:
			var started := Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		var key := "before" if index == 0 else "after"
		if not timings.has(key): timings[key] = []
		timings[key].append(samples)
	var file := FileAccess.open(output.path_join("frame-samples.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(timings, "  "))
	view.queue_free()
	await process_frame
	print("COVERAGE PROBE RESULTS: %d passed, %d failed" % [1 if saved else 0, 0 if saved else 1])
	quit(0 if saved else 1)

func _add_row(view: SubViewport, columns: Array[Node2D], template: Sprite2D, art_scale: float, label: String, row: int) -> void:
	for col: int in 3:
		var holder := Node2D.new()
		holder.position.y = 160 + row * 160
		holder.scale = Vector2.ONE * art_scale * (2.0 if col == 2 else 1.0)
		columns[col].add_child(holder)
		var sprite := template.duplicate() as Sprite2D
		sprite.visible = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := template.material.duplicate() as ShaderMaterial
		if col == 0:
			material.shader = old_native if template.material.shader == NATIVE else old_generic
		sprite.material = material
		holder.add_child(sprite)
		_label(view, label, Vector2(20 + col * 320, 170 + row * 160))

func _label(view: SubViewport, text_value: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.add_theme_font_size_override("font_size", 16)
	view.add_child(label)
