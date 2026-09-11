extends RefCounted
class_name PushResolver

## Расчёт направления и результата толкания по изометрической 4-направленной
## сетке (та же 4-connectivity, что и в Pathfinding — см. DECISIONS.md).
## Толкание срабатывает, когда цель "ломает" Баланс (`Vitals.add_impact`).
##
## ЧТО ИСПРАВЛЕНО НА ШАГЕ 0.4 (дефекты C-4 и D-6.2). Раньше резолвер видел
## только геометрию через `GridDataProvider` и НЕ ЗНАЛ О ЮНИТАХ, поэтому
## толчок в занятую клетку считался успешным. Из-за этого была невыразима
## главная механика жанра: толкнул -> цель врезалась в другого -> оба
## получили урон. Теперь резолвер работает с `BattleBoard` и различает
## четыре принципиально разных исхода:
##
##   1. свободная клетка        -> цель перемещается;
##   2. занята другим юнитом    -> COLLISION: оба получают урон, цель стоит;
##   3. стена                   -> цель упирается, получает урон о стену;
##   4. пропасть / край доски   -> цель улетает и погибает (FALL).
##
## Различие (3) и (4) — тот самый случай, ради которого `TerrainType`
## разделяет `blocks_push` и `is_lethal`: в стену упираются, в пустоту падают.

## Направление толкания = направление ОТ атакующего К цели, спроецированное
## на ближайшую из 4 осей сетки (никаких диагональных толчков — соответствует
## правилу "без диагоналей" из Pathfinding).
##
## При |dx| == |dy| предпочитается ось X. Для ближнего боя (дистанция 1) такая
## ситуация невозможна, но для дальних атак и AoE — возможна (D-6.4), поэтому
## поведение зафиксировано явно и детерминированно (R-5), а не "как получится".
static func compute_push_direction(attacker_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	var delta := target_cell - attacker_cell
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO

	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


static func compute_push_target(
	target_cell: Vector2i,
	direction: Vector2i,
	distance: int = 1
) -> Vector2i:
	return target_cell + direction * distance


## Полный расчёт толкания с учётом юнитов, террейна и высот.
##
## `board` — авторитетное состояние доски. `pushed_unit` нужен, чтобы юнит не
## считал блокирующим сам себя.
##
## ЧИСТАЯ функция: ничего не мутирует. Перемещение и урон выполняет
## `PushCommand` (шаг 0.5) — это позволяет показать полный результат в превью
## до подтверждения (R-6).
static func resolve_push(
	board: BattleBoard,
	pushed_unit: UnitState,
	target_cell: Vector2i,
	direction: Vector2i,
	max_height_step: int = 1
) -> PushResult:
	if board == null or direction == Vector2i.ZERO:
		return PushResult.make_success(target_cell)

	var destination := target_cell + direction

	# 1. За краем доски или в пустоте — падение. Проверяется ПЕРВЫМ:
	#    вне границ нет ни террейна, ни высоты, ни occupancy.
	if not board.is_in_bounds(destination):
		return PushResult.make_fall(destination, PushResult.REASON_BOUNDS)

	var terrain := board.get_terrain(destination)

	# 2. Стена — цель упирается и остаётся на месте.
	if TerrainType.blocks_push(terrain):
		return PushResult.make_blocked(target_cell, PushResult.REASON_WALL)

	# 3. Уступ вверх слишком высок — цель упирается в него.
	#
	#    ПОРЯДОК ВАЖЕН: высота проверяется РАНЬШЕ occupancy. Если на высоком
	#    уступе кто-то стоит, цель всё равно физически не долетает до него —
	#    она бьётся об край уступа, а не о юнита. Обратный порядок давал бы
	#    COLLISION и урон юниту, до которого толчок не доходит.
	#    (Именно это поймал регрессионный тест.)
	#
	#    Сравнение ОДНОСТОРОННЕЕ: вниз падать можно, поэтому толчок с обрыва
	#    блокировкой не считается.
	var height_delta := board.get_height(destination) - board.get_height(target_cell)
	if height_delta > max_height_step:
		return PushResult.make_blocked(target_cell, PushResult.REASON_HEIGHT)

	# 4. Занято другим живым юнитом — столкновение, урон обоим.
	var occupant := board.occupant_at(destination)
	if occupant != null and (pushed_unit == null or occupant.id != pushed_unit.id):
		return PushResult.make_collision(target_cell, destination, occupant)

	# 5. Смертельная клетка — цель улетает в неё и погибает.
	if TerrainType.is_lethal(terrain):
		return PushResult.make_fall(destination, PushResult.REASON_HAZARD)

	# 6. Свободно. Падение с высоты — это успешный толчок, но с уроном;
	#    величину считает PushCommand по глубине падения.
	var result := PushResult.make_success(destination)
	if height_delta < 0:
		result.fall_height = absi(height_delta)
	return result


## УСТАРЕВШАЯ проверка только по геометрии, без юнитов.
## Оставлена для кода, у которого ещё нет доски (дебаг-панели, старые вызовы).
## НЕ ИСПОЛЬЗОВАТЬ в новом коде: она не видит occupancy и поэтому не может
## сообщить о столкновении — то есть воспроизводит дефект C-4.
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
