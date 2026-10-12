class_name BattleDefenderIdleVisual
extends BattleManagedUnitVisual

@export var idle_frames: SpriteFrames
@export var buff_frames: SpriteFrames
@export var death_frames: SpriteFrames
@export_range(1, 120, 1) var idle_normal_cycles_min: int = 24
@export_range(1, 120, 1) var idle_normal_cycles_max: int = 36

var idle_clock := DefenderIdleClock.new()
var _idle_owner: int = UnitId.NONE
var _idle_sprite: Sprite2D
var _still_sprite: Sprite2D
var _configured_min: int = -1
var _configured_max: int = -1
var _buff_elapsed: float = -1.0
var _death_active: bool = false


func _ready() -> void:
	_idle_sprite = get_node_or_null("ArtRoot/DefenderIdleSprite") as Sprite2D
	_still_sprite = get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
	super._ready()
	visibility_changed.connect(sync_scene_art)
	sync_scene_art()


func sync_scene_art() -> void:
	super.sync_scene_art()
	_still_sprite = get_node_or_null("ArtRoot/EnemyWarriorSprite" if unit != null and unit.faction == Faction.Type.ENEMY else "ArtRoot/PlayerWarriorSprite") as Sprite2D
	if _idle_sprite == null or _still_sprite == null: return
	# Отражаем рисунок вокруг прежней опоры ног, не HUD и не всю фигуру доски.
	var mirrored := unit != null and unit.faction == Faction.Type.ENEMY
	_idle_sprite.scale.x = -1.0 if mirrored else 1.0
	_idle_sprite.position.x = 69.42 if mirrored else -69.42
	if _death_active and can_play_death():
		_idle_sprite.visible = true
		_still_sprite.visible = false
		set_process(false)
		var art := get_node("ArtRoot") as Node2D
		art.rotation = 0.0
		art.scale.y = art.scale.x
		_apply_clip_frame(death_frames, &"death", death_progress * death_duration())
		return
	if _buff_elapsed >= 0.0 and can_play_buff():
		_idle_sprite.visible = true
		_still_sprite.visible = false
		set_process(false)
		_apply_clip_frame(buff_frames, &"buff", _buff_elapsed)
		return
	_buff_elapsed = -1.0
	var available := _can_play_idle()
	_idle_sprite.visible = available
	set_process(available)
	if not available: return
	if _idle_owner != unit.id or _configured_min != idle_normal_cycles_min or _configured_max != idle_normal_cycles_max:
		_idle_owner = unit.id
		_configured_min = idle_normal_cycles_min
		_configured_max = idle_normal_cycles_max
		idle_clock.configure(_idle_owner, _configured_min, _configured_max)
	_still_sprite.visible = false
	_apply_idle_frame()


func _can_play_idle() -> bool:
	return _can_show_defender() and not ambient_animation_paused \
		and idle_frames != null and idle_frames.has_animation(&"vertical") \
		and idle_frames.has_animation(&"sway") \
		and idle_frames.get_frame_count(&"vertical") == 12 \
		and idle_frames.get_frame_count(&"sway") == 12


func _can_show_defender() -> bool:
	return _still_sprite != null and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY] \
		and visual_class_id == &"warrior" and _still_sprite.texture != null \
		and not frozen and not stunned and not summon_pending \
		and action_offset == Vector2.ZERO and presentation_offset == Vector2.ZERO \
		and presentation_lift == 0.0 and fall_drop == 0.0 \
		and landing_compression == 0.0 and death_progress == 0.0


func can_play_buff() -> bool:
	return _can_show_defender() and buff_frames != null and buff_frames.has_animation(&"buff") \
		and buff_frames.get_frame_count(&"buff") > 0


func buff_duration() -> float:
	if not can_play_buff(): return 0.0
	return _clip_duration(buff_frames, &"buff")


func can_play_death() -> bool:
	# Оглушение/заморозка не отменяют подтверждённую смерть; падениями владеет доска.
	return _idle_sprite != null and _still_sprite != null and _still_sprite.texture != null \
		and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY] \
		and visual_class_id == &"warrior" and death_frames != null \
		and death_frames.has_animation(&"death") and death_frames.get_frame_count(&"death") > 0 \
		and death_frames.get_animation_speed(&"death") > 0.0


func death_duration() -> float:
	return _clip_duration(death_frames, &"death") if can_play_death() else 0.0


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
			_idle_sprite.texture = frames.get_frame_texture(animation, frame)
			return
		remaining -= duration


func reset_view_pose() -> void:
	_death_active = false
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
	var texture := idle_frames.get_frame_texture(animation, idle_clock.get_frame_index())
	# Меняется только текстура дочернего рисунка; внешней позой и эффектами владеет доска.
	if _idle_sprite.texture != texture: _idle_sprite.texture = texture


func retire_view() -> void:
	super.retire_view()
	_idle_owner = UnitId.NONE
	idle_clock.reset()
	set_process(false)


func _exit_tree() -> void:
	_death_active = false
	_buff_elapsed = -1.0
	set_process(false)
	_idle_owner = UnitId.NONE
	idle_clock.reset()
