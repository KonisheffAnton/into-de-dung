extends RefCounted
class_name PushResolver

## Расчёт направления и результата толкания по изометрической 4-направленной
## сетке (та же 4-connectivity, что и в Pathfinding — см. DECISIONS.md).
## Толкание срабатывает, когда цель "ломает" Баланс (BalanceSystem).

## Направление толкания = направление ОТ атакующего К цели, спроецированное
## на ближайшую из 4 осей сетки (в отличие от free-form Vector2, здесь либо
## X, либо Y ось - никаких диагональных толчков, соответствует правилу
## "без диагоналей" из Pathfinding).
static func compute_push_direction(attacker_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	var delta := target_cell - attacker_cell
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO

	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	else:
		return Vector2i(0, signi(delta.y))


static func compute_push_target(target_cell: Vector2i, direction: Vector2i, distance: int = 1) -> Vector2i:
	return target_cell + direction * distance


## Проверяет, может ли цель быть толкнута в push_target_cell.
## Возвращает Dictionary: {success: bool, final_cell: Vector2i, blocked_reason: StringName}.
## blocked_reason: &"wall" (стена/непроходимая клетка), &"height" (слишком
## большой перепад высоты для толкания), &"" (успех).
##
## ПРИМЕЧАНИЕ: столкновение с ДРУГИМ юнитом на клетке толкания — это
## ответственность будущего Модуля 9 (Tile Effects & Status) / occupancy-слоя,
## который пока не существует. Здесь проверяется только геометрия/стены/
## высота через GridDataProvider.
static func validate_push(
	target_cell: Vector2i,
	push_target_cell: Vector2i,
	data_provider: GridDataProvider,
	max_height_step: int = 1
) -> Dictionary:
	if push_target_cell == target_cell:
		return {"success": true, "final_cell": target_cell, "blocked_reason": &""}

	if not data_provider.cell_is_walkable(push_target_cell):
		return {"success": false, "final_cell": target_cell, "blocked_reason": &"wall"}

	var height_diff := absi(data_provider.cell_height(target_cell) - data_provider.cell_height(push_target_cell))
	if height_diff > max_height_step:
		return {"success": false, "final_cell": target_cell, "blocked_reason": &"height"}

	return {"success": true, "final_cell": push_target_cell, "blocked_reason": &""}
