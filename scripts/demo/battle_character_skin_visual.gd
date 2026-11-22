class_name BattleCharacterSkinVisual
extends BattleDefenderIdleVisual

var skin_definition: CharacterSkinDefinition
var skin_clock := CharacterIdleClock.new()
var _skin_sprite: Sprite2D
var _skin_owner: int = UnitId.NONE
var _skin_buff_elapsed: float = -1.0
var _skin_dying: bool = false
var _skin_durations: Dictionary[StringName, float] = {}
var _skin_ambient_wait: float = 0.0
var _skin_ambient_elapsed: float = -1.0
var _skin_ambient_first: bool = true

func _ready() -> void:
	_skin_sprite = get_node_or_null("ArtRoot/CharacterSkinSprite") as Sprite2D
	if _skin_sprite != null and _skin_sprite.material != null:
		_skin_sprite.material = _skin_sprite.material.duplicate()
	super._ready()

func apply_view(values: Dictionary, config: IsoGridConfig) -> bool:
	var next := CharacterSkinCatalog.definition(values["visual_class_id"], values.get("visual_skin_id", &""))
	var changed := skin_definition != next or _skin_owner != int(values["unit"]["id"])
	if changed:
		skin_definition = next
		_skin_owner = int(values["unit"]["id"])
		_skin_buff_elapsed = -1.0
		_skin_dying = false
		_cancel_ambient_buff()
		_skin_ambient_first = true
		_skin_durations.clear()
		if next != null:
			for animation: StringName in [&"idle", &"idle_secondary", &"buff", &"death"]:
				_skin_durations[animation] = next.clip_duration(animation)
			skin_clock.configure(_skin_owner * 7919 + String(next.id).hash(), _skin_durations[&"idle"], _skin_durations[&"idle_secondary"])
			if _skin_sprite != null: _skin_sprite.texture = next.still
	var applied := super.apply_view(values, config)
	if changed and not applied:
		sync_scene_art()
		view_apply_count += 1
	return changed or applied

func _has_skin() -> bool:
	return skin_definition != null and skin_definition.class_id == visual_class_id \
		and skin_definition.still != null and _skin_sprite != null

func class_still_sprite() -> Sprite2D:
	if _has_skin() and unit != null and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return _skin_sprite
	return super.class_still_sprite()

func get_unit_art_scale() -> float:
	if _has_skin() and visual_class_id == &"archer":
		# Уменьшение удерживает силуэт Лучницы в масштабе выбранной группы персонажей.
		return warrior_art_scale * 0.9
	if _has_skin() and visual_class_id == &"mage": return warrior_art_scale
	return super.get_unit_art_scale()

func get_unit_pick_rect() -> Rect2:
	if _has_skin() and visual_class_id == &"sick_hobgoblin": return Rect2(-31, -55, 62, 58)
	if _has_skin() and visual_class_id == &"tamed_troglodyte": return Rect2(-37, -40, 74, 50)
	if _has_skin() and visual_class_id in [&"mage", &"archer"]: return Rect2(-40, -78, 80, 82)
	return super.get_unit_pick_rect()

func _sync_ground_shadow() -> void:
	super._sync_ground_shadow()
	# Опора остаётся на клетке; размер пятна задаётся силуэтом выбранного скина.
	if _has_skin() and _ground_shadow != null and _ground_shadow.visible:
		_ground_shadow.scale *= skin_definition.ground_shadow_scale

func _skin_clip_available(animation: StringName) -> bool:
	if not _has_skin() or float(_skin_durations.get(animation, 0.0)) <= 0.0: return false
	var frames := skin_definition.animations
	return frames != null and frames.has_animation(animation) and frames.get_frame_count(animation) > 0 and frames.get_animation_speed(animation) > 0.0

func _skin_can_show() -> bool:
	return _has_skin() and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]

func _skin_idle_allowed() -> bool:
	return _skin_can_show() and not ambient_animation_paused and not frozen and not stunned and not summon_pending \
		and action_offset == Vector2.ZERO and presentation_offset == Vector2.ZERO and presentation_lift == 0.0 \
		and fall_drop == 0.0 and landing_compression == 0.0 and death_progress == 0.0 and _skin_clip_available(&"idle")

func _sync_scene_art_layers() -> void:
	super._sync_scene_art_layers()
	if _skin_sprite == null: return
	if not _has_skin():
		_skin_sprite.visible = false
		return
	# Выбранный скин заменяет также старый анимированный слой, а не только still.
	if _idle_sprite != null: _idle_sprite.visible = false
	_skin_sprite.visible = _skin_can_show()
	set_process(false)
	if not _skin_idle_allowed(): _cancel_ambient_buff()
	if not _skin_sprite.visible: return
	# У моделей исходная ориентация различается, поэтому базовое отражение задаёт сторону относительно направления автора.
	var desired_facing := 1 if unit.faction == Faction.Type.PLAYER else -1
	var source_facing := -1 if skin_definition.source_facing_x < 0 else 1
	var mirrored := desired_facing != source_facing
	var scale_value := skin_definition.texture_scale
	_skin_sprite.scale = Vector2(-scale_value if mirrored else scale_value, scale_value)
	_skin_sprite.position = Vector2(skin_definition.anchor.x if mirrored else -skin_definition.anchor.x, -skin_definition.anchor.y) * scale_value
	_skin_sprite.set_meta(&"source_facing_x", skin_definition.source_facing_x)
	if _skin_dying and can_play_death():
		# Авторские кадры уже содержат падение; общий наклон тела здесь лишний.
		var art := get_node("ArtRoot") as Node2D
		art.rotation = 0.0
		art.scale.y = art.scale.x
		_draw_skin_clip(&"death", death_progress * death_duration())
	elif _skin_buff_elapsed >= 0.0 and can_play_buff():
		_draw_skin_clip(&"buff", _skin_buff_elapsed)
	elif _skin_idle_allowed():
		set_process(true)
		if _skin_ambient_elapsed >= 0.0: _draw_skin_clip(&"buff", _skin_ambient_elapsed)
		else: _draw_skin_idle()
	else:
		_set_skin_texture(skin_definition.still)

func _set_skin_texture(texture: Texture2D) -> void:
	if texture == null: texture = skin_definition.still
	var material := _skin_sprite.material as ShaderMaterial
	var region := Rect2(Vector2.ZERO, texture.get_size())
	if texture is AtlasTexture: region = (texture as AtlasTexture).region
	if _skin_sprite.texture != texture: _skin_sprite.texture = texture
	if material == null: return
	var source := Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
	if material.get_shader_parameter(&"source_region") != source: material.set_shader_parameter(&"source_region", source)
	# Шейдер покрывает исходные тексели кадра; размер игровой сетки ему больше не нужен.
	var native_size := region.size
	if material.get_shader_parameter(&"native_size") != native_size: material.set_shader_parameter(&"native_size", native_size)
	if material.get_shader_parameter(&"shieldbearer_palette_strength") != skin_definition.shieldbearer_palette_strength:
		material.set_shader_parameter(&"shieldbearer_palette_strength", skin_definition.shieldbearer_palette_strength)

func _draw_skin_clip(animation: StringName, elapsed: float) -> void:
	if not _skin_clip_available(animation):
		_set_skin_texture(skin_definition.still)
		return
	var frames := skin_definition.animations
	var remaining := elapsed * frames.get_animation_speed(animation)
	var last := frames.get_frame_count(animation) - 1
	for frame: int in last + 1:
		var duration := frames.get_frame_duration(animation, frame)
		if remaining < duration or frame == last:
			_set_skin_texture(frames.get_frame_texture(animation, frame))
			return
		remaining -= duration

func _draw_skin_idle() -> void:
	_draw_skin_clip(&"idle_secondary" if skin_clock.secondary else &"idle", skin_clock.elapsed)

func _process(delta: float) -> void:
	if not _has_skin():
		super._process(delta)
		return
	if _skin_buff_elapsed >= 0.0 or _skin_dying: return
	if not _skin_idle_allowed():
		_cancel_ambient_buff()
		sync_scene_art()
		return
	if not is_finite(delta) or delta <= 0.0: return
	if _skin_ambient_elapsed >= 0.0:
		_skin_ambient_elapsed += delta
		if _skin_ambient_elapsed >= float(_skin_durations.get(&"buff", 0.0)):
			_cancel_ambient_buff()
			_draw_skin_idle()
		else:
			_draw_skin_clip(&"buff", _skin_ambient_elapsed)
		return
	skin_clock.advance(delta)
	var interval := skin_definition.ambient_buff_interval
	if interval > 0.0 and _skin_clip_available(&"buff"):
		# Рык — только рисунок: собственные часы не расходуют действия и RNG боя.
		_skin_ambient_wait += delta
		var delay := minf(6.0, interval) if _skin_ambient_first else interval
		if _skin_ambient_wait >= delay and not skin_clock.secondary:
			_skin_ambient_elapsed = 0.0
			_skin_ambient_first = false
			_skin_ambient_wait = 0.0
			_draw_skin_clip(&"buff", 0.0)
			return
	_draw_skin_idle()

func _cancel_ambient_buff() -> void:
	_skin_ambient_elapsed = -1.0
	_skin_ambient_wait = 0.0

func can_play_buff() -> bool:
	if not _has_skin(): return super.can_play_buff()
	return _skin_can_show() and not frozen and not stunned and not summon_pending and _skin_clip_available(&"buff")

func buff_duration() -> float:
	if not _has_skin(): return super.buff_duration()
	return float(_skin_durations.get(&"buff", 0.0)) if can_play_buff() else 0.0

func sample_buff(elapsed: float) -> void:
	if not _has_skin():
		super.sample_buff(elapsed)
		return
	_cancel_ambient_buff()
	_skin_buff_elapsed = maxf(0.0, elapsed)
	sync_scene_art()

func clear_buff() -> void:
	if _skin_buff_elapsed >= 0.0:
		_skin_buff_elapsed = -1.0
		sync_scene_art()
	super.clear_buff()

func can_play_death() -> bool:
	if not _has_skin(): return super.can_play_death()
	return _skin_can_show() and _skin_clip_available(&"death")

func death_duration() -> float:
	if not _has_skin(): return super.death_duration()
	return float(_skin_durations.get(&"death", 0.0)) if can_play_death() else 0.0

func sample_death(progress: float) -> void:
	if not _has_skin():
		super.sample_death(progress)
		return
	_skin_dying = true
	_cancel_ambient_buff()
	_skin_buff_elapsed = -1.0
	death_progress = progress

func reset_view_pose() -> void:
	# Refresh/resize сбрасывает только позу: локальный рык и его ожидание принадлежат тому же владельцу.
	_skin_dying = false
	_skin_buff_elapsed = -1.0
	super.reset_view_pose()

func retire_view() -> void:
	_cancel_ambient_buff()
	_skin_ambient_first = true
	_skin_dying = false
	_skin_buff_elapsed = -1.0
	_skin_owner = UnitId.NONE
	super.retire_view()
