extends RefCounted
class_name PushResult

## Результат расчёта толкания — фикс дефекта D-6.1.
##
## Раньше `PushResolver.validate_push()` возвращал НЕТИПИЗИРОВАННЫЙ
## `Dictionary` с магическими строковыми ключами:
##     {"success": bool, "final_cell": Vector2i, "blocked_reason": StringName}
## Это противоречило правилу "strictly typed везде": опечатка в ключе
## (`"sucess"`) давала не ошибку компиляции, а тихий `null`, и автокомплит
## не работал.
##
## РАСШИРЕНО НА ШАГЕ 0.4 (D-6.2): "успех/неуспех" — недостаточная модель.
## Толкание в тактике такого жанра имеет ЧЕТЫРЕ качественно разных исхода, и
## каждый вызывает разные последствия, которые обязано показать превью (R-6).

enum Outcome {
	MOVED,      ## Цель переместилась в свободную клетку.
	BLOCKED,    ## Упёрлась (стена/высокий уступ) — урон о препятствие.
	COLLISION,  ## Врезалась в другого юнита — урон ОБОИМ.
	FELL,       ## Улетела в пропасть/за край — гибель.
}

## Причины для UI-подсказок ("Цель не отбрасывается: стена").
## StringName, а не enum: причины будут пополняться из будущих модулей
## (статус "укоренён", эффекты тайлов) без правки перечисления.
const REASON_NONE: StringName = &""
const REASON_WALL: StringName = &"wall"
const REASON_HEIGHT: StringName = &"height"
const REASON_OCCUPIED: StringName = &"occupied"
const REASON_BOUNDS: StringName = &"bounds"
const REASON_HAZARD: StringName = &"hazard"

var outcome: Outcome = Outcome.MOVED

## Клетка, где цель окажется по итогу.
## Для BLOCKED/COLLISION — исходная клетка (цель не сдвинулась).
## Для FELL — клетка, в которую она улетела (там она погибает).
var final_cell: Vector2i = Vector2i.ZERO

## Причина, если толчок не привёл к обычному перемещению.
var blocked_reason: StringName = REASON_NONE

## Юнит, в которого врезалась цель (только при COLLISION).
## Именно это поле разблокирует главную механику жанра: `PushCommand` нанесёт
## урон обоим участникам столкновения.
var blocker: UnitState = null

## На сколько уровней высоты цель упала при перемещении (0 = ровно).
## Урон за падение считает `PushCommand`.
var fall_height: int = 0
var fall_steps: int = 0


## Сдвинулась ли цель физически. Используется вместо старого `success`:
## FELL — это тоже перемещение (в пропасть), но радоваться там нечему,
## поэтому отдельный вопрос "а жива ли она" задаётся через `is_lethal()`.
func moved() -> bool:
	return outcome == Outcome.MOVED or outcome == Outcome.FELL


## Приведёт ли толчок к гибели цели.
func is_lethal() -> bool:
	return outcome == Outcome.FELL


## Обратная совместимость со старым API (`push_result.success`).
## `BLOCKED`/`COLLISION` — не успех: цель осталась на месте.
var success: bool:
	get: return outcome == Outcome.MOVED or outcome == Outcome.FELL


static func make_success(cell: Vector2i) -> PushResult:
	var result := PushResult.new()
	result.outcome = Outcome.MOVED
	result.final_cell = cell
	result.blocked_reason = REASON_NONE
	return result


static func make_blocked(
	stay_cell: Vector2i,
	reason: StringName,
	p_blocker: UnitState = null
) -> PushResult:
	var result := PushResult.new()
	result.outcome = Outcome.BLOCKED
	result.final_cell = stay_cell
	result.blocked_reason = reason
	result.blocker = p_blocker
	return result


## Столкновение с юнитом. `into_cell` — клетка, где стоит препятствие
## (нужна для визуализации удара), но цель остаётся в `stay_cell`.
static func make_collision(
	stay_cell: Vector2i,
	_into_cell: Vector2i,
	p_blocker: UnitState
) -> PushResult:
	var result := PushResult.new()
	result.outcome = Outcome.COLLISION
	result.final_cell = stay_cell
	result.blocked_reason = REASON_OCCUPIED
	result.blocker = p_blocker
	return result


static func make_fall(into_cell: Vector2i, reason: StringName) -> PushResult:
	var result := PushResult.new()
	result.outcome = Outcome.FELL
	result.final_cell = into_cell
	result.blocked_reason = reason
	return result


func to_debug_string() -> String:
	match outcome:
		Outcome.MOVED:
			var fall := " (fall %d)" % fall_height if fall_height > 0 else ""
			return "push -> %s%s" % [str(final_cell), fall]
		Outcome.BLOCKED:
			return "push BLOCKED (%s)" % blocked_reason
		Outcome.COLLISION:
			var name := blocker.debug_name if blocker != null else "?"
			return "push COLLISION with %s" % name
		Outcome.FELL:
			return "push FELL into %s (%s)" % [str(final_cell), blocked_reason]
	return "push ?"
