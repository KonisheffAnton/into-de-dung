extends Resource
class_name DamageInfo

## DTO, описывающий одну атаку от расчёта до применения. Один и тот же
## объект используется и для ПРЕВЬЮ (DamageCalculator.calculate заполняет
## поля, но НЕ применяет их), и для реального выполнения (apply() читает
## уже посчитанные поля) — исключает расхождение между тем, что показали
## в превью, и тем, что произошло по факту.
##
## attacker_cell/target_cell — ГИПОТЕТИЧЕСКИЕ позиции на сетке в момент
## удара (не обязательно текущие живые позиции юнитов) — важно для
## комбо-потока "движение+атака за одно подтверждение" (см. DECISIONS.md).

var attacker: StatsComponent
var target: StatsComponent
var attacker_cell: Vector2i
var target_cell: Vector2i

var base_damage: float = 0.0
var impact_power: float = 0.0
var damage_type: StringName = &"physical"

## --- Поля, заполняемые DamageCalculator.calculate() ---
var final_damage: float = 0.0
var balance_added: float = 0.0
var would_break_balance: bool = false
var push_direction: Vector2i = Vector2i.ZERO
var push_target_cell: Vector2i = Vector2i.ZERO
var push_blocked: bool = false
var push_blocked_reason: StringName = &""
