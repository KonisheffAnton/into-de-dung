class_name BattleDefenderIdleVisual
extends BattleManagedUnitVisual

@export var idle_frames: SpriteFrames
@export_range(1, 120, 1) var idle_normal_cycles_min: int = 24
@export_range(1, 120, 1) var idle_normal_cycles_max: int = 36

var idle_clock := DefenderIdleClock.new()
var _idle_owner: int = UnitId.NONE
var _idle_sprite: Sprite2D
var _still_sprite: Sprite2D
var _configured_min: int = -1
var _configured_max: int = -1


func _ready() -> void:
	_idle_sprite = get_node_or_null("ArtRoot/DefenderIdleSprite") as Sprite2D
	_still_sprite = get_node_or_null("ArtRoot/PlayerWarriorSprite") as Sprite2D
	super._ready()
	visibility_changed.connect(sync_scene_art)
	sync_scene_art()


func sync_scene_art() -> void:
	super.sync_scene_art()
	if _idle_sprite == null or _still_sprite == null: return
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
	return is_inside_tree() and is_visible_in_tree() and role == Role.UNIT \
		and unit != null and unit.alive and unit.faction == Faction.Type.PLAYER \
		and visual_class_id == &"warrior" and _still_sprite.texture != null \
		and not ambient_animation_paused and not frozen and not stunned and not summon_pending \
		and action_offset == Vector2.ZERO and presentation_offset == Vector2.ZERO \
		and presentation_lift == 0.0 and fall_drop == 0.0 \
		and landing_compression == 0.0 and death_progress == 0.0 \
		and idle_frames != null and idle_frames.has_animation(&"vertical") \
		and idle_frames.has_animation(&"sway") \
		and idle_frames.get_frame_count(&"vertical") == 12 \
		and idle_frames.get_frame_count(&"sway") == 12


func _process(delta: float) -> void:
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
	set_process(false)
	_idle_owner = UnitId.NONE
	idle_clock.reset()
