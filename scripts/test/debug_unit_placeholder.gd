extends YSortable

## Плейсхолдер юнита для проверки Y-сортировки и слоёв отрисовки.
## Рисует цветной круг со смещением по высоте, не являясь частью
## финальной архитектуры юнитов (та появится в Modular Stats Engine).

@export var color: Color = Color.RED
@export var radius: float = 28.0
@export var label: String = ""


func _draw() -> void:
	var offset := get_visual_offset()
	draw_circle(offset, radius, color)
	draw_circle(offset, radius, Color.BLACK, false, 2.0)

	if label != "":
		draw_string(
			ThemeDB.fallback_font,
			offset + Vector2(-radius * 0.5, -radius - 6.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14
		)
