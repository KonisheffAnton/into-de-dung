extends RefCounted

const NATIVE_SHADER: Shader = preload("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")
const ARCHER_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/archer_idle_v1/idle_frames.tres")


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
	sprite.scale = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = NATIVE_SHADER
	sprite.material = material
	view.add_child(sprite)
	material.set_shader_parameter("source_region", Vector4(0, 0, 128, 128))
	material.set_shader_parameter("native_size", Vector2(128, 128))
	material.set_shader_parameter("brighter_palette_strength", 1.0)
	var mask := ArcherClothPalette.MASKS.get_image()
	var gallery := Image.create(128 * 7, 128 * 12, false, Image.FORMAT_RGBA8)
	for slot: int in 12:
		var texture := ARCHER_IDLE.get_frame_texture(&"idle", slot)
		sprite.texture = texture
		ArcherClothPalette.apply(material, 0, slot)
		var original := await _capture(tree, view)
		for palette: int in DefenderClothPalette.count():
			ArcherClothPalette.apply(material, palette, slot)
			var variant := await _capture(tree, view)
			gallery.blit_rect(variant, Rect2i(0, 0, 128, 128), Vector2i(palette * 128, slot * 128))
			if palette > 0:
				var changed: int = 0
				var outside_mask: int = 0
				var alpha_changed: int = 0
				var origin := Vector2i(ArcherClothPalette.mask_origin(slot))
				for y: int in 128:
					for x: int in 128:
						var before := original.get_pixel(x, y)
						var after := variant.get_pixel(x, y)
						if before.a != after.a: alpha_changed += 1
						if before == after: continue
						changed += 1
						if mask.get_pixel(origin.x + x, origin.y + y).r < 0.5: outside_mask += 1
				if changed > 0 and outside_mask == 0 and alpha_changed == 0:
					passed += 1
				else:
					failed += 1
					printerr("FAIL ARCHER CLOTH PALETTE: rendered slot=%d palette=%d changed=%d outside_mask=%d alpha=%d" % [slot, palette, changed, outside_mask, alpha_changed])
			ArcherClothPalette.apply(material, 0, slot)
			var restored := await _capture(tree, view)
			if restored.get_data() == original.get_data():
				passed += 1
			else:
				failed += 1
				printerr("FAIL ARCHER CLOTH PALETTE: original restore slot %d palette %d" % [slot, palette])
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
		if gallery.save_png(captures.path_join("archer-cloth-gallery.png")) == OK: passed += 1
		else: failed += 1
	view.queue_free()
	await tree.process_frame
	return {"passed": passed, "failed": failed}


static func _capture(tree: SceneTree, view: SubViewport) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
