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
##
## ИЗМЕНЕНО (фикс D-6.1): возвращает типизированный `PushResult` вместо
## нетипизированного `Dictionary` с магическими строковыми ключами
## (`result["sucess"]` раньше давал тихий null вместо ошибки компиляции).
##
## ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (D-6.2/C-4, закрывается на шаге 0.4 вместе с
## `BattleBoard`): столкновение с ДРУГИМ юнитом на клетке толкания не
## проверяется — occupancy-слоя пока нет, поэтому толчок в занятую клетку
## считается успешным. Это блокирует главную механику жанра (толкнул -> цель
## врезалась в другого -> оба получили урон). Поле `PushResult.blocker` и
## причина `REASON_OCCUPIED` уже введены под это.
##
## Также отложено (D-6.2): дистанция толчка от IMPACT_POWER, цепное
## толкание, урон при столкновении и при падении с высоты.
static func validate_push(
	target_cell: Vector2i,
	push_target_cell: Vector2i,
	data_provider: GridDataProvider,
	max_height_step: int = 1
) -> PushResult:
	if push_target_cell == target_cell:
		return PushResult.make_success(target_cell)

	if data_provider == null:
		return PushResult.make_success(push_target_cell)

	if not data_provider.cell_is_walkable(push_target_cell):
		return PushResult.make_blocked(target_cell, PushResult.REASON_WALL)

	var height_diff := absi(
		data_provider.cell_height(target_cell) - data_provider.cell_height(push_target_cell)
	)
	if height_diff > max_height_step:
		return PushResult.make_blocked(target_cell, PushResult.REASON_HEIGHT)

	return PushResult.make_success(push_target_cell)
