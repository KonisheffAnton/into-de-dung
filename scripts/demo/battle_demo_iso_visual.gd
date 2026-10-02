extends YSortable
class_name BattleDemoIsoVisual

enum Role { FLOOR, PLATFORM, WALL, UNIT }
var role: Role = Role.FLOOR
var half_steps: int = 0
var unit: BattleUnitView
var is_void: bool = false
var selected: bool = false
var reachable: bool = false
var enemy_range: bool = false
var inspected: bool = false
var hovered: bool = false
var acting: bool = false
var forecast_entry: Dictionary = {}
var armor_values: Dictionary = {}
var show_rear: bool = false
var status_text: String = ""
var transient_label: String = ""
var transient_tint := Color("f7c97d")
## Доска передаёт снимок значений, чтобы рисунок не читал runtime боя.
var status_entries: Array[Dictionary] = []
## Пассивный снимок стойки; отдельный знак не занимает место в строке состояний.
var reaction_view: Dictionary = {}
## Доска публикует только видимые остатки ресурсов; HUD не обращается к runtime.
var action_resources_view: Dictionary = {}
@export var body_pick_rect: Rect2 = Rect2(-17, -37, 34, 44)
## Демонстрационные состояния выбираются доской; сцена только отображает слои.
var frozen: bool = false
var burning: bool = false
var stunned: bool = false
var entangled: bool = false
const STATUS_ICON_SIZE: float = 16.0
const STATUS_ICON_GAP: float = 1.0
const STATUS_ICON_LIMIT: int = 5
const BLEEDING_ICON: Texture2D = preload("res://assets/placeholder_battle/bleeding_icon.svg")
const BURNING_ICON: Texture2D = preload("res://assets/placeholder_battle/burning_icon.svg")
const WET_ICON: Texture2D = preload("res://assets/placeholder_battle/wet_icon.svg")
var _scene_art_enabled: bool = false
var _status_hud: Node2D
## Выпад/отдача сдвигают рисунок, но не опору сортировки, клетку и HUD.
var action_offset: Vector2 = Vector2.ZERO:
	set(value):
		action_offset = value
		sync_scene_art()
		queue_redraw()
var presentation_lift: float = 0.0:
	set(value):
		presentation_lift = value
		sync_scene_art()
		queue_redraw()
var fall_drop: float = 0.0:
	set(value):
		fall_drop = value
		sync_scene_art()
		queue_redraw()
var presentation_offset: Vector2 = Vector2.ZERO:
	set(value):
		presentation_offset = value
		sync_scene_art()
		queue_redraw()

func _ready() -> void:
	super._ready()
	if role != Role.UNIT: return
	_status_hud = Node2D.new()
	_status_hud.name = "StatusHud"
	# HUD остаётся в локальной сортировке, чтобы передние фигуры и тайлы могли его закрыть.
	_status_hud.z_index = 0
	add_child(_status_hud)
	_status_hud.draw.connect(_draw_status_hud)
	_sync_status_hud()

func _sync_status_hud() -> void:
	if _status_hud == null: return
	_status_hud.position = get_visual_offset()
	_status_hud.scale = Vector2.ONE * (grid_config.tile_size.x / 128.0 if grid_config != null else 1.0)
	_status_hud.visible = role == Role.UNIT and unit != null and unit.alive
	_status_hud.queue_redraw()

func _draw_status_hud() -> void:
	_draw_status_icons(_status_hud)
	_draw_action_resources(_status_hud)
	_draw_reaction_view(_status_hud)

func _draw_action_resources(canvas: Node2D) -> void:
	var main_left := maxi(0, int(action_resources_view.get("main", 0)))
	var bonus_left := maxi(0, int(action_resources_view.get("bonus", 0)))
	var main_text := "О: %d" % main_left
	var bonus_text := "Д: %d" % bonus_left
	var font := ThemeDB.fallback_font
	var font_size := 9
	var text_width := maxf(font.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
		font.get_string_size(bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# Правый край фиксирован у тела, поэтому длинные числа расширяют плашку влево.
	var width := maxf(26.0, text_width + 6.0)
	var box := Rect2(-29.0 - width, -59.0, width, 26.0)
	canvas.draw_rect(box, Color("101d27", 0.94))
	var main_tint := Color("75dfdc") if main_left > 0 else Color("6b7782")
	var bonus_tint := Color("f2b85e") if bonus_left > 0 else Color("6b7782")
	canvas.draw_string(font, Vector2(box.position.x + 3.0, -47.0), main_text, HORIZONTAL_ALIGNMENT_LEFT, width - 6.0, font_size, main_tint)
	canvas.draw_string(font, Vector2(box.position.x + 3.0, -35.0), bonus_text, HORIZONTAL_ALIGNMENT_LEFT, width - 6.0, font_size, bonus_tint)

func _draw_reaction_view(canvas: Node2D) -> void:
	var mode := int(reaction_view.get("mode", 0))
	var guard_active := bool(reaction_view.get("guard", false))
	var owned := bool(reaction_view.get("owned", false))
	if not guard_active and mode == 0 and (not owned or bool(reaction_view.get("uses_bonus", false))):
		return
	var charge := clampi(int(reaction_view.get("charge", 0)), 0, 1)
	var ready := bool(reaction_view.get("ready", false))
	var tint := Color("75dfdc") if ready else Color("6b7782")
	var box := Rect2(29, -39, 18, 26)
	# Знак вынесен из ряда эффектов: его смысл и габариты не зависят от числа статусов.
	# Даже полная строка и +N остаются ниже капсулы с небольшим зазором.
	canvas.draw_set_transform(Vector2(0, -20))
	canvas.draw_rect(box, Color("101d27", 0.94))
	canvas.draw_rect(box, tint, false, 1.0)
	if guard_active:
		var shield := PackedVector2Array([Vector2(32, -36), Vector2(44, -36), Vector2(43, -29), Vector2(38, -25), Vector2(33, -29), Vector2(32, -36)])
		canvas.draw_polyline(shield, Color("83c9e7") if owned else Color("d5e0e7"), 1.4, true)
	var mode_label := ""
	match mode:
		1: mode_label = "О"
		2: mode_label = "П"
		3: mode_label = "К"
	if not mode_label.is_empty():
		canvas.draw_string(ThemeDB.fallback_font, Vector2(31, -16), mode_label, HORIZONTAL_ALIGNMENT_LEFT, 8, 10, tint)
	if owned and not bool(reaction_view.get("uses_bonus", false)):
		canvas.draw_circle(Vector2(43, -18), 2.2, tint.darkened(0.55))
		if charge == 1:
			canvas.draw_circle(Vector2(43, -18), 1.3, tint)
	canvas.draw_set_transform(Vector2.ZERO)

func reaction_hud_bounds() -> Rect2:
	return Rect2(29, -59, 18, 26)

func status_hud_bounds() -> Rect2:
	var entries := visible_status_entries().size()
	var overflow := status_overflow_count() > 0
	if entries == 0 and not overflow: return Rect2()
	var width := maxf(0.0, float(entries - 1) * (STATUS_ICON_SIZE + STATUS_ICON_GAP) + STATUS_ICON_SIZE)
	if overflow: width += STATUS_ICON_GAP + 26.0
	# Строка стоит над бронёй, чтобы передняя ровная поверхность не закрывала значки и бейджи.
	# Верхний бейдж стаков выходит над значком; нижний показывает оставшуюся длительность.
	return Rect2(-width * 0.5 - 1.0, -29, width + 2.0, 29)

func _update_sort_position() -> void:
	super._update_sort_position()
	# При одной опоре площадка рисуется перед стоящей на ней фигурой.
	if role != Role.UNIT: position.y -= 0.5

func get_visual_offset() -> Vector2:
	if grid_config == null: return Vector2.ZERO
	return Vector2(0, -0.5 * float(half_steps) * grid_config.height_step + fall_drop + presentation_lift) + presentation_offset

func sync_scene_art() -> void:
	_sync_status_hud()
	var art := get_node_or_null("ArtRoot") as Node2D
	if art == null: return
	_scene_art_enabled = true
	var factor := grid_config.tile_size.x / 128.0 if grid_config != null else 1.0
	art.scale = Vector2.ONE * factor
	art.position = get_visual_offset() + action_offset
	art.show_behind_parent = true
	var surface := get_node_or_null("ArtRoot/SurfaceSprite") as Sprite2D
	var body := get_node_or_null("ArtRoot/BodySprite") as Sprite2D
	if surface != null:
		surface.visible = role != Role.UNIT
		surface.position = (_top_offset() - get_visual_offset()) / factor
		surface.modulate = _surface_tint()
	if body != null:
		body.visible = role == Role.UNIT and (unit == null or unit.alive)
		body.modulate = transient_tint if unit == null else (Color("65dfcc") if unit.faction == Faction.Type.PLAYER else Color("f7c97d"))
	_sync_scene_sides(factor)
	var effect_root := get_node_or_null("ArtRoot/EffectRoot") as Node2D
	if effect_root == null: return
	effect_root.scale = Vector2.ONE
	effect_root.position = Vector2.ZERO
	var fire := get_node_or_null("ArtRoot/EffectRoot/BurningSprite") as Sprite2D
	var ice := get_node_or_null("ArtRoot/EffectRoot/IceSprite") as Sprite2D
	var stun_mark := get_node_or_null("ArtRoot/EffectRoot/StunSprite") as Sprite2D
	var entangle_mark := get_node_or_null("ArtRoot/EffectRoot/EntangleSprite") as Sprite2D
	if fire != null: fire.visible = role != Role.UNIT and burning
	# Смерть завершает демонстрацию состояния: ледяная оболочка не скрывает крест.
	if ice != null: ice.visible = role == Role.UNIT and frozen and (unit == null or unit.alive)
	if stun_mark != null: stun_mark.visible = role == Role.UNIT and stunned and (unit == null or unit.alive)
	if entangle_mark != null: entangle_mark.visible = role == Role.UNIT and entangled and (unit == null or unit.alive)
	# Якоря наследуют ArtRoot; их локальные позиции задаёт заменяемая сцена.

func _surface_tint() -> Color:
	var tint := Color("344858") if (grid_anchor.x + grid_anchor.y) % 2 == 0 else Color("3d5361")
	if half_steps > 0: tint = Color("527e78").lightened(float(half_steps) * 0.025)
	if half_steps < 0: tint = Color("304453")
	if role == Role.WALL: tint = Color("78818d")
	if is_void: tint = Color("080f1a")
	return tint

func _sync_scene_sides(factor: float) -> void:
	var left := get_node_or_null("ArtRoot/SideLeft") as Polygon2D
	var right := get_node_or_null("ArtRoot/SideRight") as Polygon2D
	if left == null or right == null: return
	var shapes := surface_polygons()
	if role == Role.UNIT or shapes.size() != 3:
		left.visible = false
		right.visible = false
		return
	var visual_offset := get_visual_offset()
	left.visible = true
	right.visible = true
	left.polygon = _to_art_points(shapes[0], visual_offset, factor)
	right.polygon = _to_art_points(shapes[1], visual_offset, factor)
	var base_tint := _surface_tint()
	left.color = base_tint.darkened(0.40)
	right.color = base_tint.darkened(0.22)

func _to_art_points(points: PackedVector2Array, visual_offset: Vector2, factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append((point - visual_offset) / factor)
	return result

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
		if unit != null and not unit.alive: return []
		var factor := grid_config.tile_size.x / 128.0
		var offset := get_visual_offset()
		return [PackedVector2Array([offset + body_pick_rect.position * factor, offset + Vector2(body_pick_rect.end.x, body_pick_rect.position.y) * factor, offset + body_pick_rect.end * factor, offset + Vector2(body_pick_rect.position.x, body_pick_rect.end.y) * factor])]
	var top := top_polygon()
	if is_void: return [top]
	var bottom := Vector2(0, grid_config.height_step * 0.55 + 0.5)
	if role == Role.WALL: bottom = get_visual_offset() + Vector2(0, 0.5)
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	return [PackedVector2Array([top[3], top[2], bottom + Vector2(0, hh), bottom + Vector2(-hw, 0)]), PackedVector2Array([top[2], top[1], bottom + Vector2(hw, 0), bottom + Vector2(0, hh)]), top]

## Возвращает первые пять уникальных не воплощённых видов в порядке доски.
func visible_status_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Dictionary in status_entries:
		var id := String(entry.get("id", ""))
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		if _is_embodied_status(id, entry):
			continue
		result.append(entry.duplicate())
		if result.size() >= STATUS_ICON_LIMIT:
			break
	return result

## Считает скрытые виды после дедупликации и исключения нарисованных на фигуре.
func status_overflow_count() -> int:
	var count := 0
	var seen: Dictionary = {}
	for entry: Dictionary in status_entries:
		var id := String(entry.get("id", ""))
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		if _is_embodied_status(id, entry):
			continue
		count += 1
	return maxi(0, count - STATUS_ICON_LIMIT)

func _is_embodied_status(id: String, entry: Dictionary) -> bool:
	return bool(entry.get("embodied", false)) or id in ["stun", "stunned", "frozen", "freeze", "entangled", "entangle"]

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
	if not _scene_art_enabled and shapes.size() == 3:
		draw_colored_polygon(shapes[0], color.darkened(0.40))
		draw_colored_polygon(shapes[1], color.darkened(0.22))
	var top := top_polygon()
	if not _scene_art_enabled: draw_colored_polygon(top, color)
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
	if unit != null and not unit.alive:
		var marker := foot + Vector2(16, 4) * factor
		draw_line(marker - Vector2(4, 4), marker + Vector2(4, 4), Color("a5b3c5"), 2)
		draw_line(marker - Vector2(4, -4), marker + Vector2(4, -4), Color("a5b3c5"), 2)
		return
	var tint := transient_tint if unit == null else (Color("65dfcc") if unit.faction == Faction.Type.PLAYER else Color("f7c97d"))
	if stunned and not _scene_art_enabled:
		# Знак рисуется вместе с фигурой, поэтому движется синхронно с ArtRoot.
		var stun_center := foot + action_offset + Vector2(0, -73) * factor
		var ring := PackedVector2Array()
		for point_index: int in range(17):
			var angle := TAU * float(point_index) / 16.0
			ring.append(stun_center + Vector2(cos(angle) * 18.0, sin(angle) * 8.0) * factor)
		draw_polyline(ring, Color("9dd9ed"), 1.5 * factor, true)
		for index: int in range(3):
			var star_center := stun_center + Vector2(float(index - 1) * 8.0, -3.0) * factor
			draw_circle(star_center, 2.8 * factor, Color("ffd85e"))
	if entangled and not _scene_art_enabled:
		# Корни оплетают опору и следуют за временным сдвигом рисунка.
		var root_center := foot + action_offset + Vector2(0, 4) * factor
		for root_index: int in range(3):
			var side := float(root_index - 1)
			var root_points := PackedVector2Array([
				root_center + Vector2(side * 8.0, 9.0) * factor,
				root_center + Vector2(side * 5.0, 3.0) * factor,
				root_center + Vector2(side * 12.0, -3.0) * factor,
			])
			draw_polyline(root_points, Color("9bb86b"), 2.0 * factor, true)
	if show_rear and unit != null:
		var rear := AttackModifiers.rear_offset(unit.faction)
		if rear != Vector2i.ZERO:
			# Направление берём из логики; проекция служит только отрисовке указателя.
			var direction := (IsoGridUtils.grid_to_screen(rear, grid_config, 0) - IsoGridUtils.grid_to_screen(Vector2i.ZERO, grid_config, 0)).normalized()
			var tip := foot + direction * 35.0 * factor
			var side := Vector2(-direction.y, direction.x) * 4.0 * factor
			draw_line(foot + direction * 18.0 * factor, tip, Color("f29b9b"), 2.0)
			draw_polyline(PackedVector2Array([tip - direction * 7.0 * factor + side, tip, tip - direction * 7.0 * factor - side]), Color("f29b9b"), 2.0)
	if selected:
		var hw := grid_config.tile_size.x * 0.38
		var hh := grid_config.tile_size.y * 0.38
		draw_polyline(PackedVector2Array([foot + Vector2(0, -hh), foot + Vector2(hw, 0), foot + Vector2(0, hh), foot + Vector2(-hw, 0), foot + Vector2(0, -hh)]), tint, 2, true)
	if inspected:
		var ring_hw := grid_config.tile_size.x * 0.42
		var ring_hh := grid_config.tile_size.y * 0.42
		draw_polyline(PackedVector2Array([foot + Vector2(0, -ring_hh), foot + Vector2(ring_hw, 0), foot + Vector2(0, ring_hh), foot + Vector2(-ring_hw, 0), foot + Vector2(0, -ring_hh)]), Color("f7c97d"), 3, true)
	if hovered:
		# Уголки осмотра не подменяют замкнутый ромб выбранного бойца.
		for side: float in [-1.0, 1.0]:
			var corner := foot + Vector2(side * 31, -18) * factor
			draw_polyline(PackedVector2Array([corner + Vector2(-side * 8, -12) * factor, corner + Vector2(0, -12) * factor, corner + Vector2(0, 10) * factor]), Color("eef4fa"), 2, true)
	if acting:
		var tip := foot + Vector2(0, 20) * factor
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, 10) * factor, tip + Vector2(8, 10) * factor]), Color("f7c97d"))
	# Высота силуэта отделена от его наземной опоры для общей Y-сортировки.
	draw_set_transform(foot, 0, Vector2.ONE * factor)
	if not _scene_art_enabled:
		draw_set_transform(foot + action_offset, 0, Vector2.ONE * factor)
		draw_colored_polygon(PackedVector2Array([Vector2(-18, 0), Vector2(0, -7), Vector2(18, 0), Vector2(0, 7)]), Color(0.03, 0.07, 0.10, 0.65))
		draw_rect(Rect2(-10, -10, 7, 12), tint.darkened(0.5))
		draw_rect(Rect2(3, -10, 7, 12), tint.darkened(0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(-14, -26), Vector2(10, -26), Vector2(14, -9), Vector2(-12, -9)]), tint)
		draw_colored_polygon(PackedVector2Array([Vector2(10, -26), Vector2(16, -22), Vector2(17, -8), Vector2(14, -9)]), tint.darkened(0.3))
		draw_rect(Rect2(-8, -37, 16, 13), tint.lightened(0.25))
		draw_line(Vector2(-4, -30), Vector2(7, -30), Color("172230"), 3)
		draw_set_transform(foot, 0, Vector2.ONE * factor)
	var label := transient_label if unit == null else unit.debug_name
	draw_string(ThemeDB.fallback_font, Vector2(-10, -12), label.left(1), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color("172230"))
	if unit != null:
		var hp_max := unit.hp_max
		var balance_max := unit.balance_max
		var hp := clampf(unit.hp / hp_max if hp_max > 0 else 0, 0, 1)
		var forecast_after: Dictionary = forecast_entry.get("after", {}) as Dictionary
		var expected_hp := float(forecast_after.get("hp", unit.hp))
		var expected_alive := bool(forecast_after.get("alive", unit.alive))
		var balance := BattleBalanceDisplay.ratio(unit.balance, balance_max)
		draw_rect(Rect2(-19, 7, 38, 4), Color("0f1d28"))
		draw_rect(Rect2(-19, 7, 38 * hp, 4), Color("65dfcc"))
		if not is_equal_approx(expected_hp, unit.hp):
			var expected_ratio := clampf(expected_hp / hp_max if hp_max > 0 else 0.0, 0.0, 1.0)
			var current_ratio := hp
			var segment_start := minf(current_ratio, expected_ratio)
			var segment_width := absf(expected_ratio - current_ratio)
			draw_rect(Rect2(-19 + 38 * segment_start, 7, 38 * segment_width, 4), Color("f29b9b") if expected_hp < unit.hp else Color("65dfcc"))
			draw_string(ThemeDB.fallback_font, Vector2(-28, 28), "%.1f→%.1f" % [unit.hp, expected_hp], HORIZONTAL_ALIGNMENT_CENTER, 56, 9, Color("f29b9b") if expected_hp < unit.hp else Color("65dfcc"))
			draw_line(Vector2(-19 + 38 * expected_ratio, 6), Vector2(-19 + 38 * expected_ratio, 12), Color.WHITE, 1)
		if not expected_alive: draw_string(ThemeDB.fallback_font, Vector2(-18, 38), "ПОГИБ", HORIZONTAL_ALIGNMENT_CENTER, 36, 8, Color("f29b9b"))
		# Runtime хранит нарушение; полоса показывает оставшуюся устойчивость даже без осмотра.
		draw_rect(Rect2(-19, 13, 38, 1), Color("0f1d28"))
		draw_rect(Rect2(-19, 13, 38 * balance, 1), Color("f7c97d"))
		if not armor_values.is_empty():
			var maximum := maxf(1.0, float(armor_values["maximum"]))
			var current: float = armor_values["current"]
			var expected := float(forecast_after.get("armor_current", current))
			draw_rect(Rect2(-19, 1, 38, 4), Color("0f1d28"))
			draw_rect(Rect2(-19, 1, 38 * clampf(current / maximum, 0.0, 1.0), 4), Color("91b9f4"))
			if expected != current:
				var mark := -19 + 38 * clampf(expected / maximum, 0.0, 1.0)
				draw_line(Vector2(mark, 0), Vector2(mark, 6), Color.WHITE, 1)
	draw_set_transform(Vector2.ZERO)

func _draw_status_icons(canvas: Node2D) -> void:
	var entries := visible_status_entries()
	var overflow := status_overflow_count()
	var count := entries.size() + (1 if overflow > 0 else 0)
	if count == 0:
		return
	var total_width := float(entries.size()) * STATUS_ICON_SIZE + float(maxi(0, entries.size() - 1)) * STATUS_ICON_GAP
	if overflow > 0: total_width += STATUS_ICON_GAP + 26.0
	var x := -total_width * 0.5
	for entry: Dictionary in entries:
		var id := String(entry.get("id", ""))
		var rect := Rect2(Vector2(x, -21), Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE))
		var icon := _status_icon(id)
		if icon != null:
			canvas.draw_texture_rect(icon, rect, false)
		else:
			# Неизвестные виды получают одинаковую геометрию для проверки переполнения.
			var center := rect.position + rect.size * 0.5
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -4), center + Vector2(4, 0), center + Vector2(0, 4), center + Vector2(-4, 0)]), Color("c7d4e2"))
		var stacks := int(entry.get("stacks", 0))
		if id in ["bleeding", "burning"] and stacks > 0:
			var badge := "99+" if stacks > 99 else "×%d" % stacks
			# Стаки сверху и срок снизу не смешиваются; срок остаётся числом, единица есть в подсказке.
			canvas.draw_rect(Rect2(x - 1, -29, STATUS_ICON_SIZE + 2, 10), Color("101d27", 0.92))
			canvas.draw_string(ThemeDB.fallback_font, Vector2(x - 1, -21), badge, HORIZONTAL_ALIGNMENT_CENTER, STATUS_ICON_SIZE + 2, 9, Color("fff0ce"))
		var remaining := int(entry.get("remaining", 0))
		if remaining > 0:
			var remaining_label := "99+" if remaining > 99 else str(remaining)
			canvas.draw_rect(Rect2(x - 1, -11, STATUS_ICON_SIZE + 2, 10), Color("101d27", 0.92))
			canvas.draw_string(ThemeDB.fallback_font, Vector2(x - 1, -3), remaining_label, HORIZONTAL_ALIGNMENT_CENTER, STATUS_ICON_SIZE + 2, 9, Color("b9dfff"))
		x += STATUS_ICON_SIZE + STATUS_ICON_GAP
	if overflow > 0:
		var overflow_label := "+99+" if overflow > 99 else "+%d" % overflow
		canvas.draw_rect(Rect2(x, -21, 26, 21), Color("101d27", 0.92))
		canvas.draw_string(ThemeDB.fallback_font, Vector2(x, -7), overflow_label, HORIZONTAL_ALIGNMENT_CENTER, 26, 10, Color("d4deea"))

func _status_icon(id: String) -> Texture2D:
	match id:
		"bleeding": return BLEEDING_ICON
		"burning": return BURNING_ICON
		"wet": return WET_ICON
		_: return null
