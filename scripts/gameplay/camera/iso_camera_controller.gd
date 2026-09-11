extends Camera2D
class_name IsoCameraController

## Камера с поддержкой drag-to-pan (мышь ПКМ / touch) и pinch/wheel-to-zoom,
## с инерцией панорамирования и плавным сглаживанием зума.
## Подписывается на сигналы InputManager, ничего не знает о сетке/боях.

@export var pan_speed_multiplier: float = 1.0
@export var pan_friction: float = 6.0       ## Выше = быстрее гасится инерция.
@export var pan_velocity_smoothing: float = 0.6

@export var zoom_min: float = 0.5
@export var zoom_max: float = 2.5
@export var zoom_smoothing_speed: float = 8.0

var _pan_velocity: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0


func _ready() -> void:
	_target_zoom = zoom.x
	InputManager.camera_pan.connect(_on_camera_pan)
	InputManager.camera_zoom.connect(_on_camera_zoom)


func _process(delta: float) -> void:
	_update_pan(delta)
	_update_zoom(delta)


func _on_camera_pan(delta_screen: Vector2) -> void:
	var dt := get_process_delta_time()
	if dt <= 0.0:
		dt = 1.0 / 60.0

	# Инвертируем и делим на зум, чтобы контент "следовал" за пальцем/мышью
	# одинаково на любом уровне приближения.
	var instant_velocity := (-delta_screen / zoom.x) * pan_speed_multiplier / dt
	_pan_velocity = _pan_velocity.lerp(instant_velocity, pan_velocity_smoothing)


func _on_camera_zoom(factor: float, _center: Vector2) -> void:
	_target_zoom = clampf(_target_zoom * factor, zoom_min, zoom_max)


func _update_pan(delta: float) -> void:
	if _pan_velocity.length() > 0.5:
		position += _pan_velocity * delta
		var decay := clampf(pan_friction * delta, 0.0, 1.0)
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, decay)
	else:
		_pan_velocity = Vector2.ZERO


func _update_zoom(delta: float) -> void:
	var current := zoom.x
	if not is_equal_approx(current, _target_zoom):
		var t := clampf(zoom_smoothing_speed * delta, 0.0, 1.0)
		var new_zoom := lerpf(current, _target_zoom, t)
		zoom = Vector2(new_zoom, new_zoom)
