extends RefCounted

const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")

## Увеличивается уже отрисованный кадр, чтобы видеть экранные пиксели A/B.
static func capture_comparison(tree: SceneTree, captures: String) -> bool:
	var prototype := UNIT.instantiate()
	var success: bool = true
	for kind: String in ["Player", "Enemy"]:
		var original := prototype.get_node("ArtRoot/" + kind + "WarriorSprite") as Sprite2D
		success = await _check_fade(tree, original) and success
		var panel := SubViewport.new()
		panel.size = Vector2i(1152, 744)
		panel.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tree.root.add_child(panel)
		var samples: Array[SubViewport] = []
		for row: int in range(2):
			for column: int in range(3):
				var zoom: float = [0.75, 1.0, 1.25][column]
				var sample := SubViewport.new()
				sample.size = Vector2i(128, 112)
				sample.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				tree.root.add_child(sample)
				samples.append(sample)
				var sprite := original.duplicate() as Sprite2D
				sprite.position = Vector2(12, 12)
				sprite.scale = original.scale * zoom
				sprite.visible = true
				if row == 0:
					sprite.material = null
				sample.add_child(sprite)
				var enlarged := Sprite2D.new()
				enlarged.texture = sample.get_texture()
				enlarged.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				enlarged.centered = false
				enlarged.scale = Vector2(3, 3)
				enlarged.position = Vector2(column * 384, row * 372 + 32)
				panel.add_child(enlarged)
				var label := Label.new()
				label.position = Vector2(column * 384 + 12, row * 372 + 4)
				label.text = "%s %d%% / %s / pixels x3" % [kind, roundi(zoom * 100), "source" if row == 0 else "native grid"]
				panel.add_child(label)
		await tree.process_frame
		await tree.process_frame
		await RenderingServer.frame_post_draw
		var result := panel.get_texture().get_image()
		success = result != null and result.save_png(captures.path_join("sampling-" + kind.to_lower() + ".png")) == OK and success
		panel.queue_free()
		for sample: SubViewport in samples:
			sample.queue_free()
		await tree.process_frame
	prototype.free()
	return success

static func _check_fade(tree: SceneTree, original: Sprite2D) -> bool:
	var target := SubViewport.new()
	target.size = Vector2i(128, 112)
	target.transparent_bg = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(target)
	var parent := Node2D.new()
	target.add_child(parent)
	var sprite := original.duplicate() as Sprite2D
	sprite.visible = true
	sprite.position = Vector2(12, 12)
	parent.add_child(sprite)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var opaque := target.get_texture().get_image()
	var sample := Vector2i(-1, -1)
	for y: int in range(opaque.get_height()):
		for x: int in range(opaque.get_width()):
			if opaque.get_pixel(x, y).a > 0.99:
				sample = Vector2i(x, y)
				break
		if sample.x >= 0:
			break
	parent.modulate.a = 0.5
	sprite.self_modulate.a = 0.5
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var faded := target.get_texture().get_image()
	var success: bool = sample.x >= 0 and absf(faded.get_pixelv(sample).a - 0.25) < 0.01
	if not success:
		printerr("FAIL SPRITE SAMPLING: parent/self alpha must retain a quarter-opacity rendered pixel")
	target.queue_free()
	await tree.process_frame
	return success
