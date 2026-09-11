extends RefCounted
class_name DamageInfo

## DTO, описывающий одну атаку от расчёта до применения. Один и тот же объект
## используется и для ПРЕВЬЮ (`DamageCalculator.calculate()` заполняет поля, но
## НЕ применяет их), и для реального выполнения (`apply()` читает уже
## посчитанные поля) — исключает расхождение "показали одно, случилось другое".
##
## ИЗМЕНЕНО: было `extends Resource` (дефект S-2). Транзиентный DTO, живущий
## один кадр, наследовал `Resource` с его RID и инфраструктурой загрузки,
## причём все поля объявлены через `var`, а не `@export` — то есть он всё
## равно не сериализовался, и от `Resource` были взяты только накладные
## расходы. Цена была реальной: `UtilityAIController` создаёт по одному
## DamageInfo на каждую пару (достижимая клетка x враг) — 40 клеток x 4 врага
## = 160 Resource-аллокаций на ход ОДНОГО юнита (см. R-1).
##
## `attacker`/`target` теперь `UnitState`, а не `StatsComponent` (фикс C-1):
## "мешок характеристик" больше не является идентичностью юнита.
##
## `attacker_cell`/`target_cell` — ГИПОТЕТИЧЕСКИЕ позиции на сетке в момент
## удара (не обязательно текущие живые позиции юнитов). Это СОХРАНЁННОЕ
## решение из модуля 6: оно необходимо для комбо-потока "движение+атака за
## одно подтверждение" (см. DECISIONS.md), где превью нужно построить ДО
## фактического перемещения.

var attacker: UnitState
var target: UnitState
var attacker_cell: Vector2i
var target_cell: Vector2i

var base_damage: float = 0.0
var impact_power: float = 0.0
var damage_type: StringName = &"physical"

## --- Поля, заполняемые DamageCalculator.calculate() ---
var final_damage: float = 0.0
var balance_added: float = 0.0
var would_break_balance: bool = false

## true, если рассчитанный урон уменьшит HP цели до нуля. Заполняется на
## основе `Vitals.get_hp()` — до фикса C-2 предсказать смерть было
## невозможно, потому что смерти не существовало как понятия.
var would_kill: bool = false

var push_direction: Vector2i = Vector2i.ZERO
var push_target_cell: Vector2i = Vector2i.ZERO
var push_blocked: bool = false
var push_blocked_reason: StringName = &""


## Человекочитаемая сводка для дебаг-панелей.
func to_debug_string() -> String:
	var parts: Array[String] = []
	parts.append("dmg %.1f%s" % [final_damage, " (KILL)" if would_kill else ""])
	parts.append("balance +%.1f%s" % [balance_added, " (BREAK)" if would_break_balance else ""])
	if would_break_balance:
		if push_blocked:
			parts.append("push BLOCKED (%s)" % push_blocked_reason)
		else:
			parts.append("push %s -> %s" % [str(push_direction), str(push_target_cell)])
	return " | ".join(parts)
