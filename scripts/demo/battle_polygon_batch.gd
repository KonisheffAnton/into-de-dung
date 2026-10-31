class_name BattlePolygonBatch
extends RefCounted

## Polygon2D остаётся авторским источником геометрии. Простые поверхности
## отправляются как примитивы, которые Compatibility может собрать в один batch.
static func configure(polygon: Polygon2D, enabled: bool) -> void:
	var callback := _draw.bind(polygon)
	if enabled and not polygon.draw.is_connected(callback):
		polygon.draw.connect(callback)
	elif not enabled and polygon.draw.is_connected(callback):
		polygon.draw.disconnect(callback)
	polygon.queue_redraw()

static func _draw(surface: Polygon2D) -> void:
	# Не подменяем произвольный authoring: сложные полигоны, skinning, AA,
	# пользовательский draw и трансформации UV сохраняют штатный путь движка.
	if surface.get_script() != null or surface.draw.get_connections().size() != 1: return
	if surface.polygon.size() != 4 or surface.invert_enabled or surface.antialiased \
		or not surface.polygons.is_empty() or not surface.skeleton.is_empty() \
		or surface.internal_vertex_count != 0 or surface.get_bone_count() != 0: return
	if surface.texture_rotation != 0.0 or surface.texture_offset != Vector2.ZERO \
		or surface.texture_scale != Vector2.ONE: return
	var texture := surface.texture
	if texture != null and (surface.uv.size() != 4 or texture.get_width() <= 0 or texture.get_height() <= 0): return
	if not surface.vertex_colors.is_empty() and surface.vertex_colors.size() != 4: return
	var points := surface.polygon
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() != 6: return
	# draw испускается после native NOTIFICATION_DRAW. Заменяем только команды
	# этого CanvasItem; положение, Z, material, clip и соседние узлы не меняются.
	RenderingServer.canvas_item_clear(surface.get_canvas_item())
	for triangle: int in 2:
		var vertices := PackedVector2Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		for corner: int in 3:
			var index: int = indices[triangle * 3 + corner]
			vertices.append(points[index] + surface.offset)
			colors.append(surface.color if surface.vertex_colors.is_empty() else surface.vertex_colors[index])
			uvs.append(surface.uv[index] / texture.get_size() if texture != null else Vector2.ZERO)
		surface.draw_primitive(vertices, colors, uvs, texture)
