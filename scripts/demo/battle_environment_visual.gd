class_name BattleEnvironmentVisual
extends Node2D

var has_spikes: bool = false
var has_burning_fallback: bool = false
var is_warning: bool = false
var corpse_records: Array[Dictionary] = []

var collapse_progress: float = -1.0:
	set(value):
		collapse_progress = value
		queue_redraw()

var hazard_progress: float = -1.0:
	set(value):
		hazard_progress = value
		queue_redraw()

var warning_phase: float = 0.0:
	set(value):
		warning_phase = value
		queue_redraw()


func configure(spikes: bool, burning_fallback: bool, collapse_warning: bool, corpses: Array[Dictionary]) -> void:
	has_spikes = spikes
	has_burning_fallback = burning_fallback
	is_warning = collapse_warning
	# Значения отделяются от вызывающей стороны, чтобы визуал не удерживал живые runtime-записи.
	corpse_records = corpses.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var collapse: float = clampf(collapse_progress, 0.0, 1.0) if collapse_progress >= 0.0 else -1.0
	var remains_alpha: float = 1.0 - collapse if collapse >= 0.0 else 1.0
	if collapse >= 1.0:
		remains_alpha = 0.0

	if is_warning and collapse < 1.0:
		_draw_warning(remains_alpha)
	if has_spikes:
		_draw_spikes(remains_alpha)
	if has_burning_fallback:
		_draw_fire(remains_alpha)
	_draw_corpses(remains_alpha)
	if hazard_progress >= 0.0:
		_draw_hazard_accent(clampf(hazard_progress, 0.0, 1.0), remains_alpha)
	if collapse >= 0.0:
		_draw_collapse(collapse)


func _draw_spikes(alpha: float) -> void:
	var tint: Color = Color("d6dce1", 0.86 * alpha)
	var dark: Color = Color("414d55", 0.9 * alpha)
	# Низкие треугольные шипы повторяют поверхность клетки и не закрывают соседние тайлы.
	for index: int in range(5):
		var x: float = -35.0 + float(index) * 17.5
		var y: float = 12.0 + absf(x) * 0.22
		var tip: Vector2 = Vector2(x, y - 9.0)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(x - 5.0, y + 2.0), Vector2(x + 5.0, y + 2.0)]), tint)
		draw_polyline(PackedVector2Array([tip, Vector2(x, y + 1.0)]), dark, 1.1, true)


func _draw_fire(alpha: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(warning_phase)
	var center: Vector2 = Vector2(0.0, 10.0)
	var glow: Color = Color("f5a34b", (0.22 + pulse * 0.12) * alpha)
	draw_colored_polygon(_ellipse_points(center, 19.0, 7.0, 14), glow)
	for index: int in range(3):
		var x: float = -9.0 + float(index) * 9.0
		var base_y: float = 13.0 + (1.0 if index == 1 else 0.0)
		var height: float = 11.0 + pulse * 3.0 - float(index % 2) * 2.0
		var flame: PackedVector2Array = PackedVector2Array([
			Vector2(x - 4.0, base_y), Vector2(x - 2.0, base_y - height * 0.58),
			Vector2(x, base_y - height), Vector2(x + 1.5, base_y - height * 0.48),
			Vector2(x + 4.0, base_y)
		])
		draw_colored_polygon(flame, Color("f27d3e", alpha * 0.88))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 1.8, base_y), Vector2(x, base_y - height * 0.56), Vector2(x + 1.8, base_y)]), Color("ffd27a", alpha * 0.9))


func _draw_warning(alpha: float) -> void:
	if alpha <= 0.0:
		return
	var pulse: float = 0.5 + 0.5 * sin(warning_phase)
	var tint: Color = Color("f0a267", alpha * (0.42 + pulse * 0.32))
	# Разломы лежат внутри ромба: они предупреждают об обвале без текстовой метки.
	var cracks: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-37, -7), Vector2(-25, -12), Vector2(-16, -8), Vector2(-6, -14), Vector2(5, -10)]),
		PackedVector2Array([Vector2(-27, 6), Vector2(-18, 11), Vector2(-20, 18), Vector2(-11, 23)]),
		PackedVector2Array([Vector2(25, 3), Vector2(17, 9), Vector2(20, 15), Vector2(11, 20)]),
		PackedVector2Array([Vector2(-5, 17), Vector2(1, 13), Vector2(7, 18), Vector2(12, 15)])
	]
	for crack: PackedVector2Array in cracks:
		draw_polyline(crack, Color("291711", alpha * 0.9), 4.5, true)
		draw_polyline(crack, tint, 1.7, true)
		for point_index: int in range(crack.size() - 1):
			var point: Vector2 = crack[point_index]
			draw_circle(point, 1.0, Color("ffe0ab", tint.a * 0.8))
	# Край остаётся заметным даже под несколькими телами или стоящей фигурой.
	var rim := PackedVector2Array([Vector2(0, -28), Vector2(56, 0), Vector2(0, 28), Vector2(-56, 0), Vector2(0, -28)])
	draw_polyline(rim, Color("291711", alpha * 0.8), 3.5, true)
	draw_polyline(rim, Color("ffc17d", alpha * (0.30 + pulse * 0.40)), 1.6, true)


func _draw_corpses(alpha: float) -> void:
	var visible_count: int = mini(corpse_records.size(), 3)
	if visible_count == 0 or alpha <= 0.0:
		return
	for index: int in range(visible_count):
		var record: Dictionary = corpse_records[index]
		var centered_index: float = float(index) - float(visible_count - 1) * 0.5
		var center: Vector2 = Vector2(centered_index * 12.0, 4.0 + float(index) * 6.0)
		_draw_corpse(center, _faction_color(record.get("faction", -1)), alpha)
	if corpse_records.size() > 1:
		# Число сообщает только количество тел; детали состояния юнита здесь недоступны.
		draw_string(ThemeDB.fallback_font, Vector2(24.0, 17.0), str(corpse_records.size()), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 10, Color("e3e0d9", alpha * 0.9))


func _draw_corpse(center: Vector2, base_tint: Color, alpha: float) -> void:
	var tint: Color = Color(base_tint.r, base_tint.g, base_tint.b, base_tint.a * alpha)
	var shadow: Color = Color("18232a", alpha * 0.52)
	# Лежащий силуэт остаётся коротким и приглушённым, не напоминая активного бойца.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-23, 1), center + Vector2(-12, -7), center + Vector2(13, -6),
		center + Vector2(19, 0), center + Vector2(11, 9), center + Vector2(-20, 8)
	]), shadow)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-21, -5), center + Vector2(-11, -5), center + Vector2(-6, -3),
		center + Vector2(5, -5), center + Vector2(9, -3), center + Vector2(6, 1),
		center + Vector2(2, 6), center + Vector2(-1, 5), center + Vector2(2, 1),
		center + Vector2(-7, 2), center + Vector2(-19, 6), center + Vector2(-22, 3),
		center + Vector2(-11, -1), center + Vector2(-21, -2)
	]), tint)
	draw_circle(center + Vector2(13, -3), 3.7, tint.lightened(0.12))


func _draw_hazard_accent(progress: float, alpha: float) -> void:
	var strength: float = sin(progress * PI) * alpha
	if strength <= 0.0:
		return
	var tint: Color = Color("ffe2a0", strength * 0.95)
	if has_spikes:
		for index: int in range(5):
			var x: float = -35.0 + float(index) * 17.5
			var y: float = 4.0 + absf(x) * 0.22
			draw_circle(Vector2(x, y), 2.0 + strength, tint)
	else:
		draw_polyline(_ellipse_points(Vector2(0.0, 10.0), 22.0, 9.0, 20), Color("ffd07a", strength * 0.7), 2.0, true)


func _draw_collapse(progress: float) -> void:
	if progress <= 0.0:
		return
	var amount: float = clampf(progress, 0.0, 1.0)
	# Фрагменты вычисляются из индекса, поэтому повторный кадр не меняет результат.
	for index: int in range(7):
		var phase: float = float(index) * 1.71
		var travel: float = amount * (7.0 + float(index % 3) * 5.0)
		var point: Vector2 = Vector2(sin(phase) * (13.0 + float(index % 4) * 8.0), 5.0 + float(index % 3) * 8.0 + travel)
		var fade: float = 1.0 - amount * 0.72
		var tint: Color = Color("c6a789", fade * 0.75)
		draw_colored_polygon(PackedVector2Array([
			point, point + Vector2(2.2, -1.2), point + Vector2(3.0, 1.6), point + Vector2(0.4, 2.4)
		]), tint)
		if index % 2 == 0:
			draw_circle(point + Vector2(0.0, 3.5), 1.1 + amount, Color("b8a99a", fade * 0.35))


func _faction_color(faction_value: Variant) -> Color:
	var faction: int = int(faction_value)
	match faction:
		0: return Color("8297aa")
		1: return Color("a87970")
		2: return Color("9c916b")
		3: return Color("817ba0")
		_: return Color("8e969a")


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points
