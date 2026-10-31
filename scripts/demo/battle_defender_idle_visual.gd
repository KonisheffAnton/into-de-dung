class_name BattleDefenderIdleVisual
extends BattleManagedUnitVisual

@export var idle_frames: SpriteFrames
@export var buff_frames: SpriteFrames
@export var death_frames: SpriteFrames
@export var rogue_idle_frames: SpriteFrames
@export var rogue_buff_frames: SpriteFrames
@export var rogue_death_frames: SpriteFrames
@export var rogue_animation_anchor: Vector2 = Vector2(64.0, 94.0)
@export var rogue_texture_scale: float = 0.25
@export_range(1, 120, 1) var rogue_death_frame_count: int = 13
@export var archer_idle_frames: SpriteFrames
@export var enemy_warrior_art_enabled: bool = false
@export var enemy_warrior_idle_frames: SpriteFrames
@export var enemy_warrior_death_frames: SpriteFrames
@export var enemy_warrior_idle_anchor: Vector2 = Vector2(71.0, 83.0)
@export var enemy_warrior_pick_rect: Rect2 = Rect2(-29.0, -67.0, 64.0, 80.0)
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
var _cloth_states: Dictionary[int, String] = {}


func _ready() -> void:
	_idle_sprite = get_node_or_null("ArtRoot/DefenderIdleSprite") as Sprite2D
	_still_sprite = get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
	# Материалы сцен общие между фракциями и классами, поэтому каждый рисунок получает свой экземпляр.
	for path: String in ["ArtRoot/PlayerWarriorSprite", "ArtRoot/EnemyWarriorSprite", "ArtRoot/DefenderIdleSprite",
			"ArtRoot/PlayerRogueSprite", "ArtRoot/EnemyRogueSprite", "ArtRoot/RogueIdleSprite",
			"ArtRoot/PlayerArcherSprite", "ArtRoot/EnemyArcherSprite", "ArtRoot/ArcherIdleSprite",
			"ArtRoot/EnemyWarriorIdleSprite"]:
		var sprite := get_node_or_null(path) as Sprite2D
		if sprite != null and sprite.material is ShaderMaterial:
			sprite.material = sprite.material.duplicate() as ShaderMaterial
			_cloth_sprites.append(sprite)
			# Замена авторской текстуры должна сразу пересчитать соответствующую маску.
			sprite.texture_changed.connect(_sync_cloth_frame.bind(sprite))
	super._ready()
	visibility_changed.connect(sync_scene_art)
	sync_scene_art()


func _sync_scene_art_layers() -> void:
	super._sync_scene_art_layers()
	if visual_class_id in [&"fighter", &"shieldbearer"]:
		# Новые статичные рисунки не подменяются клипами прежнего Защитника.
		_restore_rogue_death_alpha(_idle_sprite)
		if _idle_sprite != null: _idle_sprite.visible = false
		_still_sprite = class_still_sprite()
		_buff_elapsed = -1.0
		_death_active = false
		set_process(false)
		return
	var idle_path := "ArtRoot/DefenderIdleSprite"
	if _uses_enemy_warrior_art(): idle_path = "ArtRoot/EnemyWarriorIdleSprite"
	elif visual_class_id == &"rogue": idle_path = "ArtRoot/RogueIdleSprite"
	elif visual_class_id == &"archer": idle_path = "ArtRoot/ArcherIdleSprite"
	var next_sprite := get_node_or_null(idle_path) as Sprite2D
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
	# Отражаем только рисунок вокруг выбранной точки посадки, не HUD или опору доски.
	var mirrored := unit != null and unit.faction == Faction.Type.ENEMY
	var rogue := visual_class_id == &"rogue"
	var texture_scale := rogue_texture_scale if rogue else 1.0
	_idle_sprite.scale = Vector2(-texture_scale if mirrored else texture_scale, texture_scale)
	var anchor := rogue_animation_anchor if rogue else Vector2(69.42, 90.14)
	if _uses_enemy_warrior_art(): anchor = enemy_warrior_idle_anchor
	elif visual_class_id == &"archer": anchor = Vector2(68.0, 95.0)
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
	if _uses_enemy_warrior_art():
		return _can_show_defender() and not ambient_animation_paused and _enemy_warrior_idle_is_valid()
	if visual_class_id == &"archer":
		return _can_show_defender() and not ambient_animation_paused and archer_idle_frames != null \
			and archer_idle_frames.has_animation(&"idle") and archer_idle_frames.get_frame_count(&"idle") == 12 \
			and archer_idle_frames.get_animation_speed(&"idle") > 0.0
	if visual_class_id == &"rogue":
		return _can_show_defender() and not ambient_animation_paused and rogue_idle_frames != null \
			and rogue_idle_frames.has_animation(&"idle") and rogue_idle_frames.get_frame_count(&"idle") == 12
	return _can_show_defender() and not ambient_animation_paused \
		and idle_frames != null and idle_frames.has_animation(&"vertical") \
		and idle_frames.has_animation(&"sway") \
		and idle_frames.get_frame_count(&"vertical") == 12 \
		and idle_frames.get_frame_count(&"sway") == 12


func _uses_enemy_warrior_art() -> bool:
	return enemy_warrior_art_enabled and unit != null and unit.faction == Faction.Type.ENEMY \
		and visual_class_id == &"warrior"


func _enemy_warrior_idle_is_valid() -> bool:
	if enemy_warrior_idle_frames == null or not enemy_warrior_idle_frames.has_animation(&"idle"):
		return false
	var frame_count := enemy_warrior_idle_frames.get_frame_count(&"idle")
	if frame_count != 17 or enemy_warrior_idle_frames.get_animation_speed(&"idle") <= 0.0:
		return false
	for frame: int in frame_count:
		if enemy_warrior_idle_frames.get_frame_texture(&"idle", frame) == null:
			return false
	return true


func _can_show_defender() -> bool:
	return _still_sprite != null and is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY] \
		and visual_class_id in [&"warrior", &"rogue", &"archer"] and _still_sprite.texture != null \
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
	if _uses_enemy_warrior_art(): return null
	if visual_class_id == &"archer": return null
	return rogue_buff_frames if visual_class_id == &"rogue" else buff_frames


func _active_death_frames() -> SpriteFrames:
	if _uses_enemy_warrior_art(): return enemy_warrior_death_frames if _enemy_warrior_death_is_valid() else null
	if visual_class_id == &"archer": return null
	if visual_class_id == &"rogue":
		# Неполный или чужой по длине клип не должен маскировать штатную смерть.
		return rogue_death_frames if _death_frames_are_valid(rogue_death_frames) \
			and rogue_death_frames.get_frame_count(&"death") == rogue_death_frame_count else null
	return death_frames


func _enemy_warrior_death_is_valid() -> bool:
	return _death_frames_are_valid(enemy_warrior_death_frames) \
		and enemy_warrior_death_frames.get_frame_count(&"death") == 17


func _death_frames_are_valid(frames: SpriteFrames) -> bool:
	if frames == null or not frames.has_animation(&"death") \
		or frames.get_frame_count(&"death") <= 0 or frames.get_animation_speed(&"death") <= 0.0:
		return false
	for frame: int in frames.get_frame_count(&"death"):
		if frames.get_frame_texture(&"death", frame) == null: return false
	return true


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
	# Общие часы сохраняют фазу по ID; у лучницы выбран более длинный цикл 2.6 с.
	var clock_delta := delta
	if _uses_enemy_warrior_art():
		clock_delta *= DefenderIdleClock.CYCLE_DURATION / _clip_duration(enemy_warrior_idle_frames, &"idle")
	elif visual_class_id == &"archer":
		clock_delta *= DefenderIdleClock.CYCLE_DURATION / _clip_duration(archer_idle_frames, &"idle")
	idle_clock.advance(clock_delta)
	_apply_idle_frame()


func _apply_idle_frame() -> void:
	if _uses_enemy_warrior_art():
		var duration := _clip_duration(enemy_warrior_idle_frames, &"idle")
		var phase := fposmod(idle_clock.get_elapsed(), DefenderIdleClock.CYCLE_DURATION) / DefenderIdleClock.CYCLE_DURATION
		_apply_clip_frame(enemy_warrior_idle_frames, &"idle", phase * duration + DefenderIdleClock.TIME_EPSILON)
		return
	var animation: StringName = &"sway" if idle_clock.is_rare() else &"vertical"
	var frames := idle_frames
	if visual_class_id == &"rogue":
		animation = &"idle"
		frames = rogue_idle_frames
	elif visual_class_id == &"archer":
		animation = &"idle"
		frames = archer_idle_frames
	var texture := frames.get_frame_texture(animation, idle_clock.get_frame_index())
	# Меняется только текстура дочернего рисунка; внешней позой и эффектами владеет доска.
	if _idle_sprite.texture != texture:
		_idle_sprite.texture = texture
		_sync_cloth_frame(_idle_sprite)


func set_cloth_palette(index: int) -> void:
	cloth_palette = DefenderClothPalette.valid_index(index)
	_sync_cloth_palette()


func get_unit_pick_rect() -> Rect2:
	var still := class_still_sprite()
	if _uses_enemy_warrior_art() and still != null and still.texture != null:
		return enemy_warrior_pick_rect
	return super.get_unit_pick_rect()


func get_unit_bars_offset() -> Vector2:
	var still := class_still_sprite()
	if _uses_enemy_warrior_art() and still != null and still.texture != null:
		return Vector2(0, 11)
	return super.get_unit_bars_offset()


func _sync_cloth_palette() -> void:
	# При смене класса/стороны/роли все слои пересчитываются даже при том же номере палитры.
	for sprite: Sprite2D in _cloth_sprites:
		_sync_cloth_frame(sprite)


func _sync_cloth_frame(sprite: Sprite2D) -> void:
	if sprite == null or sprite.material == null or not _cloth_sprites.has(sprite): return
	var is_rogue := sprite.name in ["PlayerRogueSprite", "EnemyRogueSprite", "RogueIdleSprite"]
	var is_archer := sprite.name in ["PlayerArcherSprite", "EnemyArcherSprite", "ArcherIdleSprite"]
	var expected_class: StringName = &"rogue" if is_rogue else (&"archer" if is_archer else &"warrior")
	var eligible := unit != null and unit.faction == Faction.Type.PLAYER and visual_class_id == expected_class and role == Role.UNIT
	var selected := cloth_palette if eligible else 0
	var slot := -1
	if selected > 0 and sprite.texture != null:
		if is_rogue:
			slot = RogueClothPalette.mask_slot(sprite.texture)
		elif is_archer:
			slot = ArcherClothPalette.mask_slot(sprite.texture)
		else:
			slot = DefenderClothPalette.mask_slot(sprite.texture)
	var id := sprite.get_instance_id()
	var class_key := "rogue" if is_rogue else ("archer" if is_archer else "warrior")
	var state := "%s:%d:%d" % [class_key, selected if slot >= 0 else 0, slot]
	if _cloth_states.get(id, "") == state: return
	_cloth_states[id] = state
	var material := sprite.material as ShaderMaterial
	if is_rogue:
		RogueClothPalette.apply(material, selected if slot >= 0 else 0, slot)
	elif is_archer:
		ArcherClothPalette.apply(material, selected if slot >= 0 else 0, slot)
	else:
		DefenderClothPalette.apply(material, selected if slot >= 0 else 0, slot)


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
