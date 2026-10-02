extends Node2D
class_name BattlePresentationReaction

var kind: StringName = &""
var title: String = ""
var progress: float = 0.0
var source_point: Vector2 = Vector2.ZERO
var target_point: Vector2 = Vector2.ZERO

func sample(p_kind: StringName, p_title: String, p_progress: float, p_source: Vector2, p_target: Vector2) -> void:
	kind = p_kind
	title = p_title
	progress = clampf(p_progress, 0.0, 1.0)
	source_point = p_source
	target_point = p_target
	queue_redraw()

func _draw() -> void:
	if kind == &"":
		return
	var tint := Color("76d9f2") if kind == &"cover" else Color("ffbd69")
	if kind == &"guard":
		_draw_shield(target_point, tint, 10.0 + 2.0 * progress)
	else:
		var endpoint := target_point
		var reveal := progress
		# Линия показывает связь реакции; частичный прогресс раскрывает её от источника.
		var visible_end := source_point.lerp(endpoint, reveal)
		draw_line(source_point, visible_end, Color(tint, 0.18 + 0.68 * progress), 2.0, true)
		if kind == &"cover":
			_draw_shield(target_point, tint, 9.0)
		else:
			_draw_arrow(source_point, visible_end, tint)
	_draw_title(source_point + Vector2(0, -15), tint)

func _draw_shield(center: Vector2, tint: Color, size: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-size * 0.55, -size * 0.48),
		center + Vector2(size * 0.55, -size * 0.48),
		center + Vector2(size * 0.48, size * 0.12),
		center + Vector2(0, size * 0.62),
		center + Vector2(-size * 0.48, size * 0.12),
		center + Vector2(-size * 0.55, -size * 0.48),
	])
	draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], points[3], points[4]]), Color(tint, 0.18 + progress * 0.35))
	draw_polyline(points, tint, 1.8, true)

func _draw_arrow(p_start: Vector2, p_end: Vector2, tint: Color) -> void:
	var direction := (p_end - p_start).normalized()
	if direction == Vector2.ZERO:
		return
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([
		p_end,
		p_end - direction * 7.0 + side * 3.8,
		p_end - direction * 7.0 - side * 3.8,
	]), tint)

func _draw_title(anchor: Vector2, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var box := Rect2(anchor + Vector2(-3, -12), Vector2(minf(text_size.x + 6.0, 160.0), 17.0))
	draw_rect(box, Color("101d27", 0.94))
	draw_rect(box, Color(tint, 0.85), false, 1.0)
	draw_string(font, anchor, title, HORIZONTAL_ALIGNMENT_LEFT, 154.0, 13, Color("f3f5f7"))
