extends RefCounted
class_name BattleCompactForecast

static func build(title: String, status: StringName, reason_text: String, units: Dictionary, events: Array, primary_id: int, names: Dictionary, pending: bool = false) -> Dictionary:
	if pending:
		return {"text": title + " · Расчёт…", "details": "", "affected_ids": []}
	if status not in [&"APPLIED", &"INTERRUPTED"]:
		return {"text": title + " · Недоступно: " + reason_text, "details": "", "affected_ids": []}
	var included: Dictionary = {}
	for key: Variant in units.keys():
		var id := int(key)
		if id == primary_id or _changed(units[id]) or _has_chain(events, id) or _is_collision_participant(events, id): included[id] = true
	for raw: Variant in events:
		if not raw is Dictionary: continue
		var event: Dictionary = raw
		match StringName(event.get("kind", &"")):
			&"chain_link":
				_include(included, int(event.get("from_unit_id", -1)))
				_include(included, int(event.get("target_unit_id", -1)))
			&"collision":
				_include(included, int(event.get("actor_unit_id", -1)))
				_include(included, int(event.get("target_unit_id", -1)))
				_include(included, int(event.get("blocker_unit_id", -1)))
			&"push_blocked":
				_include(included, int(event.get("target_unit_id", -1)))
	var ids: Array[int] = []
	for key: Variant in included.keys():
		var id := int(key)
		if id != primary_id: ids.append(id)
	ids.sort()
	var all_ids: Array[int] = []
	if included.has(primary_id): all_ids.append(primary_id)
	for id: int in ids: all_ids.append(id)
	var full_lines: Array[String] = []
	for id: int in all_ids:
		var row: Dictionary = units.get(id, {"before": {}, "after": {}})
		full_lines.append(_unit_line(id, row, names, events, id == primary_id))
	var visible: Array[String] = []
	for i: int in range(mini(full_lines.size(), 3)): visible.append(full_lines[i])
	if full_lines.size() > 3: visible.append("Ещё %d: %s" % [full_lines.size() - 3, ", ".join(_overflow_names(all_ids.slice(3), names))])
	var lead := title
	if status == &"INTERRUPTED": lead += " · Путь прерван: " + reason_text
	return {"text": lead + ("\n" + "\n".join(visible) if not visible.is_empty() else ""), "details": "\n".join(full_lines), "affected_ids": all_ids}

static func _changed(row: Dictionary) -> bool:
	var before: Variant = row.get("before")
	var after: Variant = row.get("after")
	if before == null or after == null: return true
	return before != after

static func _unit_line(id: int, row: Dictionary, names: Dictionary, events: Array, primary: bool) -> String:
	var name := String(names.get(id, "#%d" % id))
	var before: Variant = row.get("before")
	var after: Variant = row.get("after")
	if before == null:
		var appeared := name + " — появляется"
		if after is Dictionary:
			if after.has("pending") and bool(after["pending"]): appeared += ", со следующего хода"
			if after.has("hp"): appeared += "; ОЗ " + _number(after["hp"])
		return appeared
	if after == null: return name + " — исчезает"
	var parts: Array[String] = []
	var old: Dictionary = before
	var now: Dictionary = after
	if primary or old.get("hp") != now.get("hp"): _pair(parts, "ОЗ", old, now, "hp")
	if old.get("armor_current") != now.get("armor_current"): _pair(parts, "броня", old, now, "armor_current")
	if old.get("balance") != now.get("balance") or old.get("balance_max") != now.get("balance_max") or _has_balance_break(events, id):
		if float(old.get("balance_max", 1.0)) <= 0.0 or float(now.get("balance_max", 1.0)) <= 0.0:
			parts.append("равновесие: невосприимчив")
		elif old.has("balance") and now.has("balance") and old.has("balance_max") and now.has("balance_max"):
			parts.append("нарушение %s/%s→%s/%s" % [_number(old["balance"]), _number(old["balance_max"]), _number(now["balance"]), _number(now["balance_max"])])
	if _has_balance_break(events, id): parts.append("Потеря равновесия")
	if old.get("cell") != now.get("cell"):
		parts.append("клетка %s→%s" % [_cell(old.get("cell")), _cell(now.get("cell"))])
	if old.get("main") != now.get("main"): _pair(parts, "основное", old, now, "main")
	if old.get("bonus") != now.get("bonus"): _pair(parts, "дополнительное", old, now, "bonus")
	if old.get("move") != now.get("move"): _pair(parts, "движение", old, now, "move")
	if old.get("guard_stance") != now.get("guard_stance") and old.has("guard_stance") and now.has("guard_stance"):
		parts.append("стойка " + ("включена" if bool(now["guard_stance"]) else "снята"))
	if old.get("combat_perks") != now.get("combat_perks"): parts.append("перки изменятся")
	var blocked_reason := _push_blocked_reason(events, id)
	if blocked_reason != "": parts.append(blocked_reason)
	if _has_target_kind(events, &"collision", id) or _is_collision_blocker(events, id): parts.append("столкновение с бойцом")
	var death := _target_event(events, &"died", id)
	var died := not death.is_empty() or (bool(old.get("alive", true)) and not bool(now.get("alive", true)))
	if died:
		var source: Dictionary = death.get("source", {})
		parts.append("Падение · погиб" if StringName(source.get("kind", &"")) == &"fall" or _has_target_kind(events, &"fell", id) else "погиб")
	elif _has_target_kind(events, &"fell", id):
		parts.append("сорвался")
	var chain_roles := _chain_roles(events, id)
	if bool(chain_roles["from_unit"]): parts.append("Импульс передан")
	if bool(chain_roles["stopped"]):
		var immune := float(now.get("balance_max", old.get("balance_max", 1.0))) <= 0.0
		parts.append("Цепь остановлена · " + ("невосприимчив" if immune else "устоял"))
	if _has_push_move(events, id) and old.get("cell") == now.get("cell"): parts.append("оттеснён")
	if old.get("control") != now.get("control") or old.get("elemental") != now.get("elemental") or old.get("bleeding") != now.get("bleeding"): parts.append("состояния изменятся")
	if parts.is_empty(): parts.append("без изменения итоговых значений")
	return name + " — " + "; ".join(parts)

static func _pair(parts: Array[String], label: String, old: Dictionary, now: Dictionary, key: String) -> void:
	if old.has(key) and now.has(key): parts.append("%s %s→%s" % [label, _number(old[key]), _number(now[key])])

static func _number(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, round(number)) else String.num(number, 1)

static func _cell(value: Variant) -> String:
	if not value is Vector2i: return "?"
	var cell: Vector2i = value
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]

static func _has_balance_break(events: Array, id: int) -> bool:
	return _has_target_kind(events, &"balance_broken", id)

static func _has_target_kind(events: Array, kind: StringName, id: int) -> bool:
	for raw: Variant in events:
		if raw is Dictionary and StringName(raw.get("kind", &"")) == kind and int(raw.get("target_unit_id", -1)) == id: return true
	return false

static func _has_chain(events: Array, id: int) -> bool:
	for raw: Variant in events:
		if raw is Dictionary and raw.get("kind", &"") == &"chain_link" and (int(raw.get("target_unit_id", -1)) == id or int(raw.get("from_unit_id", -1)) == id): return true
	return false

static func _chain_roles(events: Array, id: int) -> Dictionary:
	var from_unit := false
	var stopped := false
	for raw: Variant in events:
		if not raw is Dictionary or raw.get("kind", &"") != &"chain_link": continue
		if int(raw.get("from_unit_id", -1)) == id: from_unit = true
		if int(raw.get("target_unit_id", -1)) == id and not bool(raw.get("broke", false)): stopped = true
	return {"from_unit": from_unit, "stopped": stopped}

static func _is_collision_blocker(events: Array, id: int) -> bool:
	for raw: Variant in events:
		if raw is Dictionary and raw.get("kind", &"") == &"collision" and int(raw.get("blocker_unit_id", -1)) == id: return true
	return false

static func _is_collision_participant(events: Array, id: int) -> bool:
	for raw: Variant in events:
		if raw is Dictionary and raw.get("kind", &"") == &"collision" and id in [int(raw.get("actor_unit_id", -1)), int(raw.get("target_unit_id", -1)), int(raw.get("blocker_unit_id", -1))]: return true
	return false

static func _include(values: Dictionary, id: int) -> void:
	if id > 0: values[id] = true

static func _push_blocked_reason(events: Array, id: int) -> String:
	for raw: Variant in events:
		if not raw is Dictionary: continue
		var event: Dictionary = raw
		if event.get("kind", &"") != &"push_blocked" or int(event.get("target_unit_id", -1)) != id: continue
		match StringName(event.get("reason", &"")):
			&"wall": return "толчок остановлен: стена"
			&"height": return "толчок остановлен: высота"
			_: return "толчок остановлен: прочее"
	return ""

static func _target_event(events: Array, kind: StringName, id: int) -> Dictionary:
	for raw: Variant in events:
		if raw is Dictionary and StringName(raw.get("kind", &"")) == kind and int(raw.get("target_unit_id", -1)) == id: return raw
	return {}

static func _has_push_move(events: Array, id: int) -> bool:
	for raw: Variant in events:
		if raw is Dictionary and raw.get("kind", &"") == &"moved" and int(raw.get("target_unit_id", -1)) == id and raw.get("movement_kind", &"") == &"push": return true
	return false

static func _overflow_names(ids: Array, names: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw: Variant in ids:
		var id := int(raw)
		result.append(String(names.get(id, "#%d" % id)))
	return result
