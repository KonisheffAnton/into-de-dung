extends SceneTree

const NATIVE = preload("res://assets/art_presets/trials/pixel_zoom_v1/native_sprite.gdshader")
const GENERIC = preload("res://assets/art_presets/trials/pixel_zoom_v1/character_palette.gdshader")
const UNIT = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
const PANEL := 128
const TOLERANCE := 3.0 / 255.0
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL CHARACTER COVERAGE: " + label)

func _run() -> void:
	_check_material_routes()
	if DisplayServer.get_name() == "headless":
		print("CHARACTER COVERAGE GPU: skipped on headless")
	else:
		for fixture: Dictionary in [
			{"name": "native exact 1:1", "scale": Vector2.ONE},
			{"name": "native half", "scale": Vector2(0.5, 0.5)},
			{"name": "native fractional", "scale": Vector2(0.313, 0.417), "offset": Vector2(0.25, 0.75)},
			{"name": "native footprint 16", "scale": Vector2(0.0625, 0.0625)},
			{"name": "native magnified", "scale": Vector2(1.75, 1.75)},
			{"name": "native mirrored atlas", "scale": Vector2(-0.4, 0.4), "atlas": true, "offset": Vector2(0.25, 0.5)},
			{"name": "native region rect", "scale": Vector2(0.5, 0.5), "crop": true},
			{"name": "generic source alpha", "scale": Vector2(0.313, 0.417), "generic": true},
			{"name": "generic mirrored atlas", "scale": Vector2(-0.07, 0.07), "generic": true, "atlas": true},
		]:
			await _check_pixels(fixture)
	print("CHARACTER COVERAGE RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_material_routes() -> void:
	var unit := UNIT.instantiate()
	for path: String in ["BodySprite", "EnemyPresets/Bearded", "EnemyPresets/Helmet", "EnemyPresets/Redhair",
		"CharacterSkinSprite", "PlayerWarriorSprite", "EnemyWarriorSprite", "DefenderIdleSprite",
		"PlayerRogueSprite", "EnemyRogueSprite", "RogueIdleSprite", "PlayerArcherSprite", "EnemyArcherSprite",
		"ArcherIdleSprite", "EnemyWarriorIdleSprite", "PlayerShieldbearerSprite", "EnemyShieldbearerSprite",
		"PlayerFighterSprite", "EnemyFighterSprite"]:
		var sprite := unit.get_node_or_null("ArtRoot/" + path) as Sprite2D
		var material := sprite.material as ShaderMaterial if sprite != null else null
		check(material != null and material.shader in [NATIVE, GENERIC], path + " uses coverage material")
		if sprite == null or material == null: continue
		if sprite.texture is AtlasTexture and path.begins_with("EnemyPresets"):
			var region := (sprite.texture as AtlasTexture).region
			check(material.get_shader_parameter("source_region") == Vector4(region.position.x, region.position.y, region.size.x, region.size.y), path + " clips its own atlas region")
		if material.shader == GENERIC:
			check(material.get_shader_parameter("source_alpha_cutout") == false, path + " retains original alpha")
	unit.free()

func _check_pixels(fixture: Dictionary) -> void:
	var cropped: bool = fixture.get("atlas", false) or fixture.get("crop", false)
	var generic: bool = fixture.get("generic", false)
	var region := Rect2i(8, 12, 48, 40) if cropped else Rect2i(0, 0, 64, 64)
	var source := Image.create(80 if cropped else 64, 80 if cropped else 64, false, Image.FORMAT_RGBA8)
	source.fill(Color.MAGENTA)
	# Контраст за границей кадра ловит протекание соседней ячейки атласа.
	for y: int in region.size.y:
		for x: int in region.size.x:
			var color := Color.WHITE if (x + y) % 2 == 0 else Color.BLACK
			if x < 3 or y < 3 or x >= region.size.x - 3 or y >= region.size.y - 3:
				color = Color(1, 0, 0, 0)
			elif y % 7 == 0:
				color.a = 0.3
			elif x % 5 == 0:
				color.a = 0.8
			source.set_pixelv(region.position + Vector2i(x, y), color)
	var texture := ImageTexture.create_from_image(source)
	var frame: Texture2D = texture
	if fixture.get("atlas", false):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(region)
		frame = atlas
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PANEL, PANEL * 2)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.size = Vector2(PANEL, PANEL)
	viewport.add_child(background)
	var scale_value: Vector2 = fixture.scale
	var origin := Vector2(8, 8) + Vector2(fixture.get("offset", Vector2.ZERO))
	if scale_value.x < 0: origin.x += region.size.x * absf(scale_value.x)
	for panel: int in 2:
		var sprite := Sprite2D.new()
		sprite.texture = frame
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if fixture.get("crop", false):
			sprite.region_enabled = true
			sprite.region_rect = Rect2(region)
		sprite.position = origin + Vector2(0, PANEL * panel)
		sprite.scale = scale_value
		# Родительская и собственная прозрачность должны примениться ровно по разу.
		sprite.modulate.a = 0.75
		var parent := Node2D.new()
		parent.modulate.a = 0.8
		viewport.add_child(parent)
		parent.add_child(sprite)
		var material := ShaderMaterial.new()
		material.shader = GENERIC if generic else NATIVE
		material.set_shader_parameter("native_size", Vector2(32, 32))
		material.set_shader_parameter("source_alpha_cutout", not generic)
		if cropped or not generic:
			material.set_shader_parameter("source_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
		sprite.material = material
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	var expected := _raster_source(source, region, origin, scale_value, generic)
	var color_errors := 0
	var alpha_errors := 0
	var visible := 0
	var max_error := 0.0
	for y: int in PANEL:
		for x: int in PANEL:
			var want := expected.get_pixel(x, y)
			var got := actual.get_pixel(x, y)
			var error := maxf(absf(got.r - want.r), maxf(absf(got.g - want.g), absf(got.b - want.b)))
			max_error = maxf(max_error, error)
			if error > TOLERANCE: color_errors += 1
			if absf(actual.get_pixel(x, y + PANEL).a - want.a) > TOLERANCE: alpha_errors += 1
			if want.a > 0: visible += 1
	check(visible > 0, fixture.name + " exercises visible pixels")
	check(color_errors == 0, "%s source area RGB: %d errors, max %.5f" % [fixture.name, color_errors, max_error])
	check(alpha_errors == 0, "%s coverage/alpha/fade: %d errors" % [fixture.name, alpha_errors])
	viewport.queue_free()
	await process_frame

func _raster_source(source: Image, region: Rect2i, origin: Vector2, scale_value: Vector2, generic: bool) -> Image:
	var expected := Image.create(PANEL, PANEL, false, Image.FORMAT_RGBAF)
	# CPU-эталон идёт от исходных квадратов к экрану, независимо от обхода fragment shader.
	for sy: int in region.size.y:
		for sx: int in region.size.x:
			var color := source.get_pixelv(region.position + Vector2i(sx, sy))
			var alpha := color.a if generic else (1.0 if color.a >= 0.5 else 0.0)
			if alpha == 0: continue
			var a := origin + Vector2(sx, sy) * scale_value
			var b := a + scale_value
			var left := minf(a.x, b.x)
			var top := minf(a.y, b.y)
			var right := maxf(a.x, b.x)
			var bottom := maxf(a.y, b.y)
			for y: int in range(maxi(0, floori(top)), mini(PANEL, ceili(bottom))):
				for x: int in range(maxi(0, floori(left)), mini(PANEL, ceili(right))):
					var weight := maxf(0.0, minf(right, x + 1.0) - maxf(left, x)) * maxf(0.0, minf(bottom, y + 1.0) - maxf(top, y))
					var contribution := alpha * weight * 0.75 * 0.8
					expected.set_pixel(x, y, expected.get_pixel(x, y) + Color(color.r * contribution, color.g * contribution, color.b * contribution, contribution))
	# Растеризация прямоугольника спрайта выбирает фрагменты по центру экранного пикселя.
	for y: int in PANEL:
		for x: int in PANEL:
			var local := (Vector2(x + 0.5, y + 0.5) - origin) / scale_value
			if local.x < 0 or local.y < 0 or local.x >= region.size.x or local.y >= region.size.y:
				expected.set_pixel(x, y, Color(0, 0, 0, 0))
	return expected
