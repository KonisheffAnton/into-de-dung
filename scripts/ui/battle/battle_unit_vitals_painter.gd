extends RefCounted
class_name BattleUnitVitalsPainter

## Только опубликованный снимок: экранная геометрия не меняет бой и picking фигуры.
const BAR_WIDTH: float = 48.0
const BAR_HEIGHT: float = 11.0
const NUMBER_SIZE: int = 12
const MINIMUM_NUMBER_SIZE: int = 7
static var _number_font: FontFile
static var _baseline_offsets: Dictionary = {}
static var _glyph_heights: Dictionary = {}


static func draw_vitals(canvas: Node2D, unit: BattleUnitView, armor: Dictionary, forecast: Dictionary, local_anchor: Vector2) -> void:
	if unit == null or not unit.alive: return
	var screen := canvas.get_viewport_transform() * canvas.get_global_transform()
	if is_zero_approx(screen.determinant()): return
	var origin := (screen * local_anchor).round()
	var hp_text := BattleEventText.amount_text(unit.hp)
	var armor_text := BattleEventText.amount_text(float(armor.get("current", 0.0)))
	var width := _track_width(hp_text, armor_text if not armor.is_empty() else "")
	var hp_rect := Rect2(origin + Vector2(-width * 0.5, 14), Vector2(width, BAR_HEIGHT))
	var armor_rect := Rect2(origin + Vector2(-width * 0.5, 1), Vector2(width, BAR_HEIGHT))
	var after: Dictionary = forecast.get("after", {}) as Dictionary
	var expected_hp := float(after.get("hp", unit.hp))
	var hp_ratio := clampf(unit.hp / unit.hp_max if unit.hp_max > 0.0 else 0.0, 0.0, 1.0)
	# Компенсируем весь canvas/stretch сразу; числа и рамка не уменьшаются с камерой.
	canvas.draw_set_transform_matrix(screen.affine_inverse())
	_draw_track(canvas, hp_rect, hp_ratio, Color("a2bf7b"), Color("bad592"), Color("89a365"), Color("777d70"))
	if not is_equal_approx(expected_hp, unit.hp):
		var expected_ratio := clampf(expected_hp / unit.hp_max if unit.hp_max > 0.0 else 0.0, 0.0, 1.0)
		var inner := hp_rect.grow(-1.0)
		var tint := Color("f29b9b") if expected_hp < unit.hp else Color("a2bf7b")
		canvas.draw_rect(Rect2(inner.position + Vector2(inner.size.x * minf(hp_ratio, expected_ratio), 0), Vector2(inner.size.x * absf(hp_ratio - expected_ratio), inner.size.y)), tint)
		canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(-32, 56), "%s→%s" % [hp_text, BattleEventText.amount_text(expected_hp)], HORIZONTAL_ALIGNMENT_CENTER, 64, 9, tint)
		var mark := inner.position.x + inner.size.x * expected_ratio
		canvas.draw_line(Vector2(mark, hp_rect.position.y - 1), Vector2(mark, hp_rect.end.y + 1), Color.WHITE, 1)
	_draw_amount(canvas, hp_rect, hp_text)
	if not bool(after.get("alive", unit.alive)):
		canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(-18, 67), "ПОГИБ", HORIZONTAL_ALIGNMENT_CENTER, 36, 8, Color("f29b9b"))
	_draw_balance(canvas, Rect2(origin + Vector2(-width * 0.5, 27), Vector2(width, 4)), unit.balance, unit.balance_max)
	if not armor.is_empty():
		var maximum := float(armor.get("maximum", 0.0))
		var current := float(armor.get("current", 0.0))
		var expected := float(after.get("armor_current", current))
		_draw_track(canvas, armor_rect, current / maximum if maximum > 0.0 else 0.0, Color("c0cacb"), Color("dce4e2"), Color("a4b1b4"), Color("747d80"))
		if expected != current:
			var inner := armor_rect.grow(-1.0)
			var mark := inner.position.x + inner.size.x * (clampf(expected / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0)
			canvas.draw_line(Vector2(mark, armor_rect.position.y - 1), Vector2(mark, armor_rect.end.y + 1), Color.WHITE, 1)
		_draw_amount(canvas, armor_rect, armor_text)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _font() -> FontFile:
	if _number_font == null:
		# Приватная копия сохраняет прежний Jersey20 у урона и статусных счётчиков.
		_number_font = (load("res://assets/ui/combat_fonts/combat_letters.ttf") as FontFile).duplicate() as FontFile
		_number_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_number_font.hinting = TextServer.HINTING_NORMAL
		_number_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_number_font.oversampling = 1.0
		_number_font.keep_rounding_remainders = false
	return _number_font


static func _track_width(hp_text: String, armor_text: String) -> float:
	var font := _font()
	var minimum_width := maxf(font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, MINIMUM_NUMBER_SIZE).x, font.get_string_size(armor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, MINIMUM_NUMBER_SIZE).x)
	# Редкое длинное значение расширяет трек симметрично; число не обрезается и не округляется.
	return maxf(BAR_WIDTH, ceilf((minimum_width + 4.0) * 0.5) * 2.0)


static func _baseline_offset(font_size: int) -> float:
	if _baseline_offsets.has(font_size): return float(_baseline_offsets[font_size])
	var server := TextServerManager.get_primary_interface()
	var rid: RID = _font().get_rids()[0]
	var top := INF
	var bottom := -INF
	for character: String in "0123456789.":
		var glyph := server.font_get_glyph_index(rid, font_size, character.unicode_at(0), 0)
		var size := Vector2i(font_size, 0)
		server.font_render_glyph(rid, size, glyph)
		var offset := server.font_get_glyph_offset(rid, size, glyph)
		var extent := server.font_get_glyph_size(rid, size, glyph)
		if extent.y <= 0.0: continue
		top = minf(top, offset.y)
		bottom = maxf(bottom, offset.y + extent.y)
	var baseline := -(top + bottom) * 0.5 if is_finite(top) and is_finite(bottom) else 3.5
	_baseline_offsets[font_size] = baseline
	_glyph_heights[font_size] = bottom - top if is_finite(top) and is_finite(bottom) else INF
	return baseline


static func _glyph_height(font_size: int) -> float:
	# Метрики каждого кегля растеризуются один раз, а не для каждой полосы при pan.
	_baseline_offset(font_size)
	return float(_glyph_heights[font_size])


static func _draw_amount(canvas: Node2D, rect: Rect2, text: String) -> void:
	var font := _font()
	var font_size := NUMBER_SIZE
	while font_size > MINIMUM_NUMBER_SIZE and (_glyph_height(font_size) > 7.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4.0):
		font_size -= 1
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := Vector2(rect.get_center().x - width * 0.5, rect.get_center().y + _baseline_offset(font_size)).round()
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	# Второй проход усиливает тонкий штрих малого кегля, не расширяя его до рамки.
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	# Прогноз может пересекать рамку; после текста восстанавливаем её внутри внешних границ.
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color.BLACK)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), Color.BLACK)
	canvas.draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), Color.BLACK)
	canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), Color.BLACK)


static func _draw_track(canvas: Node2D, rect: Rect2, ratio: float, fill: Color, light: Color, shade: Color, empty: Color) -> void:
	canvas.draw_rect(rect, Color.BLACK)
	var inner := rect.grow(-1.0)
	canvas.draw_rect(inner, empty)
	if ratio <= 0.0: return
	var filled := Rect2(inner.position, Vector2(minf(inner.size.x, maxf(1.0, inner.size.x * clampf(ratio, 0.0, 1.0))), inner.size.y))
	canvas.draw_rect(filled, fill)
	canvas.draw_rect(Rect2(filled.position, Vector2(filled.size.x, 1)), light)
	canvas.draw_rect(Rect2(filled.end - Vector2(filled.size.x, 1), Vector2(filled.size.x, 1)), shade)


static func _draw_balance(canvas: Node2D, rect: Rect2, disruption: float, maximum: float) -> void:
	var whole_maximum := BalancePoints.whole(maximum)
	var remaining := BattleBalanceDisplay.remaining(disruption, whole_maximum)
	canvas.draw_rect(rect, Color.BLACK)
	var inner := rect.grow(-1.0)
	canvas.draw_rect(inner, Color("45494b"))
	# Невосприимчивость не имеет делимых очков и показывает полный ресурс без делений.
	if whole_maximum <= 0.0:
		_draw_balance_segment(canvas, inner, Color("bea16c"))
		return
	# При плотной шкале сохраняем пропорцию трека, потому что отдельные очки неразличимы.
	if inner.size.x / whole_maximum < 2.0:
		var ratio := BattleBalanceDisplay.ratio(disruption, whole_maximum)
		var dense_width := minf(inner.size.x, maxf(1.0, inner.size.x * ratio))
		if ratio > 0.0:
			_draw_balance_segment(canvas, Rect2(inner.position, Vector2(dense_width, inner.size.y)), Color("bea16c"))
		return
	var section_count := int(whole_maximum)
	var filled_sections := int(remaining)
	var edges: Array[int] = []
	for point: int in range(section_count + 1):
		# Целые экранные границы не оставляют случайных дробных полос внутри очка.
		edges.append(roundi(inner.position.x + inner.size.x * float(point) / float(section_count)))
	for section: int in section_count:
		var section_rect := Rect2(Vector2(edges[section], inner.position.y),
			Vector2(edges[section + 1] - edges[section], inner.size.y))
		if section < filled_sections:
			_draw_balance_segment(canvas, section_rect, Color("bea16c"))
	for point: int in range(1, section_count):
		canvas.draw_rect(Rect2(Vector2(edges[point], inner.position.y), Vector2(1.0, inner.size.y)), Color.BLACK)


static func _draw_balance_segment(canvas: Node2D, rect: Rect2, fill: Color) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), Color("cdb888"))
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - 1.0), Vector2(rect.size.x, 1.0)), Color("a58b60"))
