extends "res://tests/test_character_skins.gd"

# Только диагностический рендер: альтернативы не подключены к игровым сценам.
func _initialize() -> void:
	call_deferred("_run_sampling")

func _run_sampling() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1080, 1110)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("182131")
	background.size = Vector2(viewport.size)
	viewport.add_child(background)
	var code := FileAccess.get_file_as_string("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")
	code = code.replace('"character_palette.gdshaderinc"', '"res://assets/art_presets/trials/pixel_zoom_v1/character_palette.gdshaderinc"')
	code = code.replace('"shieldbearer_palette.gdshaderinc"', '"res://assets/art_presets/trials/pixel_zoom_v1/shieldbearer_palette.gdshaderinc"')
	code = code.replace("vec2(2.0)", "vec2(4.0)").replace("int y = -1; y <= 1", "int y = -2; y <= 2").replace("int x = -1; x <= 1", "int x = -2; x <= 2")
	var full_shader := Shader.new()
	full_shader.code = code
	var entries: Array[Dictionary] = [
		{"id": &"watch_shield", "class": &"shieldbearer", "name": "Щитоносец"},
		{"id": &"red_bastion", "class": &"fighter", "name": "Воин"},
		{"id": &"short_cape", "class": &"rogue", "name": "Разбойник −10%"},
	]
	var cells: Array[Dictionary] = []
	for row: int in entries.size():
		for column: int in 3:
			var inner := SubViewport.new()
			inner.size = Vector2i(140, 110)
			inner.world_2d = World2D.new()
			inner.transparent_bg = true
			inner.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(inner)
			var entry: Dictionary = entries[row]
			var visual := _make_visual(900 + row * 3 + column, entry.class, Faction.Type.PLAYER, entry.id, inner)
			visual.position = Vector2(70, 90)
			visual.self_modulate.a = 0.0
			visual.set_process(false)
			var sprite := visual.class_still_sprite()
			if column == 1:
				sprite.material = null
			elif column == 2:
				var material := sprite.material.duplicate() as ShaderMaterial
				material.shader = full_shader
				material.set_shader_parameter(&"native_size", Vector2(256, 256))
				material.set_shader_parameter(&"source_region", Vector4(0, 0, 256, 256))
				material.set_shader_parameter(&"brighter_palette_strength", 0.0)
				material.set_shader_parameter(&"shieldbearer_palette_strength", 0.0)
				sprite.material = material
			cells.append({"viewport": inner, "row": row, "column": column, "name": entry.name})
	await process_frame
	await RenderingServer.frame_post_draw
	var images: Array[Image] = []
	for cell: Dictionary in cells:
		var inner := cell.viewport as SubViewport
		var pixels := inner.get_texture().get_image()
		check(not pixels.is_empty(), "sampling probe has GPU pixels")
		images.append(pixels)
		var texture := ImageTexture.create_from_image(pixels)
		var position := Vector2(cell.column * 360 + 20, cell.row * 370)
		var label := Label.new()
		label.text = "%s\n%s" % [cell.name, ["Игра: сетка128 + покрытие", "Полный кадр: nearest", "Полный кадр: покрытие"][cell.column]]
		label.position = position + Vector2(0, 8)
		viewport.add_child(label)
		for magnification: int in [1, 2]:
			var display := Sprite2D.new()
			display.texture = texture
			display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			display.centered = false
			display.scale = Vector2.ONE * magnification
			display.position = position + Vector2(0, 42 if magnification == 1 else 148)
			viewport.add_child(display)
		inner.queue_free()
	var differences: Array[int] = []
	for row: int in entries.size():
		var count := 0
		for y: int in 110:
			for x: int in 140:
				if images[row * 3].get_pixel(x, y) != images[row * 3 + 2].get_pixel(x, y): count += 1
		check(count > 100, "full-source sampling changes visible output independently of geometry")
		differences.append(count)
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(_capture_path().path_join("sampling-comparison.png")) == OK, "save sampling comparison")
	print("SAMPLING DIFFERENCES: ", differences)
	print("SAMPLING PROBE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
