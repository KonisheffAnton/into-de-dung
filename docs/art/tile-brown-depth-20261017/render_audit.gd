extends "res://docs/art/archer-placement-20261017/render_audit.gd"

const TILE: PackedScene = preload("res://scenes/demo/visuals/art_trial_tile.tscn")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var gallery := Image.create(768, 2240, false, Image.FORMAT_RGBA8)
	gallery.fill(Color("101a27"))
	var cases: Array[Dictionary] = [
		{"role": BattleDemoIsoVisual.Role.FLOOR, "steps": 0, "void": false},
		{"role": BattleDemoIsoVisual.Role.PLATFORM, "steps": 2, "void": false},
		{"role": BattleDemoIsoVisual.Role.FLOOR, "steps": -2, "void": false},
		{"role": BattleDemoIsoVisual.Role.WALL, "steps": 0, "void": false},
		{"role": BattleDemoIsoVisual.Role.FLOOR, "steps": 0, "void": true}]
	for index: int in cases.size(): await _tile(cases[index], index, gallery)
	check(gallery.save_png(output.path_join("comparison.png")) == OK, "save tile comparison")
	await _battle()
	print("BROWN TILE DEPTH AUDIT RESULTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _tile(values: Dictionary, index: int, gallery: Image) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(384, 448)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var tile := TILE.instantiate() as BattleTerrainVisual
	view.add_child(tile)
	await process_frame
	var config := IsoGridConfig.new()
	config.tile_size = Vector2(256, 192)
	config.height_step = 64.0
	config.origin_offset = Vector2(192, 210)
	tile.apply_view({"cell": Vector2i.ZERO, "role": values.role, "half_steps": values.steps,
		"is_void": values.void, "reachable": false, "enemy_range": false, "burning": false}, config)
	var surfaces := tile.surface_polygons()
	var top := tile.top_polygon()
	var prior_transform := tile.transform
	var depth: float = tile.side_depth_pixels
	var ground_art_active: bool = tile._uses_ground_art()
	var sides: Array[Polygon2D] = [tile.get_node("ArtRoot/SideLeft"), tile.get_node("ArtRoot/SideRight")]
	# Отдельный снимок верха не зависит от боковин ни одной из сравниваемых версий.
	for side: Polygon2D in sides: side.visible = false
	var clean_top := await _capture(view)
	# Состояние до этой правки: толщина18, зелёный верх грани и холодный тёмный низ.
	tile.side_depth_pixels = 18.0
	tile.sync_scene_art()
	if ground_art_active:
		var base: Color = tile.ground_base_tint
		for face: int in 2:
			var upper: Color = base.darkened(0.25 if face == 0 else 0.12)
			var lower: Color = Color("1d2326") if face == 0 else Color("20272a")
			sides[face].vertex_colors = PackedColorArray([upper, upper, lower, lower])
	var before := await _capture(view)
	tile.side_depth_pixels = depth
	tile.sync_scene_art()
	var after := await _capture(view)
	check(tile.transform == prior_transform and tile.surface_polygons() == surfaces
		and tile.top_polygon() == top, "top/picking/root unchanged case " + str(index))
	var top_changes: int = 0
	var center := tile.position + (top[0] + top[2]) * 0.5
	for y: int in 448:
		for x: int in 384:
			var p := Vector2(x + 0.5, y + 0.5) - center
			if absf(p.x) / 128.0 + absf(p.y) / 96.0 >= 0.90: continue
			if clean_top.get_pixel(x, y) != after.get_pixel(x, y): top_changes += 1
	check(top_changes == 0, "authored top interior pixels preserved case %d (%d)" % [index, top_changes])
	check((before.get_data() != after.get_data()) == ground_art_active, "only ground-art sides change case " + str(index))
	gallery.blend_rect(before, Rect2i(0, 0, 384, 448), Vector2i(0, index * 448))
	gallery.blend_rect(after, Rect2i(0, 0, 384, 448), Vector2i(384, index * 448))
	view.queue_free()
	await process_frame
