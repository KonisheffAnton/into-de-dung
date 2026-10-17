extends SceneTree

# Отдельный render-аудит: оба столбца используют те же кадры и authored-материалы.
const UNIT: PackedScene = preload("res://scenes/demo/visuals/art_trial_unit.tscn")
var output: String = ""
var viewport: SubViewport
var pairs: Array[Sprite2D] = []
var rows: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Render backend and --output=<directory> are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for index: int in 2:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(sprite)
		pairs.append(sprite)
	var unit := UNIT.instantiate() as BattleDefenderIdleVisual
	# До _ready доступны исходные значения сцены без жизни игровых часов.
	for path: String in ["PlayerWarriorSprite", "EnemyWarriorSprite", "PlayerRogueSprite",
			"EnemyRogueSprite", "PlayerArcherSprite", "EnemyArcherSprite", "BodySprite",
			"EnemyPresets/Bearded", "EnemyPresets/Helmet", "EnemyPresets/Redhair"]:
		var sprite := unit.get_node("ArtRoot/" + path) as Sprite2D
		await _audit(path, sprite, sprite.texture, Color.WHITE, -1, 0, true)
	for clip: Dictionary in [
		{"name": "defender_idle", "frames": unit.idle_frames, "sprite": "DefenderIdleSprite"},
		{"name": "defender_buff", "frames": unit.buff_frames, "sprite": "DefenderIdleSprite"},
		{"name": "defender_death", "frames": unit.death_frames, "sprite": "DefenderIdleSprite"},
		{"name": "rogue_idle", "frames": unit.rogue_idle_frames, "sprite": "RogueIdleSprite"},
		{"name": "rogue_buff", "frames": unit.rogue_buff_frames, "sprite": "RogueIdleSprite"},
		{"name": "rogue_death", "frames": unit.rogue_death_frames, "sprite": "RogueIdleSprite"},
		{"name": "archer_idle", "frames": unit.archer_idle_frames, "sprite": "ArcherIdleSprite"}]:
		var frames: SpriteFrames = clip.frames
		var sprite := unit.get_node("ArtRoot/" + String(clip.sprite)) as Sprite2D
		for animation: StringName in frames.get_animation_names():
			for frame: int in frames.get_frame_count(animation):
				await _audit("%s/%s/%d" % [clip.name, animation, frame], sprite, frames.get_frame_texture(animation, frame))
	# Не только непрозрачный белый modulate: фракция и затухание также входят в сравнение alpha.
	var body := unit.get_node("ArtRoot/BodySprite") as Sprite2D
	await _audit("helper_player_tint", body, body.texture, Color("65dfcc"))
	await _audit("helper_enemy_tint", body, body.texture, Color("f7c97d"))
	for class_name_: String in ["Defender", "Rogue", "Archer"]:
		var sprite := unit.get_node("ArtRoot/" + class_name_ + "IdleSprite") as Sprite2D
		var frames: SpriteFrames = unit.idle_frames if class_name_ == "Defender" else (unit.rogue_idle_frames if class_name_ == "Rogue" else unit.archer_idle_frames)
		var animation: StringName = frames.get_animation_names()[0]
		var texture: Texture2D = frames.get_frame_texture(animation, 0)
		await _audit(class_name_ + "_fade", sprite, texture, Color(0.8, 0.9, 1.0, 0.35))
		if class_name_ == "Archer": continue
		var slot: int = DefenderClothPalette.mask_slot(texture) if class_name_ == "Defender" else RogueClothPalette.mask_slot(texture)
		for palette: int in range(1, 7):
			await _audit(class_name_ + "_cloth_" + str(palette), sprite, texture, Color.WHITE, slot, palette)
	unit.free()
	await _overview()
	var report := {"backend": DisplayServer.get_name(), "cases": rows.size(), "failures": failures,
		"status": "PASS" if failures.is_empty() else "FAIL", "rows": rows}
	var file := FileAccess.open(output.path_join("render-audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	viewport.queue_free()
	await process_frame
	print("CHARACTER PALETTE AUDIT: %d cases, %d failures" % [rows.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func _audit(label: String, source: Sprite2D, texture: Texture2D, tint: Color = Color.WHITE,
		cloth_slot: int = -1, cloth_palette: int = 0, sample: bool = false) -> void:
	var authored := source.material as ShaderMaterial
	if authored == null or not is_equal_approx(float(authored.get_shader_parameter("brighter_palette_strength")), 1.0):
		failures.append(label + ": missing authored palette")
		return
	for index: int in 2:
		var sprite := pairs[index]
		sprite.texture = texture
		sprite.scale = source.scale
		var size := texture.get_size() * source.scale.abs()
		sprite.position = Vector2(index * 128 + (128.0 - size.x) * 0.5, 128.0 - size.y)
		if source.scale.x < 0.0: sprite.position.x += size.x
		sprite.modulate = tint
		var material := authored.duplicate() as ShaderMaterial
		material.set_shader_parameter("brighter_palette_strength", float(index))
		if cloth_slot >= 0:
			if label.begins_with("Defender"): DefenderClothPalette.apply(material, cloth_palette, cloth_slot)
			else: RogueClothPalette.apply(material, cloth_palette, cloth_slot)
		sprite.material = material
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var alpha_changed: int = 0
	var rgb_changed: int = 0
	var visible: int = 0
	var before_luma: float = 0.0
	var after_luma: float = 0.0
	for y: int in 128:
		for x: int in 128:
			var before := picture.get_pixel(x, y)
			var after := picture.get_pixel(x + 128, y)
			if before.a != after.a: alpha_changed += 1
			if before.a > 0.0:
				visible += 1
				if before != after: rgb_changed += 1
				before_luma += before.r * 0.2126 + before.g * 0.7152 + before.b * 0.0722
				after_luma += after.r * 0.2126 + after.g * 0.7152 + after.b * 0.0722
	if alpha_changed != 0 or rgb_changed == 0 or after_luma <= before_luma:
		failures.append(label + ": alpha/RGB/brightness gate")
	rows.append({"case": label, "alpha_changed": alpha_changed, "rgb_changed": rgb_changed,
		"visible_pixels": visible, "mean_before": before_luma / maxi(1, visible), "mean_after": after_luma / maxi(1, visible)})
	if sample: samples.append({"label": label, "image": picture})


func _overview() -> void:
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1120, 970)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var background := ColorRect.new()
	background.size = Vector2(sheet.size)
	background.color = Color("202a30")
	sheet.add_child(background)
	_label(sheet, "Текущие персонажи · палитра стражника", Vector2(24, 12), 26)
	_label(sheet, "В каждой паре: до → чуть ярче. Рендер исходных игровых текстур; увеличение ×2.", Vector2(24, 50), 18)
	var chosen: Array[int] = [0, 2, 4, 7, 8, 9]
	var titles: Array[String] = ["Защитник", "Разбойник", "Лучница", "Враг · бородатый", "Враг · шлем", "Враг · рыжий"]
	for index: int in chosen.size():
		var origin := Vector2(24 + (index % 2) * 552, 88 + (index / 2) * 290)
		_label(sheet, titles[index], origin, 22)
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(samples[chosen[index]].image)
		sprite.centered = false
		sprite.position = origin + Vector2(0, 26)
		sprite.scale = Vector2(2, 2)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sheet.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	if sheet.get_texture().get_image().save_png(output.path_join("comparison.png")) != OK:
		failures.append("comparison PNG write")
	sheet.queue_free()
	await process_frame


func _label(parent: Node, text: String, position: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
