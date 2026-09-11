extends AIConsideration
class_name PushCollisionConsideration

## Ценит толчок, при котором цель ВРЕЗАЕТСЯ в другого юнита — урон получают
## оба. Это классический "двойной размен" из Into the Breach.
##
## ЭТОТ ФАКТОР СТАЛ ВОЗМОЖЕН ТОЛЬКО НА ШАГЕ 0.4. До появления `BattleBoard`
## резолвер толкания не знал о юнитах (дефект C-4), поэтому толчок в занятую
## клетку считался обычным успешным перемещением — отличить столкновение от
## свободного толчка было НЕЧЕМ, и главная механика жанра не могла быть даже
## оценена ИИ.
##
## Показательно, что новый тактический мотив добавляется отдельным файлом и
## подключением в `.tres`, без правки `UtilityAIController` — ровно так, как
## обещала архитектура модуля 7 (и чего она фактически не обеспечивала для
## новых ТИПОВ действий, см. S-3а).

## Оценка, если в столкновение улетает ВРАГ думающего юнита.
@export var enemy_collision_score: float = 1.0

## Оценка, если пострадает СОЮЗНИК (обычно это плохо — своих не бьём).
@export var ally_collision_score: float = 0.0

## Запрещать ли толчок, ведущий к удару по союзнику, вместо простого штрафа.
## По умолчанию выключено: иногда разменять союзника — единственный ход.
@export var veto_ally_collision: bool = false


func score(action: AIAction, _context: AIDecisionContext) -> float:
	if not action.has_attack():
		return ABSTAIN

	var push := action.damage_info.push_result
	if push == null or push.outcome != PushResult.Outcome.COLLISION:
		return ABSTAIN ## столкновения не будет — фактор не имеет мнения

	var victim := push.blocker
	if victim == null:
		return ABSTAIN

	# Жертва столкновения — с точки зрения ДУМАЮЩЕГО юнита, а не цели атаки.
	var thinker := action.damage_info.attacker
	if thinker != null and thinker.is_friendly_to(victim):
		if veto_ally_collision:
			return VETO
		return clampf(ally_collision_score, 0.0, 1.0)

	return clampf(enemy_collision_score, 0.0, 1.0)
