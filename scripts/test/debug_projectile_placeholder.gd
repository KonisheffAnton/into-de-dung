extends Node2D

## Плейсхолдер "снаряда в полёте" для проверки, что слой PROJECTILES
## всегда рисуется НАД слоем ENTITIES (Y-sorted юниты), независимо от
## их взаимной глубины. Не привязан к сетке — летает по свободным
## экранным координатам, как и положено визуальному эффекту в полёте.

@export var amplitude: Vector2 = Vector2(220.0, 40.0)
@export var speed: float = 1.2

var _time: float = 0.0
var _start_position: Vector2


func _ready() -> void:
	_start_position = position


func _process(delta: float) -> void:
	_time += delta * speed
	position = _start_position + Vector2(sin(_time) * amplitude.x, cos(_time * 2.0) * amplitude.y - 60.0)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color.YELLOW)
	draw_circle(Vector2.ZERO, 9.0, Color.BLACK, false, 2.0)
