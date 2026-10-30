extends SceneTree

const CURRENT_UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const FLOOR_PATH: String = "res://assets/art_presets/trials/dungeon_room_v2/floor.png"
const OLD_UNIT_PATH: String = "res://assets/art_presets/trials/warrior_classes_v1/shieldbearer-17.png"
const REFERENCE_PATH: String = "res://assets/art_presets/approved/warrior_format_v1/character.png"
const NATIVE_SHADER_PATH: String = "res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader"
const PALETTE_UNIFORM: StringName = &"shieldbearer_palette_strength"
const PANEL_SIZE := Vector2i(320, 280)
const OUTPUT_SIZE := Vector2i(960, 360)
const PANEL_LABELS: Array[String] = ["Исходные цвета", "Новая палитра", "Эталон цветов"]

var captures: String = ""
var output: SubViewport
var panels: Array[SubViewport] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	call_deferred("_render")

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		print("SHIELDBEARER PALETTE CAPTURES: skipped on headless display")
		quit(0)
		return
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	output = SubViewport.new()
	output.size = OUTPUT_SIZE
	output.transparent_bg = false
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(output)
	var background := ColorRect.new()
	background.size = OUTPUT_SIZE
	background.color = Color("101720")
	output.add_child(background)
	for index: int in 3: _add_panel(index)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if not captures.is_empty():
		var native_saved := await _save_capture("palette-native.png", 1.0)
		var zoom_saved := await _save_capture("palette-2x.png", 2.0)
		if not native_saved or not zoom_saved:
			quit(1)
			return
		print("SHIELDBEARER PALETTE CAPTURES: palette-native.png, palette-2x.png")
	else:
		print("SHIELDBEARER PALETTE CAPTURES: render complete; --captures was not supplied")
	quit(0)

func _add_panel(index: int) -> void:
	var label := Label.new()
	label.position = Vector2(index * PANEL_SIZE.x, 4)
	label.size = Vector2(PANEL_SIZE.x, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = PANEL_LABELS[index]
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("e5e9ed"))
	output.add_child(label)
	var container := SubViewportContainer.new()
	container.position = Vector2(index * PANEL_SIZE.x, 40)
	container.size = PANEL_SIZE
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	output.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = PANEL_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	panels.append(viewport)
	var panel_background := ColorRect.new()
	panel_background.size = PANEL_SIZE
	panel_background.color = Color("282e35")
	viewport.add_child(panel_background)
	_add_floor(viewport)
	match index:
		0: _add_old_sprite(viewport)
		1: _add_current_sprite(viewport)
		2: _add_reference_sprite(viewport)

func _add_floor(viewport: SubViewport) -> void:
	var texture := _load_texture(FLOOR_PATH)
	if texture == null: return
	var step := texture.get_size() / 8.0
	for grid_y: int in 5:
		for grid_x: int in 5:
			var origin := Vector2(float(grid_x) * step.x, float(grid_y) * step.y)
			var end := origin + step
			var tile := Polygon2D.new()
			tile.texture = texture
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tile.polygon = PackedVector2Array([Vector2(-64, 0), Vector2(0, -48), Vector2(64, 0), Vector2(0, 48)])
			tile.uv = PackedVector2Array([origin, Vector2(end.x, origin.y), end, Vector2(origin.x, end.y)])
			tile.position = Vector2((grid_x - grid_y) * 64, (grid_x + grid_y - 4) * 48) + Vector2(160, 140)
			viewport.add_child(tile)

func _add_old_sprite(viewport: SubViewport) -> void:
	var texture := _load_texture(OLD_UNIT_PATH)
	var shader := load(NATIVE_SHADER_PATH) as Shader
	if texture == null or shader == null: return
	var parent := _art_parent(viewport)
	var material := _material(shader, 0.0)
	var sprite := _shieldbearer_sprite(texture, material, false)
	parent.add_child(sprite)

func _add_current_sprite(viewport: SubViewport) -> void:
	var visual := CURRENT_UNIT.instantiate() as BattleDefenderIdleVisual
	if visual == null: return
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.unit = BattleUnitView.new()
	visual.unit.id = 17
	visual.unit.faction = Faction.Type.PLAYER
	visual.unit.alive = true
	visual.visual_class_id = &"shieldbearer"
	visual.grid_config = IsoGridConfig.new()
	visual.grid_config.tile_size = Vector2(128, 96)
	visual.show_ground_shadow = false
	visual.self_modulate = Color(1, 1, 1, 0)
	viewport.add_child(visual)
	visual.sync_scene_art()
	visual.position = Vector2(160, 140)

func _add_reference_sprite(viewport: SubViewport) -> void:
	var texture := _load_texture(REFERENCE_PATH)
	if texture == null: return
	var parent := _art_parent(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = Vector2(-71, -83)
	parent.add_child(sprite)

func _art_parent(viewport: SubViewport) -> Node2D:
	var parent := Node2D.new()
	parent.position = Vector2(160, 140)
	parent.scale = Vector2.ONE * 0.8
	viewport.add_child(parent)
	return parent

func _shieldbearer_sprite(texture: Texture2D, material: ShaderMaterial, mirrored: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = material
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(96, 89, 1051, 1102)
	sprite.position = Vector2(42.1 if mirrored else -42.1, -73.8)
	sprite.scale = Vector2(-0.0689655172 if mirrored else 0.0689655172, 0.0689655172)
	return sprite

func _material(shader: Shader, palette_strength: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("source_region", Vector4(96, 89, 1051, 1102))
	material.set_shader_parameter("native_size", Vector2(72.483, 76.0))
	material.set_shader_parameter(PALETTE_UNIFORM, palette_strength)
	return material

func _load_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		printerr("Не удалось прочитать PNG: " + path)
		return null
	return ImageTexture.create_from_image(image)

func _save_capture(filename: String, zoom: float) -> bool:
	for viewport: SubViewport in panels:
		var offset := Vector2(PANEL_SIZE) * 0.5 * (1.0 - zoom)
		viewport.canvas_transform = Transform2D(Vector2(zoom, 0), Vector2(0, zoom), offset)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := output.get_texture().get_image()
	if image == null or image.is_empty(): return false
	return image.save_png(captures.path_join(filename)) == OK
