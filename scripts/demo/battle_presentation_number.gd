class_name BattlePresentationNumber
extends Node2D

@export var lifetime: float = 1.2
@export var rise: float = 24.0

var _tween: Tween
var _label: Label
var _tint: Color = Color.WHITE


func _ready() -> void:
	_label = get_node_or_null("Label") as Label


func start(value: String, tint: Color) -> void:
	if _label == null:
		return
	_stop_tween()
	_tint = tint
	_label.text = value
	_label.size = _label.get_minimum_size()
	sample(0.0)
	_tween = create_tween()
	_tween.tween_method(Callable(self, "sample"), 0.0, 1.0, maxf(lifetime, 0.001))
	_tween.tween_callback(queue_free)


func sample(progress: float) -> void:
	if _label == null:
		return
	var amount: float = clampf(progress, 0.0, 1.0)
	var fade_start: float = 0.75
	var alpha: float = 1.0 if amount <= fade_start else 1.0 - (amount - fade_start) / (1.0 - fade_start)
	_label.position = Vector2(-_label.size.x * 0.5, -_label.size.y - rise * amount)
	_label.modulate = Color(_tint.r, _tint.g, _tint.b, _tint.a * alpha)


func _exit_tree() -> void:
	_stop_tween()


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
