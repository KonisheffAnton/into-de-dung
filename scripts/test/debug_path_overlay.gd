extends Node2D

## Отрисовывает текущий путь (GridPathfinder) в слое UI_PREVIEW (z=500),
## чтобы линия пути ВСЕГДА была видна над платформами/укрытиями/юнитами,
## а не "проваливалась" визуально под ElevatedTileVisual (ENTITIES, z=200).
## Системное следствие правила слоёв из RenderLayers/DECISIONS.md: любой
## чисто UI/превью-элемент (путь, зона хода, стрелки push vectors) должен
## жить в UI_PREVIEW, а не в TILES/ENTITIES, иначе он визуально конкурирует
## за occlusion с игровыми объектами, хотя логически должен быть просто
## "оверлеем поверх всего". Не финальная архитектура (Path Preview как
## продакшен-фича появится в Модуле 6 Damage/Balance & Push Preview).

@export var grid_visualizer_path: NodePath
var _grid_visualizer: Node


func _ready() -> void:
	if not grid_visualizer_path.is_empty():
		_grid_visualizer = get_node(grid_visualizer_path)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _grid_visualizer == null:
		return
	var points: PackedVector2Array = _grid_visualizer.get_current_path_screen_points()
	if points.size() < 2:
		return

	draw_polyline(points, Color.WHITE, 3.0)
	for p in points:
		draw_circle(p, 5.0, Color.WHITE)
