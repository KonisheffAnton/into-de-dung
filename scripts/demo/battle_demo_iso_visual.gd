extends YSortable
class_name BattleDemoIsoVisual

enum Role { FLOOR, PLATFORM, WALL, UNIT }
var role: Role = Role.FLOOR
var half_steps: int = 0
var unit: BattleUnitView
var visual_class_id: StringName = &""
## Направление текстуры задаёт автор сцены: фракция не описывает рисунок.
@export_enum("Left:-1", "Right:1") var source_facing_x: int = 1
## Временная сторона атаки не попадает в UnitState и не меняет механическую спину.
var presentation_facing_x: int = 0:
	set(value):
		presentation_facing_x = clampi(value, -1, 1)
		sync_scene_art()
		queue_redraw()
var _body_authored_transforms: Dictionary = {}
var _body_authored_components: Dictionary = {}
var _scene_sync_depth: int = 0
var is_void: bool = false
var deep_acid: bool = false
var selected: bool = false
var reachable: bool = false
var enemy_range: bool = false
var inspected: bool = false
var hovered: bool = false
var acting: bool = false
var forecast_entry: Dictionary = {}
var armor_values: Dictionary = {}
var shield_view: Dictionary = {}
var raised_shield_view: Dictionary = {}
var summon_pending: bool = false
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
## Клеточные отметки рисуются после поверхности, но в её Y-sort.
var ground_marks: Array[Dictionary] = []
var ground_overlay_enabled: bool = true
## Авторская сцена включает общий sync только если offset и lift меняются одной позой.
@export var batch_motion_pose: bool = false
@export var show_resource_badges: bool = false
@export var show_ground_shadow: bool = true
@export var ground_shadow_color: Color = Color(0.045, 0.055, 0.065, 0.28)
@export_range(1.0, 64.0, 1.0) var ground_shadow_radius: float = 28.0
@export_range(0.1, 1.0, 0.05) var ground_shadow_flattening: float = 0.5
@export var body_pick_rect: Rect2 = Rect2(-17, -37, 34, 44)
@export var warrior_pick_rect: Rect2 = Rect2(-45, -56, 78, 73)
@export_range(0.25, 2.0, 0.05) var warrior_art_scale: float = 1.0
@export var rogue_pick_rect: Rect2 = Rect2(-40, -65, 80, 73)
@export_range(0.25, 2.0, 0.01) var rogue_art_scale: float = 0.73
@export var archer_pick_rect: Rect2 = Rect2(-49, -81, 98, 92)
@export_range(0.25, 2.0, 0.01) var archer_art_scale: float = 0.64
@export var show_flat_height_labels: bool = false
## Демонстрационные состояния выбираются доской; сцена только отображает слои.
var frozen: bool = false
var burning: bool = false
var stunned: bool = false
var entangled: bool = false
const STATUS_ICON_SIZE: float = 16.0
const STATUS_ICON_GAP: float = 1.0
const STATUS_ICON_LIMIT: int = 5
static var _combat_number_font: FontFile
@export var ground_base_tint: Color = Color("697553")
const BLEEDING_ICON: Texture2D = preload("res://assets/placeholder_battle/bleeding_icon.svg")
const BURNING_ICON: Texture2D = preload("res://assets/placeholder_battle/burning_icon.svg")
const WET_ICON: Texture2D = preload("res://assets/placeholder_battle/wet_icon.svg")
var _scene_art_enabled: bool = false
var _status_hud: Node2D
var _ground_overlay: Node2D
var _unit_highlights: Node2D
var _ground_shadow: Node2D
var landing_compression: float = 0.0:
	set(value):
		landing_compression = clampf(value, 0.0, 0.4)
		sync_scene_art()
		queue_redraw()
## Оседание относится к рисунку; HUD и опора остаются на опубликованном кадре.
var death_progress: float = 0.0:
	set(value):
		death_progress = clampf(value, 0.0, 1.0)
		sync_scene_art()
		queue_redraw()
## Выпад/отдача сдвигают рисунок, но не опору сортировки, клетку и HUD.
var action_offset: Vector2 = Vector2.ZERO:
	set(value):
		action_offset = value
		sync_scene_art()
		queue_redraw()

var _presentation_lift: float = 0.0
var presentation_lift: float:
	get:
		return _presentation_lift
	set(value):
		_presentation_lift = value
		sync_scene_art()
		queue_redraw()
var fall_drop: float = 0.0:
	set(value):
		fall_drop = value
		sync_scene_art()
		queue_redraw()
var _presentation_offset: Vector2 = Vector2.ZERO
var presentation_offset: Vector2:
	get:
		return _presentation_offset
	set(value):
		_presentation_offset = value
		sync_scene_art()
		queue_redraw()

func set_motion_pose(offset: Vector2, lift: float) -> void:
	if not batch_motion_pose:
		presentation_offset = offset
		presentation_lift = lift
		return
	# Сначала фиксируем всю позу, чтобы один sync увидел согласованные координаты.
	_presentation_offset = offset
	_presentation_lift = lift
	sync_scene_art()
	queue_redraw()
## Экранное направление толчка с интенсивностью, которую задаёт доска.
var push_lean: Vector2 = Vector2.ZERO:
	set(value):
		push_lean = value.limit_length(1.0)
		sync_scene_art()
		queue_redraw()

func _ready() -> void:
	super._ready()
	if role == Role.UNIT:
		set_notify_transform(true)
		get_viewport().size_changed.connect(queue_redraw)
	if role != Role.UNIT:
		_ground_overlay = Node2D.new()
		_ground_overlay.name = "GroundOverlay"
		add_child(_ground_overlay)
		_ground_overlay.draw.connect(_draw_ground_overlay.bind(_ground_overlay))
	if role != Role.UNIT: return
	_unit_highlights = Node2D.new()
	_unit_highlights.name = "UnitHighlights"
	_unit_highlights.show_behind_parent = true
	add_child(_unit_highlights)
	move_child(_unit_highlights, 0)
	_unit_highlights.draw.connect(_draw_unit_highlights.bind(_unit_highlights))
	_ground_shadow = Node2D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.show_behind_parent = true
	_ground_shadow.visible = false
	add_child(_ground_shadow)
	move_child(_ground_shadow, 0)
	_ground_shadow.draw.connect(_draw_ground_shadow.bind(_ground_shadow))
	_status_hud = Node2D.new()
	_status_hud.name = "StatusHud"
	# HUD остаётся в локальной сортировке, чтобы передние фигуры и тайлы могли его закрыть.
	_status_hud.z_index = 0
	add_child(_status_hud)
	_status_hud.draw.connect(_draw_status_hud)
	_sync_status_hud()

func _notification(what: int) -> void:
	# Пиксельная привязка цифр пересчитывается при движении/масштабе родителя камеры.
	if what == NOTIFICATION_TRANSFORM_CHANGED and role == Role.UNIT:
		queue_redraw()

func _sync_status_hud() -> void:
	if _status_hud == null: return
	_status_hud.position = get_visual_offset()
	_status_hud.scale = Vector2.ONE * (grid_config.tile_size.x / 128.0 if grid_config != null else 1.0)
	_status_hud.visible = role == Role.UNIT and unit != null and unit.alive
	_status_hud.queue_redraw()

func _draw_status_hud() -> void:
	_draw_status_icons(_status_hud)
	if show_resource_badges:
		_draw_action_resources(_status_hud)
		_draw_reaction_view(_status_hud)
	if bool(raised_shield_view.get("active", false)):
		# Рядом с реакцией: выше поверхности тайла и внутри видимой высоты фигуры.
		_status_hud.draw_rect(Rect2(29, -31, 64, 15), Color("172230"))
		_status_hud.draw_string(ThemeDB.fallback_font, Vector2(32, -19), "ЩИТ 90%", HORIZONTAL_ALIGNMENT_CENTER, 58, 11, Color("f7d58d"))

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
	if not show_resource_badges: return Rect2()
	return Rect2(29, -59, 18, 26)

func queue_ground_overlay_redraw() -> void:
	if _ground_overlay != null: _ground_overlay.queue_redraw()

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

func _sync_ground_shadow() -> void:
	if _ground_shadow == null: return
	var visible_shadow := show_ground_shadow and role == Role.UNIT and unit != null \
		and unit.alive and grid_config != null
	_ground_shadow.visible = visible_shadow
	if not visible_shadow: return
	# Тень следует опоре и высотной интерполяции, но не анимации тела и не его смерти.
	_ground_shadow.position = get_visual_offset()
	_ground_shadow.scale = Vector2(1.0, ground_shadow_flattening) \
		* (grid_config.tile_size.x / 128.0) * get_unit_art_scale()
	_ground_shadow.rotation = 0.0
	_ground_shadow.queue_redraw()

func _draw_ground_shadow(canvas: Node2D) -> void:
	if not canvas.visible: return
	canvas.draw_circle(Vector2.ZERO, ground_shadow_radius, ground_shadow_color, true, -1.0, true)
	if push_lean.length_squared() > 0.0001:
		# Короткие следы показывают скольжение по опоре, не поднимая тень вместе с телом.
		# Canvas тени сжат по Y; компенсируем это, чтобы след шёл вдоль сдвига.
		var direction := Vector2(push_lean.x, push_lean.y / ground_shadow_flattening).normalized()
		var across := Vector2(-direction.y, direction.x)
		for index: int in range(3):
			var start := -direction * (ground_shadow_radius * (0.55 + float(index) * 0.18)) + across * (float(index - 1) * 4.0)
			canvas.draw_line(start, start - direction * (5.0 + push_lean.length() * 4.0), Color(ground_shadow_color, 0.22 * push_lean.length()), 1.2, true)

func body_pose_transform(factor: float) -> Transform2D:
	var pose_scale := Vector2(factor, factor * (1.0 - death_progress * 0.25) * (1.0 - landing_compression))
	var pose_rotation := death_progress * PI * 0.5
	var base := Transform2D(pose_rotation, pose_scale, 0.0, Vector2.ZERO)
	# Наклон меняет силуэт вокруг стоп, сохраняя точку опоры на исходной высоте.
	var lean := Transform2D(Vector2.RIGHT, Vector2(-push_lean.x * 0.32, 1.0 - push_lean.y * 0.12), Vector2.ZERO)
	base = base * lean
	base.origin = get_visual_offset() + action_offset
	return base

func sync_scene_art() -> void:
	# Вложенный sync возможен у смены idle/death; отражение накладывается один раз после всех слоёв.
	var outermost := _scene_sync_depth == 0
	if outermost:
		_restore_body_branch_transforms()
	_scene_sync_depth += 1
	_sync_scene_art_layers()
	_scene_sync_depth -= 1
	if outermost:
		_apply_attack_facing()

func _sync_scene_art_layers() -> void:
	_sync_status_hud()
	if _unit_highlights != null: _unit_highlights.queue_redraw()
	_sync_ground_shadow()
	var art := get_node_or_null("ArtRoot") as Node2D
	if art == null: return
	_scene_art_enabled = true
	var factor := grid_config.tile_size.x / 128.0 if grid_config != null else 1.0
	art.transform = body_pose_transform(factor * get_unit_art_scale())
	art.show_behind_parent = true
	var surface_position := (_top_offset() - get_visual_offset()) / factor
	var surface := get_node_or_null("ArtRoot/SurfaceSprite") as Sprite2D
	var ground_base := get_node_or_null("ArtRoot/GroundBase") as Polygon2D
	var ground_surface := get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
	var ground_art_active := ground_surface != null and _uses_ground_art()
	var body := get_node_or_null("ArtRoot/BodySprite") as Sprite2D
	var player_warrior := get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
	var enemy_warrior := get_node_or_null("ArtRoot/EnemyWarriorSprite") as Sprite2D
	var player_rogue := get_node_or_null("ArtRoot/PlayerRogueSprite") as Sprite2D
	var enemy_rogue := get_node_or_null("ArtRoot/EnemyRogueSprite") as Sprite2D
	var player_archer := get_node_or_null("ArtRoot/PlayerArcherSprite") as Sprite2D
	var enemy_archer := get_node_or_null("ArtRoot/EnemyArcherSprite") as Sprite2D
	var enemy_presets := _enemy_preset_sprites()
	var selected_enemy_preset: Sprite2D
	var warrior_sprite := class_still_sprite()
	# Отсутствующий рисунок считается отсутствующим классным слоем и позволяет fallback.
	if warrior_sprite != null and warrior_sprite.texture == null:
		warrior_sprite = null
	var presets_ready: bool = enemy_presets.size() == 3
	for preset: Sprite2D in enemy_presets:
		presets_ready = presets_ready and preset.texture != null
	# Именованный класс при отказе своего рисунка не превращается в случайного старого NPC.
	if role == Role.UNIT and unit != null and unit.faction == Faction.Type.ENEMY and visual_class_id == &"" and presets_ready and warrior_sprite == null:
		selected_enemy_preset = enemy_presets[posmod(unit.id, enemy_presets.size())]
	# Кастомный силуэт остаётся нейтральным: исходная палитра уже задаёт его сторону.
	if player_warrior != null:
		player_warrior.visible = player_warrior == warrior_sprite and role == Role.UNIT and unit != null and unit.alive
		player_warrior.modulate = Color.WHITE
	if enemy_warrior != null:
		enemy_warrior.visible = selected_enemy_preset == null and enemy_warrior == warrior_sprite and role == Role.UNIT and unit != null and unit.alive
		enemy_warrior.modulate = Color.WHITE
	for class_sprite: Sprite2D in [player_rogue, enemy_rogue, player_archer, enemy_archer, get_node_or_null("ArtRoot/PlayerShieldbearerSprite"), get_node_or_null("ArtRoot/EnemyShieldbearerSprite"), get_node_or_null("ArtRoot/PlayerFighterSprite"), get_node_or_null("ArtRoot/EnemyFighterSprite")]:
		if class_sprite != null:
			class_sprite.visible = class_sprite == warrior_sprite and role == Role.UNIT and unit != null and unit.alive
			class_sprite.modulate = Color.WHITE
	for preset: Sprite2D in enemy_presets:
		preset.visible = preset == selected_enemy_preset and unit != null and unit.alive
		preset.modulate = Color.WHITE
	if surface != null:
		surface.visible = role != Role.UNIT and not ground_art_active and not is_void and not deep_acid
		surface.position = surface_position
		surface.modulate = _surface_tint()
	if ground_base != null:
		ground_base.visible = ground_art_active and not deep_acid
		ground_base.position = surface_position
		ground_base.color = ground_base_tint
	if ground_surface != null:
		ground_surface.visible = ground_art_active and not deep_acid
		ground_surface.position = surface_position
		ground_surface.modulate = Color.WHITE
	if body != null:
		body.visible = role == Role.UNIT and (unit == null or unit.alive) and warrior_sprite == null and selected_enemy_preset == null
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
	if fire != null: fire.visible = role != Role.UNIT and burning and not is_void
	# Смерть завершает демонстрацию состояния: ледяная оболочка не скрывает крест.
	if ice != null: ice.visible = role == Role.UNIT and frozen and (unit == null or unit.alive)
	if stun_mark != null: stun_mark.visible = role == Role.UNIT and stunned and (unit == null or unit.alive)
	if entangle_mark != null: entangle_mark.visible = role == Role.UNIT and entangled and (unit == null or unit.alive)
	# Якоря наследуют ArtRoot; их локальные позиции задаёт заменяемая сцена.

func _body_branches() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var art := get_node_or_null("ArtRoot") as Node2D
	if art == null: return result
	for child: Node in art.get_children():
		if child is not Node2D or child is Marker2D: continue
		if child.name in [&"SurfaceSprite", &"GroundBase", &"GroundSurface", &"SideLeft", &"SideRight", &"EffectRoot"]: continue
		result.append(child as Node2D)
	return result

func _restore_body_branch_transforms() -> void:
	for node: Variant in _body_authored_transforms.keys():
		if is_instance_valid(node):
			var branch := node as Node2D
			var components: Dictionary = _body_authored_components.get(node, {}) as Dictionary
			# Присваивание отражённой матрицы меняет разложение scale/rotation; возвращаем авторские компоненты до idle-sync.
			branch.position = components.get("position", branch.position) as Vector2
			branch.rotation = float(components.get("rotation", branch.rotation))
			branch.scale = components.get("scale", branch.scale) as Vector2
			branch.skew = float(components.get("skew", branch.skew))
	_body_authored_transforms.clear()
	_body_authored_components.clear()

func _apply_attack_facing() -> void:
	if role != Role.UNIT or unit == null or not unit.alive or _body_facing_target_x() == 0: return
	var mirror := get_attack_mirror_x()
	if mirror > 0.0: return
	for branch: Node2D in _body_branches():
		_body_authored_transforms[branch] = branch.transform
		_body_authored_components[branch] = {
			"position": branch.position,
			"rotation": branch.rotation,
			"scale": branch.scale,
			"skew": branch.skew,
		}
		var reflected := Transform2D(Vector2(mirror, 0.0), Vector2(0.0, 1.0), Vector2.ZERO) * branch.transform
		branch.transform = reflected

func _selected_body_node() -> Node2D:
	var sprite := class_still_sprite()
	if sprite != null and sprite.texture != null: return sprite
	var presets := _enemy_preset_sprites()
	var ready := presets.size() == 3
	for preset: Sprite2D in presets:
		ready = ready and preset.texture != null
	if role == Role.UNIT and unit != null and unit.faction == Faction.Type.ENEMY and visual_class_id == &"" and ready:
		return presets[posmod(unit.id, presets.size())]
	var fallback := get_node_or_null("ArtRoot/BodySprite") as Node2D
	if fallback is Sprite2D and (fallback as Sprite2D).texture != null: return fallback
	if fallback is AnimatedSprite2D:
		var animated := fallback as AnimatedSprite2D
		var frames := animated.sprite_frames
		if frames != null and frames.has_animation(animated.animation) \
			and frames.get_frame_count(animated.animation) > animated.frame \
			and frames.get_frame_texture(animated.animation, animated.frame) != null:
			return animated
	return null

func get_authored_facing_x() -> int:
	var authored := -1 if source_facing_x < 0 else 1
	var sprite := _selected_body_node()
	if sprite == null: return authored
	var sprite_direction := int(sprite.get_meta(&"source_facing_x", authored))
	if sprite_direction == 0: sprite_direction = authored
	var relative_sign := 1.0
	var node: Node = sprite
	while node != null and node != get_node_or_null("ArtRoot"):
		if node is Node2D:
			var authored_transform: Transform2D = _body_authored_transforms.get(node, (node as Node2D).transform)
			var x_sign := signf(authored_transform.x.x)
			if is_zero_approx(x_sign): x_sign = signf(authored_transform.determinant())
			relative_sign *= x_sign
		node = node.get_parent()
	if sprite is Sprite2D and (sprite as Sprite2D).flip_h: relative_sign *= -1.0
	if sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).flip_h: relative_sign *= -1.0
	return -1 if float(sprite_direction) * relative_sign < 0.0 else 1

func get_attack_mirror_x() -> float:
	if role != Role.UNIT or unit == null or not unit.alive or _body_facing_target_x() == 0: return 1.0
	return float(_body_facing_target_x() * get_authored_facing_x())

func _body_facing_target_x() -> int:
	if presentation_facing_x != 0: return presentation_facing_x
	# Сторона Мага сохраняется также при отказе скина и возврате к условному BodySprite.
	if visual_class_id == &"mage" and unit != null and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]:
		return 1 if unit.faction == Faction.Type.PLAYER else -1
	return 0

func body_drawing_transform(factor: float) -> Transform2D:
	var pose := body_pose_transform(factor)
	if role == Role.UNIT and unit != null and unit.alive and _body_facing_target_x() != 0:
		var mirror := get_attack_mirror_x()
		# Локальное отражение не сдвигает origin выпадов и экранную опору тела.
		pose = pose * Transform2D(Vector2(mirror, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	return pose

func _enemy_preset_sprites() -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for node_path: NodePath in [
		NodePath("ArtRoot/EnemyPresets/Bearded"),
		NodePath("ArtRoot/EnemyPresets/Helmet"),
		NodePath("ArtRoot/EnemyPresets/Redhair")
	]:
		var sprite := get_node_or_null(node_path) as Sprite2D
		if sprite != null: result.append(sprite)
	return result

func _surface_tint() -> Color:
	var tint := Color("344858") if (grid_anchor.x + grid_anchor.y) % 2 == 0 else Color("3d5361")
	if half_steps > 0: tint = Color("527e78").lightened(float(half_steps) * 0.025)
	if half_steps < 0: tint = Color("304453")
	if role == Role.WALL: tint = Color("78818d")
	if is_void: tint = Color("080f1a")
	return tint

func _uses_ground_art() -> bool:
	return role in [Role.FLOOR, Role.PLATFORM] and not is_void

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
	var ground_surface := get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
	var ground_art_active := ground_surface != null and _uses_ground_art()
	var base_tint := ground_base_tint if ground_art_active else _surface_tint()
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
		var art_scale := get_unit_art_scale()
		var pick_rect := get_unit_pick_rect()
		return [PackedVector2Array([offset + pick_rect.position * factor * art_scale, offset + Vector2(pick_rect.end.x, pick_rect.position.y) * factor * art_scale, offset + pick_rect.end * factor * art_scale, offset + Vector2(pick_rect.position.x, pick_rect.end.y) * factor * art_scale])]
	var top := top_polygon()
	if is_void: return [top]
	var bottom := Vector2(0, grid_config.height_step * 0.55 + 0.5)
	if role == Role.WALL: bottom = get_visual_offset() + Vector2(0, 0.5)
	elif _uses_ground_art():
		# PNG уже содержит шестипиксельный торец; совпадающая опора не удваивает его толщину.
		bottom = Vector2(0, grid_config.tile_size.x * (6.0 / 128.0) + 0.5)
	var hw := grid_config.tile_size.x * 0.5
	var hh := grid_config.tile_size.y * 0.5
	return [PackedVector2Array([top[3], top[2], bottom + Vector2(0, hh), bottom + Vector2(-hw, 0)]), PackedVector2Array([top[2], top[1], bottom + Vector2(hw, 0), bottom + Vector2(0, hh)]), top]

func _has_visible_warrior_sprite() -> bool:
	var sprite := class_still_sprite()
	return unit != null and unit.alive and sprite != null and sprite.texture != null

func get_unit_pick_rect() -> Rect2:
	var pick_rect := warrior_pick_rect if _has_visible_warrior_sprite() else body_pick_rect
	if _has_visible_warrior_sprite() and visual_class_id == &"rogue": pick_rect = rogue_pick_rect
	if _has_visible_warrior_sprite() and visual_class_id == &"archer": pick_rect = archer_pick_rect
	return pick_rect

func get_unit_bars_offset() -> Vector2:
	return Vector2.ZERO

func class_still_sprite() -> Sprite2D:
	if unit == null or unit.faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return null
	var suffix: String
	match visual_class_id:
		&"warrior": suffix = "WarriorSprite"
		&"shieldbearer": suffix = "ShieldbearerSprite"
		&"fighter": suffix = "FighterSprite"
		&"rogue": suffix = "RogueSprite"
		&"archer": suffix = "ArcherSprite"
		_: return null
	var side := "Enemy" if unit.faction == Faction.Type.ENEMY else "Player"
	return get_node_or_null("ArtRoot/" + side + suffix) as Sprite2D

func get_unit_art_scale() -> float:
	if role != Role.UNIT or not _has_visible_warrior_sprite(): return 1.0
	if visual_class_id == &"archer": return archer_art_scale
	return rogue_art_scale if visual_class_id == &"rogue" else warrior_art_scale

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
	if is_void and role != Role.UNIT:
		# После обрушения нет поверхности: соседние торцы обрамляют настоящий просвет.
		if _ground_overlay != null: _ground_overlay.queue_redraw()
		return
	if role == Role.UNIT:
		# Родительский draw обновляет маркеры перед отрисовкой child-слоя за спрайтом.
		if _unit_highlights != null: _unit_highlights.queue_redraw()
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
	var ground_surface := get_node_or_null("ArtRoot/GroundSurface") as Sprite2D
	var ground_art_active := ground_surface != null and _uses_ground_art()
	if not ground_art_active: draw_polyline(top + PackedVector2Array([top[0]]), Color("14232e"), 1.2, true)
	var center := _top_offset()
	var hh := grid_config.tile_size.y * 0.5
	if role == Role.WALL:
		draw_line(top[3].lerp(top[0], 0.5), top[2].lerp(top[1], 0.5), color.darkened(0.25), 1)

	else:
		if half_steps != 0 or show_flat_height_labels:
			draw_string(ThemeDB.fallback_font, center + Vector2(-22, -hh * 0.37), "%+.1f" % (float(half_steps) / 2.0), HORIZONTAL_ALIGNMENT_CENTER, 44, 10, Color("b7c9ce"))
	if _ground_overlay != null: _ground_overlay.queue_redraw()

func _draw_ground_overlay(canvas: Node2D) -> void:
	if grid_config == null or not ground_overlay_enabled or is_void: return
	var center := get_visual_offset() + Vector2(0, 0.5)
	if role == Role.WALL: center.y -= grid_config.height_step
	var half := grid_config.tile_size * 0.48
	var diamond := PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0), center + Vector2(0, half.y), center + Vector2(-half.x, 0), center + Vector2(0, -half.y)])
	if enemy_range:
		canvas.draw_colored_polygon(top_polygon(), Color(0.78, 0.64, 0.40, 0.09))
		canvas.draw_polyline(top_polygon() + PackedVector2Array([top_polygon()[0]]), Color("ad9b78", 0.28), 1.0, true)
	if reachable:
		canvas.draw_circle(center + Vector2(grid_config.tile_size.x * 0.31, 0), 1.5, Color("8eaaa7", 0.42))
	for mark: Dictionary in ground_marks:
		var kind := String(mark.get("kind", ""))
		match kind:
			"hover":
				var hover_color: Color = mark.get("color", Color("829fa5"))
				hover_color.a = 0.24
				canvas.draw_polyline(diamond, hover_color, 1.2, true)
			"reaction_zone":
				canvas.draw_polyline(diamond, Color("9daab5", 0.20), 1.0, true)
			"cover_target":
				canvas.draw_polyline(diamond, Color("83a9b5", 0.26), 1.4, true)
			"sneak":
				canvas.draw_arc(center, grid_config.tile_size.x * 0.25, 0, TAU, 24, Color("a99b79", 0.26), 1.3, true)
			"action_area":
				var color: Color = mark.get("color", Color("9daab5"))
				var area_half := grid_config.tile_size * float(mark.get("inset", 0.48))
				var area_diamond := PackedVector2Array([center + Vector2(0, -area_half.y), center + Vector2(area_half.x, 0), center + Vector2(0, area_half.y), center + Vector2(-area_half.x, 0), center + Vector2(0, -area_half.y)])
				if bool(mark.get("fill", false)):
					var fill_color := color
					fill_color.a = 0.035
					canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -area_half.y), center + Vector2(area_half.x, 0), center + Vector2(0, area_half.y), center + Vector2(-area_half.x, 0)]), fill_color)
				color.a = 0.30 if bool(mark.get("preview", false)) else 0.20
				canvas.draw_polyline(area_diamond, color, 1.3 if bool(mark.get("preview", false)) else 1.0, true)
			"action_origin":
				var origin_color: Color = mark.get("color", Color("9daab5"))
				origin_color.a = 0.24
				canvas.draw_arc(center, grid_config.tile_size.x * 0.27, 0, TAU, 32, origin_color, 1.4, true)
			"move_endpoint":
				var endpoint_color := Color("D3AD6A") if bool(mark.get("alive", true)) else Color("B9604E")
				canvas.draw_arc(center, 9.0, 0, TAU, 24, Color("202C31"), 4.0, true)
				canvas.draw_arc(center, 9.0, 0, TAU, 24, endpoint_color, 2.0, true)

func _draw_unit() -> void:
	var factor := grid_config.tile_size.x / 128.0
	var body_factor := factor * get_unit_art_scale()
	var foot := get_visual_offset()
	if unit != null and not unit.alive:
		# Наличие тела определяет environment, а не оставшийся мёртвый UnitState.
		return
	var tint := transient_tint if unit == null else (Color("65dfcc") if unit.faction == Faction.Type.PLAYER else Color("f7c97d"))
	if not shield_view.is_empty():
		var center := foot + action_offset + Vector2(0, -29) * body_factor
		var outline := PackedVector2Array()
		for index: int in range(33):
			var angle := TAU * float(index) / 32.0
			outline.append(center + Vector2(cos(angle) * 26, sin(angle) * 39) * body_factor)
		draw_colored_polygon(outline, Color(0.3, 0.75, 1.0, 0.10))
		draw_polyline(outline, Color("71cefa"), 1.7 * factor, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-25, -43) * factor, "Щ %s · %d" % [BattleEventText.amount_text(shield_view.hp), int(shield_view.hits_left)], HORIZONTAL_ALIGNMENT_CENTER, 50 * factor, int(11 * factor), Color("aee7ff"))
	if summon_pending:
		draw_string(ThemeDB.fallback_font, foot + Vector2(-29, 102) * factor, "ЖДЁТ ХОДА", HORIZONTAL_ALIGNMENT_CENTER, 58 * factor, int(9 * factor), Color("b6d5ec"))
	if not _scene_art_enabled:
		# Fallback-накладки используют ту же позу, что EffectRoot у сценического тела.
		draw_set_transform_matrix(body_pose_transform(factor))
	if stunned and not _scene_art_enabled:
		# Знак рисуется вместе с фигурой, поэтому движется синхронно с ArtRoot.
		var stun_center := Vector2(0, -73)
		var ring := PackedVector2Array()
		for point_index: int in range(17):
			var angle := TAU * float(point_index) / 16.0
			ring.append(stun_center + Vector2(cos(angle) * 18.0, sin(angle) * 8.0))
		draw_polyline(ring, Color("9dd9ed"), 1.5, true)
		for index: int in range(3):
			var star_center := stun_center + Vector2(float(index - 1) * 8.0, -3.0)
			draw_circle(star_center, 2.8, Color("ffd85e"))
	if entangled and not _scene_art_enabled:
		# Корни оплетают опору и следуют за временным сдвигом рисунка.
		var root_center := Vector2(0, 4)
		for root_index: int in range(3):
			var side := float(root_index - 1)
			var root_points := PackedVector2Array([
				root_center + Vector2(side * 8.0, 9.0),
				root_center + Vector2(side * 5.0, 3.0),
				root_center + Vector2(side * 12.0, -3.0),
			])
			draw_polyline(root_points, Color("9bb86b"), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	if show_rear and unit != null:
		var rear := AttackModifiers.rear_offset(unit.faction)
		if rear != Vector2i.ZERO:
			# Направление берём из логики; проекция служит только отрисовке указателя.
			var direction := (IsoGridUtils.grid_to_screen(rear, grid_config, 0) - IsoGridUtils.grid_to_screen(Vector2i.ZERO, grid_config, 0)).normalized()
			var tip := foot + direction * 35.0 * factor
			var side := Vector2(-direction.y, direction.x) * 4.0 * factor
			draw_line(foot + direction * 18.0 * factor, tip, Color("f29b9b"), 2.0)
			draw_polyline(PackedVector2Array([tip - direction * 7.0 * factor + side, tip, tip - direction * 7.0 * factor - side]), Color("f29b9b"), 2.0)
	# Высота силуэта отделена от его наземной опоры для общей Y-сортировки.
	draw_set_transform(foot, 0, Vector2.ONE * factor)
	if not _scene_art_enabled:
		draw_set_transform_matrix(body_drawing_transform(factor))
		# Отдельный круглый GroundShadow заменяет старый ромб и исключает двойную тень.
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
		# Посадка нового рисунка ниже требует места полосам, не сдвигая опору клетки.
		draw_set_transform(foot + get_unit_bars_offset() * factor, 0, Vector2.ONE * factor)
		if _combat_number_font == null:
			# Настройки только для маленьких цифр полос, без мутации общего шрифта урона.
			_combat_number_font = (load("res://assets/ui/combat_fonts/jersey20_numbers.ttf") as FontFile).duplicate() as FontFile
			_combat_number_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_combat_number_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_combat_number_font.oversampling = 1.0
			_combat_number_font.keep_rounding_remainders = false
		var hp_max := unit.hp_max
		var balance_max := unit.balance_max
		var hp := clampf(unit.hp / hp_max if hp_max > 0 else 0, 0, 1)
		var forecast_after: Dictionary = forecast_entry.get("after", {}) as Dictionary
		var expected_hp := float(forecast_after.get("hp", unit.hp))
		var expected_alive := bool(forecast_after.get("alive", unit.alive))
		var balance := BattleBalanceDisplay.ratio(unit.balance, balance_max)
		const BAR_WIDTH: float = 48.0
		const BAR_HEIGHT: float = 11.0
		const BAR_LEFT: float = -24.0
		const HP_Y: float = 14.0
		const ARMOR_Y: float = 1.0
		var hp_text := BattleEventText.amount_text(unit.hp)
		var hp_rect := Rect2(BAR_LEFT, HP_Y, BAR_WIDTH, BAR_HEIGHT)
		var hp_inner := hp_rect.grow(-_vital_rim_width())
		_draw_vital_track(hp_rect, hp, Color("829969"), Color("96ab7c"), Color("6e8259"), Color("777d70"))
		if not is_equal_approx(expected_hp, unit.hp):
			var expected_ratio := clampf(expected_hp / hp_max if hp_max > 0 else 0.0, 0.0, 1.0)
			var current_ratio := hp
			var segment_start := minf(current_ratio, expected_ratio)
			var segment_width := absf(expected_ratio - current_ratio)
			draw_rect(Rect2(hp_inner.position + Vector2(hp_inner.size.x * segment_start, 0), Vector2(hp_inner.size.x * segment_width, hp_inner.size.y)), Color("f29b9b") if expected_hp < unit.hp else Color("829969"))
			draw_string(ThemeDB.fallback_font, Vector2(-32, 56), "%s→%s" % [hp_text, BattleEventText.amount_text(expected_hp)], HORIZONTAL_ALIGNMENT_CENTER, 64, 9, Color("f29b9b") if expected_hp < unit.hp else Color("829969"))
			draw_line(Vector2(hp_inner.position.x + hp_inner.size.x * expected_ratio, HP_Y - 1), Vector2(hp_inner.position.x + hp_inner.size.x * expected_ratio, HP_Y + BAR_HEIGHT + 1), Color.WHITE, 1)
		_draw_vital_amount(hp_rect, hp_text)
		if not expected_alive: draw_string(ThemeDB.fallback_font, Vector2(-18, 67), "ПОГИБ", HORIZONTAL_ALIGNMENT_CENTER, 36, 8, Color("f29b9b"))
		# Баланс — второстепенная шкала запаса: два цветных ряда сохраняются при отдалении.
		_draw_vital_track(Rect2(BAR_LEFT, 27, BAR_WIDTH, 4 * _vital_rim_width()), balance, Color("bea16c"), Color("cdb888"), Color("a58b60"), Color("45494b"))
		if not armor_values.is_empty():
			var maximum: float = armor_values["maximum"]
			var current: float = armor_values["current"]
			var expected := float(forecast_after.get("armor_current", current))
			var armor_ratio := clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
			var armor_text := BattleEventText.amount_text(current)
			var armor_rect := Rect2(BAR_LEFT, ARMOR_Y, BAR_WIDTH, BAR_HEIGHT)
			var armor_inner := armor_rect.grow(-_vital_rim_width())
			_draw_vital_track(armor_rect, armor_ratio, Color("9ca5a6"), Color("b1b9b6"), Color("828d8f"), Color("747d80"))
			if expected != current:
				var mark := armor_inner.position.x + armor_inner.size.x * (clampf(expected / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0)
				draw_line(Vector2(mark, ARMOR_Y - 1), Vector2(mark, ARMOR_Y + BAR_HEIGHT + 1), Color.WHITE, 1)
			_draw_vital_amount(armor_rect, armor_text)
	draw_set_transform(Vector2.ZERO)

func _vital_rim_width() -> float:
	# Рамка сохраняет экранный пиксель на боевом zoom 75–125%; обзор карты не раздувает HUD.
	var screen_scale := get_global_transform_with_canvas().x.length() * grid_config.tile_size.x / 128.0
	return maxf(1.0, 1.0 / maxf(screen_scale, 0.75))

func _draw_vital_track(rect: Rect2, ratio: float, fill: Color, light: Color, shade: Color, empty: Color) -> void:
	var rim := _vital_rim_width()
	var inner := rect.grow(-rim)
	draw_rect(rect, Color.BLACK)
	draw_rect(inner, empty)
	if ratio <= 0.0: return
	# При отдалении столбец не исчезает между пикселями; точный остаток остаётся в числе/осмотре.
	var screen_scale := get_global_transform_with_canvas().x.length() * grid_config.tile_size.x / 128.0
	var minimum_width := maxf(1.0, 1.0 / maxf(screen_scale, 0.01))
	var filled := Rect2(inner.position, Vector2(minf(inner.size.x, maxf(minimum_width, inner.size.x * clampf(ratio, 0.0, 1.0))), inner.size.y))
	draw_rect(filled, fill)
	draw_rect(Rect2(filled.position, Vector2(filled.size.x, rim)), light)
	draw_rect(Rect2(filled.position + Vector2(0, filled.size.y - rim), Vector2(filled.size.x, rim)), shade)

func _draw_vital_amount(rect: Rect2, text: String) -> void:
	var factor := grid_config.tile_size.x / 128.0
	var bar_transform := Transform2D(Vector2(factor, 0), Vector2(0, factor), get_visual_offset() + get_unit_bars_offset() * factor)
	var canvas := get_viewport_transform() * get_global_transform()
	var screen := canvas * bar_transform
	var scale_factor := screen.x.length()
	var font_size := maxi(1, floori(14.0 * scale_factor))
	var minimum_size := maxi(1, floori(8.0 * scale_factor))
	var available_width := (rect.size.x - 4.0) * scale_factor
	while font_size > minimum_size and _combat_number_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width:
		font_size -= 1
	var text_width := _combat_number_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var center := screen * rect.get_center()
	var baseline := Vector2(center.x - text_width * 0.5, center.y + 4.0 * float(font_size) / 14.0).round()
	# Растеризуем сразу в экранном размере: масштаб поля не растягивает готовые глифы.
	draw_set_transform_matrix(canvas.affine_inverse())
	draw_string(_combat_number_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_set_transform_matrix(bar_transform)
	var rim := _vital_rim_width()
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rim)), Color.BLACK)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - rim), Vector2(rect.size.x, rim)), Color.BLACK)
	draw_rect(Rect2(rect.position, Vector2(rim, rect.size.y)), Color.BLACK)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - rim, 0), Vector2(rim, rect.size.y)), Color.BLACK)

func _draw_unit_highlights(canvas: Node2D) -> void:
	if grid_config == null or role != Role.UNIT or (unit != null and not unit.alive): return
	var factor := grid_config.tile_size.x / 128.0
	var foot := get_visual_offset()
	var tint := transient_tint if unit == null else (Color("65dfcc") if unit.faction == Faction.Type.PLAYER else Color("f7c97d"))
	if selected:
		var hw := grid_config.tile_size.x * 0.38
		var hh := grid_config.tile_size.y * 0.38
		var selected_color := tint.darkened(0.22)
		selected_color.a = 0.42
		canvas.draw_polyline(PackedVector2Array([foot + Vector2(0, -hh), foot + Vector2(hw, 0), foot + Vector2(0, hh), foot + Vector2(-hw, 0), foot + Vector2(0, -hh)]), selected_color, 1.5, true)
	if inspected:
		var ring_hw := grid_config.tile_size.x * 0.42
		var ring_hh := grid_config.tile_size.y * 0.42
		canvas.draw_polyline(PackedVector2Array([foot + Vector2(0, -ring_hh), foot + Vector2(ring_hw, 0), foot + Vector2(0, ring_hh), foot + Vector2(-ring_hw, 0), foot + Vector2(0, -ring_hh)]), Color("b3a687", 0.42), 1.5, true)
	if hovered:
		# Уголки осмотра остаются различимы, не заливая фигуру непрозрачным цветом.
		for side: float in [-1.0, 1.0]:
			var corner := foot + Vector2(side * 31, -18) * factor
			canvas.draw_polyline(PackedVector2Array([corner + Vector2(-side * 8, -12) * factor, corner + Vector2(0, -12) * factor, corner + Vector2(0, 10) * factor]), Color("b8c1c8", 0.32), 1.3, true)
	if acting:
		# Маркер действия держится ниже полос, включая их авторский сдвиг у бойца.
		var tip := foot + (get_unit_bars_offset() + Vector2(0, 70)) * factor
		canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, 10) * factor, tip + Vector2(8, 10) * factor]), Color("b5a37e", 0.38))

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
		elif id == "acid":
			canvas.draw_circle(rect.get_center(), 6.0, Color("57dd72"))
			canvas.draw_circle(rect.get_center() + Vector2(2.0, -2.0), 1.4, Color("d0ff9d"))
			canvas.draw_circle(rect.get_center() + Vector2(-2.0, 2.0), 1.0, Color("d0ff9d"))
		elif id == "poison":
			# Яд получает собственный оттенок, чтобы его счётчик не читался как вода.
			canvas.draw_circle(rect.get_center(), 6.0, Color("8acb55"))
			canvas.draw_circle(rect.get_center() + Vector2(1.0, -2.0), 2.0, Color("d8ff9d"))
		else:
			# Неизвестные виды получают одинаковую геометрию для проверки переполнения.
			var center := rect.position + rect.size * 0.5
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -4), center + Vector2(4, 0), center + Vector2(0, 4), center + Vector2(-4, 0)]), Color("c7d4e2"))
		var stacks := int(entry.get("stacks", 0))
		if id in ["bleeding", "burning", "poison"] and stacks > 0:
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
