extends RefCounted
class_name BattleStatusPresentation

## Один перевод опубликованных значений для обычного refresh, кадров и осмотра.
## Здесь нет ссылок на бой и нет предположения, что источник равен одному стаку.
static func entries(row: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var control: Dictionary = row.get("control", {})
	var elemental: Dictionary = row.get("elemental", {})
	var bleeding: Dictionary = row.get("bleeding", {})
	_add(result, "stunned", "Оглушён", 0, int(control.get("stunned_turns", 0)), "до конца ближайшего хода своей команды", true)
	_add(result, "frozen", "Заморожен", 0, int(elemental.get("frozen_turns", 0)), "концов хода своей команды", true)
	_add(result, "entangled", "Путы", 0, int(control.get("entangled_turns", 0)), "до конца ближайшего хода своей команды", true)
	_add(result, "bleeding", "Кровотечение", int(bleeding.get("stacks", 0)), int(bleeding.get("ticks_left", 0)), "тиков в начале своего хода", false)
	_add(result, "burning", "Горение", int(elemental.get("burning_stacks", 0)), int(elemental.get("burning_ticks", 0)), "тиков в начале своего хода", false)
	_add(result, "wet", "Мокрый", 0, int(elemental.get("wet_turns", 0)), "концов хода своей команды", false)
	return result

static func _add(result: Array[Dictionary], id: String, title: String, stacks: int, remaining: int, unit: String, embodied: bool) -> void:
	if remaining <= 0: return
	result.append({"id": id, "title": title, "stacks": stacks, "remaining": remaining, "duration_unit": unit, "embodied": embodied})

static func has(values: Array[Dictionary], id: String) -> bool:
	return values.any(func(entry: Dictionary) -> bool: return entry.id == id)

static func summary(values: Array[Dictionary]) -> String:
	var labels: PackedStringArray = []
	for entry: Dictionary in values:
		labels.append(String(entry.title) + (" ×%d" % int(entry.stacks) if int(entry.stacks) > 0 else ""))
	return " · ".join(labels)

static func details(values: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in values:
		var duration := String(entry.duration_unit)
		if entry.id not in ["stunned", "entangled"]: duration = "%d %s" % [int(entry.remaining), duration]
		var stacks := "стаки: %d · " % int(entry.stacks) if int(entry.stacks) > 0 else ""
		lines.append("%s — %sсрок: %s" % [entry.title, stacks, duration])
	return "\n".join(lines) if not lines.is_empty() else "Состояний нет."

static func event_feedback(event: Dictionary) -> String:
	var field := ""
	match StringName(event.get("kind", &"")):
		&"bleeding_changed": field = "bleeding"
		&"elemental_changed": field = "elemental"
		&"control_changed": field = "control"
		_: return ""
	var before := entries({field: event.get("before", {})})
	var after := entries({field: event.get("after", {})})
	var parts: PackedStringArray = []
	for old: Dictionary in before:
		if not has(after, old.id): parts.append("− " + String(old.title))
	for current: Dictionary in after:
		var previous: Dictionary = {}
		for old: Dictionary in before:
			if old.id == current.id: previous = old
		if previous.is_empty(): parts.append("+ " + String(current.title))
		elif int(current.stacks) != int(previous.stacks): parts.append("%s ×%d" % [current.title, int(current.stacks)])
		elif int(current.remaining) != int(previous.remaining):
			parts.append("%s · %d %s" % [current.title, int(current.remaining), "тиков" if current.id in ["bleeding", "burning"] else "своих ходов"])
		elif String(event.get("reason", "")) in ["refreshed", "stun_refreshed"]: parts.append(String(current.title) + " · обновлено")
	# Тик — факт события, а не выдуманное изменение HP или новый стак.
	if String(event.get("reason", "")) in ["tick", "burn_tick"]:
		return "Тик: " + ("Кровотечение" if field == "bleeding" else "Горение") + (" · снято" if after.is_empty() else "")
	return " · ".join(parts)
