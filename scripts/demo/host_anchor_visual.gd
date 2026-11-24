extends Node2D
class_name HostAnchorVisual

var _kind: String = ""
var _color: Color = Color("ffbd45")

func configure(kind: String, glow: Dictionary) -> void:
	_kind = kind
	var configured: Variant = HostGlowAppearance.COLORS.get(String(glow.get("color", "amber")), HostGlowAppearance.COLORS.amber)
	if configured is Color: _color = configured
	visible = kind in ["fresh", "bones", "spirit"]
	queue_redraw()

func _draw() -> void:
	if _kind == "fresh" or _kind == "bones":
		# Небольшой свет отмечает останки, не выдавая их за живую цель.
		draw_circle(Vector2(0, -5), 11.0, Color(_color, 0.16))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -20), Vector2(7, -8), Vector2(3, -2), Vector2(-4, -2), Vector2(-7, -9)]), _color)
		draw_circle(Vector2.ZERO, 3.0, _color.lightened(0.45))
		return
	if _kind == "spirit":
		# Дух — только декоративный слой; никаких collider, unit view или полос состояния.
		var veil := Color(_color, 0.34)
		draw_circle(Vector2(0, -35), 9.0, Color(_color, 0.48))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-8, -28), Vector2(8, -28), Vector2(11, -13),
			Vector2(15, -2), Vector2(7, -6), Vector2(0, -1),
			Vector2(-7, -6), Vector2(-15, -2), Vector2(-11, -13),
		]), veil)
		draw_circle(Vector2(-3, -36), 1.5, Color(_color.lightened(0.65), 0.9))
		draw_circle(Vector2(3, -36), 1.5, Color(_color.lightened(0.65), 0.9))
		draw_circle(Vector2(0, -4), 4.0, Color(_color, 0.20))
