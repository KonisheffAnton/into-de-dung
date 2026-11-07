extends SceneTree

const TILE: PackedScene = preload("res://scenes/demo/visuals/dungeon_comparison_tile.tscn")
# Отрицательный контроль сохраняет маску и цвет, но срезает выход за ромб.
const CLIPPED_SHADER: String = """shader_type canvas_item;
uniform sampler2D fixed_mask : filter_linear;
void fragment() {
 COLOR = texture(TEXTURE, UV);
 COLOR.a *= texture(fixed_mask, UV).r;
 vec2 p = abs((UV * 256.0 - vec2(128.0, 128.4580897)) / vec2(115.162242, 87.3567251));
 COLOR.a *= step(p.x + p.y, 1.0);
}"""
var passed: int = 0
var failed: int = 0
var captures: String = ""
var viewport: SubViewport

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): captures = argument.trim_prefix("--captures=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL FIRE29 OVERLAP: " + label)

func values(cell: Vector2i, burning: bool) -> Dictionary:
	return {"cell": cell, "role": BattleDemoIsoVisual.Role.FLOOR, "half_steps": 0,
		"is_void": false, "deep_acid": false, "reachable": false, "enemy_range": false, "burning": burning}

func frame(label: String = "") -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	if not label.is_empty() and not captures.is_empty():
		check(result.save_png(captures.path_join(label + ".png")) == OK, "capture " + label)
	return result

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if DisplayServer.get_name() != "headless": await gpu_neighbours()
	await production_lifecycle()
	viewport.queue_free()
	await process_frame
	print("FIRE29 OVERLAP RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func gpu_neighbours() -> void:
	var world := Node2D.new()
	world.y_sort_enabled = true
	viewport.add_child(world)
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(256, 192)
	config.height_step = 64
	config.origin_offset = Vector2(500, -64)
	var tiles: Dictionary[Vector2i, BattleTerrainVisual] = {}
	for y: int in range(1, 4):
		for x: int in range(1, 4):
			var cell := Vector2i(x, y)
			var tile := TILE.instantiate() as BattleTerrainVisual
			world.add_child(tile)
			tile.apply_view(values(cell, cell == Vector2i(2, 2)), config)
			tiles[cell] = tile
	var source := tiles[Vector2i(2, 2)]
	var fire := source._fire_view as BattleFire29Visual
	var animation := fire.get_node(^"Animation") as AnimatedSprite2D
	var base := fire.get_node(^"Base") as Polygon2D
	animation.pause()
	animation.frame = 0
	var correct := await frame("fire29-neighbours")
	# Обрушение гасит родительский terrain через modulate, а не visibility.
	source.modulate.a = 0.0
	var faded := await frame("fire29-collapse-faded")
	source.hide()
	var hidden := await frame("fire29-collapse-hidden")
	check(faded.get_data() == hidden.get_data(), "collapse opacity removes both floor and flames")
	source.show()
	source.modulate = Color.WHITE
	animation.pause()
	animation.frame = 0
	var original_material := animation.material as ShaderMaterial
	var negative_shader := Shader.new()
	negative_shader.code = CLIPPED_SHADER
	var negative_material := ShaderMaterial.new()
	negative_material.shader = negative_shader
	negative_material.set_shader_parameter("fixed_mask", original_material.get_shader_parameter("fixed_mask"))
	animation.material = negative_material
	var clipped := await frame("negative-diamond-clip")
	animation.material = original_material
	var inverse := animation.global_transform.affine_inverse()
	var restored: Array[Vector2i] = []
	var invalid_changes := 0
	for y: int in correct.get_height():
		for x: int in correct.get_width():
			var pixel := Vector2i(x, y)
			if not different(correct.get_pixelv(pixel), clipped.get_pixelv(pixel)): continue
			var source_pixel := inverse * (Vector2(pixel) + Vector2(0.5, 0.5))
			var relative := (source_pixel - Vector2(128, 128.4580897)) / Vector2(115.162242, 87.3567251)
			if absf(relative.x) + absf(relative.y) < 0.98: invalid_changes += 1
			if absf(relative.x) + absf(relative.y) > 1.01: restored.append(pixel)
	check(restored.size() > 3 and invalid_changes == 0, "native tongues cross neighbouring stone while tile interior stays identical to clipped control")
	print("FIRE OVERLAP GPU restored=%d interior_changes=%d" % [restored.size(), invalid_changes])
	# Фигура закрывает языки обычным Y-sort, без глобального Z огня.
	var figure := Node2D.new()
	world.add_child(figure)
	figure.position = source.position + Vector2(0, 0.5)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-160, -220), Vector2(160, -220), Vector2(160, 2), Vector2(-160, 2)])
	body.color = Color(0.05, 0.9, 0.95, 1)
	figure.add_child(body)
	var covered := await frame("fire29-figure-depth")
	var covered_count := 0
	for pixel: Vector2i in restored:
		var local := Vector2(pixel) - figure.position
		if local.x > -155 and local.x < 155 and local.y > -215 and local.y < -3:
			var color := covered.get_pixelv(pixel)
			if color.g > 0.8 and color.b > 0.85 and color.r < 0.15: covered_count += 1
	check(covered_count > 0, "figure remains in front of restored flames")
	figure.queue_free()
	var base_texture := base.texture
	for slot: int in 12:
		animation.frame = slot
		check(base.texture == base_texture and base.transform == Transform2D.IDENTITY, "static floor does not animate with pose %d" % slot)
	await frame("fire29-neighbours-11")
	animation.frame = 0
	var looped := await frame("fire29-neighbours-00-loop")
	check(looped.get_data() == correct.get_data(), "return to frame0 has exact same rendered pixels")
	world.queue_free()
	await process_frame

func different(a: Color, b: Color) -> bool:
	return maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) > 0.025

func production_lifecycle() -> void:
	var profile := HeroHubState.create(443)
	profile.enable_mage_deck()
	var started := ExpeditionTransitions.apply(profile, "start")
	check(started.is_ok(), "production expedition starts")
	if not started.is_ok(): return
	var bundle := HeroHubBattleFactory.create(started.profile)
	var session: BattleCoreReactionsSession = bundle.session
	var original := ActionPresentationState.capture(session.state)
	var rng_before := session.context.get_rng().to_dict()
	var board := BattleDemoBoard.new()
	board.tile_visual_scene = TILE
	board.size = Vector2(1000, 800)
	viewport.add_child(board)
	board.session = session
	board.refresh()
	var chosen: BattleTerrainVisual
	for terrain: BattleDemoIsoVisual in board._terrain_visuals.values():
		if terrain is BattleTerrainVisual and (terrain as BattleTerrainVisual)._fire_view != null:
			chosen = terrain as BattleTerrainVisual
			break
	check(chosen != null, "production burning cell creates selected fire")
	if chosen != null:
		var fire := chosen._fire_view as BattleFire29Visual
		var base := fire.get_node(^"Base") as Polygon2D
		var animation := fire.get_node(^"Animation") as AnimatedSprite2D
		var original_id := base.get_instance_id()
		for _refresh: int in 3: board.refresh()
		check(chosen._fire_view == fire and fire.get_node(^"Base").get_instance_id() == original_id, "repeat publication reuses fire and static base")
		board.size += Vector2(75, 43)
		board._rescale_layout()
		await process_frame
		check(base.transform == Transform2D.IDENTITY and fire.position.is_equal_approx(chosen._top_offset())
			and animation.position.is_equal_approx(Vector2(-71.1344262, -(99.4580897 + 29.0) * 0.549471147)), "resize preserves accepted base and flame alignment")
		var detached := original.duplicate(true)
		detached.fires = []
		board.show_presentation_state(detached)
		check(not base.is_visible_in_tree() and not animation.is_playing(), "extinguish hides static base and pauses clock")
		board.show_presentation_state(original)
		check(base.is_visible_in_tree() and animation.is_playing(), "re-ignition restores static base and clock")
		board.tile_visual_scene = load("res://scenes/demo/visuals/art_trial_tile.tscn") as PackedScene
		board.refresh()
		await process_frame
		check(not is_instance_valid(fire) and not is_instance_valid(base), "scene replacement retires base and animation")
	check(ActionPresentationState.capture(session.state) == original and session.context.get_rng().to_dict() == rng_before, "render changes preserve live state and RNG")
	board.session = null
	board.queue_free()
	session.close()
	await process_frame
