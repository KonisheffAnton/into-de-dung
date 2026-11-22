extends Node2D
class_name HostGlowSprite

var points: Array[Vector2] = []
var style: Dictionary = {}
var elapsed: float = 0.0

func configure(skin_id: StringName, texture: Texture2D, appearance: Dictionary, active: bool) -> void:
	points.clear()
	if active: points = HostGlowAppearance.eyes(skin_id,texture)
	style = appearance.duplicate(true)
	visible = active and not points.is_empty()
	set_process(visible and style.get("flicker","soft") == "soft")
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	HostGlowAppearance.paint(self,points,style,elapsed)
