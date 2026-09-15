extends YSortable
class_name BattleDemoIsoVisual

enum Role { FLOOR, PLATFORM, WALL, UNIT }
var role: Role = Role.FLOOR
var half_steps: int = 0
var unit: UnitState
var is_void: bool = false
var selected: bool = false
var reachable: bool = false
var enemy_range: bool = false
var inspected: bool = false
var forecast_entry: Dictionary = {}
var transient_label: String = ""
var transient_tint := Color("f7c97d")
var fall_drop: float = 0.0:
	set(value):
		fall_drop = value
		queue_redraw()

func _update_sort_position() -> void:
	super._update_sort_position()
	# При одной опоре площадка рисуется перед стоящей на ней фигурой.
	if role != Role.UNIT: position.y -= 0.5

func get_visual_offset() -> Vector2:
	if grid_config == null: return Vector2.ZERO
	return Vector2(0, -0.5 * float(half_steps) * grid_config.height_step + fall_drop)

func _top_offset() -> Vector2:
	var offset := get_visual_offset()
	if role == Role.WALL: offset.y -= grid_config.height_step
	# Эпсилон влияет только на сортировку, а не на видимую геометрию.
	if role != Role.UNIT: offset.y += 0.5
	return offset

func top_polygon() -> PackedVector2Array:
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	var top := _top_offset()
	return PackedVector2Array([top + Vector2(0, -hh), top + Vector2(hw, 0), top + Vector2(0, hh), top + Vector2(-hw, 0)])

func surface_polygons() -> Array[PackedVector2Array]:
	if role == Role.UNIT:
		if unit != null and not unit.is_alive(): return []
		var factor := grid_config.tile_size.x / 128.0
		var offset := get_visual_offset()
		return [PackedVector2Array([offset + Vector2(-17, 7) * factor, offset + Vector2(-17, -37) * factor, offset + Vector2(17, -37) * factor, offset + Vector2(17, 7) * factor])]
	var top := top_polygon()
	if is_void: return [top]
	var bottom := Vector2(0, grid_config.height_step * 0.55 + 0.5)
	if role == Role.WALL: bottom = get_visual_offset() + Vector2(0, 0.5)
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	return [PackedVector2Array([top[3], top[2], bottom + Vector2(0, hh), bottom + Vector2(-hw, 0)]), PackedVector2Array([top[2], top[1], bottom + Vector2(hw, 0), bottom + Vector2(0, hh)]), top]

func contains_point(point: Vector2) -> bool:
	for polygon in surface_polygons():
		if Geometry2D.is_point_in_polygon(point - position, polygon): return true
	return false

func _draw() -> void:
	if grid_config == null: return
	if role == Role.UNIT:
		_draw_unit()
		return
	var color := Color("344858") if (grid_anchor.x + grid_anchor.y) % 2 == 0 else Color("3d5361")
	if half_steps > 0: color = Color("527e78").lightened(float(half_steps) * 0.025)
	if half_steps < 0: color = Color("304453")
	if role == Role.WALL: color = Color("78818d")
	if is_void: color = Color("080f1a")
	var shapes := surface_polygons()
	if shapes.size() == 3:
		draw_colored_polygon(shapes[0], color.darkened(0.40))
		draw_colored_polygon(shapes[1], color.darkened(0.22))
	var top := top_polygon()
	draw_colored_polygon(top, color)
	draw_polyline(top + PackedVector2Array([top[0]]), Color("14232e"), 1.2, true)
	if enemy_range:
		# Зона осмотра лежит на самой поверхности, чтобы не закрывать native Y-sort сущностей.
		draw_colored_polygon(top, Color(0.96, 0.68, 0.20, 0.22))
		draw_polyline(top + PackedVector2Array([top[0]]), Color(0.98, 0.76, 0.28, 0.78), 1.5, true)
	var center := _top_offset()
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	if role == Role.WALL:
		draw_line(top[3].lerp(top[0], 0.5), top[2].lerp(top[1], 0.5), color.darkened(0.25), 1)
	elif is_void:
		draw_string(ThemeDB.fallback_font, center + Vector2(-hw * 0.6, 3), "ПРОПАСТЬ", HORIZONTAL_ALIGNMENT_CENTER, hw * 1.2, 8, Color("53647a"))
	else:
		draw_string(ThemeDB.fallback_font, center + Vector2(-22, -hh * 0.37), "%+.1f" % (float(half_steps) / 2.0), HORIZONTAL_ALIGNMENT_CENTER, 44, 10, Color("b7c9ce"))
		if reachable: draw_circle(center + Vector2(hw * 0.62, 0), 2, Color("65dfcc"))

func _draw_unit() -> void:
	var factor := grid_config.tile_size.x / 128.0
	var foot := get_visual_offset()
	if unit != null and not unit.is_alive():
		var marker := foot + Vector2(16, 4) * factor
		draw_line(marker - Vector2(4, 4), marker + Vector2(4, 4), Color("a5b3c5"), 2)
		draw_line(marker - Vector2(4, -4), marker + Vector2(4, -4), Color("a5b3c5"), 2)
		return
	var tint := transient_tint if unit == null else (Color("65dfcc") if unit.faction == Faction.Type.PLAYER else Color("f7c97d"))
	if selected:
		var hw := grid_config.tile_size.x * 0.38
		var hh := grid_config.tile_size.y * 0.38
		draw_polyline(PackedVector2Array([foot + Vector2(0, -hh), foot + Vector2(hw, 0), foot + Vector2(0, hh), foot + Vector2(-hw, 0), foot + Vector2(0, -hh)]), tint, 2, true)
	if inspected:
		var ring_hw := grid_config.tile_size.x * 0.42
		var ring_hh := grid_config.tile_size.y * 0.42
		draw_polyline(PackedVector2Array([foot + Vector2(0, -ring_hh), foot + Vector2(ring_hw, 0), foot + Vector2(0, ring_hh), foot + Vector2(-ring_hw, 0), foot + Vector2(0, -ring_hh)]), Color("f7c97d"), 3, true)
	# Высота силуэта отделена от его наземной опоры для общей Y-сортировки.
	draw_set_transform(foot, 0, Vector2.ONE * factor)
	draw_colored_polygon(PackedVector2Array([Vector2(-18, 0), Vector2(0, -7), Vector2(18, 0), Vector2(0, 7)]), Color(0.03, 0.07, 0.10, 0.65))
	draw_rect(Rect2(-10, -10, 7, 12), tint.darkened(0.5))
	draw_rect(Rect2(3, -10, 7, 12), tint.darkened(0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(-14, -26), Vector2(10, -26), Vector2(14, -9), Vector2(-12, -9)]), tint)
	draw_colored_polygon(PackedVector2Array([Vector2(10, -26), Vector2(16, -22), Vector2(17, -8), Vector2(14, -9)]), tint.darkened(0.3))
	draw_rect(Rect2(-8, -37, 16, 13), tint.lightened(0.25))
	draw_line(Vector2(-4, -30), Vector2(7, -30), Color("172230"), 3)
	var label := transient_label if unit == null else unit.debug_name
	draw_string(ThemeDB.fallback_font, Vector2(-10, -12), label.left(1), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color("172230"))
	if unit != null:
		var hp_max := unit.get_stat(StatTypes.StatType.HP_MAX)
		var balance_max := unit.get_stat(StatTypes.StatType.BALANCE_MAX)
		var hp := clampf(unit.vitals.get_hp() / hp_max if hp_max > 0 else 0, 0, 1)
		var forecast_after: Dictionary = forecast_entry.get("after", {}) as Dictionary
		var expected_hp := float(forecast_after.get("hp", unit.vitals.get_hp()))
		var expected_alive := bool(forecast_after.get("alive", unit.is_alive()))
		var balance := clampf(unit.vitals.get_balance() / balance_max if balance_max > 0 else 0, 0, 1)
		draw_rect(Rect2(-19, 7, 38, 4), Color("0f1d28"))
		draw_rect(Rect2(-19, 7, 38 * hp, 4), Color("65dfcc"))
		if not is_equal_approx(expected_hp, unit.vitals.get_hp()):
			var expected_ratio := clampf(expected_hp / hp_max if hp_max > 0 else 0.0, 0.0, 1.0)
			var current_ratio := hp
			var segment_start := minf(current_ratio, expected_ratio)
			var segment_width := absf(expected_ratio - current_ratio)
			draw_rect(Rect2(-19 + 38 * segment_start, 7, 38 * segment_width, 4), Color("f29b9b") if expected_hp < unit.vitals.get_hp() else Color("65dfcc"))
			draw_string(ThemeDB.fallback_font, Vector2(-28, 28), "%.1f→%.1f" % [unit.vitals.get_hp(), expected_hp], HORIZONTAL_ALIGNMENT_CENTER, 56, 9, Color("f29b9b") if expected_hp < unit.vitals.get_hp() else Color("65dfcc"))
			draw_line(Vector2(-19 + 38 * expected_ratio, 6), Vector2(-19 + 38 * expected_ratio, 12), Color.WHITE, 1)
		if not expected_alive: draw_string(ThemeDB.fallback_font, Vector2(-18, 38), "ПОГИБ", HORIZONTAL_ALIGNMENT_CENTER, 36, 8, Color("f29b9b"))
		draw_rect(Rect2(-19, 13, 38, 3), Color("0f1d28"))
		draw_rect(Rect2(-19, 13, 38 * balance, 3), Color("f7c97d"))
	draw_set_transform(Vector2.ZERO)
