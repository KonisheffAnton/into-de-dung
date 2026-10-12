class_name BattleDefenderIdleVisual
extends BattleManagedUnitVisual

@export var idle_frames: SpriteFrames
@export var buff_frames: SpriteFrames
@export var death_frames: SpriteFrames
@export var rogue_idle_frames: SpriteFrames
@export var rogue_buff_frames: SpriteFrames
@export var rogue_death_frames: SpriteFrames
@export_range(1, 120, 1) var idle_normal_cycles_min: int = 24
@export_range(1, 120, 1) var idle_normal_cycles_max: int = 36

var idle_clock := DefenderIdleClock.new()
var _idle_owner: int = UnitId.NONE
var _idle_class: StringName = &""
var _idle_sprite: Sprite2D
var _still_sprite: Sprite2D
var _configured_min: int = -1
var _configured_max: int = -1
var _buff_elapsed: float = -1.0
var _death_active: bool = false
var _rogue_idle_authored_alpha: float = 1.0
var _rogue_idle_alpha_captured: bool = false
var cloth_palette: int = 0
var _cloth_sprites: Array[Sprite2D] = []
var _cloth_slots: Dictionary[int, int] = {}
var _cloth_applied: int = -1


func _ready() -> void:
	_idle_sprite = get_node_or_null("ArtRoot/DefenderIdleSprite") as Sprite2D
	_still_sprite = get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
	# Материалы сцены общие у союзников и врагов; параметры одежды принадлежат экземпляру.
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite"]:
		var sprite := get_node_or_null(path) as Sprite2D
		if sprite != null and sprite.material is ShaderMaterial:
			sprite.material = sprite.material.duplicate() as ShaderMaterial
			_cloth_sprites.append(sprite)
	super._ready()
	visibility_changed.connect(sync_scene_art)
	sync_scene_art()


func sync_scene_art() -> void:
	super.sync_scene_art()
	var next_sprite := get_node_or_null("ArtRoot/RogueIdleSprite" if visual_class_id == &"rogue" else "ArtRoot/DefenderIdleSprite") as Sprite2D
	var sprite_changed := _idle_sprite != null and _idle_sprite != next_sprite
	if sprite_changed:
		_restore_rogue_death_alpha(_idle_sprite)
		_idle_sprite.visible = false
	_idle_sprite = next_sprite
	if sprite_changed:
		_death_active = false
		death_progress = 0.0
	if visual_class_id == &"rogue" and _idle_sprite != null and not _rogue_idle_alpha_captured:
		_rogue_idle_authored_alpha = _idle_sprite.self_modulate.a
		_rogue_idle_alpha_captured = true
	_still_sprite = class_still_sprite()
	_sync_cloth_palette()
	if _idle_sprite == null or _still_sprite == null:
		_restore_rogue_death_alpha(_idle_sprite)
		if _idle_sprite != null: _idle_sprite.visible = false
		set_process(false)
		return
	_restore_rogue_death_alpha(_idle_sprite)
	# Отражаем рисунок вокруг прежней опоры ног, не HUD и не всю фигуру доски.
	var mirrored := unit != null and unit.faction == Faction.Type.ENEMY
	var rogue := visual_class_id == &"rogue"
	var texture_scale := 0.25 if rogue else 1.0
	_idle_sprite.scale = Vector2(-texture_scale if mirrored else texture_scale, texture_scale)
	var anchor := Vector2(64, 94) if rogue else Vector2(69.42, 90.14)
	_idle_sprite.position = Vector2(anchor.x if mirrored else -anchor.x, -anchor.y)
	if _death_active and can_play_death():
		_idle_sprite.visible = true
		_still_sprite.visible = false
		set_process(false)
		var art := get_node("ArtRoot") as Node2D
		art.rotation = 0.0
		art.scale.y = art.scale.x
		var death_elapsed := death_progress * death_duration()
		if rogue:
			var clip_duration := _clip_duration(_active_death_frames(), &"death")
			_apply_clip_frame(_active_death_frames(), &"death", minf(death_elapsed, clip_duration))
			# Рисунок остаётся непрозрачным до конца авторского падения и короткой паузы.
			var fade_elapsed := maxf(0.0, death_elapsed - clip_duration - ROGUE_DEATH_HOLD_SECONDS)
			_idle_sprite.self_modulate.a = _rogue_idle_authored_alpha * (1.0 - clampf(fade_elapsed / ROGUE_DEATH_FADE_SECONDS, 0.0, 1.0))
		else:
			_apply_clip_frame(_active_death_frames(), &"death", death_elapsed)
		return
	if _buff_elapsed >= 0.0 and can_play_buff():
		_idle_sprite.visible = true
		_still_sprite.visible = false
		set_process(false)
		_apply_clip_frame(_active_buff_frames(), &"buff", _buff_elapsed)
		return
	_buff_elapsed = -1.0
	var available := _can_play_idle()
	_idle_sprite.visible = available
	set_process(available)
	if not available: return
	if _idle_owner != unit.id or _idle_class != visual_class_id or _configured_min != idle_normal_cycles_min or _configured_max != idle_normal_cycles_max:
		_idle_owner = unit.id
		_idle_class = visual_class_id
		_configured_min = idle_normal_cycles_min
		_configured_max = idle_normal_cycles_max
		idle_clock.configure(_idle_owner, _configured_min, _configured_max)
	_still_sprite.visible = false
	_apply_idle_frame()


func _can_play_idle() -> bool:
	if visual_class_id == &"rogue":
		return _can_show_defender() and not ambient_animation_paused and rogue_idle_frames != null \
			and rogue_idle_frames.has_animation(&"idle") and rogue_idle_frames.get_frame_count(&"idle") == 12
	return _can_show_defender() and not ambient_animation_paused \
		and idle_frames != null and idle_frames.has_animation(&"vertical") \
		and idle_frames.has_animation(&"sway") \
		and idle_frames.get_frame_count(&"vertical") == 12 \
		and idle_frames.get_frame_count(&"sway") == 12


func _can_show_defender() -> bool:
	return _still_sprite != null and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY] \
		and visual_class_id in [&"warrior", &"rogue"] and _still_sprite.texture != null \
		and not frozen and not stunned and not summon_pending \
		and action_offset == Vector2.ZERO and presentation_offset == Vector2.ZERO \
		and presentation_lift == 0.0 and fall_drop == 0.0 \
		and landing_compression == 0.0 and death_progress == 0.0


func can_play_buff() -> bool:
	var frames := _active_buff_frames()
	return _idle_sprite != null and _can_show_defender() and frames != null and frames.has_animation(&"buff") \
		and frames.get_frame_count(&"buff") > 0


func buff_duration() -> float:
	if not can_play_buff(): return 0.0
	return _clip_duration(_active_buff_frames(), &"buff")


func can_play_death() -> bool:
	var frames := _active_death_frames()
	# Оглушение/заморозка не отменяют подтверждённую смерть; падениями владеет доска.
	return _idle_sprite != null and _still_sprite != null and _still_sprite.texture != null \
		and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY] \
		and visual_class_id in [&"warrior", &"rogue"] and frames != null \
		and frames.has_animation(&"death") and frames.get_frame_count(&"death") > 0 \
		and frames.get_animation_speed(&"death") > 0.0


func death_duration() -> float:
	if not can_play_death(): return 0.0
	var duration := _clip_duration(_active_death_frames(), &"death")
	return duration + ROGUE_DEATH_HOLD_SECONDS + ROGUE_DEATH_FADE_SECONDS if visual_class_id == &"rogue" else duration


const ROGUE_DEATH_HOLD_SECONDS: float = 0.25
const ROGUE_DEATH_FADE_SECONDS: float = 0.80


func _restore_rogue_death_alpha(sprite: Sprite2D) -> void:
	if sprite == null or sprite.name != "RogueIdleSprite" or not _rogue_idle_alpha_captured: return
	var modulation := sprite.self_modulate
	modulation.a = _rogue_idle_authored_alpha
	sprite.self_modulate = modulation


func _active_buff_frames() -> SpriteFrames:
	return rogue_buff_frames if visual_class_id == &"rogue" else buff_frames


func _active_death_frames() -> SpriteFrames:
	return rogue_death_frames if visual_class_id == &"rogue" else death_frames


func sample_death(progress: float) -> void:
	_death_active = true
	_buff_elapsed = -1.0
	death_progress = progress


static func _clip_duration(frames: SpriteFrames, animation: StringName) -> float:
	var duration := 0.0
	for frame: int in frames.get_frame_count(animation):
		duration += frames.get_frame_duration(animation, frame)
	return duration / frames.get_animation_speed(animation)


func sample_buff(elapsed: float) -> void:
	# Единственные часы действия — Tween доски: скорость, пропуск и пауза общие с playback.
	_buff_elapsed = maxf(0.0, elapsed)
	sync_scene_art()


func clear_buff() -> void:
	if _buff_elapsed < 0.0: return
	_buff_elapsed = -1.0
	sync_scene_art()


func _apply_clip_frame(frames: SpriteFrames, animation: StringName, elapsed: float) -> void:
	var remaining := elapsed * frames.get_animation_speed(animation)
	var last := frames.get_frame_count(animation) - 1
	for frame: int in last + 1:
		var duration := frames.get_frame_duration(animation, frame)
		if remaining < duration or frame == last:
			var texture := frames.get_frame_texture(animation, frame)
			if _idle_sprite.texture != texture:
				_idle_sprite.texture = texture
				_sync_cloth_frame(_idle_sprite)
			return
		remaining -= duration


func reset_view_pose() -> void:
	_death_active = false
	_restore_rogue_death_alpha(_idle_sprite)
	clear_buff()
	super.reset_view_pose()


func _process(delta: float) -> void:
	if _buff_elapsed >= 0.0 or _death_active: return
	if not _can_play_idle():
		sync_scene_art()
		return
	idle_clock.advance(delta)
	_apply_idle_frame()


func _apply_idle_frame() -> void:
	var animation: StringName = &"sway" if idle_clock.is_rare() else &"vertical"
	var frames := idle_frames
	if visual_class_id == &"rogue":
		animation = &"idle"
		frames = rogue_idle_frames
	var texture := frames.get_frame_texture(animation, idle_clock.get_frame_index())
	# Меняется только текстура дочернего рисунка; внешней позой и эффектами владеет доска.
	if _idle_sprite.texture != texture:
		_idle_sprite.texture = texture
		_sync_cloth_frame(_idle_sprite)


func set_cloth_palette(index: int) -> void:
	cloth_palette = DefenderClothPalette.valid_index(index)
	_sync_cloth_palette()


func _sync_cloth_palette() -> void:
	var selected := cloth_palette if unit != null and unit.faction == Faction.Type.PLAYER \
		and visual_class_id == &"warrior" and role == Role.UNIT else 0
	if selected != _cloth_applied:
		_cloth_applied = selected
		_cloth_slots.clear()
	for sprite: Sprite2D in _cloth_sprites:
		_sync_cloth_frame(sprite)


func _sync_cloth_frame(sprite: Sprite2D) -> void:
	if sprite == null or sprite.material == null or not _cloth_sprites.has(sprite): return
	var slot := DefenderClothPalette.mask_slot(sprite.texture)
	var id := sprite.get_instance_id()
	if _cloth_slots.get(id, -2) == slot: return
	_cloth_slots[id] = slot
	DefenderClothPalette.apply(sprite.material as ShaderMaterial, maxi(0, _cloth_applied), slot)


func retire_view() -> void:
	_restore_rogue_death_alpha(_idle_sprite)
	super.retire_view()
	_idle_owner = UnitId.NONE
	idle_clock.reset()
	set_process(false)


func _exit_tree() -> void:
	_restore_rogue_death_alpha(_idle_sprite)
	_death_active = false
	_buff_elapsed = -1.0
	set_process(false)
	_idle_owner = UnitId.NONE
	idle_clock.reset()
