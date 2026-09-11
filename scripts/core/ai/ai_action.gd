extends RefCounted
class_name AIAction

## Один "кандидат-намерение" ИИ на текущий ход: куда переместиться и,
## опционально, кого атаковать. Аналог "Потока B" (move+attack одним
## подтверждением) из DECISIONS.md, но решение принимает ИИ, а не игрок.
##
## RefCounted (не Resource) — это эфемерные данные одного расчёта хода,
## не нужно сохранять/инспектировать как ассет.
##
## damage_info, если не null, — результат ActionPreview.build() (ЧИСТЫЙ
## расчёт, без побочных эффектов) для конкретной пары final_cell/target_cell.
## UtilityAIController только СРАВНИВАЕТ кандидатов; реальное применение
## (DamageCalculator.apply + перемещение по сетке) — ответственность
## вызывающего кода/Модуля 10 (Action & Visual Execution Queue).

var action_type: StringName = &"idle" ## &"idle" | &"move" | &"move_and_attack"
var final_cell: Vector2i = Vector2i.ZERO ## клетка, куда должен переместиться юнит
var target: StatsComponent = null
var target_cell: Vector2i = Vector2i.ZERO
var damage_info: DamageInfo = null

## Заполняется UtilityAIController после оценки — удобно для дебага/UI.
var score: float = 0.0
