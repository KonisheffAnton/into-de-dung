class_name BattlePresentationProjectile
extends Node2D


func sample(from: Vector2, to: Vector2, progress: float, art_scale: float) -> void:
	position = from.lerp(to, clampf(progress, 0.0, 1.0))
	rotation = (to - from).angle()
	scale = Vector2.ONE * art_scale
