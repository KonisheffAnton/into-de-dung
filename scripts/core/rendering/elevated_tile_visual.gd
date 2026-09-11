extends YSortable
class_name ElevatedTileVisual

## Визуальное представление тайла/платформы с height_level > 0. Живёт в
## слое ENTITIES и участвует в общем Y-sort с юнитами — именно поэтому,
## в отличие от плоских тайлов слоя TILES (которые всегда рисуются под
## ENTITIES независимо от их grid-глубины, см. docs/DECISIONS.md), этот
## компонент способен визуально ПЕРЕКРЫВАТЬ юниты, стоящие "позади" него
## по логической глубине сетки — и корректно перекрываться юнитами,
## стоящими "перед" ним.
##
## СИСТЕМНОЕ ПРАВИЛО (см. DECISIONS.md): любой тайл/платформа/укрытие с
## height_level > 0, которое должно визуально взаимодействовать с юнитами
## по глубине, ДОЛЖНО использовать этот (или аналогичный) YSortable-компонент
## вместо плоской тайловой сетки. Хардкода конкретных клеток здесь нет —
## компонент просто рисует блок по своим grid_anchor/height_level.

@export var top_color: Color = Color(0.35, 0.45, 0.3, 1.0)
@export var side_color: Color = Color(0.20, 0.26, 0.17, 1.0)
@export var outline_color: Color = Color.BLACK

var _highlight_color: Color = Color.TRANSPARENT


func set_highlight(color: Color) -> void:
	_highlight_color = color
	queue_redraw()


## Небольшой эпсилон сортировки: гарантирует, что платформа рисуется
## НЕМНОГО раньше (то есть "позади"), чем юнит, стоящий на той же клетке.
## При равном сортировочном Y порядок между узлами не гарантирован (зависит
## от индекса в дереве), а юнит на платформе визуально должен быть "на ней",
## а не под ней.
func _update_sort_position() -> void:
	super._update_sort_position()
	position.y -= 1.0


func _draw() -> void:
	if grid_config == null:
		return

	var offset := get_visual_offset()
	var half_w := grid_config.tile_size.x * 0.5
	var half_h := grid_config.tile_size.y * 0.5

	var top_n := offset + Vector2(0, -half_h)
	var top_e := offset + Vector2(half_w, 0)
	var top_s := offset + Vector2(0, half_h)
	var top_w := offset + Vector2(-half_w, 0)

	# Точки на уровне земли (height=0) для тех же двух "передних" вершин —
	# формируют боковую грань (риsер), создающую эффект объёма/блока.
	var ground_e := Vector2(half_w, 0)
	var ground_s := Vector2(0, half_h)
	var ground_w := Vector2(-half_w, 0)

	var riser_points := PackedVector2Array([top_w, top_s, top_e, ground_e, ground_s, ground_w])
	draw_colored_polygon(riser_points, side_color)

	var top_points := PackedVector2Array([top_n, top_e, top_s, top_w])
	draw_colored_polygon(top_points, top_color)
	draw_polyline(top_points + PackedVector2Array([top_points[0]]), outline_color, 1.0)

	if _highlight_color.a > 0.0:
		draw_colored_polygon(top_points, _highlight_color)
