class_name BattleAnimatedAcidPool
extends Node2D

@export var animation_name: StringName = &"acid"

@onready var _sprite: AnimatedSprite2D = $Animation

func _ready() -> void:
	visibility_changed.connect(_sync_playback)
	_sync_playback()

func set_active(active: bool) -> void:
	visible = active
	_sync_playback()

func _sync_playback() -> void:
	if _sprite == null: return
	if is_visible_in_tree():
		# play прежнего имени продолжает паузу; публикация/resize не сбрасывают кадр.
		if not _sprite.is_playing(): _sprite.play(animation_name)
	else:
		_sprite.pause()

func retire_view() -> void:
	visible = false
	if _sprite != null: _sprite.stop()

func _exit_tree() -> void:
	# Нет внешнего Tween или общего игрового времени; часы уходят вместе с узлом.
	if _sprite != null: _sprite.stop()
