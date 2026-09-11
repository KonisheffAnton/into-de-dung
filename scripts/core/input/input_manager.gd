extends Node

## Единый слой абстракции ввода (Autoload Singleton).
## Нормализует Mouse/Keyboard (PC) и Touch/Gestures (Mobile) в единый набор
## сигналов, не зная НИЧЕГО о сетке или боевой логике (SRP).
##
## Позиции в сигналах передаются в VIEWPORT (screen) координатах.
## Потребитель, которому нужны мировые/grid координаты, обязан сначала
## перевести их через get_viewport().get_canvas_transform().affine_inverse(),
## чтобы корректно учесть панорамирование и зум камеры.

# --- Публичные сигналы -------------------------------------------------

## Короткое одиночное нажатие/тап (ЛКМ или одиночный палец).
signal primary_action(screen_pos: Vector2)

## Короткое нажатие вторичной кнопки (ПКМ) без драга.
signal secondary_action(screen_pos: Vector2)

## Долгое удержание на месте (ЛКМ или палец).
signal long_press(screen_pos: Vector2)

## Движение указателя без нажатия. Актуально только для PC (hover).
## На touch-устройствах не эмитится вне активного драга.
signal pointer_moved(screen_pos: Vector2)

## Панорамирование камеры. delta — смещение в экранных пикселях за кадр.
signal camera_pan(delta: Vector2)

## Зум камеры. factor > 1 = приближение, center — точка в экранных координатах.
signal camera_zoom(factor: float, center: Vector2)

# --- Настройки жестов ---------------------------------------------------

@export var tap_max_distance: float = 16.0
@export var tap_max_time: float = 0.25
@export var long_press_time: float = 0.5
@export var mouse_wheel_zoom_step: float = 0.1

# --- Внутреннее состояние: мышь -----------------------------------------

var _mouse_left_pressed: bool = false
var _mouse_left_press_pos: Vector2 = Vector2.ZERO
var _mouse_left_press_time: float = 0.0
var _mouse_current_pos: Vector2 = Vector2.ZERO

var _mouse_right_pressed: bool = false
var _mouse_right_press_pos: Vector2 = Vector2.ZERO
var _mouse_right_panning: bool = false

var _mouse_long_press_fired: bool = false

# --- Внутреннее состояние: touch ----------------------------------------

var _touch_points: Dictionary = {}       # index -> Vector2 (текущая позиция)
var _touch_start_points: Dictionary = {} # index -> Vector2 (позиция начала касания)
var _touch_start_time: Dictionary = {}   # index -> float
var _touch_long_press_fired: Dictionary = {} # index -> bool

var _is_pinching: bool = false
var _pinch_last_distance: float = 0.0


func _ready() -> void:
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventPanGesture:
		camera_pan.emit(event.delta)
	elif event is InputEventMagnifyGesture:
		camera_zoom.emit(event.factor, event.position)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _process(_delta: float) -> void:
	_update_long_press_detection()


# --- Мышь -----------------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var now := _now()

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_left_pressed = true
				_mouse_left_press_pos = event.position
				_mouse_left_press_time = now
				_mouse_long_press_fired = false
			else:
				if _mouse_left_pressed and not _mouse_long_press_fired:
					var dist := event.position.distance_to(_mouse_left_press_pos)
					var dt := now - _mouse_left_press_time
					if dist <= tap_max_distance and dt <= tap_max_time:
						primary_action.emit(event.position)
				_mouse_left_pressed = false

		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_mouse_right_pressed = true
				_mouse_right_press_pos = event.position
				_mouse_right_panning = false
			else:
				if _mouse_right_pressed and not _mouse_right_panning:
					var dist := event.position.distance_to(_mouse_right_press_pos)
					if dist <= tap_max_distance:
						secondary_action.emit(event.position)
				_mouse_right_pressed = false
				_mouse_right_panning = false

		MOUSE_BUTTON_WHEEL_UP:
			camera_zoom.emit(1.0 + mouse_wheel_zoom_step, event.position)

		MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom.emit(1.0 - mouse_wheel_zoom_step, event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_mouse_current_pos = event.position

	if _mouse_right_pressed:
		_mouse_right_panning = true
		camera_pan.emit(event.relative)
	elif not _mouse_left_pressed:
		pointer_moved.emit(event.position)


# --- Touch ------------------------------------------------------------------

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var now := _now()

	if event.pressed:
		_touch_points[event.index] = event.position
		_touch_start_points[event.index] = event.position
		_touch_start_time[event.index] = now
		_touch_long_press_fired[event.index] = false

		if _touch_points.size() == 2:
			_is_pinching = true
			var pts := _touch_points.values()
			_pinch_last_distance = (pts[0] as Vector2).distance_to(pts[1])
	else:
		var was_long_press: bool = _touch_long_press_fired.get(event.index, false)

		if _touch_points.size() == 1 and not was_long_press:
			var start: Vector2 = _touch_start_points.get(event.index, event.position)
			var dist := event.position.distance_to(start)
			var dt := now - float(_touch_start_time.get(event.index, now))
			if dist <= tap_max_distance and dt <= tap_max_time:
				primary_action.emit(event.position)

		_touch_points.erase(event.index)
		_touch_start_points.erase(event.index)
		_touch_start_time.erase(event.index)
		_touch_long_press_fired.erase(event.index)

		if _touch_points.size() < 2:
			_is_pinching = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position

	if _touch_points.size() == 2 and _is_pinching:
		var pts := _touch_points.values()
		var p0: Vector2 = pts[0]
		var p1: Vector2 = pts[1]
		var dist := p0.distance_to(p1)

		if _pinch_last_distance > 0.0:
			var factor := dist / _pinch_last_distance
			var center := (p0 + p1) * 0.5
			camera_zoom.emit(factor, center)
		_pinch_last_distance = dist

		# Двухпальцевый пан: каждый палец шлёт свой drag-event, делим на 2,
		# чтобы не удваивать смещение камеры.
		camera_pan.emit(event.relative * 0.5)
	elif _touch_points.size() == 1:
		var start: Vector2 = _touch_start_points.get(event.index, event.position)
		var dist_from_start := event.position.distance_to(start)
		if dist_from_start > tap_max_distance:
			camera_pan.emit(event.relative)


# --- Long press ---------------------------------------------------------

func _update_long_press_detection() -> void:
	var now := _now()

	if _mouse_left_pressed and not _mouse_long_press_fired:
		if now - _mouse_left_press_time >= long_press_time:
			if _mouse_current_pos.distance_to(_mouse_left_press_pos) <= tap_max_distance:
				long_press.emit(_mouse_left_press_pos)
				_mouse_long_press_fired = true

	for idx in _touch_start_time.keys():
		if _touch_long_press_fired.get(idx, false):
			continue
		if not _touch_points.has(idx):
			continue
		var start_time: float = _touch_start_time[idx]
		if now - start_time >= long_press_time:
			var current_pos: Vector2 = _touch_points[idx]
			var start_pos: Vector2 = _touch_start_points[idx]
			if current_pos.distance_to(start_pos) <= tap_max_distance:
				long_press.emit(current_pos)
				_touch_long_press_fired[idx] = true


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
