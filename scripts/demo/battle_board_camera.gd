class_name BattleBoardCamera
extends RefCounted

const MIN_ZOOM: float = 0.75
const MAX_ZOOM: float = 2.5

var zoom: float = 1.0
var offset: Vector2 = Vector2.ZERO

func get_transform() -> Transform2D:
	return Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), offset)

func world_to_view(point: Vector2) -> Vector2:
	return point * zoom + offset

func view_to_world(point: Vector2) -> Vector2:
	return (point - offset) / zoom

func zoom_at(value: float, anchor: Vector2) -> void:
	# Нефинитные входы отравили бы все последующие координаты камеры.
	if not is_finite(value) or not _is_finite_vector(anchor):
		return
	var world_anchor: Vector2 = view_to_world(anchor)
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	# Смещение пересчитывается так, чтобы выбранная точка мира оставалась под курсором.
	offset = anchor - world_anchor * zoom

func pan(delta: Vector2) -> void:
	# Отбрасываем некорректный жест, чтобы смещение оставалось пригодным для преобразований.
	if not _is_finite_vector(delta):
		return
	offset += delta

func reset() -> void:
	zoom = 1.0
	offset = Vector2.ZERO

func recenter_after_resize(old_center: Vector2, new_center: Vector2) -> void:
	# Центры задаются полем; некорректный размер не должен портить runtime-состояние.
	if not _is_finite_vector(old_center) or not _is_finite_vector(new_center):
		return
	# Перенос центра доски уже выполняет поле; камера компенсирует свою долю смещения.
	offset += (new_center - old_center) * (1.0 - zoom)

func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
