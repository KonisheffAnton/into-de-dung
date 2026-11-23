extends RefCounted
class_name BattleVitalsOcclusion

const SHADER: Shader = preload("res://assets/shaders/battle_vitals_occlusion.gdshader")
const MAX_BLOCKERS: int = 64
const _META_COUNT: StringName = &"battle_vitals_occlusion_count"
const _META_RECTS: StringName = &"battle_vitals_occlusion_rects"

static var _opaque_bounds_by_texture: Dictionary[int, Rect2i] = {}


static func create_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("blocker_count", 0)
	material.set_meta(_META_COUNT, -1)
	material.set_meta(_META_RECTS, PackedVector4Array())
	return material


static func body_rects(branches: Array[Node2D]) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for branch: Node2D in branches:
		if is_instance_valid(branch):
			_collect_visible_rects(branch, result)
	return result


static func apply(material: ShaderMaterial, rectangles: Array[Rect2], selected: bool) -> void:
	if material == null: return
	var blockers := PackedVector4Array()
	blockers.resize(MAX_BLOCKERS)
	var blocker_count := 0
	if not selected:
		if rectangles.size() <= MAX_BLOCKERS:
			blocker_count = rectangles.size()
			for index: int in blocker_count:
				blockers[index] = _rect_vector(rectangles[index])
		else:
			# При редком переполнении последний слот консервативно закрывает весь хвост bounds.
			blocker_count = MAX_BLOCKERS
			for index: int in MAX_BLOCKERS - 1:
				blockers[index] = _rect_vector(rectangles[index])
			var merged := rectangles[MAX_BLOCKERS - 1]
			for index: int in range(MAX_BLOCKERS, rectangles.size()):
				merged = merged.merge(rectangles[index])
			blockers[MAX_BLOCKERS - 1] = _rect_vector(merged)
	var old_rects: PackedVector4Array = material.get_meta(_META_RECTS, PackedVector4Array())
	var old_count: int = int(material.get_meta(_META_COUNT, -1))
	if old_count == blocker_count and old_rects == blockers: return
	material.set_shader_parameter("blocker_rects", blockers)
	material.set_shader_parameter("blocker_count", blocker_count)
	material.set_meta(_META_RECTS, blockers)
	material.set_meta(_META_COUNT, blocker_count)


static func _rect_vector(rect: Rect2) -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y)


static func _collect_visible_rects(node: Node, output: Array[Rect2]) -> void:
	if node is CanvasItem:
		var item := node as CanvasItem
		if not item.is_visible_in_tree() or _effective_alpha(item) <= 0.0: return
	if node is Sprite2D:
		var sprite := node as Sprite2D
		var sprite_rect := _sprite_rect(sprite)
		if sprite_rect.has_area():
			var screen_rect := _transform_rect(sprite.get_global_transform_with_canvas(), sprite_rect)
			if screen_rect.has_area(): output.append(screen_rect)
	elif node is Polygon2D:
		var polygon := node as Polygon2D
		if polygon.color.a > 0.0 and polygon.polygon.size() >= 3:
			var polygon_rect := _polygon_rect(polygon)
			var screen_rect := _transform_rect(polygon.get_global_transform_with_canvas(), polygon_rect)
			if screen_rect.has_area(): output.append(screen_rect)
	for child: Node in node.get_children():
		_collect_visible_rects(child, output)


static func _effective_alpha(item: CanvasItem) -> float:
	var alpha := item.self_modulate.a
	var cursor: Node = item
	while cursor != null:
		if cursor is CanvasItem:
			var canvas_item := cursor as CanvasItem
			alpha *= canvas_item.modulate.a
			if alpha <= 0.0: return 0.0
		cursor = cursor.get_parent()
	return alpha


static func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var texture := sprite.texture
	if texture == null: return Rect2()
	if not sprite.region_enabled and sprite.hframes == 1 and sprite.vframes == 1:
		var used := _opaque_bounds(texture)
		if used.size.x <= 0 or used.size.y <= 0: return Rect2()
		var texture_size := Vector2(texture.get_size())
		var source_rect := Rect2(Vector2(used.position), Vector2(used.size))
		if sprite.flip_h: source_rect.position.x = texture_size.x - source_rect.end.x
		if sprite.flip_v: source_rect.position.y = texture_size.y - source_rect.end.y
		var base := -texture_size * 0.5 if sprite.centered else Vector2.ZERO
		return Rect2(source_rect.position + base + sprite.offset, source_rect.size)
	# Регионы самого Sprite2D и sprite sheets используют полный authored rect.
	return sprite.get_rect()


static func _opaque_bounds(texture: Texture2D) -> Rect2i:
	var texture_id: int = texture.get_instance_id()
	if _opaque_bounds_by_texture.has(texture_id): return _opaque_bounds_by_texture[texture_id]
	var image: Image = texture.get_image()
	var bounds := image.get_used_rect() if image != null and not image.is_empty() else Rect2i()
	_opaque_bounds_by_texture[texture_id] = bounds
	return bounds


static func _polygon_rect(polygon: Polygon2D) -> Rect2:
	var points := polygon.polygon
	var first := points[0] + polygon.offset
	var bounds := Rect2(first, Vector2.ZERO)
	for index: int in range(1, points.size()):
		bounds = bounds.expand(points[index] + polygon.offset)
	return bounds


static func _transform_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var first := transform * rect.position
	var second := transform * Vector2(rect.end.x, rect.position.y)
	var third := transform * rect.end
	var fourth := transform * Vector2(rect.position.x, rect.end.y)
	var bounds := Rect2(first, Vector2.ZERO)
	for point: Vector2 in [second, third, fourth]:
		bounds = bounds.expand(point)
	return bounds
