class_name BattlePresentationProjectile
extends Node2D


func sample(
	from: Vector2,
	to: Vector2,
	progress: float,
	art_scale: float,
	arc_height: float = 0.0
) -> void:
	var t: float = clampf(progress, 0.0, 1.0)
	var height: float = maxf(arc_height, 0.0)
	position = from.lerp(to, t) + Vector2(0.0, -4.0 * height * t * (1.0 - t))
	var tangent: Vector2 = (to - from) + Vector2(0.0, -4.0 * height * (1.0 - 2.0 * t))
	# Поворот по касательной сохраняет ориентацию снаряда вдоль дуги на подъёме и спуске.
	rotation = 0.0 if tangent.is_zero_approx() else tangent.angle()
	scale = Vector2.ONE * art_scale
