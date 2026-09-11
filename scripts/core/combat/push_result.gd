extends RefCounted
class_name PushResult

## Результат проверки толкания — фикс дефекта D-6.1.
##
## Раньше `PushResolver.validate_push()` возвращал НЕТИПИЗИРОВАННЫЙ
## `Dictionary` с магическими строковыми ключами:
##     {"success": bool, "final_cell": Vector2i, "blocked_reason": StringName}
## Это напрямую противоречило правилу "strictly typed GDScript везде":
## опечатка в ключе (`"sucess"`) давала не ошибку компиляции, а тихий `null`,
## и автокомплит не работал. Теперь это обычный объект с типизированными
## полями.

## Причины блокировки толчка. Строковые константы, а не enum: они попадают в
## UI как ключ для текста подсказки ("Цель не может быть отброшена: стена"),
## и StringName удобнее расширять новыми причинами из будущих модулей
## (эффекты тайлов, статусы "укоренён" и т.п.) без правки enum.
const REASON_NONE: StringName = &""
const REASON_WALL: StringName = &"wall"
const REASON_HEIGHT: StringName = &"height"
const REASON_OCCUPIED: StringName = &"occupied"
const REASON_BOUNDS: StringName = &"bounds"

## Удалось ли толкнуть.
var success: bool = false

## Клетка, где цель окажется по итогу. При неудаче — исходная клетка цели.
var final_cell: Vector2i = Vector2i.ZERO

## Причина блокировки (одна из REASON_*). Пустая при успехе.
var blocked_reason: StringName = REASON_NONE

## Юнит, в которого упёрлась цель (только при REASON_OCCUPIED).
## Задел под главную механику жанра — урон при столкновении (D-6.2):
## сейчас occupancy-слоя нет, поле всегда null и заполнится на шаге 0.4
## вместе с `BattleBoard`.
var blocker: UnitState = null


static func make_success(cell: Vector2i) -> PushResult:
	var result := PushResult.new()
	result.success = true
	result.final_cell = cell
	result.blocked_reason = REASON_NONE
	return result


static func make_blocked(
	stay_cell: Vector2i,
	reason: StringName,
	p_blocker: UnitState = null
) -> PushResult:
	var result := PushResult.new()
	result.success = false
	result.final_cell = stay_cell
	result.blocked_reason = reason
	result.blocker = p_blocker
	return result
