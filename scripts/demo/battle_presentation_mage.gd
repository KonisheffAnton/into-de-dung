extends Node2D
class_name BattlePresentationMage

var phase: StringName = &"prepare"
var progress: float = 0.0
var source_point: Vector2 = Vector2.ZERO
var target_point: Vector2 = Vector2.ZERO
var spell_id: StringName = &"mage.fire"
var show_target: bool = true

func sample(p_phase: StringName, p_progress: float, p_source: Vector2, p_target: Vector2) -> void:
	phase = p_phase
	progress = clampf(p_progress, 0.0, 1.0)
	source_point = p_source
	target_point = p_target
	queue_redraw()

func _draw() -> void:
	var fire := spell_id == &"mage.fire"
	var tint := Color("ffb35c") if fire else Color("75e6a3")
	var title := "Внешний маг · Огонь" if fire else "Внешний маг · Лечение"
	if spell_id == &"mage.shield":
		tint = Color("71cefa"); title = "Верховный маг · Щит"
	elif spell_id == &"mage.test_summon":
		tint = Color("8fc9fa"); title = "Внешний маг · Призыв"
	elif spell_id == &"mage.test_raise":
		tint = Color("c7a2ed"); title = "Внешний маг · Поднятие"
	draw_string(ThemeDB.fallback_font, source_point + Vector2(0, -18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f3f5f7"))
	draw_circle(source_point, 8.0, Color("17212e"))
	draw_arc(source_point, 9.0, 0.0, TAU, 24, tint, 2.0, true)
	# Оплаченный FAULTED prefix может знать источник, но ещё не подтверждать клетку.
	if not show_target: return
	draw_arc(target_point, 12.0, 0.0, TAU, 32, Color(tint, 0.75), 2.0, true)
	if phase == &"prepare":
		var pulse := 1.0 + 0.16 * sin(progress * PI)
		draw_circle(source_point, 4.0 * pulse, tint)
	else:
		var t := progress if phase == &"delivery" else 1.0
		var point := source_point.lerp(target_point, t)
		draw_line(source_point, point, Color(tint, 0.42), 2.0, true)
		if phase == &"delivery":
			if fire:
				draw_set_transform(point, (target_point - source_point).angle())
				draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-6, -5), Vector2(-4, 0), Vector2(-6, 5)]), tint)
				draw_set_transform(Vector2.ZERO, 0.0)
			else:
				draw_circle(point, 6.0, tint)
				draw_line(point + Vector2(-9, 0), point + Vector2(9, 0), Color.WHITE, 1.5, true)
		else:
			var radius := 15.0 + 8.0 * progress
			draw_arc(target_point, radius, 0.0, TAU, 32, Color(tint, 1.0 - progress * 0.55), 3.0, true)
