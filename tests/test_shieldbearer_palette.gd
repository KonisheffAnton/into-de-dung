extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const OLD_TEXTURE_PATH: String = "res://assets/art_presets/trials/warrior_classes_v1/shieldbearer-17.png"
const APPROVED_PORTRAIT_PATH: String = "res://assets/ui/hub/shieldbearer_portrait.tres"
const SHADER_PATH: String = "res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader"
const PALETTE_UNIFORM: StringName = &"shieldbearer_palette_strength"
const SOURCE_REGION := Rect2(96, 89, 1051, 1102)
const NATIVE_SIZE := Vector2(72.483, 76.0)
const ART_SCALE: float = 0.8
const SPRITE_SCALE: float = 0.0689655172
const SPRITE_POSITION := Vector2(-42.1, -73.8)
const PROBE_SIZE := Vector2i(1280, 720)
const ZOOMS: Array[float] = [0.75, 1.0, 1.5, 2.0]
const PALETTE_TOLERANCE: float = 1.0 / 255.0

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL SHIELDBEARER PALETTE: " + label)

func _run() -> void:
	await _check_scene_routes()
	_check_portrait()
	if DisplayServer.get_name() == "headless":
		print("SHIELDBEARER PALETTE GPU AUDIT: skipped on headless display")
	else:
		await _check_gpu_palette()
	print("SHIELDBEARER PALETTE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _new_visual(faction: Faction.Type, class_id: StringName) -> BattleDefenderIdleVisual:
	var visual := UNIT_SCENE.instantiate() as BattleDefenderIdleVisual
	visual.role = BattleDemoIsoVisual.Role.UNIT
	visual.unit = BattleUnitView.new()
	visual.unit.id = 17 if class_id == &"shieldbearer" else 11
	visual.unit.faction = faction
	visual.unit.alive = true
	visual.visual_class_id = class_id
	visual.grid_config = IsoGridConfig.new()
	visual.grid_config.tile_size = Vector2(128, 96)
	visual.ambient_animation_paused = true
	visual.show_ground_shadow = false
	visual.self_modulate = Color(1, 1, 1, 0)
	root.add_child(visual)
	return visual

func _check_scene_routes() -> void:
	var player := _new_visual(Faction.Type.PLAYER, &"shieldbearer")
	var enemy := _new_visual(Faction.Type.ENEMY, &"shieldbearer")
	var fighter := _new_visual(Faction.Type.PLAYER, &"fighter")
	await process_frame
	for visual: BattleDefenderIdleVisual in [player, enemy, fighter]:
		visual.sync_scene_art()
	var player_sprite := player.class_still_sprite()
	var enemy_sprite := enemy.class_still_sprite()
	var fighter_sprite := fighter.class_still_sprite()
	check(player_sprite != null and player_sprite.visible and player_sprite.texture.resource_path.ends_with("shieldbearer-17.png"), "player uses original shieldbearer-17 source")
	check(enemy_sprite != null and enemy_sprite.visible and enemy_sprite.texture.resource_path.ends_with("shieldbearer-17.png"), "enemy uses the same original shieldbearer-17 source")
	check(_shieldbearer_geometry(player, player_sprite, false), "player retains approved crop, native cell, anchor, scale, and ArtRoot scale")
	check(_shieldbearer_geometry(enemy, enemy_sprite, true), "enemy retains the matching mirrored crop, anchor, scale, and ArtRoot scale")
	check(_palette_strength(player_sprite) == 1.0 and _palette_strength(enemy_sprite) == 1.0, "both selected Shieldbearer materials explicitly enable the palette")
	check(fighter_sprite != null and fighter_sprite.visible and fighter_sprite.texture.resource_path.ends_with("fighter-11.png"), "fighter still uses its original source")
	var fighter_palette: Variant = null
	if fighter_sprite != null and fighter_sprite.material is ShaderMaterial:
		fighter_palette = _effective_shader_parameter(fighter_sprite.material as ShaderMaterial, PALETTE_UNIFORM)
	# Dummy renderer не вычисляет default uniform; реальное значение проверяется в GPU-ветке.
	if DisplayServer.get_name() == "headless":
		var palette_override: Variant = (fighter_sprite.material as ShaderMaterial).get_shader_parameter(PALETTE_UNIFORM)
		check(palette_override == null or palette_override == 0.0, "fighter has no nonzero palette override")
	else:
		check(fighter_palette != null and float(fighter_palette) == 0.0, "fighter palette remains at the shader default")
	check(fighter_sprite != null and fighter_sprite.region_rect == Rect2(193, 132, 870, 1046)
		and fighter_sprite.position == Vector2(-35.6, -73.8)
		and fighter_sprite.scale.is_equal_approx(Vector2.ONE * 0.0726577438)
		and (fighter.get_node("ArtRoot") as Node2D).scale.is_equal_approx(Vector2.ONE * ART_SCALE),
		"fighter source crop and authored placement are unchanged")
	player.queue_free()
	enemy.queue_free()
	fighter.queue_free()
	await process_frame

func _shieldbearer_geometry(visual: BattleDefenderIdleVisual, sprite: Sprite2D, mirrored: bool) -> bool:
	if sprite == null or not sprite.region_enabled or sprite.region_rect != SOURCE_REGION: return false
	var material := sprite.material as ShaderMaterial
	if material == null or material.shader.resource_path != SHADER_PATH: return false
	if material.get_shader_parameter("source_region") != Vector4(96, 89, 1051, 1102): return false
	var material_native_size: Vector2 = material.get_shader_parameter("native_size")
	if not material_native_size.is_equal_approx(NATIVE_SIZE): return false
	var art_root := visual.get_node("ArtRoot") as Node2D
	if not art_root.scale.is_equal_approx(Vector2.ONE * ART_SCALE): return false
	var expected_position := Vector2(-SPRITE_POSITION.x if mirrored else SPRITE_POSITION.x, SPRITE_POSITION.y)
	var expected_scale := Vector2(-SPRITE_SCALE if mirrored else SPRITE_SCALE, SPRITE_SCALE)
	return sprite.centered == false and sprite.position.is_equal_approx(expected_position) and sprite.scale.is_equal_approx(expected_scale)

func _palette_strength(sprite: Sprite2D) -> float:
	if sprite == null or not sprite.material is ShaderMaterial: return -1.0
	return float((sprite.material as ShaderMaterial).get_shader_parameter(PALETTE_UNIFORM))

func _effective_shader_parameter(material: ShaderMaterial, parameter: StringName) -> Variant:
	var override_value: Variant = material.get_shader_parameter(parameter)
	if override_value != null: return override_value
	if material.shader == null: return null
	return RenderingServer.shader_get_parameter_default(material.shader.get_rid(), parameter)

func _check_portrait() -> void:
	var portrait := load(APPROVED_PORTRAIT_PATH) as AtlasTexture
	check(portrait != null and portrait.atlas != null and portrait.atlas.resource_path.ends_with("shieldbearer-17.png")
		and portrait.region == Rect2(126, 119, 991, 1042), "portrait remains on the original PNG and its accepted crop")

func _check_gpu_palette() -> void:
	var texture := _load_image_texture(OLD_TEXTURE_PATH)
	var shader := load(SHADER_PATH) as Shader
	check(texture != null and shader != null, "GPU probe loads the original source and production shader")
	if texture == null or shader == null: return
	var viewport := SubViewport.new()
	viewport.size = PROBE_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for zoom_index: int in ZOOMS.size():
		for state_index: int in 4:
			_add_probe_pair(viewport, texture, shader, zoom_index, state_index)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var alpha_errors: int = 0
	var opaque_rgb_changes: int = 0
	var transparent_rgb_changes: int = 0
	var visible_alpha: int = 0
	var faded_alpha: int = 0
	for zoom_index: int in ZOOMS.size():
		for state_index: int in 4:
			var x_start := zoom_index * 320
			var y_start := state_index * 180
			for y: int in range(y_start, y_start + 180):
				for x: int in range(x_start, x_start + 155):
					var base_pixel := image.get_pixel(x, y)
					var palette_pixel := image.get_pixel(x + 160, y)
					if absf(base_pixel.a - palette_pixel.a) > PALETTE_TOLERANCE: alpha_errors += 1
					if base_pixel.a > 0.0: visible_alpha += 1
					if state_index >= 2 and base_pixel.a >= 0.3 and base_pixel.a <= 0.5: faded_alpha += 1
					var rgb_changed := _rgb_changed(base_pixel, palette_pixel)
					if base_pixel.a > 0.8 and rgb_changed: opaque_rgb_changes += 1
					if base_pixel.a == 0.0 and rgb_changed: transparent_rgb_changes += 1
	check(alpha_errors == 0, "palette keeps alpha within 1/255 at every zoom, mirror, and fade case; pixel errors %d" % alpha_errors)
	check(opaque_rgb_changes > 0, "palette changes RGB on opaque source pixels at full modulation")
	check(visible_alpha > 0, "both material strengths preserve visible source alpha")
	check(faded_alpha > 0, "0.4 modulation keeps semi-transparent fade pixels visible")
	check(transparent_rgb_changes == 0, "palette introduces no RGB change outside existing alpha coverage")
	viewport.queue_free()
	await process_frame

func _add_probe_pair(viewport: SubViewport, texture: Texture2D, shader: Shader, zoom_index: int, state_index: int) -> void:
	var zoom := ZOOMS[zoom_index]
	var mirrored: bool = state_index % 2 == 1
	var alpha: float = 1.0 if state_index < 2 else 0.4
	var x_origin := float(zoom_index * 320)
	var y := float(state_index * 180 + 140)
	for side: int in 2:
		var parent := Node2D.new()
		parent.position = Vector2(x_origin + float(side * 160 + 80), y)
		parent.scale = Vector2(ART_SCALE * zoom, ART_SCALE * zoom)
		viewport.add_child(parent)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("source_region", Vector4(96, 89, 1051, 1102))
		material.set_shader_parameter("native_size", NATIVE_SIZE)
		material.set_shader_parameter("shieldbearer_palette_strength", 1.0 if side == 1 else 0.0)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = material
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = SOURCE_REGION
		sprite.position = Vector2(42.1 if mirrored else -42.1, -73.8)
		sprite.scale = Vector2(-SPRITE_SCALE if mirrored else SPRITE_SCALE, SPRITE_SCALE)
		sprite.modulate = Color(1, 1, 1, alpha)
		parent.add_child(sprite)

func _rgb_changed(first: Color, second: Color) -> bool:
	return absf(first.r - second.r) > PALETTE_TOLERANCE or absf(first.g - second.g) > PALETTE_TOLERANCE or absf(first.b - second.b) > PALETTE_TOLERANCE

func _load_image_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)
