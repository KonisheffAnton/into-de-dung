extends RefCounted

const NATIVE_SHADER: Shader = preload("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")
const ROGUE_IDLE: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/idle_frames.tres")
const ROGUE_BUFF: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/buff_frames.tres")
const ROGUE_DEATH: SpriteFrames = preload("res://assets/art_presets/trials/rogue_animations_v1/death_frames.tres")


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
	sprite.scale = Vector2(0.25, 0.25)
	var material := ShaderMaterial.new()
	material.shader = NATIVE_SHADER
	sprite.material = material
	view.add_child(sprite)
	material.set_shader_parameter("source_region", Vector4(0, 0, 512, 512))
	material.set_shader_parameter("native_size", Vector2(128, 128))
	var mask := RogueClothPalette.MASKS.get_image()
	var sheet := Image.create(768, 1408, false, Image.FORMAT_RGBA8)
	var palettes := Image.create(128 * 7, 128 * 4, false, Image.FORMAT_RGBA8)
	var palette_slots: Array[int] = [0, 12, 16, 31]
	for slot: int in 32:
		var texture := _texture_for_slot(slot)
		sprite.texture = texture
		RogueClothPalette.apply(material, 0, slot)
		var original := await _capture(tree, view)
		RogueClothPalette.apply(material, 1, slot)
		var colored := await _capture(tree, view)
		var origin := Vector2i(RogueClothPalette.mask_origin(slot))
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
				if mask.get_pixel(origin.x + x, origin.y + y).r < 0.5: outside += 1
		if changed > 0 and outside == 0 and alpha == 0: passed += 1
		else:
			failed += 1
			printerr("FAIL ROGUE CLOTH PALETTE: rendered slot %d changed=%d outside_mask=%d alpha=%d" % [slot, changed, outside, alpha])
		var cell := Vector2i((slot % 3) * 256, (slot / 3) * 128)
		sheet.blit_rect(original, Rect2i(0, 0, 128, 128), cell)
		sheet.blit_rect(colored, Rect2i(0, 0, 128, 128), cell + Vector2i(128, 0))
		RogueClothPalette.apply(material, 0, slot)
		var restored := await _capture(tree, view)
		if restored.get_data() == original.get_data(): passed += 1
		else:
			failed += 1
			printerr("FAIL ROGUE CLOTH PALETTE: original restore slot %d" % slot)
		if palette_slots.has(slot):
			var row := palette_slots.find(slot)
			for index: int in DefenderClothPalette.count():
				RogueClothPalette.apply(material, index, slot)
				var variant := await _capture(tree, view)
				palettes.blit_rect(variant, Rect2i(0, 0, 128, 128), Vector2i(index * 128, row * 128))
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
		if sheet.save_png(captures.path_join("rogue-cloth-frame-pairs.png")) == OK: passed += 1
		else: failed += 1
		if palettes.save_png(captures.path_join("rogue-cloth-palettes.png")) == OK: passed += 1
		else: failed += 1
	view.queue_free()
	await tree.process_frame
	return {"passed": passed, "failed": failed}


static func _texture_for_slot(slot: int) -> Texture2D:
	if slot == 0:
		return load("res://assets/art_presets/trials/rogue_animations_v1/still.png") as Texture2D
	if slot <= 12: return ROGUE_IDLE.get_frame_texture(&"idle", slot - 1)
	if slot <= 18: return ROGUE_BUFF.get_frame_texture(&"buff", slot - 13)
	return ROGUE_DEATH.get_frame_texture(&"death", slot - 19)


static func _capture(tree: SceneTree, view: SubViewport) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
