class_name BattlePresentationImpact
extends Node2D

@export var lifetime: float = 0.16

var _tween: Tween
var _sprite: Sprite2D
var _tint: Color = Color.WHITE


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D


func start(tint: Color) -> void:
	if _sprite == null:
		return
	_stop_tween()
	_tint = tint
	sample(0.0)
	_tween = create_tween()
	_tween.tween_method(Callable(self, "sample"), 0.0, 1.0, maxf(lifetime, 0.001))
	_tween.tween_callback(queue_free)


func sample(progress: float) -> void:
	if _sprite == null:
		return
	var amount: float = clampf(progress, 0.0, 1.0)
	# Вспышка быстро раскрывается, чтобы контакт читался даже при короткой жизни эффекта.
	_sprite.scale = Vector2.ONE * lerpf(0.35, 1.0, amount)
	_sprite.modulate = Color(_tint.r, _tint.g, _tint.b, _tint.a * (1.0 - amount))


func _exit_tree() -> void:
	_stop_tween()


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
