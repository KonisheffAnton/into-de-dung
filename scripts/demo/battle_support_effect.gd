extends Node2D
class_name BattleSupportEffect

var effect_kind: StringName = &"item_potion"
var phase: StringName = &"prepare"
var progress: float = 0.0
var source_point: Vector2 = Vector2.ZERO
var target_point: Vector2 = Vector2.ZERO

func sample(p_kind: StringName, p_phase: StringName, p_progress: float, p_source: Vector2, p_target: Vector2) -> void:
	effect_kind = p_kind
	phase = p_phase
	progress = clampf(p_progress, 0.0, 1.0)
	source_point = p_source
	target_point = p_target
	queue_redraw()

func _draw() -> void:
	var raised := effect_kind in [&"character_raise", &"mage_raise"]
	var summoned := effect_kind in [&"item_seal", &"mage_summon"]
	var tint := Color("c7a2ed") if raised else (Color("8fc9fa") if summoned else Color("7de0a0"))
	if effect_kind == &"item_potion":
		_draw_potion(tint)
	elif effect_kind == &"item_seal":
		_draw_seal(tint)
	elif phase == &"prepare":
		draw_circle(source_point, 7.0 + 2.0 * sin(progress * PI), Color("17212e"))
		draw_arc(source_point, 10.0, 0.0, TAU, 24, tint, 2.0, true)
	if phase == &"delivery":
		var point := source_point.lerp(target_point, progress)
		draw_line(source_point, point, Color(tint, 0.48), 2.0, true)
		draw_circle(point, 4.0, tint)
	elif phase == &"contact":
		if raised:
			_draw_raised_wisps(tint)
		elif summoned:
			_draw_emerging_silhouette(tint)

func _draw_potion(tint: Color) -> void:
	var point := source_point.lerp(target_point, progress) if phase == &"delivery" else source_point
	# Флакон остаётся видимым у бойца: лечебное действие не маскируется под обычную атаку.
	draw_rect(Rect2(point + Vector2(-4, -7), Vector2(8, 13)), Color("182432"), true)
	draw_rect(Rect2(point + Vector2(-3, -4), Vector2(6, 8)), tint, true)
	draw_rect(Rect2(point + Vector2(-2, -10), Vector2(4, 3)), Color("e6edf5"), true)
	if phase == &"contact":
		for index in 3:
			var angle := TAU * float(index) / 3.0 + progress * TAU
			draw_circle(target_point + Vector2.RIGHT.rotated(angle) * (8.0 + progress * 8.0), 2.0, Color(tint, 1.0 - progress * 0.6))

func _draw_seal(tint: Color) -> void:
	var point := source_point.lerp(target_point, progress) if phase == &"delivery" else source_point
	draw_set_transform(point, 0.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(8, -4), Vector2(6, 6), Vector2(0, 10), Vector2(-6, 6), Vector2(-8, -4)]), Color("26334a"))
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, tint, 2.0, true)
	draw_line(Vector2(-4, 0), Vector2(4, 0), tint, 2.0, true)
	draw_line(Vector2(0, -4), Vector2(0, 4), tint, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0)

func _draw_emerging_silhouette(tint: Color) -> void:
	var rise := (1.0 - progress) * 14.0
	var center := target_point + Vector2(0, rise)
	draw_arc(target_point, 11.0 + progress * 8.0, 0.0, TAU, 28, Color(tint, 1.0 - progress * 0.6), 2.0, true)
	draw_circle(center + Vector2(0, -8), 3.0, tint)
	draw_line(center + Vector2(0, -4), center + Vector2(0, 5), tint, 3.0, true)
	draw_line(center + Vector2(0, -1), center + Vector2(-5, 3), tint, 2.0, true)
	draw_line(center + Vector2(0, -1), center + Vector2(5, 3), tint, 2.0, true)

func _draw_raised_wisps(tint: Color) -> void:
	# Тело уже лежит на клетке: wisps поднимаются над ним, не рисуя новую фигуру до after.
	for index in 3:
		var phase_shift := float(index) * 0.26
		var lift := fposmod(progress + phase_shift, 1.0)
		var x := float(index - 1) * 6.0
		var base := target_point + Vector2(x, 2.0)
		var tip := base + Vector2(sin((progress + phase_shift) * TAU) * 3.0, -6.0 - lift * 15.0)
		draw_line(base, tip, Color(tint, 1.0 - lift * 0.55), 2.0, true)
		draw_circle(tip, 1.7, Color(tint, 1.0 - lift * 0.55))
