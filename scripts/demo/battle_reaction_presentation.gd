extends RefCounted
class_name BattleReactionPresentation

## Причину показывает только подтверждённая запись того же шага, не прогноз.
static func cues(events: Array, step: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if int(event.get("command_seq", -1)) != int(step.get("command_seq", -2)): continue
		var kind := StringName(event.get("kind", &""))
		if kind == &"guarded" and step.get("kind") == &"guard":
			result.append(_cue(&"guard", event, "Стойка · " + mode_name(int(event.get("reaction_mode", 0)))))
		elif kind == &"opportunity_attacked" and step.get("kind") == &"opportunity_attack":
			result.append(_cue(&"opportunist", event, "Оппортунист"))
		elif kind == &"counterattacked" and step.get("kind") == &"counterattack":
			result.append(_cue(&"counterattack", event, "Контратака"))
		elif kind == &"reaction_used" and int(event.get("mode", 0)) == CombatPerksState.Mode.COVER:
			for attack: Dictionary in events:
				if attack.get("kind") not in [&"attacked", &"opportunity_attacked", &"counterattacked"]: continue
				if attack.get("root_id") == event.get("root_id") and attack.get("command_seq") == event.get("command_seq") and attack.get("target_unit_id") == event.get("target_unit_id"):
					result.append(_cue(&"cover", event, "Прикрытие"))
					break
	return result

static func _cue(kind: StringName, event: Dictionary, title: String) -> Dictionary:
	return {"kind": kind, "actor_id": int(event.get("actor_unit_id", 0)), "target_id": int(event.get("target_unit_id", 0)), "title": title}

static func mode_name(mode: int) -> String:
	match mode:
		CombatPerksState.Mode.OPPORTUNIST: return "Оппортунист"
		CombatPerksState.Mode.COVER: return "Прикрытие"
		CombatPerksState.Mode.COUNTERATTACK: return "Контратака"
	return "Защита"

static func details(view: Dictionary, names: Dictionary) -> String:
	if view.is_empty(): return ""
	var mode := int(view.get("mode", 0))
	var text := "Стойка: " + ("активна" if bool(view.get("guard", false)) else "снята")
	if mode != 0:
		text += " · " + mode_name(mode)
		text += " · " + ("готов" if bool(view.get("ready", false)) else "не готов")
	if bool(view.get("owned", false)):
		text += "\nОбщий заряд реакции: %d/1. Выбор режима не пополняет заряд." % int(view.get("charge", 0))
	if mode == CombatPerksState.Mode.COVER:
		text += "\nПрикрывает: %s. Урон получает союзник; прямое попадание ослаблено на 30%% до брони." % String(names.get(int(view.get("cover_target_id", 0)), "нет цели"))
		if not bool(view.get("cover_valid", false)): text += " Связь сейчас недоступна."
	return text

static func feedback(events: Array, step: Dictionary, before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cue: Dictionary in cues(events, step):
		result.append({"id": cue.actor_id, "text": String(cue.title) + (" · заряд потрачен" if cue.kind != &"guard" else "")})
	# Refill не содержит события: сравниваем соседние опубликованные снимки.
	if step.get("kind") == &"battle_turn_refill" and step.get("status") == &"APPLIED":
		for id: int in after.get("units", {}):
			var old: Dictionary = before.get("units", {}).get(id, {}).get("reaction_view", {})
			var current: Dictionary = after.units[id].get("reaction_view", {})
			if not bool(after.units[id].get("alive", false)): continue
			var parts: PackedStringArray = []
			if bool(old.get("guard", false)) and not bool(current.get("guard", false)): parts.append("Стойка снята")
			if int(current.get("charge", 0)) > int(old.get("charge", 0)): parts.append("Заряд реакции восстановлен")
			if not parts.is_empty(): result.append({"id": id, "text": " · ".join(parts)})
	return result
