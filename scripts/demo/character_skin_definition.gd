class_name CharacterSkinDefinition
extends Resource

@export var id: StringName
@export var class_id: StringName
@export var display_name: String
@export var still: Texture2D
@export var animations: SpriteFrames
@export var anchor := Vector2(128.0, 200.0)
@export var texture_scale: float = 0.5
@export_enum("Left:-1", "Right:1") var source_facing_x: int = 1
@export_range(0.0, 1.0) var shieldbearer_palette_strength: float = 0.0
## Периодический жест вне действий не имеет боевого эффекта; ноль сохраняет прежнее поведение.
@export_range(0.0, 120.0) var ambient_buff_interval: float = 0.0

func clip_valid(animation: StringName) -> bool:
	if animations == null or not animations.has_animation(animation): return false
	if animations.get_frame_count(animation) < 1 or animations.get_animation_speed(animation) <= 0.0: return false
	for frame: int in animations.get_frame_count(animation):
		if animations.get_frame_texture(animation, frame) == null or animations.get_frame_duration(animation, frame) <= 0.0: return false
	return true

func clip_duration(animation: StringName) -> float:
	if not clip_valid(animation): return 0.0
	var duration := 0.0
	for frame: int in animations.get_frame_count(animation): duration += animations.get_frame_duration(animation, frame)
	return duration / animations.get_animation_speed(animation)
