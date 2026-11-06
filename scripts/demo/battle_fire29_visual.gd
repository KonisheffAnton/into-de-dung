class_name BattleFire29Visual
extends BattleAnimatedAcidPool

const FLAME_FRAMES: SpriteFrames = preload("res://assets/art_presets/approved/fire29_flame_overlay_v1/fire29_flames_frames.tres")
@onready var _flames: Sprite2D = $Flames

func _ready() -> void:
	super._ready()
	_sprite.frame_changed.connect(_sync_flame_frame)
	_sync_flame_frame()

func _sync_flame_frame() -> void:
	# У слоя языков нет своих часов: пауза, смена кадра и возврат цикла принадлежат основанию.
	_flames.texture = FLAME_FRAMES.get_frame_texture(&"fire", _sprite.frame)
