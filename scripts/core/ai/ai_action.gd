extends RefCounted
class_name AIAction

## Один кандидат-намерение ИИ на ход.
##
## ИЗМЕНЕНО (фикс S-3б): `action_type` был `StringName` (`&"move"`, `&"move_and_attack"`)
## — stringly-typed, без проверки компилятором. Хуже того, considerations ХАРДКОДИЛИ
## эти строки:
##     if action.action_type != &"move_and_attack": return 0.0
## Из-за этого новый тип действия (например `use_ability`, тоже наносящий
## урон) был бы ПРОИГНОРИРОВАН всеми существующими considerations — прямое
## нарушение OCP, обратное тому, что обещала документация модуля 7.
##
## Теперь тип — enum (проверяется компилятором), а considerations должны
## оценивать кандидата по НАЛИЧИЮ ДАННЫХ (`has_attack()`), а не по типу.
## Тогда новый тип действия автоматически учитывается старыми факторами.

enum Type {
	IDLE,             ## Остаться на месте, ничего не делать.
	MOVE,             ## Переместиться в final_cell.
	MOVE_AND_ATTACK,  ## Переместиться и атаковать цель (одно подтверждение).
}

var action_type: Type = Type.IDLE

## Клетка, где юнит окажется после выполнения действия.
var final_cell: Vector2i = Vector2i.ZERO

## Цель атаки (null для IDLE/MOVE).
var target: UnitState = null
var target_cell: Vector2i = Vector2i.ZERO

## Результат `ActionPreview.build()` — ЧИСТЫЙ расчёт, безопасный для
## сравнения кандидатов (не мутирует состояние).
var damage_info: DamageInfo = null

## Итоговая оценка профиля поведения. Только для дебага/логов.
var score: float = 0.0


## Есть ли у кандидата атакующая составляющая. Considerations должны
## спрашивать ЭТО, а не сравнивать `action_type` (см. комментарий выше).
func has_attack() -> bool:
	return target != null and damage_info != null


static func make_idle(cell: Vector2i) -> AIAction:
	var action := AIAction.new()
	action.action_type = Type.IDLE
	action.final_cell = cell
	return action


static func make_move(cell: Vector2i) -> AIAction:
	var action := AIAction.new()
	action.action_type = Type.MOVE
	action.final_cell = cell
	return action


static func make_move_and_attack(
	cell: Vector2i,
	p_target: UnitState,
	p_target_cell: Vector2i,
	p_damage_info: DamageInfo
) -> AIAction:
	var action := AIAction.new()
	action.action_type = Type.MOVE_AND_ATTACK
	action.final_cell = cell
	action.target = p_target
	action.target_cell = p_target_cell
	action.damage_info = p_damage_info
	return action


func to_debug_string() -> String:
	match action_type:
		Type.IDLE:
			return "IDLE @%s (score %.3f)" % [str(final_cell), score]
		Type.MOVE:
			return "MOVE -> %s (score %.3f)" % [str(final_cell), score]
		Type.MOVE_AND_ATTACK:
			var target_name := target.debug_name if target != null else "?"
			var dmg := damage_info.to_debug_string() if damage_info != null else ""
			return "ATTACK %s from %s (score %.3f) [%s]" % [
				target_name, str(final_cell), score, dmg
			]
	return "UNKNOWN"
