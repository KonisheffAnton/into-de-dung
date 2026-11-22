extends RefCounted
class_name HostGlowAppearance

const COLORS: Dictionary = {"amber":Color("ffbd45"),"blue":Color("65d7ff"),"violet":Color("bf8cff"),"white":Color("fff5dd")}
const STILL_EYES: Dictionary = {
	"watch_shield":[Vector2(137,82),Vector2(145,81)],
	"grey_bastion":[Vector2(138,78),Vector2(147,79)],
	"red_bastion":[Vector2(123,89),Vector2(113,88)],
	"short_cape":[Vector2(145,85)],
	"star_hood":[Vector2(144,81),Vector2(153,80)],
	"silver_ranger":[Vector2(139,86),Vector2(148,84)],
}
static var _anchors: Dictionary = {}
static var _flames: Dictionary = {}

static func eyes(skin_id: StringName, texture: Texture2D) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not STILL_EYES.has(String(skin_id)): return result
	var offset := Vector2.ZERO
	if texture is AtlasTexture:
		if _anchors.is_empty():
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/host_glow_anchors.json"))
			if parsed is Dictionary: _anchors = parsed
		var atlas := texture as AtlasTexture
		var key := "%s@%d,%d" % [atlas.atlas.resource_path.get_file(),int(atlas.region.position.x),int(atlas.region.position.y)]
		var value: Array = _anchors.get(String(skin_id),{}).get(key,[0,0])
		offset = Vector2(float(value[0]),float(value[1]))
	for point: Vector2 in STILL_EYES[String(skin_id)]: result.append(point + offset)
	return result

static func paint(canvas: CanvasItem, points: Array[Vector2], style: Dictionary, elapsed: float, origin: Vector2 = Vector2.ZERO, scale_value: float = 1.0) -> void:
	var color: Color = COLORS.get(style.get("color","amber"),COLORS.amber)
	var strength: float = 0.9 + 0.1 * sin(elapsed * 2.8) if style.get("flicker","soft") == "soft" else 1.0
	for point: Vector2 in points:
		var center := origin + point * scale_value
		canvas.draw_circle(center,4.5*scale_value,Color(color,0.18*strength))
		canvas.draw_circle(center,2.6*scale_value,Color(color,0.65*strength))
		canvas.draw_circle(center,1.3*scale_value,Color(color.lightened(0.5),strength))
		if style.get("form","glow") == "flame":
			var color_id: String = String(style.get("color","amber"))
			if not COLORS.has(color_id): color_id = "amber"
			if not _flames.has(color_id): _flames[color_id] = load("res://assets/ui/host_flame/%s.png" % color_id)
			var texture := _flames[color_id] as Texture2D
			if texture == null: continue
			# Только готовые позы PixelLab; первый кадр — спокойный вариант без анимации.
			var frame: int = int(elapsed / 0.08) % 17 if style.get("flicker","soft") == "soft" else 0
			var factor: float = 0.25 * scale_value
			var destination := Rect2(center-Vector2(31,40)*factor,Vector2(64,64)*factor)
			var source := Rect2(frame*64,0,64,64)
			# Обводка отдельным слоем сохраняет исходные кадры и точно повторяет их альфу.
			var outline_color := Color("241b25")
			for offset: Vector2 in [Vector2(-1,-1),Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,1),Vector2(1,1)]:
				canvas.draw_texture_rect_region(texture,Rect2(destination.position + offset * scale_value,destination.size),source,outline_color)
			canvas.draw_texture_rect_region(texture,destination,source)
