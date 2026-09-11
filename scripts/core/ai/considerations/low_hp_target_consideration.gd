extends AIConsideration
class_name LowHpTargetConsideration

## Выше, если атака способна добить/сильно ранить цель с малым остатком HP
## (приоритет "убить раненого" вместо размена по здоровым целям).
##
## ИЗМЕНЕНО: проверка через `has_attack()` вместо сравнения `action_type` со
## строкой (S-3б) — теперь фактор автоматически учтёт любой новый тип
## действия, который наносит урон (способность, предмет). И возвращает
## `ABSTAIN` вместо `0.0` для неатакующих кандидатов (S-3в): "нет мнения" не
## должно быть голосом против.
##
## HP читается из `Vitals`, а не из стата (R-2).

func score(action: AIAction, _context: AIDecisionContext) -> float:
	if not action.has_attack():
		return ABSTAIN

	var vitals := action.target.vitals
	if vitals == null:
		return ABSTAIN

	var hp_max := vitals.get_hp_max()
	if hp_max <= 0.0:
		return ABSTAIN

	# `would_kill` уже посчитан в DamageInfo — используем готовый результат,
	# чтобы превью ИИ и реальный расчёт не могли разойтись.
	if action.damage_info.would_kill:
		return 1.0 ## смертельный удар — максимальный приоритет

	var projected_hp := vitals.get_hp() - action.damage_info.final_damage
	# Чем меньше остаётся HP относительно максимума, тем выше score.
	return clampf(1.0 - (projected_hp / hp_max), 0.0, 1.0)
