extends Node2D
class_name YSortable

## Базовый компонент для объектов внутри слоя ENTITIES, которым нужна
## Y-сортировка по логической глубине сетки, НЕ зависящая от визуального
## сдвига по высоте (height_level).
##
## Идея: node.position выставляется в "наземную" экранную точку опорной
## клетки (height=0) — именно по ней работает встроенный Godot Y-sort
## родительского контейнера (y_sort_enabled=true). Визуальный сдвиг вверх
## из-за height_level применяется ТОЛЬКО к отрисовке/дочерним визуалам
## через get_visual_offset(), не трогая position, иначе высокая клетка
## могла бы "перепрыгивать" глубину сортировки.
##
## Для крупных объектов (2x2 укрытия и т.п.) grid_anchor должен быть
## самой "нижней" (ближней к камере) клеткой объекта.

@export var grid_config: IsoGridConfig
@export var grid_anchor: Vector2i = Vector2i.ZERO
@export var height_level: int = 0


func _ready() -> void:
	_update_sort_position()


func set_grid_anchor(anchor: Vector2i, height: int = 0) -> void:
	grid_anchor = anchor
	height_level = height
	_update_sort_position()
	queue_redraw()


func _update_sort_position() -> void:
	if grid_config == null:
		return
	# Высота намеренно игнорируется (height=0) — сортируем по логической
	# глубине клетки, а не по её визуальному сдвигу.
	position = IsoGridUtils.grid_to_screen(grid_anchor, grid_config, 0)


## Смещение, которое нужно применить к визуальным элементам (спрайт/draw),
## чтобы отобразить объект "приподнятым" на height_level уровней, без
## влияния на сортировочную позицию.
func get_visual_offset() -> Vector2:
	if grid_config == null:
		return Vector2.ZERO
	return Vector2(0.0, -float(height_level) * grid_config.height_step)
