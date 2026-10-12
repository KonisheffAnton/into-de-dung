extends RefCounted

const NATIVE_SHADER: Shader = preload("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")


static func run(tree: SceneTree, captures: String) -> Dictionary:
	var passed: int = 0
	var failed: int = 0
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(view)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = NATIVE_SHADER
	sprite.material = material
	view.add_child(sprite)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_presets/trials/defender_cloth_v1/mask_sources.json"))
	var mask := DefenderClothPalette.MASKS.get_image()
	var sheets: Dictionary[String, Image] = {}
	var palettes := Image.create(128 * 7, 128 * 3, false, Image.FORMAT_RGBA8)
	for row: Dictionary in manifest.frames:
		var clip: String = row.clip
		var slot := int(row.slot)
		var frame := int(row.frame)
		var size := Vector2i(int(row.native_size[0]), int(row.native_size[1]))
		var source := load("res://" + String(row.source)) as Texture2D
		if clip == "still":
			var atlas := AtlasTexture.new()
			atlas.atlas = source
			atlas.region = Rect2(89, 206, 1034, 966)
			sprite.texture = atlas
			sprite.scale = Vector2(77.0 / 1034.0, 72.0 / 966.0)
			material.set_shader_parameter("source_region", Vector4(89, 206, 1034, 966))
		else:
			sprite.texture = source
			sprite.scale = Vector2.ONE
			material.set_shader_parameter("source_region", Vector4(0, 0, 128, 128))
		material.set_shader_parameter("native_size", Vector2(size))
		DefenderClothPalette.apply(material, 0, slot)
		var original := await _capture(tree, view)
		DefenderClothPalette.apply(material, 1, slot)
		var colored := await _capture(tree, view)
		var origin := Vector2i(DefenderClothPalette.mask_origin(slot))
		var changed: int = 0
		var outside: int = 0
		var alpha: int = 0
		for y: int in 128:
			for x: int in 128:
				var before := original.get_pixel(x, y)
				var after := colored.get_pixel(x, y)
				if before.a != after.a: alpha += 1
				if before == after: continue
				changed += 1
				if x >= size.x or y >= size.y or mask.get_pixel(origin.x + x, origin.y + y).r < 0.5:
					outside += 1
		if changed > 0 and outside == 0 and alpha == 0:
			passed += 1
		else:
			failed += 1
			printerr("FAIL DEFENDER CLOTH PALETTE: rendered %s/%d changed=%d outside_mask=%d alpha=%d" % [clip, frame, changed, outside, alpha])
		# Проверяем возврат исходных пикселей, а не только значение параметра материала.
		DefenderClothPalette.apply(material, 0, slot)
		var restored := await _capture(tree, view)
		if restored.get_data() == original.get_data(): passed += 1
		else:
			failed += 1
			printerr("FAIL DEFENDER CLOTH PALETTE: original restore %s/%d" % [clip, frame])
		if not captures.is_empty():
			if not sheets.has(clip):
				var count := 1 if clip == "still" else (12 if clip in ["vertical", "sway"] else 33)
				sheets[clip] = Image.create(128 * 12, ceili(float(count) / 6.0) * 128, false, Image.FORMAT_RGBA8)
			var position := Vector2i((frame % 6) * 256, (frame / 6) * 128)
			sheets[clip].blit_rect(original, Rect2i(0, 0, 128, 128), position)
			sheets[clip].blit_rect(colored, Rect2i(0, 0, 128, 128), position + Vector2i(128, 0))
			if (clip == "vertical" and frame == 0) or (clip == "buff" and frame == 16) or (clip == "death" and frame == 32):
				var palette_row := 0 if clip == "vertical" else (1 if clip == "buff" else 2)
				for index: int in DefenderClothPalette.count():
					DefenderClothPalette.apply(material, index, slot)
					var variant := await _capture(tree, view)
					palettes.blit_rect(variant, Rect2i(0, 0, 128, 128), Vector2i(index * 128, palette_row * 128))
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
		for clip: String in sheets:
			if sheets[clip].save_png(captures.path_join("cloth-" + clip + "-pairs.png")) == OK: passed += 1
			else: failed += 1
		if palettes.save_png(captures.path_join("cloth-palettes.png")) == OK: passed += 1
		else: failed += 1
	view.queue_free()
	await tree.process_frame
	return {"passed": passed, "failed": failed}


static func _capture(tree: SceneTree, view: SubViewport) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
