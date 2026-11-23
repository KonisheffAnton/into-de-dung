extends SceneTree

## Монтаж точных вырезок кадра: только целое увеличение NEAREST и подписи снаружи.
var manifest_path: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest_path = arg.trim_prefix("--manifest=")
	call_deferred("_run")

func _label(parent: Node, value: String, position: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_override("font", load("res://assets/ui/combat_fonts/combat_letters.ttf") as FontFile)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee8d9"))
	parent.add_child(label)

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var rows: Array = data.rows
	var width := 0
	var height := 18
	for row: Dictionary in rows:
		width = maxi(width, 24 + (int(row.crop[2]) * int(row.enlarge) + 12) * 3)
		height += 78 + int(row.crop[3]) * int(row.enlarge)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("24292a")
	backdrop.size = Vector2(width, height)
	viewport.add_child(backdrop)
	var y := 18
	for row: Dictionary in rows:
		_label(viewport, row.title, Vector2(18, y), 18)
		y += 30
		var x := 18
		var rectangle := Rect2i(int(row.crop[0]), int(row.crop[1]), int(row.crop[2]), int(row.crop[3]))
		for panel: Dictionary in row.panels:
			_label(viewport, panel.title, Vector2(x, y), 17)
			var original := Image.load_from_file(panel.source)
			var crop := original.get_region(rectangle)
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.texture = ImageTexture.create_from_image(crop)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = Vector2(x, y + 28)
			sprite.scale = Vector2.ONE * int(row.enlarge)
			viewport.add_child(sprite)
			x += rectangle.size.x * int(row.enlarge) + 12
		y += 48 + rectangle.size.y * int(row.enlarge)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var error := result.save_png(String(data.output))
	viewport.queue_free()
	await process_frame
	print("ADJACENT COMPOSITION: " + ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
