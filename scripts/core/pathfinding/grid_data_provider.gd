extends RefCounted
class_name GridDataProvider

## Контракт данных о карте для GridPathfinder, реализованный через Callable,
## а не через наследование/интерфейс (в GDScript это проще и не требует
## виртуальных методов). Сама боевая карта (уровень/Run State) заполняет
## эти Callable своей логикой — Pathfinder ничего не знает о том, как
## устроена карта, юниты или эффекты (Dependency Inversion).

## (cell: Vector2i) -> bool. false — клетка непроходима в принципе
## (стена, занята непроходимым укрытием и т.п.), независимо от высоты.
var is_walkable: Callable

## (cell: Vector2i) -> int. Высота уровня клетки (Height Level).
var get_height: Callable

## (cell: Vector2i) -> float. Стоимость входа в клетку (>= 1.0).
## Используется для "дорогих" клеток (яд, дым и т.п.), которые
## юнит физически может пройти, но это должно учитываться в
## расчёте зоны хода/пути.
var get_move_cost: Callable


func _init(
	p_is_walkable: Callable = Callable(),
	p_get_height: Callable = Callable(),
	p_get_move_cost: Callable = Callable()
) -> void:
	is_walkable = p_is_walkable
	get_height = p_get_height
	get_move_cost = p_get_move_cost


func cell_is_walkable(cell: Vector2i) -> bool:
	if not is_walkable.is_valid():
		return true
	return bool(is_walkable.call(cell))


func cell_height(cell: Vector2i) -> int:
	if not get_height.is_valid():
		return 0
	return int(get_height.call(cell))


func cell_move_cost(cell: Vector2i) -> float:
	if not get_move_cost.is_valid():
		return 1.0
	return float(get_move_cost.call(cell))
